const builtin = @import("builtin");
const pool = @import("pool.zig");
const proto = @import("protocol.zig");
const errors = @import("error.zig");
const root = @import("root");
const std = @import("std");

const Message = proto.Message;
const ErrorMessageBody = proto.ErrorMessageBody;
const HandlerError = errors.HandlerError;
const EmptyStringArray = [0][]const u8{};

pub const thread_safe: bool = !builtin.single_threaded;
pub const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

// FIXME: what we can do about those? - move to the heap with BufReader.
pub const read_buf_size = if (@hasDecl(root, "read_buf_size")) root.read_buf_size else 4096;

pub const Handler = fn (*Runtime, *Message) HandlerError!void;
pub const HandlerPtr = *const Handler;
pub const HandlerMap = std.StringHashMap(HandlerPtr);

pub const Runtime = struct {
    gpa: ?std.heap.GeneralPurposeAllocator(.{}),
    // thread-safe by itself
    alloc: std.mem.Allocator,

    outm: std.Thread.Mutex,
    out: std.fs.File,

    pool: pool.Pool,
    // log: TODO: @TypeOf(Scoped)

    handlers: HandlerMap,

    // init state
    m: MutexType,
    node_id: []const u8,
    nodes: [][]const u8,

    pub fn init() !*Runtime {
        return initWithAllocator(null);
    }

    // alloc is expected to be thread-safe by itself.
    pub fn initWithAllocator(alloc: ?std.mem.Allocator) !*Runtime {
        var runtime: *Runtime = undefined;

        if (alloc) |a| {
            runtime = try a.create(Runtime);
            runtime.gpa = null;
            runtime.alloc = a;
        } else {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};

            runtime = try gpa.allocator().create(Runtime);
            runtime.gpa = gpa;
            runtime.alloc = runtime.gpa.?.allocator();
        }

        runtime.outm = std.Thread.Mutex{};
        runtime.out = std.io.getStdOut();
        runtime.pool = try pool.Pool.init(runtime.alloc, @max(2, @min(4, try std.Thread.getCpuCount())));
        runtime.handlers = HandlerMap.init(runtime.alloc);
        runtime.m = MutexType{};
        runtime.node_id = "";
        runtime.nodes = &EmptyStringArray;

        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        self.pool.deinit();
        self.handlers.deinit();
    }

    /// handle(type, f) registers a handler for specific message type.
    pub fn handle(self: *Runtime, msg_type: []const u8, f: HandlerPtr) !void {
        if (self.handlers.contains(msg_type)) {
            std.debug.panic("this message type is already registered: {s}", .{msg_type});
        }

        try self.handlers.put(msg_type, f);
    }

    pub fn send_raw_f(self: *Runtime, comptime fmt: []const u8, args: anytype) void {
        if (comptime std.io.is_async) {
            @panic("async IO in unsupported at least until 0.12.0. we need sync stdout. see the comment below.");
        }

        const out = self.out.writer();

        defer std.log.debug("Sent " ++ fmt, args);

        self.outm.lock();
        defer self.outm.unlock();
        // stdout.writer().print suspends in async io mode.
        // on Darwin a suspend point in the middle of mutex causes for 0.10.1:
        //     Illegal instruction at address 0x7ff80f6c1efc
        //     ???:?:?: 0x7ff80f6c1efc in ??? (???)
        //     zig/0.10.1/lib/zig/std/Thread/Mutex.zig:115:40: 0x10f60dd84 in std.Thread.Mutex.DarwinImpl.unlock (echo)
        //     os.darwin.os_unfair_lock_unlock(&self.oul);
        //
        // FIXME: check if it works with 0.12.0 + darwin when its ready.
        nosuspend out.print(fmt ++ "\n", args) catch return;
    }

    pub fn send_raw(self: *Runtime, msg: []const u8) void {
        self.send_raw_f("{s}", .{msg});
    }

    // msg must support special treatment for arrays and messagebody flattening.
    // does not support non-struct and non array kinds.
    //
    //    runtime.send("n1", msg);
    //    runtime.send("n1", .{req.body, msg}) - merges objects.
    pub fn send(self: *Runtime, to: []const u8, msg: anytype) !void {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();

        var allocator = arena.allocator();
        
        const obj = try proto.to_json_value(allocator, msg);

        var packet = proto.Message{
            .src = self.node_id,
            .dest = to,
            .body = proto.MessageBody.init(),
        };

        packet.body.raw = obj;

        self.send_raw(try std.json.stringifyAlloc(allocator, packet, .{}));
    }

    pub fn send_back(self: *Runtime, req: *Message, msg: anytype) !void {
        try self.send(req.src, msg);
    }

    pub fn reply(self: *Runtime, req: *Message, msg: anytype) !void {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();

        var allocator = arena.allocator();
        
        var obj = try proto.to_json_value(allocator, msg);
        if (!obj.Object.contains("type")) {
            try obj.Object.put("type", std.json.Value{ .String = try std.fmt.allocPrint(allocator, "{s}_ok", .{req.body.typ}), });
        }

        try self.send_back(req, msg);
    }

    pub fn reply_err(self: *Runtime, req: *Message, resp: HandlerError) !void {
        try self.reply(req, errors.to_message(resp));
    }

    pub fn reply_ok(self: *Runtime, req: *Message) !void {
        try self.reply(req, req);
    }

    // in: std.io.Reader.{}
    // read buffer is 4kB.
    pub fn listen(self: *Runtime, in: anytype) !void {
        var buffer: [read_buf_size]u8 = undefined;

        while (nextLine(in, &buffer)) |try_line| {
            if (try_line == null) return;
            const line = try_line.?;

            if (line.len == 0) continue;
            std.log.debug("Received {s}", .{line});

            try self.pool.enqueue(self.alloc, line);
        } else |err| {
            return err;
        }
    }

    pub fn run(self: *Runtime) !void {
        try self.pool.start(worker, .{self});
        defer self.deinit();

        std.log.info("node started.", .{});

        self.listen(std.io.getStdIn().reader()) catch |e| {
            std.log.err("listen loop error: {}", .{e});
        };

        std.log.info("node finished.", .{});
    }

    pub fn worker(self: *Runtime) void {
        const id = std.Thread.getCurrentId();

        std.log.debug("[{d}] worker started.", .{id});

        while (self.pool.queue.get()) |node| {
            self.process_request_node(node);
        }

        std.log.debug("[{d}] worker finished.", .{id});
    }

    fn process_request_node(self: *Runtime, node: *pool.Pool.JobNode) void {
        defer node.data.arena.deinit();

        const id = std.Thread.getCurrentId();

        // std.log.debug("[{d}] worker: got an item: {s}", .{ id, node.data.req });

        if (proto.parse_message(node.data.arena.allocator(), node.data.req)) |m| {
            if (self.handlers.get(m.body.typ)) |f| {
                const res = f(self, m);
                res catch @panic("ops"); // TODO: implement error handling
            } else {
                // TODO: move errors handling into sep f
                // TODO: API to create responses from errors
                const res = self.reply_err(m, HandlerError.NotSupported);
                res catch @panic("ops"); // TODO: implement error handling
            }
        } else |err| {
            std.log.err("[{d}] incoming message parsing error {s}, {}", .{ id, node.data.req, err });
        }
    }
};

const DummyMutex = struct {
    fn lock(_: *DummyMutex) void {}
    fn unlock(_: *DummyMutex) void {}
};

// reader: std.io.Reader.{}
fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;
    // trim annoying windows-only carriage return character
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}

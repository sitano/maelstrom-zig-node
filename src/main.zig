const builtin = @import("builtin");
const print = @import("std").debug.print;
const std = @import("std");
const testing = std.testing;

const thread_safe: bool = !builtin.single_threaded;
const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

pub const log = @import("log.zig");

pub fn run(loop: *std.event.Loop, comptime func: anytype) !void {
    // maelstrom requires async io.
    //
    // to tell runtime we want async io define the following in root ns:
    //     pub const io_mode = .evented; // auto deducted, or
    //     var global_instance_state: std.event.Loop = undefined;
    //     pub const event_loop: *std.event.Loop = &global_instance_state;
    //
    // async io also requires enabling stage1 compiler.
    if (!std.io.is_async)
        @panic("io is not async. see code comment to fix.");

    if (builtin.single_threaded) {
        try loop.initSingleThreaded();
    } else {
        try loop.initMultiThreaded();
    }
    defer loop.deinit();

    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = alloc.deinit();

    var runtime = Runtime.init(alloc.allocator());
    defer runtime.deinit();

    const Wrapper = struct {
        fn run(rt: *Runtime) void {
            func(rt) catch |e| {
                std.debug.panic("main func error: {}", .{e});
            };

            std.log.info("node started.", .{});

            listen(std.io.getStdIn().reader(), rt) catch |e| {
                std.log.err("listen loop error: {}", .{e});
            };
        }
    };

    try loop.runDetached(runtime.alloc, Wrapper.run, .{&runtime});

    loop.run();

    std.log.info("node finished.", .{});
}

// in: std.io.Reader.{}
// read buffer is 4kB.
pub fn listen(in: anytype, runtime: *Runtime) !void {
    var buffer: [4096]u8 = undefined;

    while (nextLine(in, &buffer)) |try_line| {
        if (try_line == null) return;
        const line = try_line.?;

        try runtime.send_raw("{s}", .{line});
    } else |err| {
        return err;
    }
}

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

pub const Runtime = struct {
    // thread-safe by itself
    alloc: std.mem.Allocator,

    outm: std.Thread.Mutex,
    out: std.fs.File,

    m: MutexType,
    // log: TODO: @TypeOf(Scoped)

    // alloc is expected to be thread-safe by itself.
    pub fn init(alloc: std.mem.Allocator) Runtime {
        return .{
            .alloc = alloc,

            .outm = std.Thread.Mutex{},
            .out = std.io.getStdOut(),

            .m = MutexType{},
        };
    }

    pub fn send_raw(self: *Runtime, comptime fmt: []const u8, args: anytype) !void {
        self.outm.lock();
        defer self.outm.unlock();
        const out = self.out.writer();
        return out.print(fmt ++ "\n", args);
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
    }
};

const DummyMutex = struct {
    fn lock(_: *DummyMutex) void {}
    fn unlock(_: *DummyMutex) void {}
};

pub const Result = struct {
    answer: i32,
};

pub fn add(a: i32, b: i32) Result {
    return Result{ .answer = a + b };
}

test "basic add functionality" {
    try testing.expect(add(3, 7).answer == 10);
}

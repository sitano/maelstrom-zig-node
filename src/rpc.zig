const std = @import("std");
const proto = @import("protocol.zig");

// can't store anyframe cause zig does not support async without -fstage1.
pub const Request = struct {
    arena: std.heap.ArenaAllocator,
    req: proto.Message,
    msg_id: u64,
    // if Request is async, the Runtime shall execute a message handler,
    // to process the request. Otherwise, it expects the waiters to be notified.
    is_async: bool,

    notify: std.Thread.Condition,
    m: std.Thread.Mutex,
    completed: bool,
    // must be allocated on local arena, and available by completion.
    resp: *proto.Message,

    pub fn init(arena: std.heap.ArenaAllocator, msg_id: u64) Request {
        return Request{
            .arena = arena,
            .req = proto.Message.init(),
            .msg_id = msg_id,
            .is_async = true,
            .notify = std.Thread.Condition{},
            .m = std.Thread.Mutex{},
            .completed = false,
            .resp = undefined,
        };
    }

    pub fn deinit(self: *Request) void {
        self.arena.deinit();
    }

    pub fn is_completed(self: *Request) bool {
        self.m.lock();
        defer self.m.unlock();
        return self.completed;
    }

    pub fn get_result(self: *Request) *proto.Message {
        self.m.lock();
        defer self.m.unlock();
        return self.resp;
    }

    /// resp must be allocated on top of local (Request) arena.
    pub fn set_completed(self: *Request, resp: *proto.Message) void {
        self.m.lock();
        defer self.m.unlock();
        self.completed = true;
        self.resp = resp;
        self.notify.broadcast();
    }

    pub fn wait(self: *Request) *proto.Message {
        self.m.lock();
        defer self.m.unlock();
        while (!self.completed) {
            self.notify.wait(&self.m);
        }
        return self.resp;
    }

    pub fn timed_wait(self: *Request, timeout_ns: u64) error{Timeout}!*proto.Message {
        self.m.lock();
        defer self.m.unlock();
        while (!self.completed) {
            try self.notify.timedWait(&self.m, timeout_ns);
        }
        return self.resp;
    }
};

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    msg_id: std.atomic.Atomic(u64),
    m: std.Thread.Mutex,
    reqs: std.AutoHashMap(u64, *Request),

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        return Runtime{
            .alloc = alloc,
            .reqs = std.AutoHashMap(u64, *Request).init(alloc),
            .m = std.Thread.Mutex{},
            .msg_id = std.atomic.Atomic(u64).init(1),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
        self.reqs.deinit();
    }

    pub fn next_msg_id(self: *Runtime) u64 {
        return self.msg_id.fetchAdd(1, std.atomic.Ordering.AcqRel);
    }

    pub fn new_req(self: *Runtime, is_async: bool) !*Request {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        var req = try arena.allocator().create(Request);
        req.* = Request.init(arena, self.next_msg_id());
        req.is_async = is_async;
        return req;
    }

    pub fn add(self: *Runtime, req: *Request) !bool {
        self.m.lock();
        defer self.m.unlock();

        if (self.reqs.contains(req.msg_id)) {
            return false;
        }

        try self.reqs.put(req.msg_id, req);

        return true;
    }

    pub fn remove(self: *Runtime, req_id: u64) !void {
        self.m.lock();
        defer self.m.unlock();

        if (self.reqs.get(req_id)) |req| {
            req.arena.deinit();
        }
    }

    /// when you get a request, you are responsible for cleaning up the arena.
    pub fn poll_request(self: *Runtime, req_id: u64) ?*Request {
        self.m.lock();
        defer self.m.unlock();

        if (self.reqs.get(req_id)) |req| {
            _ = self.reqs.remove(req_id);
            return req;
        }

        return null;
    }
};

test "simple queue" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var alloc = arena.allocator();

    var runtime = try Runtime.init(alloc);
    defer runtime.deinit();

    var req = try runtime.new_req(false);
    try std.testing.expectEqual(true, try runtime.add(req));

    var resp = try req.arena.allocator().create(proto.Message);
    req.set_completed(resp);

    var resp2 = req.wait();
    try std.testing.expectEqual(resp, resp2);

    try runtime.remove(req.msg_id);
}

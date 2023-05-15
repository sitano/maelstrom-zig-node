const std = @import("std");
const proto = @import("protocol.zig");

// can't store anyframe cause zig does not support async without -fstage1.
pub const Request = struct {
    arena: *std.heap.ArenaAllocator,
    // must be allocated on top of the current arena ^^.
    req: *proto.Message,
    msg_id: u64,
};

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    msg_id: std.atomic.Atomic(u64),
    m: std.Thread.Mutex,
    reqs: std.AutoHashMap(u64, Request),

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        return Runtime{
            .alloc = alloc,
            .reqs = std.AutoHashMap(u64, Request).init(alloc),
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

    pub fn new_req(self: *Runtime) !Request {
        return Request{
            .alloc = try self.alloc.create(std.heap.ArenaAllocator).init(self.alloc),
            .req = undefined,
            .msg_id = self.next_msg_id(),
        };
    }

    pub fn add(self: *Runtime, req: Request) !bool {
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
            req.req = undefined;
            req.alloc.deinit();

            self.alloc.destroy(req.alloc);
            req.alloc = undefined;
        }
    }
};

test "simple queue" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var alloc = arena.allocator();

    var runtime = try Runtime.init(alloc);
    _ = runtime;
}

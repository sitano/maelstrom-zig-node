const builtin = @import("builtin");
const std = @import("std");

pub const thread_safe: bool = !builtin.single_threaded;
pub const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

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

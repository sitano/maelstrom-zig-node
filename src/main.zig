const builtin = @import("builtin");
const print = @import("std").debug.print;
const std = @import("std");
const testing = std.testing;

pub fn run(loop: *std.event.Loop, comptime func: anytype) !void {
    if (builtin.single_threaded) @panic("build is single threaded");
    if (!std.io.is_async) @panic("io is not async");

    try loop.initMultiThreaded();
    defer loop.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var runtime = Runtime.init(arena.allocator());
    defer runtime.deinit();

    const Wrapper = struct {
        fn run(rt: *Runtime) void {
            func(rt) catch |e| {
                std.debug.panic("main func error: {}", .{e});
            };

            std.debug.print("node started.\n", .{});
        }
    };

    try loop.runDetached(runtime.arena, Wrapper.run, .{&runtime});

    loop.run();

    std.debug.print("node finished.\n", .{});
}

pub const Runtime = struct {
    m: std.Thread.Mutex,
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) Runtime {
        return .{
            .m = std.Thread.Mutex{},
            .arena = arena,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
    }
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

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

    const Wrapper = struct {
        fn run() void {
            func() catch |e| {
                print("main func error: {}", .{e});
            };

            std.debug.print("node finished.\n", .{});
        }
    };

    try loop.runDetached(arena.allocator(), Wrapper.run, .{});

    loop.run();
}

pub const Result = struct {
    answer: i32,
};

pub fn add(a: i32, b: i32) Result {
    return Result{ .answer = a + b };
}

test "basic add functionality" {
    try testing.expect(add(3, 7).answer == 10);
}

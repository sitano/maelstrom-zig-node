const std = @import("std");
const builtin = @import("builtin");

var global_instance_state: std.event.Loop = undefined;

pub const event_loop: *std.event.Loop = &global_instance_state;

pub fn main() !void {
    if (!std.io.is_async)
        @panic("io is not async. see code comment to fix.");

    if (builtin.single_threaded) {
        try event_loop.initSingleThreaded();
    } else {
        try event_loop.initMultiThreaded();
    }
    defer event_loop.deinit();

    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = alloc.deinit();

    try event_loop.runDetached(alloc.allocator(), run0, .{});

    event_loop.run();
}

fn run0() void {
    const f = std.io.getStdOut();
    const w = f.writer();
    std.debug.print(".. i = {}\n", .{f.intended_io_mode});
    std.debug.print(".. c = {}\n", .{f.capable_io_mode});

    const fe = std.io.getStdErr();
    std.debug.print(".. i = {}\n", .{fe.intended_io_mode});
    std.debug.print(".. c = {}\n", .{fe.capable_io_mode});

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    w.print("x", .{}) catch return;

    // nosuspend w.print("x", .{}) catch return;
    // nosuspend w.print(">> {s}", .{"aaaaaaa"}) catch return;
}

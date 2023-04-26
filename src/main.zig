const builtin = @import("builtin");
const std = @import("std");

pub const log = @import("log.zig");
const rt = @import("runtime.zig");
pub const Runtime = rt.Runtime;

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

    var runtime0 = Runtime.init(alloc.allocator());
    defer runtime0.deinit();

    const Wrapper = struct {
        fn run(runtime: *Runtime) void {
            func(runtime) catch |e| {
                std.debug.panic("main func error: {}", .{e});
            };

            std.log.info("node started.", .{});

            runtime.listen(std.io.getStdIn().reader()) catch |e| {
                std.log.err("listen loop error: {}", .{e});
            };
        }
    };

    try loop.runDetached(runtime0.alloc, Wrapper.run, .{&runtime0});

    loop.run();

    std.log.info("node finished.", .{});
}

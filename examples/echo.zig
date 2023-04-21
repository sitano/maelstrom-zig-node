const maelstrom = @import("maelstrom");
const std = @import("std");

var global_instance_state: std.event.Loop = undefined;

// global markers for std.event.loop
// pub const io_mode = .evented; // auto deducted
pub const event_loop: *std.event.Loop = &global_instance_state;

pub fn main() !void {
    try maelstrom.run(event_loop, async_main);
}

fn async_main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests: {d}.\n", .{maelstrom.add(1, 2).answer});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

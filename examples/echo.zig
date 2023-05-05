const maelstrom = @import("maelstrom");
const std = @import("std");

pub const log = maelstrom.log.f;
pub const log_level = .debug;

pub fn main() !void {
    var runtime = try maelstrom.Runtime.init();
    try runtime.run();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

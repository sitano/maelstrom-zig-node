const std = @import("std");
const root = @import("root");

// root.log_level : std.log.Level = .debug;
//
// /// The current log level. This is set to root.log_level if present, otherwise
// /// log.default_level.
// pub const is_level_root_defined = @hasDecl(root, "log_level");
//
// pub fn init_log_level(allocator: std.mem.Allocator) !void {
//     if (is_level_root_defined) {
//         std.log.level = root.log_level;
//     } else if (try std.process.hasEnvVar(allocator, "LOG_LEVEL")) {
//         std.log.level = std.log.default_level;
//     } else {
//         std.log.level = std.log.default_level;
//     }
// }

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = message_level;
    _ = scope;
    _ = format;
    _ = args;
    // Implementation here
}

const maelstrom = @import("maelstrom");
const std = @import("std");

const Runtime = maelstrom.Runtime;
const Message = maelstrom.Message;
const Error = maelstrom.Error;

pub const log = maelstrom.log.f;
pub const log_level = .debug;

pub fn main() !void {
    var runtime = try Runtime.init();
    try runtime.run();
}

fn echo(self: *Runtime, req: *Message) Error!void {
    try self.reply_ok(req);
}

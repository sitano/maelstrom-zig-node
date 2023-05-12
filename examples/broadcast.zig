// zig build && ~/maelstrom/maelstrom test -w broadcast --bin ./zig-out/bin/broadcast --node-count 2 --time-limit 20 --rate 10 --log-stderr

const m = @import("maelstrom");
const std = @import("std");

pub const log = m.log.f;
pub const log_level = .debug;

pub fn main() !void {
    var runtime = try m.Runtime.init();
    try runtime.handle("read", read);
    try runtime.handle("broadcast", broadcast);
    try runtime.handle("topology", topology);
    try runtime.run();
}

fn read(self: m.ScopedRuntime, req: *m.Message) m.Error!void {
    self.reply_ok(req);
}

fn broadcast(self: m.ScopedRuntime, req: *m.Message) m.Error!void {
    self.reply_ok(req);
}

fn topology(self: m.ScopedRuntime, req: *m.Message) m.Error!void {
    // FIXME: oops sorry, compiler bug:
    //     panic: Zig compiler bug: attempted to destroy declaration with an attached error
    // const in = try m.proto.json_map_obj(Topology, self.alloc, req.body);
    const data = req.body.raw.Object.get("topology");
    if (data == null) return m.Error.MalformedRequest;
    std.log.info("got new topology: {s}", .{ std.json.stringifyAlloc(self.alloc, data, .{}) catch return m.Error.Abort });
    self.reply_ok(req);
}

const ReadOk = struct {
    messages: []u64,
};

const Broadcast = struct {
    message: u64,
};

const Topology = struct {
    topology: std.StringHashMap(std.ArrayList([]const u8)),
};

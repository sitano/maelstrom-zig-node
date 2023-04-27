const std = @import("std");

// TODO: how to display struct gracefully (strings)?
pub const Message = struct {
    src: []const u8,
    dest: []const u8,

    body: MessageBody,

    pub usingnamespace MessageMethods(@This());
};

pub const MessageBody = struct {
    typ: []const u8,
    msg_id: u64,
    in_reply_to: u64,

    raw: []const u8,

    pub usingnamespace MessageBodyMethods(@This());
};

pub const InitMessageBody = struct {
    node_id: []const u8,
    node_ids: [][]const u8,
};

pub fn parse_message(arena: *std.heap.ArenaAllocator, str: []const u8) !*Message {
    return Message.parse_into_arena(arena, str);
}

fn MessageMethods(comptime Self: type) type {
    return struct {
        pub fn parse_into_arena(arena: *std.heap.ArenaAllocator, str: []const u8) !*Message {
            var alloc = arena.allocator();
            const buf = try alloc.dupe(u8, str);

            var parser = std.json.Parser.init(alloc, false);
            defer parser.deinit();

            var tree = try parser.parse(buf);
            // we hope for arena allocator instead of defer tree.deinit();

            var m = try alloc.create(Message);
            m.* = Message.init();

            return try m.from_json(tree.root);
        }

        pub fn from_json(self: *Self, src0: ?std.json.Value) !*Message {
            if (src0 == null) return self;
            const src = src0.?;

            // TODO: replace .? with something safe
            self.src = src.Object.get("src").?.String;
            self.dest = src.Object.get("dest").?.String;
            _ = try self.body.from_json(src.Object.get("body"));

            return self;
        }

        pub fn init() Message {
            return Message{
                .src = "",
                .dest = "",
                .body = MessageBody.init(),
            };
        }
    };
}

fn MessageBodyMethods(comptime Self: type) type {
    return struct {
        pub fn from_json(self: *Self, src0: ?std.json.Value) !*MessageBody {
            if (src0 == null) return self;
            const src = src0.?;

            self.typ = try_json_string(src.Object.get("type"));

            return self;
        }

        pub fn init() MessageBody {
            return MessageBody{
                .typ = "",
                .msg_id = 0,
                .in_reply_to = 0,
                .raw = "",
            };
        }
    };
}

fn try_json_string(val: ?std.json.Value) []const u8 {
    if (val == null) return "";
    switch (val.?) {
        .String => |s| return s,
        else => return "",
    }
}

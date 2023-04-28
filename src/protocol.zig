const std = @import("std");

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

    raw: std.json.Value,

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

        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            
            var i: u32 = 0;
            if (value.src.len > 0) {
                try writer.writeAll(" \"src\": \"");
                try writer.writeAll(value.src);
                try writer.writeAll("\"");
                i += 1;
            } 

            if (value.dest.len > 0) {
                if (i > 0) try writer.writeAll(",");
                try writer.writeAll(" \"dest\": \"");
                try writer.writeAll(value.dest);
                try writer.writeAll("\"");
            } 

            if (i > 0) try writer.writeAll(",");
            try writer.writeAll(" \"body\": ");
            try value.body.format(fmt, options, writer);
            
            try writer.writeAll(" }");
        }

        pub fn to_json_value(self: Self, alloc: std.mem.Allocator) !std.json.Value {
            var v = std.json.Value{ .Object = std.json.ObjectMap.init(alloc)};
            if (self.src.len > 0)  try v.Object.put("src",  std.json.Value{ .String = self.src });
            if (self.dest.len > 0) try v.Object.put("dest", std.json.Value{ .String = self.dest });
            try v.Object.put("body", try self.to_json_value(alloc));
            return v;
        }
    };
}

fn MessageBodyMethods(comptime Self: type) type {
    return struct {
        pub fn from_json(self: *Self, src0: ?std.json.Value) !*MessageBody {
            if (src0 == null) return self;
            const src = src0.?;

            self.typ = try_json_string(src.Object.get("type"));
            self.msg_id = try_json_u64(src.Object.get("msg_id"));
            self.in_reply_to = try_json_u64(src.Object.get("in_reply_to"));
            self.raw = src;

            return self;
        }

        pub fn init() MessageBody {
            return MessageBody{
                .typ = "",
                .msg_id = 0,
                .in_reply_to = 0,
                .raw = .Null,
            };
        }

        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.writeAll("{");
            
            if (value.typ.len > 0) {
                try writer.writeAll(" \"type\": ");
                try std.json.stringify(value.typ, .{}, writer);
            }

            if (value.msg_id > 0) {
                try writer.writeAll(", \"msg_id\": ");
                try std.json.stringify(value.msg_id, .{}, writer);
            }

            if (value.in_reply_to > 0) {
                try writer.writeAll(", \"in_reply_to\": ");
                try std.json.stringify(value.in_reply_to, .{}, writer);
            }

            // TODO: merge raw

            try writer.writeAll(" }");
        }

        pub fn to_json_value(self: Self, alloc: std.mem.Allocator) !std.json.Value {
            var v = std.json.Value{ .Object = std.json.ObjectMap.init(alloc)};
            if (self.typ.len > 0) try v.Object.put("type", std.json.Value{ .String = self.typ });
            // TODO: ...
            return v;
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

fn try_json_u64(val: ?std.json.Value) u64 {
    if (val == null) return 0;
    switch (val.?) {
        .Integer => |s| return @intCast(u64, s),
        else => return 0,
    }
}

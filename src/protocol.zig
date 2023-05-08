const std = @import("std");
const root = @import("root");

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

    pub usingnamespace FormatAsJson(@This());
};

pub const ErrorMessageBody = struct {
    typ: []const u8,
    code: i64,
    text: []const u8,

    pub usingnamespace FormatAsJson(@This());
};

// buf must be allocated on arena. we would not clean or copy it.
pub fn parse_message(arena: *std.heap.ArenaAllocator, buf: []u8) !*Message {
    return Message.parse_into_arena(arena, buf);
}

fn MessageMethods(comptime Self: type) type {
    return struct {
        // buf must be allocated on arena. we would not clean or copy it.
        pub fn parse_into_arena(arena: *std.heap.ArenaAllocator, buf: []u8) !*Message {
            var alloc = arena.allocator();

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

            self.src = try_json_string(src.Object.get("src"));
            self.dest = try_json_string(src.Object.get("dest"));
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
            var v = std.json.Value{ .Object = std.json.ObjectMap.init(alloc) };
            if (self.src.len > 0) try v.Object.put("src", std.json.Value{ .String = self.src });
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

        pub fn to_json_value(self: Self, alloc: std.mem.Allocator) !std.json.Value {
            var v = std.json.Value{ .Object = std.json.ObjectMap.init(alloc) };

            if (self.typ.len > 0) try v.Object.put("type", std.json.Value{ .String = self.typ });
            if (self.msg_id > 0) try v.Object.put("msg_id", std.json.Value{ .Integer = @intCast(i64, self.msg_id) });
            if (self.in_reply_to > 0) try v.Object.put("in_reply_to", std.json.Value{ .Integer = @intCast(i64, self.in_reply_to) });

            try merge_json(&v, self.raw);

            return v;
        }
    };
}

fn FormatAsJson(comptime Self: type) type {
    return struct {
        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            // FIXME: this does not work in async IO until this fixed: https://github.com/ziglang/zig/issues/4060.
            try nosuspend std.json.stringify(value, .{}, writer);
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

const MergeJsonError = error{InvalidType};

/// merges src object into dst object.
pub fn merge_json(dst: *std.json.Value, src: std.json.Value) !void {
    switch (dst.*) {
        .Object => {},
        else => {
            return MergeJsonError.InvalidType;
        },
    }

    switch (src) {
        .Object => |inner| {
            var it = inner.iterator();
            while (it.next()) |entry| {
                try dst.Object.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        },
        else => {},
    }
}

/// all allocated memory belongs to the caller.
/// double serialization is not efficient, but we want to be simple right now.
/// until the std lib api will be able to handle it.
/// support override with to_json_value(Allocator).
pub fn to_json_value(arena: *std.heap.ArenaAllocator, value: anytype) !std.json.Value {
    var alloc = arena.allocator();

    const T = @TypeOf(value);
    const args_type_info = @typeInfo(T);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(T));
    }

    if (comptime std.meta.trait.hasFn("to_json_value")(T)) {
        return try value.to_json_value(alloc);
    }

    const str = try std.json.stringifyAlloc(alloc, value, .{});

    var parser = std.json.Parser.init(alloc, false);
    defer parser.deinit();

    const tree = try parser.parse(str);
    return tree.root;
}

/// merges a set of objects into a json Value.
///
///     merge_to_json(arena, .{body, .{ .code = 10, .text = "not supported" }});
pub fn merge_to_json(arena: *std.heap.ArenaAllocator, args: anytype) !std.json.Value {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.Struct.fields;
    const len = comptime fields_info.len;

    if (len == 0) {
        return std.json.Value{ .Object = std.json.ObjectMap.init(arena) };
    }

    comptime var i: usize = 0;
    var obj = try to_json_value(arena, @field(args, fields_info[i].name));

    i += 1;
    inline while (i < len) {
        var src = try to_json_value(arena, @field(args, fields_info[i].name));
        try merge_json(&obj, src);
        i += 1;
    }

    return obj;
}

test "merge_to_json works" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var body = MessageBody.init();

    var dst = try to_json_value(&arena, body);

    {
        const obj = dst; //try merge_json(&dst, std.json.Value{ .Null = void{} });
        const str = try std.json.stringifyAlloc(arena.allocator(), obj, .{});
        try std.testing.expectEqualStrings("{}", str);
    }

    body.msg_id = 1;
    body.in_reply_to = 2;
    body.typ = "init";
    body.raw = std.json.Value{ .Object = std.json.ObjectMap.init(arena.allocator()) };
    try body.raw.Object.put("raw_key", std.json.Value{ .Integer = 1 });

    {
        const obj = try to_json_value(&arena, body);
        const str = try std.json.stringifyAlloc(arena.allocator(), obj, .{});
        try std.testing.expectEqualStrings("{\"type\":\"init\",\"msg_id\":1,\"in_reply_to\":2,\"raw_key\":1}", str);
    }

    {
        const obj = try merge_to_json(&arena, .{ body, .{ .msg_id = 2, .text = "bbb" } });
        const str = try std.json.stringifyAlloc(arena.allocator(), obj, .{});
        try std.testing.expectEqualStrings("{\"type\":\"init\",\"msg_id\":2,\"in_reply_to\":2,\"raw_key\":1,\"text\":\"bbb\"}", str);
    }
}

const builtin = @import("builtin");
const std = @import("std");

pub const thread_safe: bool = !builtin.single_threaded;
pub const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

pub const Runtime = struct {
    // thread-safe by itself
    alloc: std.mem.Allocator,

    outm: std.Thread.Mutex,
    out: std.fs.File,

    m: MutexType,
    // log: TODO: @TypeOf(Scoped)

    // alloc is expected to be thread-safe by itself.
    pub fn init(alloc: std.mem.Allocator) Runtime {
        return .{
            .alloc = alloc,

            .outm = std.Thread.Mutex{},
            .out = std.io.getStdOut(),

            .m = MutexType{},
        };
    }

    pub fn send_raw(self: *Runtime, comptime fmt: []const u8, args: anytype) !void {
        self.outm.lock();
        defer self.outm.unlock();
        const out = self.out.writer();
        return out.print(fmt ++ "\n", args);
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
    }

    // in: std.io.Reader.{}
    // read buffer is 4kB.
    pub fn listen(self: *Runtime, in: anytype) !void {
        var buffer: [4096]u8 = undefined;

        while (nextLine(in, &buffer)) |try_line| {
            if (try_line == null) return;
            const line = try_line.?;

            try self.send_raw("{s}", .{line});
        } else |err| {
            return err;
        }
    }
};

const DummyMutex = struct {
    fn lock(_: *DummyMutex) void {}
    fn unlock(_: *DummyMutex) void {}
};

// reader: std.io.Reader.{}
fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;
    // trim annoying windows-only carriage return character
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}

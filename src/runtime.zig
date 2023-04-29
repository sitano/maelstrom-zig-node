const builtin = @import("builtin");
const proto = @import("protocol.zig");
const root = @import("root");
const std = @import("std");

pub const thread_safe: bool = !builtin.single_threaded;
pub const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

// FIXME: what we can do about those?
pub const read_buf_size = if (@hasDecl(root, "read_buf_size")) root.read_buf_size else 4096;
pub const write_buf_size = if (@hasDecl(root, "write_buf_size")) root.write_buf_size else 4096;

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

    pub fn send_raw(self: *Runtime, comptime fmt: []const u8, args: anytype) void {
        if (comptime std.io.is_async) {
            @panic("async IO in unsupported at least until 0.12.0. we need sync stdout. see the comment below.");
        }

        const out = self.out.writer();

        self.outm.lock();
        defer self.outm.unlock();
        // stdout.writer().print suspends in async io mode.
        // on Darwin a suspend point in the middle of mutex causes for 0.10.1:
        //     Illegal instruction at address 0x7ff80f6c1efc
        //     ???:?:?: 0x7ff80f6c1efc in ??? (???)
        //     zig/0.10.1/lib/zig/std/Thread/Mutex.zig:115:40: 0x10f60dd84 in std.Thread.Mutex.DarwinImpl.unlock (echo)
        //     os.darwin.os_unfair_lock_unlock(&self.oul);
        // FIXME: check if it works with 0.12.0 + darwin when its ready.
        nosuspend out.print(fmt ++ "\n", args) catch return;
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
    }

    // in: std.io.Reader.{}
    // read buffer is 4kB.
    pub fn listen(self: *Runtime, in: anytype) !void {
        var buffer: [read_buf_size]u8 = undefined;

        while (nextLine(in, &buffer)) |try_line| {
            if (try_line == null) return;
            const line = try_line.?;

            if (line.len == 0) continue;
            std.log.debug("Received {s}", .{line});

            var ap = std.heap.ArenaAllocator.init(self.alloc);
            if (proto.parse_message(&ap, line)) |m| {
                std.log.info(">> {}", .{m});

                // TODO: remove this
                self.send_raw("{s}", .{line});
            } else |err| {
                std.log.err("incoming message parsing error: {}", .{err});
            }
            ap.deinit();
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

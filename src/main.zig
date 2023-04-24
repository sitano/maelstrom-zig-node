const builtin = @import("builtin");
const print = @import("std").debug.print;
const std = @import("std");
const testing = std.testing;

const thread_safe: bool = !builtin.single_threaded;
const MutexType: type = @TypeOf(if (thread_safe) std.Thread.Mutex{} else DummyMutex{});

pub fn run(loop: *std.event.Loop, comptime func: anytype) !void {
    // maelstrom requires async io.
    //
    // to tell runtime we want async io define the following in root ns:
    //     pub const io_mode = .evented; // auto deducted, or
    //     var global_instance_state: std.event.Loop = undefined;
    //     pub const event_loop: *std.event.Loop = &global_instance_state;
    //
    // async io also requires enabling stage1 compiler.
    if (!std.io.is_async)
        @panic("io is not async. see code comment to fix.");

    if (builtin.single_threaded) {
        try loop.initSingleThreaded();
    } else {
        try loop.initMultiThreaded();
    }
    defer loop.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var runtime = Runtime.init(arena.allocator());
    defer runtime.deinit();

    const Wrapper = struct {
        fn run(rt: *Runtime) void {
            func(rt) catch |e| {
                std.debug.panic("main func error: {}", .{e});
            };

            std.debug.print("node started.\n", .{});

            listen(std.io.getStdIn().reader(), rt) catch |e| {
                std.debug.print("listen loop error: {}", .{e});
            };
        }
    };

    try loop.runDetached(runtime.arena, Wrapper.run, .{&runtime});

    loop.run();

    std.debug.print("node finished.\n", .{});
}

// in: std.io.Reader.{}
// read buffer is 4kB.
pub fn listen(in: anytype, runtime: *Runtime) !void {
    var buffer: [4096]u8 = undefined;

    while (nextLine(in, &buffer)) |try_line| {
        if (try_line == null) return;
        const line = try_line.?;

        try runtime.out.writer().print("{s}\n", .{line});
    } else |err| {
        return err;
    }
}

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

pub const Runtime = struct {
    m: MutexType,
    arena: std.mem.Allocator,
    out: std.fs.File,

    pub fn init(arena: std.mem.Allocator) Runtime {
        return .{
            .m = MutexType{},
            .arena = arena,
            .out = std.io.getStdOut(),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.m.lock();
        defer self.m.unlock();
    }
};

const DummyMutex = struct {
    fn lock(_: *DummyMutex) void {}
    fn unlock(_: *DummyMutex) void {}
};

pub const Result = struct {
    answer: i32,
};

pub fn add(a: i32, b: i32) Result {
    return Result{ .answer = a + b };
}

test "basic add functionality" {
    try testing.expect(add(3, 7).answer == 10);
}

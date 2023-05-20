const m = @import("runtime.zig");
const errors = @import("error.zig");

const Error = errors.HandlerError;

pub const LinKind = "lin-kv";
pub const SeqKind = "seq-kv";
pub const LWWKind = "lww-kv";
pub const TSOKind = "lin-tso";

pub const Storage = struct {
    kind: []const u8,

    pub fn init(kind: []const u8) Storage {
        return Storage{
            .kind = kind,
        };
    }

    pub fn init_lin_kv() Storage {
        return Storage.init(LinKind);
    }

    pub fn init_seq_kv() Storage {
        return Storage.init(SeqKind);
    }

    pub fn init_lww_kv() Storage {
        return Storage.init(LWWKind);
    }

    pub fn init_tso_kv() Storage {
        return Storage.init(TSOKind);
    }

    pub fn get(self: *Storage, runtime: m.ScopedRuntime, key: []const u8, comptime value_type: type, wait_ns: u64) Error!value_type {
        _ = wait_ns;
        _ = key;
        _ = runtime;
        _ = self;
        return Error.Abort;
    }

    pub fn put(self: *Storage, runtime: m.ScopedRuntime, key: []const u8, value: anytype, wait_ns: u64) Error!void {
        _ = value;
        _ = wait_ns;
        _ = key;
        _ = runtime;
        _ = self;
    }

    pub fn cas(self: *Storage, runtime: m.ScopedRuntime, key: []const u8, from: anytype, to: anytype, putIfAbsent: bool, wait_ns: u64) Error!void {
        _ = putIfAbsent;
        _ = to;
        _ = from;
        _ = wait_ns;
        _ = key;
        _ = runtime;
        _ = self;
    }
};

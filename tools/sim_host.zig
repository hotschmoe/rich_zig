const std = @import("std");
const assert = @import("assert").assert;
const rich = @import("rich_zig");
const host_mod = rich.host;

pub const capture_max: u32 = 1 << 21;
pub const env_entries_max: u32 = 12;
pub const env_name_max: u32 = 16;
pub const env_text_max: u32 = 48;
pub const input_max: u32 = 4096;
pub const zero_streak_max: u32 = 3;

pub const EnvEntry = struct {
    name: [env_name_max]u8 = undefined,
    name_length: u8 = 0,
    value: [env_text_max]u8 = undefined,
    value_length: u8 = 0,
};

pub const Env = struct {
    entries: [env_entries_max]EnvEntry = undefined,
    count: u32 = 0,

    pub fn set(self: *Env, name: []const u8, value: []const u8) void {
        assert(name.len > 0 and name.len <= env_name_max);
        assert(value.len <= env_text_max);
        assert(self.count < env_entries_max);
        var entry: EnvEntry = .{};
        @memcpy(entry.name[0..name.len], name);
        entry.name_length = @intCast(name.len);
        @memcpy(entry.value[0..value.len], value);
        entry.value_length = @intCast(value.len);
        self.entries[self.count] = entry;
        self.count += 1;
    }

    pub fn find(self: *const Env, name: []const u8) ?[]const u8 {
        assert(self.count <= env_entries_max);
        assert(name.len > 0);
        for (self.entries[0..self.count]) |*entry| {
            if (std.mem.eql(u8, entry.name[0..entry.name_length], name)) {
                return entry.value[0..entry.value_length];
            }
        }
        return null;
    }
};

pub const Config = struct {
    columns: u16 = 80,
    rows: u16 = 24,
    stdout_tty: bool = false,
    stderr_tty: bool = false,
    stdin_tty: bool = false,
    legacy_windows: bool = false,
    password_ok: bool = true,
    pager_ok: bool = true,
    env: Env = .{},
};

pub const Capture = struct {
    bytes: []u8,
    length: u32 = 0,
    overflowed: bool = false,

    fn append(self: *Capture, data: []const u8) void {
        assert(self.length <= self.bytes.len);
        assert(self.bytes.len <= capture_max);
        const room = self.bytes.len - self.length;
        const count = @min(room, data.len);
        @memcpy(self.bytes[self.length..][0..count], data[0..count]);
        self.length += @intCast(count);
        if (count < data.len) self.overflowed = true;
        assert(self.length <= self.bytes.len);
    }

    pub fn slice(self: *const Capture) []const u8 {
        return self.bytes[0..self.length];
    }
};

pub const Ledger = struct {
    write_calls: u32 = 0,
    failures: u32 = 0,
    accepted_after_failure: u32 = 0,
    short_writes: u32 = 0,
    waits: u32 = 0,
    pager_calls: u32 = 0,
    password_modes: u32 = 0,
    input_bytes_read: u32 = 0,
};

pub const SimHost = struct {
    config: Config,
    out: Capture,
    err: Capture,
    input: [input_max]u8 = undefined,
    input_length: u32 = 0,
    input_position: u32 = 0,
    mono_ns: i64 = 0,
    wall_ns: i64 = 0,
    mono_offset_ns: i64 = 0,
    fail_writes: u32 = 0,
    short_writes: u32 = 0,
    zero_streak: u32 = 0,
    prng: std.Random.DefaultPrng,
    ledger: Ledger = .{},
    failed_in_step: bool = false,
    password_hidden: bool = false,

    const vtable: host_mod.VTable = .{
        .write = write,
        .flush = flush,
        .read = read,
        .probe = probe,
        .size = size,
        .env_get = env_get,
        .set_mode = set_mode,
        .now = now,
        .wait = wait,
        .page = page,
        .read_file = read_file,
    };

    pub fn host(self: *SimHost) host_mod.Host {
        return .{ .ctx = self, .vtable = &vtable };
    }

    pub fn begin_step(self: *SimHost) void {
        assert(self.out.length <= capture_max and self.err.length <= capture_max);
        self.ledger = .{};
        self.failed_in_step = false;
        assert(self.ledger.failures == 0);
    }

    pub fn clear_input(self: *SimHost) void {
        assert(self.input_position <= self.input_length);
        self.input_length = 0;
        self.input_position = 0;
    }

    pub fn push_input(self: *SimHost, data: []const u8) void {
        const room = input_max - self.input_length;
        const count: u32 = @intCast(@min(room, data.len));
        assert(self.input_length <= input_max);
        @memcpy(self.input[self.input_length..][0..count], data[0..count]);
        self.input_length += count;
        assert(self.input_position <= self.input_length);
    }

    fn from(ctx: ?*anyopaque) *SimHost {
        assert(ctx != null);
        assert(@intFromPtr(ctx.?) % @alignOf(SimHost) == 0);
        return @ptrCast(@alignCast(ctx.?));
    }

    fn write(ctx: ?*anyopaque, stream: host_mod.Stream, bytes: []const u8) host_mod.Error!usize {
        const self = from(ctx);
        assert(bytes.len > 0);
        self.ledger.write_calls += 1;
        if (self.fail_writes > 0) {
            self.fail_writes -= 1;
            self.ledger.failures += 1;
            self.failed_in_step = true;
            return error.WriteFailed;
        }
        var count = bytes.len;
        if (self.short_writes > 0) {
            self.short_writes -= 1;
            count = self.short_count(bytes.len);
            self.ledger.short_writes += 1;
        }
        if (self.failed_in_step) self.ledger.accepted_after_failure += @intCast(count);
        const capture = switch (stream) {
            .stdout => &self.out,
            .stderr => &self.err,
        };
        capture.append(bytes[0..count]);
        assert(count <= bytes.len);
        return count;
    }

    fn short_count(self: *SimHost, length: usize) usize {
        assert(length > 0);
        const random = self.prng.random();
        const pick: usize = random.uintLessThan(usize, length);
        if (pick == 0 and self.zero_streak < zero_streak_max) {
            self.zero_streak += 1;
            return 0;
        }
        self.zero_streak = 0;
        assert(pick < length);
        return @max(pick, 1);
    }

    fn flush(ctx: ?*anyopaque, stream: host_mod.Stream) host_mod.Error!void {
        const self = from(ctx);
        assert(@backingInt(stream) <= @backingInt(host_mod.Stream.stderr));
        assert(self.out.length <= capture_max);
    }

    fn read(ctx: ?*anyopaque, buffer: []u8) host_mod.Error!usize {
        const self = from(ctx);
        assert(buffer.len > 0);
        const left = self.input_length - self.input_position;
        const count: u32 = @intCast(@min(left, buffer.len));
        @memcpy(buffer[0..count], self.input[self.input_position..][0..count]);
        self.input_position += count;
        self.ledger.input_bytes_read += count;
        assert(self.input_position <= self.input_length);
        return count;
    }

    fn probe(ctx: ?*anyopaque, capability: host_mod.Capability) bool {
        const self = from(ctx);
        assert(self.config.env.count <= env_entries_max);
        assert(self.out.length <= capture_max);
        return switch (capability) {
            .stdout_terminal => self.config.stdout_tty,
            .stderr_terminal => self.config.stderr_tty,
            .stdin_terminal => self.config.stdin_tty,
            .virtual_terminal => !self.config.legacy_windows,
        };
    }

    fn size(ctx: ?*anyopaque) ?host_mod.Size {
        const self = from(ctx);
        if (!self.config.stdout_tty) return null;
        if (self.config.columns == 0 or self.config.rows == 0) return null;
        assert(self.config.columns > 0 and self.config.rows > 0);
        assert(self.out.bytes.len > 0);
        return .{ .columns = self.config.columns, .rows = self.config.rows };
    }

    fn env_get(ctx: ?*anyopaque, name: []const u8, out: []u8) ?[]const u8 {
        const self = from(ctx);
        assert(out.len > 0);
        assert(name.len > 0);
        const value = self.config.env.find(name) orelse return null;
        const count = @min(value.len, out.len);
        @memcpy(out[0..count], value[0..count]);
        assert(count <= env_text_max);
        return out[0..count];
    }

    fn set_mode(ctx: ?*anyopaque, mode: host_mod.Mode, enabled: bool) bool {
        const self = from(ctx);
        assert(!self.password_hidden or self.config.password_ok);
        assert(self.ledger.password_modes < 1_000_000);
        switch (mode) {
            .virtual_terminal => return enabled and !self.config.legacy_windows,
            .utf8_output => return enabled,
            .password_input => {
                if (!enabled) {
                    const was_hidden = self.password_hidden;
                    self.password_hidden = false;
                    return was_hidden;
                }
                self.ledger.password_modes += 1;
                self.password_hidden = self.config.password_ok;
                return self.password_hidden;
            },
        }
    }

    fn now(ctx: ?*anyopaque, clock: host_mod.Clock) i64 {
        const self = from(ctx);
        const value = switch (clock) {
            .monotonic => self.mono_ns +| self.mono_offset_ns,
            .wall => self.wall_ns,
        };
        assert(self.mono_ns >= 0);
        assert(clock == .wall or value >= 0);
        return value;
    }

    fn wait(ctx: ?*anyopaque, nanoseconds: u64) host_mod.Error!void {
        const self = from(ctx);
        const step: i64 = @intCast(@min(nanoseconds, std.math.maxInt(i32)));
        self.mono_ns +|= step;
        self.wall_ns +|= step;
        self.ledger.waits += 1;
        assert(self.ledger.waits > 0);
        assert(step <= std.math.maxInt(i32));
    }

    fn page(ctx: ?*anyopaque, command: []const u8, content: []const u8) bool {
        const self = from(ctx);
        assert(command.len > 0);
        self.ledger.pager_calls += 1;
        assert(content.len < capture_max);
        return self.config.pager_ok;
    }

    fn read_file(
        ctx: ?*anyopaque,
        path: []const u8,
        offset: u64,
        out: []u8,
    ) host_mod.Error!usize {
        assert(ctx != null);
        assert(out.len > 0);
        _ = path;
        _ = offset;
        return error.FileUnavailable;
    }
};

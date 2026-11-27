const std = @import("std");
const assert = @import("assert").assert;
const real_host = @import("host_real.zig");

pub const Stream = enum(u8) { stdout, stderr };
pub const Clock = enum(u8) { monotonic, wall };
pub const Mode = enum(u8) { virtual_terminal, utf8_output, password_input };
pub const Capability = enum(u8) {
    stdout_terminal,
    stderr_terminal,
    stdin_terminal,
    virtual_terminal,
};

pub const Size = struct { columns: u16, rows: u16 };

pub const Error = error{
    WriteFailed,
    ReadFailed,
    Interrupted,
    FileUnavailable,
    LineTooLong,
};

pub const ReadFileError = Error || error{ OutOfMemory, FileTooLarge };

pub const env_value_max: u32 = 256;
pub const write_stall_max: u32 = 8;
pub const file_chunk_max: u32 = 4096;

pub const VTable = struct {
    write: *const fn (ctx: ?*anyopaque, stream: Stream, bytes: []const u8) Error!usize,
    flush: *const fn (ctx: ?*anyopaque, stream: Stream) Error!void,
    read: *const fn (ctx: ?*anyopaque, buffer: []u8) Error!usize,
    probe: *const fn (ctx: ?*anyopaque, capability: Capability) bool,
    size: *const fn (ctx: ?*anyopaque) ?Size,
    env_get: *const fn (ctx: ?*anyopaque, name: []const u8, out: []u8) ?[]const u8,
    set_mode: *const fn (ctx: ?*anyopaque, mode: Mode, enabled: bool) bool,
    now: *const fn (ctx: ?*anyopaque, clock: Clock) i64,
    wait: *const fn (ctx: ?*anyopaque, nanoseconds: u64) Error!void,
    page: *const fn (ctx: ?*anyopaque, command: []const u8, content: []const u8) bool,
    read_file: *const fn (
        ctx: ?*anyopaque,
        path: []const u8,
        offset: u64,
        out: []u8,
    ) Error!usize,
};

pub const Host = struct {
    ctx: ?*anyopaque,
    vtable: *const VTable,

    pub fn write(self: Host, stream: Stream, bytes: []const u8) Error!usize {
        return self.vtable.write(self.ctx, stream, bytes);
    }

    pub fn write_all(self: Host, stream: Stream, bytes: []const u8) Error!void {
        var index: usize = 0;
        var stalled: u32 = 0;
        while (index < bytes.len) {
            const count = try self.vtable.write(self.ctx, stream, bytes[index..]);
            assert(count <= bytes.len - index);
            if (count == 0) {
                stalled += 1;
                if (stalled >= write_stall_max) return error.WriteFailed;
            } else {
                stalled = 0;
            }
            index += count;
            assert(stalled < write_stall_max);
        }
        assert(index == bytes.len);
    }

    pub fn flush(self: Host, stream: Stream) Error!void {
        return self.vtable.flush(self.ctx, stream);
    }

    pub fn read(self: Host, buffer: []u8) Error!usize {
        return self.vtable.read(self.ctx, buffer);
    }

    pub fn probe(self: Host, capability: Capability) bool {
        return self.vtable.probe(self.ctx, capability);
    }

    pub fn size(self: Host) ?Size {
        return self.vtable.size(self.ctx);
    }

    pub fn env_get(self: Host, name: []const u8, out: []u8) ?[]const u8 {
        return self.vtable.env_get(self.ctx, name, out);
    }

    pub fn set_mode(self: Host, mode: Mode, enabled: bool) bool {
        return self.vtable.set_mode(self.ctx, mode, enabled);
    }

    pub fn now(self: Host, clock: Clock) i64 {
        return self.vtable.now(self.ctx, clock);
    }

    pub fn wait(self: Host, nanoseconds: u64) Error!void {
        return self.vtable.wait(self.ctx, nanoseconds);
    }

    pub fn page(self: Host, command: []const u8, content: []const u8) bool {
        return self.vtable.page(self.ctx, command, content);
    }

    pub fn read_file(self: Host, path: []const u8, offset: u64, out: []u8) Error!usize {
        return self.vtable.read_file(self.ctx, path, offset, out);
    }

    pub fn read_line(self: Host, buffer: []u8) Error!?[]u8 {
        assert(buffer.len > 0);
        var length: usize = 0;
        while (length < buffer.len) {
            var byte: [1]u8 = undefined;
            const count = try self.vtable.read(self.ctx, &byte);
            assert(count <= 1);
            if (count == 0) return if (length == 0) null else buffer[0..length];
            if (byte[0] == '\n') return buffer[0..length];
            buffer[length] = byte[0];
            length += 1;
            assert(length <= buffer.len);
        }
        assert(length == buffer.len);
        return error.LineTooLong;
    }

    pub fn read_file_alloc(
        self: Host,
        allocator: std.mem.Allocator,
        path: []const u8,
        limit: u32,
    ) ReadFileError![]u8 {
        assert(limit > 0);
        assert(path.len > 0);
        var content: std.ArrayList(u8) = .empty;
        errdefer content.deinit(allocator);
        var chunk: [file_chunk_max]u8 = undefined;
        while (content.items.len <= limit) {
            const offset: u64 = content.items.len;
            const count = try self.vtable.read_file(self.ctx, path, offset, &chunk);
            assert(count <= chunk.len);
            if (count == 0) return content.toOwnedSlice(allocator);
            try content.appendSlice(allocator, chunk[0..count]);
            assert(content.items.len <= limit + chunk.len);
        }
        assert(content.items.len > limit);
        return error.FileTooLarge;
    }
};

pub const Source = union(enum) {
    real: real_host.Real,
    custom: Host,

    pub fn from_io(io: std.Io, environ: std.process.Environ) Source {
        return .{ .real = real_host.Real.init(io, environ) };
    }

    pub fn host(self: *Source) Host {
        return switch (self.*) {
            .real => |*real| real.host(),
            .custom => |custom| custom,
        };
    }

    pub fn now(self: Source, clock: Clock) i64 {
        var copy = self;
        const value = copy.host().now(clock);
        assert(clock == .wall or value >= 0);
        return value;
    }
};

pub const HostWriter = struct {
    host: Host,
    stream: Stream,
    failed: bool = false,
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = flush_all };

    pub fn init(host: Host, stream: Stream, buffer: []u8) HostWriter {
        return .{
            .host = host,
            .stream = stream,
            .interface = .{ .vtable = &vtable, .buffer = buffer },
        };
    }

    fn send(self: *HostWriter, bytes: []const u8) std.Io.Writer.Error!void {
        assert(bytes.len <= std.math.maxInt(u32) * 4);
        if (self.failed) return error.WriteFailed;
        self.host.write_all(self.stream, bytes) catch {
            self.failed = true;
            return error.WriteFailed;
        };
    }

    fn drain(
        writer: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const self: *HostWriter = @fieldParentPtr("interface", writer);
        assert(data.len > 0);
        assert(writer.end <= writer.buffer.len);
        try self.send(writer.buffer[0..writer.end]);
        writer.end = 0;
        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.send(bytes);
            consumed += bytes.len;
        }
        const last = data[data.len - 1];
        if (last.len == 1) {
            var chunk: [64]u8 = undefined;
            @memset(&chunk, last[0]);
            var remaining = splat;
            while (remaining > 0) {
                const count = @min(remaining, chunk.len);
                try self.send(chunk[0..count]);
                remaining -= count;
            }
            consumed += splat;
        } else {
            for (0..splat) |_| try self.send(last);
            consumed += last.len * splat;
        }
        assert(writer.end == 0);
        return consumed;
    }

    fn flush_all(writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *HostWriter = @fieldParentPtr("interface", writer);
        try std.Io.Writer.defaultFlush(writer);
        assert(writer.end == 0);
        if (self.failed) return error.WriteFailed;
        self.host.flush(self.stream) catch {
            self.failed = true;
            return error.WriteFailed;
        };
    }
};

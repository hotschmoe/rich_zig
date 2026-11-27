const std = @import("std");
const builtin = @import("builtin");
const assert = @import("assert").assert;
const host_mod = @import("host.zig");
const Host = host_mod.Host;
const Stream = host_mod.Stream;
const Error = host_mod.Error;

const is_windows = builtin.os.tag == .windows;
const has_termios = !is_windows and builtin.os.tag != .wasi and
    builtin.os.tag != .freestanding and builtin.cpu.arch != .wasm32;
const has_winsize = !is_windows and @hasDecl(std.posix, "winsize") and has_termios;
const Saved = if (has_termios) std.posix.termios else u32;
const vt_flag: u32 = 0x0004;
const echo_and_line_flags: u32 = 0x0004 | 0x0002;

const win32 = if (is_windows) struct {
    const w = std.os.windows;

    const SMALL_RECT = extern struct {
        Left: w.SHORT,
        Top: w.SHORT,
        Right: w.SHORT,
        Bottom: w.SHORT,
    };

    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: w.COORD,
        dwCursorPosition: w.COORD,
        wAttributes: w.WORD,
        srWindow: SMALL_RECT,
        dwMaximumWindowSize: w.COORD,
    };

    extern "kernel32" fn GetConsoleMode(h: w.HANDLE, mode: *w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleMode(h: w.HANDLE, mode: w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleOutputCP(page: w.UINT) callconv(.winapi) w.BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(
        h: w.HANDLE,
        info: *CONSOLE_SCREEN_BUFFER_INFO,
    ) callconv(.winapi) w.BOOL;
    extern "kernel32" fn ReadConsoleA(
        h: w.HANDLE,
        buffer: [*]u8,
        count: w.DWORD,
        read: *w.DWORD,
        control: ?*anyopaque,
    ) callconv(.winapi) w.BOOL;
} else struct {};

pub const Real = struct {
    io: std.Io,
    environ: std.process.Environ,
    saved_input: Saved = undefined,
    input_hidden: bool = false,

    pub fn init(io: std.Io, environ: std.process.Environ) Real {
        return .{ .io = io, .environ = environ };
    }

    pub fn host(self: *Real) Host {
        return .{ .ctx = self, .vtable = &vtable };
    }
};

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

pub const LockedStderr = struct {
    writer: *std.Io.Writer,
    colors: bool,
    wall_seconds: i64,

    pub fn unlock(self: LockedStderr) void {
        assert(self.wall_seconds >= 0);
        assert(self.writer.end == 0);
        std.debug.unlockStderr();
    }
};

pub fn lock_stderr(buffer: []u8) LockedStderr {
    assert(buffer.len > 0);
    const locked = std.debug.lockStderr(buffer);
    const now_seconds = std.Io.Timestamp.now(std.Options.debug_io, .real).toSeconds();
    const writer = &locked.file_writer.interface;
    assert(writer.buffer.len > 0);
    assert(writer.end == 0);
    return .{
        .writer = writer,
        .colors = locked.terminal_mode != .no_color,
        .wall_seconds = @max(now_seconds, 0),
    };
}

pub fn enable_virtual_terminal() bool {
    return !is_windows or set_virtual_terminal();
}

fn set_virtual_terminal() bool {
    assert(is_windows);
    const handle = std.Io.File.stdout().handle;
    var mode: std.os.windows.DWORD = 0;
    if (!win32.GetConsoleMode(handle, &mode).toBool()) return false;
    const enabled = win32.SetConsoleMode(handle, mode | vt_flag).toBool();
    assert(!enabled or virtual_terminal_active());
    return enabled;
}

pub fn enable_utf8() bool {
    return !is_windows or win32.SetConsoleOutputCP(65001).toBool();
}

fn self_of(ctx: ?*anyopaque) *Real {
    assert(ctx != null);
    assert(@intFromPtr(ctx.?) % @alignOf(Real) == 0);
    return @ptrCast(@alignCast(ctx.?));
}

fn file_of(stream: Stream) std.Io.File {
    return switch (stream) {
        .stdout => std.Io.File.stdout(),
        .stderr => std.Io.File.stderr(),
    };
}

fn write(ctx: ?*anyopaque, stream: Stream, bytes: []const u8) Error!usize {
    const self = self_of(ctx);
    assert(bytes.len > 0);
    const count = file_of(stream).writeStreaming(self.io, &.{}, &.{bytes}, 1) catch {
        return error.WriteFailed;
    };
    assert(count <= bytes.len);
    assert(count > 0 or bytes.len > 0);
    return count;
}

fn flush(ctx: ?*anyopaque, stream: Stream) Error!void {
    assert(ctx != null);
    assert(@backingInt(stream) <= @backingInt(Stream.stderr));
}

fn read(ctx: ?*anyopaque, buffer: []u8) Error!usize {
    const self = self_of(ctx);
    assert(buffer.len > 0);
    assert(!self.input_hidden or buffer.len >= 1);
    if (is_windows and self.input_hidden) return read_console(buffer);
    const count = std.Io.File.stdin().readStreaming(self.io, &.{buffer}) catch |err| {
        return switch (err) {
            error.EndOfStream => 0,
            else => error.ReadFailed,
        };
    };
    assert(count <= buffer.len);
    return count;
}

fn read_console(buffer: []u8) Error!usize {
    if (!is_windows) return error.ReadFailed;
    assert(buffer.len > 0);
    var count: std.os.windows.DWORD = 0;
    const handle = std.Io.File.stdin().handle;
    const length: std.os.windows.DWORD = @intCast(@min(buffer.len, 1));
    if (!win32.ReadConsoleA(handle, buffer.ptr, length, &count, null).toBool()) {
        return error.ReadFailed;
    }
    assert(count <= length);
    return count;
}

fn is_terminal(file: std.Io.File) bool {
    if (is_windows) {
        var mode: std.os.windows.DWORD = 0;
        return win32.GetConsoleMode(file.handle, &mode).toBool();
    }
    if (!has_winsize) return false;
    var ws: std.posix.winsize = undefined;
    const request = std.posix.T.IOCGWINSZ;
    return std.posix.system.ioctl(file.handle, request, @intFromPtr(&ws)) == 0;
}

fn probe(ctx: ?*anyopaque, capability: host_mod.Capability) bool {
    assert(ctx != null);
    return switch (capability) {
        .stdout_terminal => is_terminal(std.Io.File.stdout()),
        .stderr_terminal => is_terminal(std.Io.File.stderr()),
        .stdin_terminal => is_terminal(std.Io.File.stdin()),
        .virtual_terminal => virtual_terminal_active(),
    };
}

fn virtual_terminal_active() bool {
    if (!is_windows) return true;
    var mode: std.os.windows.DWORD = 0;
    const handle = std.Io.File.stdout().handle;
    if (!win32.GetConsoleMode(handle, &mode).toBool()) return false;
    return mode & vt_flag != 0;
}

fn size(ctx: ?*anyopaque) ?host_mod.Size {
    assert(ctx != null);
    if (is_windows) return size_windows();
    if (!has_winsize) return null;
    var ws: std.posix.winsize = undefined;
    const handle = std.Io.File.stdout().handle;
    const request = std.posix.T.IOCGWINSZ;
    if (std.posix.system.ioctl(handle, request, @intFromPtr(&ws)) != 0) return null;
    if (ws.col == 0 or ws.row == 0) return null;
    assert(ws.col > 0 and ws.row > 0);
    return .{ .columns = ws.col, .rows = ws.row };
}

fn size_windows() ?host_mod.Size {
    if (!is_windows) return null;
    var info: win32.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (!win32.GetConsoleScreenBufferInfo(std.Io.File.stdout().handle, &info).toBool()) {
        return null;
    }
    const columns = info.srWindow.Right - info.srWindow.Left + 1;
    const rows = info.srWindow.Bottom - info.srWindow.Top + 1;
    if (columns <= 0 or rows <= 0) return null;
    assert(columns <= std.math.maxInt(u16) and rows <= std.math.maxInt(u16));
    return .{ .columns = @intCast(columns), .rows = @intCast(rows) };
}

fn env_get(ctx: ?*anyopaque, name: []const u8, out: []u8) ?[]const u8 {
    const self = self_of(ctx);
    assert(out.len > 0);
    assert(std.mem.indexOfScalar(u8, name, '=') == null);
    if (is_windows) return env_get_windows(self.environ, name, out);
    if (std.process.Environ.Block != std.process.Environ.PosixBlock) return null;
    assert(name.len > 0);
    const value = std.process.Environ.getPosix(self.environ, name) orelse return null;
    const length = @min(value.len, out.len);
    @memcpy(out[0..length], value[0..length]);
    assert(length <= out.len);
    return out[0..length];
}

fn env_get_windows(environ: std.process.Environ, name: []const u8, out: []u8) ?[]const u8 {
    if (!is_windows) return null;
    assert(out.len > 0);
    assert(std.mem.indexOfScalar(u8, name, 0) == null);
    var name_w: [256]u16 = undefined;
    const name_length = std.unicode.utf8ToUtf16Le(&name_w, name) catch return null;
    if (name_length >= name_w.len) return null;
    name_w[name_length] = 0;
    const key: [*:0]const u16 = name_w[0..name_length :0].ptr;
    const value = std.process.Environ.getWindows(environ, key) orelse return null;
    var length: usize = 0;
    var index: usize = 0;
    while (index < value.len) {
        const units: usize = if (std.unicode.utf16IsHighSurrogate(value[index])) 2 else 1;
        if (index + units > value.len) break;
        const units_slice = value[index..][0..units];
        const encoded = std.unicode.utf16LeToUtf8(out[length..], units_slice) catch break;
        length += encoded;
        index += units;
    }
    assert(length <= out.len);
    return out[0..length];
}

fn set_mode(ctx: ?*anyopaque, mode: host_mod.Mode, enabled: bool) bool {
    const self = self_of(ctx);
    return switch (mode) {
        .virtual_terminal => enabled and enable_virtual_terminal(),
        .utf8_output => enabled and enable_utf8(),
        .password_input => if (enabled) hide_input(self) else show_input(self),
    };
}

fn hide_input(self: *Real) bool {
    assert(!self.input_hidden);
    const handle = std.Io.File.stdin().handle;
    if (is_windows) {
        var mode: std.os.windows.DWORD = 0;
        if (!win32.GetConsoleMode(handle, &mode).toBool()) return false;
        self.saved_input = mode;
        if (!win32.SetConsoleMode(handle, mode & ~echo_and_line_flags).toBool()) return false;
    } else if (has_termios) {
        const posix = std.posix;
        if (posix.system.tcgetattr(handle, &self.saved_input) != 0) return false;
        var hidden = self.saved_input;
        hidden.lflag.ECHO = false;
        if (posix.system.tcsetattr(handle, .FLUSH, &hidden) != 0) return false;
    } else {
        return false;
    }
    self.input_hidden = true;
    assert(self.input_hidden);
    return true;
}

fn show_input(self: *Real) bool {
    if (!self.input_hidden) return false;
    const handle = std.Io.File.stdin().handle;
    self.input_hidden = false;
    assert(!self.input_hidden);
    if (is_windows) return win32.SetConsoleMode(handle, self.saved_input).toBool();
    if (has_termios) return std.posix.system.tcsetattr(handle, .FLUSH, &self.saved_input) == 0;
    return false;
}

fn now(ctx: ?*anyopaque, clock: host_mod.Clock) i64 {
    const self = self_of(ctx);
    const stamp = switch (clock) {
        .monotonic => std.Io.Timestamp.now(self.io, .awake),
        .wall => std.Io.Timestamp.now(self.io, .real),
    };
    const limit_low = std.math.minInt(i64);
    const limit_high = std.math.maxInt(i64);
    const value: i64 = @intCast(std.math.clamp(stamp.nanoseconds, limit_low, limit_high));
    assert(clock == .wall or value >= 0);
    const clamped = stamp.nanoseconds > limit_high or stamp.nanoseconds < limit_low;
    assert(value == stamp.nanoseconds or clamped);
    return value;
}

fn wait(ctx: ?*anyopaque, nanoseconds: u64) Error!void {
    const self = self_of(ctx);
    assert(nanoseconds <= std.math.maxInt(i64));
    const duration: std.Io.Duration = .fromNanoseconds(nanoseconds);
    std.Io.sleep(self.io, duration, .awake) catch return error.Interrupted;
}

fn page(ctx: ?*anyopaque, command: []const u8, content: []const u8) bool {
    const self = self_of(ctx);
    assert(command.len > 0);
    assert(std.mem.indexOfScalar(u8, command, 0) == null);
    var child = std.process.spawn(self.io, .{ .argv = &.{command}, .stdin = .pipe }) catch {
        return false;
    };
    defer child.kill(self.io);
    const stdin = child.stdin.?;
    var writer = stdin.writerStreaming(self.io, &.{});
    writer.interface.writeAll(content) catch return false;
    stdin.close(self.io);
    child.stdin = null;
    const term = child.wait(self.io) catch return false;
    assert(child.stdin == null);
    return term.success();
}

fn read_file(ctx: ?*anyopaque, path: []const u8, offset: u64, out: []u8) Error!usize {
    const self = self_of(ctx);
    assert(out.len > 0);
    assert(offset <= std.math.maxInt(i64));
    assert(std.mem.indexOfScalar(u8, path, 0) == null);
    const file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return error.FileUnavailable;
    defer file.close(self.io);
    assert(path.len > 0);
    const count = file.readPositional(self.io, &.{out}, offset) catch return error.FileUnavailable;
    assert(count <= out.len);
    return count;
}

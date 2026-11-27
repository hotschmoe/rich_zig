const std = @import("std");
const builtin = @import("builtin");
const ColorSystem = @import("color.zig").ColorSystem;

const win32 = if (builtin.os.tag == .windows) struct {
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

    extern "kernel32" fn GetConsoleMode(hConsoleHandle: w.HANDLE, lpMode: *w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: w.HANDLE, dwMode: w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: w.UINT) callconv(.winapi) w.BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleHandle: w.HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(.winapi) w.BOOL;
} else struct {};

pub const BackgroundMode = enum {
    dark,
    light,
    unknown,
};

pub const TerminalInfo = struct {
    width: u16 = 80,
    height: u16 = 24,
    color_system: ColorSystem = .standard,
    is_tty: bool = false,
    supports_unicode: bool = true,
    supports_hyperlinks: bool = false,
    term: ?[]const u8 = null,
    term_program: ?[]const u8 = null,
    supports_sync_output: bool = false,
    background_mode: BackgroundMode = .unknown,
    no_color: bool = false,
    owns_environment: bool = false,

    pub fn deinit(self: *TerminalInfo) void {
        if (self.owns_environment) {
            free_env(self.term);
            free_env(self.term_program);
        }
        self.* = undefined;
    }
};

const TerminalSize = struct { width: u16, height: u16 };

pub fn detect(environ: std.process.Environ) TerminalInfo {
    var info = TerminalInfo{ .owns_environment = builtin.os.tag == .windows };

    info.term = getEnv(environ, "TERM");
    info.term_program = getEnv(environ, "TERM_PROGRAM");

    info.is_tty = isTty();

    const no_color = getEnv(environ, "NO_COLOR");
    defer free_env(no_color);
    const force_color = getEnv(environ, "FORCE_COLOR");
    defer free_env(force_color);
    info.no_color = if (no_color) |value| value.len != 0 else false;
    if (force_color != null) {
        info.color_system = .truecolor;
    } else {
        info.no_color = info.no_color or !info.is_tty or
            (if (info.term) |term| std.mem.eql(u8, term, "dumb") else false);
        info.color_system = if (info.no_color) .standard else detectColorSystem(environ);
    }
    if (!info.is_tty) return info;

    const size = getTerminalSize();
    info.width = size.width;
    info.height = size.height;

    info.supports_hyperlinks = detectHyperlinks(environ);

    info.supports_sync_output = detectSyncOutput(environ);
    info.background_mode = detectBackground(environ);

    return info;
}

fn isTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.peb().ProcessParameters.hStdOutput;
        var mode: std.os.windows.DWORD = 0;
        return win32.GetConsoleMode(handle, &mode).toBool();
    }
    if (builtin.os.tag == .wasi or builtin.cpu.arch == .wasm32) return false;
    // No libc: probe with TIOCGWINSZ. Non-terminals fail with ENOTTY.
    if (@hasDecl(std.posix, "winsize")) {
        var ws: std.posix.winsize = undefined;
        const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        return result == 0;
    }
    return false;
}

fn getEnv(environ: std.process.Environ, name: []const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        return getEnvWindows(environ, name);
    }
    return std.process.Environ.getPosix(environ, name);
}

fn getEnvWindows(environ: std.process.Environ, name: []const u8) ?[]const u8 {
    var name_w: [256]u16 = undefined;
    const w_len = std.unicode.utf8ToUtf16Le(&name_w, name) catch return null;
    if (w_len >= name_w.len) return null;
    name_w[w_len] = 0;
    const name_w_z: [*:0]const u16 = name_w[0..w_len :0].ptr;

    const w_val = std.process.Environ.getWindows(environ, name_w_z) orelse return null;

    return std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, w_val) catch null;
}

fn free_env(value: ?[]const u8) void {
    if (builtin.os.tag == .windows) {
        if (value) |bytes| std.heap.page_allocator.free(bytes);
    }
}

fn getTerminalSize() TerminalSize {
    if (builtin.os.tag == .windows) {
        return getTerminalSizeWindows();
    } else if (builtin.os.tag == .wasi or builtin.cpu.arch == .wasm32) {
        return .{ .width = 80, .height = 24 };
    } else {
        return getTerminalSizePosix();
    }
}

fn getTerminalSizeWindows() TerminalSize {
    const handle = std.os.windows.peb().ProcessParameters.hStdOutput;

    var info: win32.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (win32.GetConsoleScreenBufferInfo(handle, &info).toBool()) {
        const width: u16 = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
        const height: u16 = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
        return .{ .width = width, .height = height };
    }

    return .{ .width = 80, .height = 24 };
}

fn getTerminalSizePosix() TerminalSize {
    if (@hasDecl(std.posix, "winsize")) {
        var ws: std.posix.winsize = undefined;
        const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0) {
            return .{ .width = ws.col, .height = ws.row };
        }
    }
    return .{ .width = 80, .height = 24 };
}

fn detectColorSystem(environ: std.process.Environ) ColorSystem {
    if (getEnv(environ, "COLORTERM")) |ct| {
        defer free_env(ct);
        if (std.mem.eql(u8, ct, "truecolor") or std.mem.eql(u8, ct, "24bit")) {
            return .truecolor;
        }
    }

    if (getEnv(environ, "TERM")) |term| {
        defer free_env(term);
        if (std.mem.indexOf(u8, term, "256color") != null or
            std.mem.indexOf(u8, term, "256") != null)
        {
            return .eight_bit;
        }
        if (std.mem.indexOf(u8, term, "truecolor") != null) {
            return .truecolor;
        }
    }

    if (getEnv(environ, "TERM_PROGRAM")) |prog| {
        defer free_env(prog);
        const truecolor_terminals = [_][]const u8{
            "iTerm.app",
            "Apple_Terminal",
            "WezTerm",
            "vscode",
            "Hyper",
            "mintty",
            "Terminus",
            "Alacritty",
            "kitty",
        };
        for (truecolor_terminals) |t| {
            if (std.mem.eql(u8, prog, t)) return .truecolor;
        }
    }

    if (getEnv(environ, "WT_SESSION")) |value| {
        defer free_env(value);
        return .truecolor;
    }

    if (getEnv(environ, "ConEmuANSI")) |ce| {
        defer free_env(ce);
        if (std.mem.eql(u8, ce, "ON")) {
            return .truecolor;
        }
    }

    return .eight_bit;
}

fn detectHyperlinks(environ: std.process.Environ) bool {
    if (getEnv(environ, "TERM_PROGRAM")) |prog| {
        defer free_env(prog);
        const supported = [_][]const u8{
            "iTerm.app",
            "WezTerm",
            "vscode",
            "Hyper",
            "Alacritty",
            "kitty",
        };
        for (supported) |t| {
            if (std.mem.eql(u8, prog, t)) return true;
        }
    }

    if (getEnv(environ, "WT_SESSION")) |value| {
        defer free_env(value);
        return true;
    }

    return false;
}

fn detectSyncOutput(environ: std.process.Environ) bool {
    if (getEnv(environ, "TERM_PROGRAM")) |prog| {
        defer free_env(prog);
        const supported = [_][]const u8{
            "WezTerm", "kitty", "Alacritty", "contour", "mintty",
        };
        for (supported) |t| {
            if (std.mem.eql(u8, prog, t)) return true;
        }
    }
    if (getEnv(environ, "WT_SESSION")) |value| {
        defer free_env(value);
        return true;
    }
    if (getEnv(environ, "TERM")) |term| {
        defer free_env(term);
        if (std.mem.startsWith(u8, term, "foot")) return true;
    }
    return false;
}

fn detectBackground(environ: std.process.Environ) BackgroundMode {
    if (getEnv(environ, "COLORFGBG")) |fgbg| {
        defer free_env(fgbg);
        if (std.mem.lastIndexOfScalar(u8, fgbg, ';')) |sep| {
            const bg_str = fgbg[sep + 1 ..];
            const bg = std.fmt.parseInt(u8, bg_str, 10) catch return .unknown;
            return if (bg < 7) .dark else .light;
        }
    }
    if (getEnv(environ, "TERM_PROGRAM")) |prog| {
        defer free_env(prog);
        if (std.mem.eql(u8, prog, "Apple_Terminal")) return .light;
    }
    return .dark;
}

pub fn enableVirtualTerminal() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.peb().ProcessParameters.hStdOutput;
        var mode: std.os.windows.DWORD = 0;
        if (!win32.GetConsoleMode(handle, &mode).toBool()) {
            return false;
        }
        mode |= 0x0004;
        return win32.SetConsoleMode(handle, mode).toBool();
    }
    return true;
}

pub fn enableUtf8() bool {
    if (builtin.os.tag == .windows) {
        return win32.SetConsoleOutputCP(65001).toBool();
    }
    return true;
}

// DEC private mode 2026 buffers terminal writes for atomic rendering.
pub const sync_output_begin = "\x1b[?2026h";
pub const sync_output_end = "\x1b[?2026l";

pub fn beginSyncOutput(writer: anytype) !void {
    try writer.writeAll(sync_output_begin);
}

pub fn endSyncOutput(writer: anytype) !void {
    try writer.writeAll(sync_output_end);
}

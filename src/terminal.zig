const std = @import("std");
const assert = @import("assert").assert;
const ColorSystem = @import("color.zig").ColorSystem;
const host_mod = @import("host.zig");
const real_host = @import("host_real.zig");
const Host = host_mod.Host;

pub const BackgroundMode = enum {
    dark,
    light,
    unknown,
};

pub const EnvText = struct {
    bytes: [64]u8 = undefined,
    length: u8 = 0,

    pub fn from(value: []const u8) EnvText {
        var text: EnvText = .{};
        const length: u8 = @intCast(@min(value.len, text.bytes.len));
        @memcpy(text.bytes[0..length], value[0..length]);
        text.length = length;
        assert(text.length <= text.bytes.len);
        assert(std.mem.eql(u8, text.slice(), value[0..length]));
        return text;
    }

    pub fn slice(self: *const EnvText) []const u8 {
        return self.bytes[0..self.length];
    }
};

pub const TerminalInfo = struct {
    width: u16 = 80,
    height: u16 = 24,
    color_system: ColorSystem = .standard,
    is_tty: bool = false,
    supports_unicode: bool = true,
    supports_hyperlinks: bool = false,
    term: ?EnvText = null,
    term_program: ?EnvText = null,
    supports_sync_output: bool = false,
    background_mode: BackgroundMode = .unknown,
    no_color: bool = false,
    legacy_windows: bool = false,
};

const Env = struct {
    host: Host,
    buffer: [host_mod.env_value_max]u8 = undefined,

    fn get(self: *Env, name: []const u8) ?[]const u8 {
        return self.host.env_get(name, &self.buffer);
    }

    fn equals(self: *Env, name: []const u8, expected: []const u8) bool {
        assert(name.len > 0);
        const value = self.get(name) orelse return false;
        assert(value.len <= host_mod.env_value_max);
        return std.mem.eql(u8, value, expected);
    }

    fn one_of(self: *Env, name: []const u8, candidates: []const []const u8) bool {
        assert(candidates.len > 0);
        const value = self.get(name) orelse return false;
        assert(value.len <= host_mod.env_value_max);
        for (candidates) |candidate| {
            if (std.mem.eql(u8, value, candidate)) return true;
        }
        return false;
    }
};

pub fn detect(environ: std.process.Environ) TerminalInfo {
    var source = host_mod.Source.from_io(std.Options.debug_io, environ);
    const info = detect_host(source.host());
    assert(info.width > 0 and info.height > 0);
    assert(info.is_tty or info.width == 80);
    return info;
}

pub fn detect_host(host: Host) TerminalInfo {
    var env: Env = .{ .host = host };
    var info: TerminalInfo = .{};
    if (env.get("TERM")) |value| info.term = EnvText.from(value);
    if (env.get("TERM_PROGRAM")) |value| info.term_program = EnvText.from(value);
    info.is_tty = host.probe(.stdout_terminal);
    info.legacy_windows = info.is_tty and !host.probe(.virtual_terminal);

    const no_color = env.get("NO_COLOR");
    info.no_color = if (no_color) |value| value.len != 0 else false;
    if (env.get("FORCE_COLOR") != null) {
        info.color_system = .truecolor;
    } else {
        const dumb = env.equals("TERM", "dumb");
        info.no_color = info.no_color or !info.is_tty or dumb or info.legacy_windows;
        info.color_system = if (info.no_color) .standard else detect_color_system(&env);
    }
    assert(!(info.no_color and info.color_system == .eight_bit and info.is_tty and false));
    if (!info.is_tty) return info;

    if (host.size()) |size| {
        info.width = size.columns;
        info.height = size.rows;
    }
    info.supports_hyperlinks = detect_hyperlinks(&env);
    info.supports_sync_output = detect_sync_output(&env);
    info.background_mode = detect_background(&env);
    assert(info.width > 0 and info.height > 0);
    return info;
}

fn detect_color_system(env: *Env) ColorSystem {
    assert(env.buffer.len == host_mod.env_value_max);
    if (env.one_of("COLORTERM", &.{ "truecolor", "24bit" })) return .truecolor;
    if (env.get("TERM")) |term| {
        if (std.mem.indexOf(u8, term, "256") != null) return .eight_bit;
        if (std.mem.indexOf(u8, term, "truecolor") != null) return .truecolor;
    }
    const truecolor_terminals = [_][]const u8{
        "iTerm.app", "Apple_Terminal", "WezTerm",   "vscode", "Hyper",
        "mintty",    "Terminus",       "Alacritty", "kitty",
    };
    if (env.one_of("TERM_PROGRAM", &truecolor_terminals)) return .truecolor;
    if (env.get("WT_SESSION") != null) return .truecolor;
    if (env.equals("ConEmuANSI", "ON")) return .truecolor;
    assert(env.get("WT_SESSION") == null);
    return .eight_bit;
}

fn detect_hyperlinks(env: *Env) bool {
    const supported = [_][]const u8{
        "iTerm.app", "WezTerm", "vscode", "Hyper", "Alacritty", "kitty",
    };
    assert(env.buffer.len == host_mod.env_value_max);
    if (env.one_of("TERM_PROGRAM", &supported)) return true;
    const session = env.get("WT_SESSION");
    assert(session == null or session.?.len <= host_mod.env_value_max);
    return session != null;
}

fn detect_sync_output(env: *Env) bool {
    const supported = [_][]const u8{ "WezTerm", "kitty", "Alacritty", "contour", "mintty" };
    assert(env.buffer.len == host_mod.env_value_max);
    if (env.one_of("TERM_PROGRAM", &supported)) return true;
    if (env.get("WT_SESSION") != null) return true;
    const term = env.get("TERM") orelse return false;
    assert(term.len <= host_mod.env_value_max);
    return std.mem.startsWith(u8, term, "foot");
}

fn detect_background(env: *Env) BackgroundMode {
    assert(env.buffer.len == host_mod.env_value_max);
    if (env.get("COLORFGBG")) |fgbg| {
        if (std.mem.lastIndexOfScalar(u8, fgbg, ';')) |separator| {
            const background = std.fmt.parseInt(u8, fgbg[separator + 1 ..], 10) catch {
                return .unknown;
            };
            return if (background < 7) .dark else .light;
        }
    }
    if (env.equals("TERM_PROGRAM", "Apple_Terminal")) return .light;
    assert(!env.equals("TERM_PROGRAM", "Apple_Terminal"));
    return .dark;
}

pub fn enableVirtualTerminal() bool {
    return real_host.enable_virtual_terminal();
}

pub fn enableUtf8() bool {
    return real_host.enable_utf8();
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

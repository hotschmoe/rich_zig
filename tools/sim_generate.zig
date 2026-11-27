const std = @import("std");
const assert = @import("assert").assert;
const rich = @import("rich_zig");
const sim_host = @import("sim_host.zig");

pub const steps_max: u32 = 256;
pub const events_max: u32 = 3;
pub const content_max: u32 = 1536;

pub const Kind = enum(u8) {
    print_markup,
    print_plain,
    print_styled,
    rule_title,
    rule_renderable,
    panel,
    table,
    tree,
    columns,
    wrapped_text,
    nested,
    progress_bar,
    progress_live,
    log_record,
    console_log,
    stderr_log,
    status_line,
    prompt_text,
    prompt_number,
    prompt_password,
    paged,
    live_text,
};

pub const EventKind = enum(u8) {
    resize,
    advance,
    backward,
    jump,
    input,
    fail_writes,
    short_writes,
};

pub const Event = struct { kind: EventKind, a: u32, b: u32 };

pub const Step = struct {
    kind: Kind,
    seed: u64,
    events: [events_max]Event = undefined,
    event_count: u8 = 0,
};

pub const Scenario = struct {
    config: sim_host.Config,
    console_width: ?u16,
    console_height: ?u16,
    no_color: bool,
    color_system: ?rich.ColorSystem,
    force_terminal: bool,
    mono_start_ns: i64,
    wall_start_ns: i64,
    host_seed: u64,
    step_count: u32,
    steps: [steps_max]Step,
};

pub const Content = struct {
    markup: [content_max]u8 = undefined,
    markup_length: u32 = 0,
    plain: [content_max]u8 = undefined,
    plain_length: u32 = 0,

    pub fn markup_slice(self: *const Content) []const u8 {
        return self.markup[0..self.markup_length];
    }

    pub fn plain_slice(self: *const Content) []const u8 {
        return self.plain[0..self.plain_length];
    }

    fn full(self: *const Content) bool {
        return self.markup_length + 200 >= content_max or self.plain_length + 200 >= content_max;
    }

    fn put_both(self: *Content, text: []const u8) void {
        assert(text.len > 0 and text.len <= 256);
        self.put_markup(text);
        self.put_plain(text);
        assert(self.markup_length <= content_max and self.plain_length <= content_max);
    }

    fn put_markup(self: *Content, text: []const u8) void {
        assert(self.markup_length <= content_max);
        const count: u32 = @intCast(@min(text.len, content_max - self.markup_length));
        @memcpy(self.markup[self.markup_length..][0..count], text[0..count]);
        self.markup_length += count;
        assert(self.markup_length <= content_max);
    }

    fn put_plain(self: *Content, text: []const u8) void {
        assert(self.plain_length <= content_max);
        const count: u32 = @intCast(@min(text.len, content_max - self.plain_length));
        @memcpy(self.plain[self.plain_length..][0..count], text[0..count]);
        self.plain_length += count;
        assert(self.plain_length <= content_max);
    }
};

const ascii_words = [_][]const u8{
    "alpha", "beta", "gamma", "delta", "quick", "brown", "fox",  "jumps",
    "over",  "lazy", "dog",   "rich",  "zig",   "term",  "x",    "a-b",
    "(ok)",  "x/y",  "1234",  "end.",  "mid,",  "w",     "node", "cell",
};
const wide_words = [_][]const u8{
    "\u{4e2d}\u{6587}", "\u{65e5}\u{672c}\u{8a9e}", "\u{d55c}\u{ad6d}\u{c5b4}",
    "\u{1f600}",        "\u{1f389}x",               "\u{ff21}\u{ff22}",
};
const combining_words = [_][]const u8{
    "e\u{301}", "a\u{308}b", "n\u{303}", "o\u{302}\u{323}", "u\u{30a}x",
};
const rtl_words = [_][]const u8{
    "\u{5e9}\u{5dc}\u{5d5}\u{5dd}", "\u{645}\u{631}\u{62d}\u{628}\u{627}", "\u{5d0}\u{5d1}\u{5d2}",
};
const tags = [_][]const u8{
    "bold",                       "italic",       "underline",      "dim",
    "reverse",                    "strike",       "red",            "green",
    "blue",                       "yellow",       "magenta",        "cyan",
    "bold red",                   "italic green", "underline blue", "on red",
    "white on blue",              "#ff8800",      "rgb(10,200,30)", "color(9)",
    "link=https://example.org/x",
};
const literal_tags = [_][]const u8{ "[zzz]", "[1]", "\\[bold]" };
const literal_plain = [_][]const u8{ "[zzz]", "[1]", "[bold]" };

pub fn pick(random: std.Random, comptime T: type, items: []const T) T {
    assert(items.len > 0);
    const index = random.uintLessThan(usize, items.len);
    assert(index < items.len);
    return items[index];
}

fn long_word(random: std.Random, content: *Content) void {
    const count = 40 + random.uintLessThan(u32, 120);
    assert(count < 200);
    var text: [200]u8 = undefined;
    for (text[0..count], 0..) |*byte, index| {
        byte.* = 'a' + @as(u8, @intCast((index + random.uintLessThan(u32, 3)) % 26));
    }
    content.put_both(text[0..count]);
    assert(content.plain_length >= count or content.full());
}

fn add_word(random: std.Random, content: *Content, exotic: bool) void {
    const roll = random.uintLessThan(u32, 100);
    assert(content.plain_length <= content_max);
    assert(content.markup_length <= content_max);
    if (!exotic or roll < 55) return content.put_both(pick(random, []const u8, &ascii_words));
    if (roll < 70) return content.put_both(pick(random, []const u8, &wide_words));
    if (roll < 82) return content.put_both(pick(random, []const u8, &combining_words));
    if (roll < 92) return content.put_both(pick(random, []const u8, &rtl_words));
    return long_word(random, content);
}

fn add_run(random: std.Random, content: *Content, exotic: bool) void {
    const count = 1 + random.uintLessThan(u32, 4);
    assert(count <= 4);
    for (0..count) |index| {
        if (index > 0) content.put_both(" ");
        add_word(random, content, exotic);
    }
    assert(content.plain_length > 0);
}

pub fn build_markup(random: std.Random, content: *Content, groups: u32, exotic: bool) void {
    assert(groups > 0);
    content.* = .{};
    for (0..groups) |_| {
        if (content.full()) break;
        const roll = random.uintLessThan(u32, 100);
        if (roll < 30) {
            add_run(random, content, exotic);
        } else if (roll < 88) {
            const tag = pick(random, []const u8, &tags);
            content.put_markup("[");
            content.put_markup(tag);
            content.put_markup("]");
            add_run(random, content, exotic);
            content.put_markup("[/]");
        } else {
            const index = random.uintLessThan(usize, literal_tags.len);
            content.put_markup(literal_tags[index]);
            content.put_plain(literal_plain[index]);
        }
        content.put_both(" ");
    }
    assert(content.plain_length <= content_max);
    assert(content.markup_length >= 1);
}

pub fn build_plain(random: std.Random, content: *Content, words: u32, exotic: bool) void {
    assert(words > 0);
    content.* = .{};
    for (0..words) |index| {
        if (content.full()) break;
        if (index > 0) content.put_both(" ");
        add_word(random, content, exotic);
    }
    content.markup_length = 0;
    assert(content.plain_length > 0);
}

const widths = [_]u16{ 1, 2, 3, 5, 10, 16, 20, 33, 40, 60, 80, 80, 100, 132, 200 };
const override_widths = [_]u16{ 0, 1, 2, 3, 4, 7, 12, 30, 50 };
const terms = [_][]const u8{
    "xterm-256color", "xterm", "dumb", "screen", "", "vt100", "linux", "foot",
};
const term_programs = [_][]const u8{
    "iTerm.app", "vscode", "Apple_Terminal", "kitty", "WezTerm", "x",
};
const colorterms = [_][]const u8{ "truecolor", "24bit", "yes", "" };
const foregrounds = [_][]const u8{ "15;0", "0;15", "garbage", "7;" };

fn chance(random: std.Random, percent: u32) bool {
    return random.uintLessThan(u32, 100) < percent;
}

fn generate_env(random: std.Random, env: *sim_host.Env) void {
    assert(env.count == 0);
    if (chance(random, 85)) env.set("TERM", pick(random, []const u8, &terms));
    if (chance(random, 30)) env.set("TERM_PROGRAM", pick(random, []const u8, &term_programs));
    if (chance(random, 35)) env.set("COLORTERM", pick(random, []const u8, &colorterms));
    if (chance(random, 15)) env.set("NO_COLOR", if (chance(random, 50)) "" else "1");
    if (chance(random, 15)) {
        const values = [_][]const u8{ "", "1", "0" };
        env.set("FORCE_COLOR", pick(random, []const u8, &values));
    }
    if (chance(random, 10)) env.set("WT_SESSION", "x");
    if (chance(random, 8)) env.set("ConEmuANSI", if (chance(random, 50)) "ON" else "OFF");
    if (chance(random, 20)) env.set("COLORFGBG", pick(random, []const u8, &foregrounds));
    assert(env.count <= sim_host.env_entries_max);
}

fn generate_config(random: std.Random, config: *sim_host.Config) void {
    config.* = .{};
    config.columns = pick(random, u16, &widths);
    config.rows = 1 + random.uintLessThan(u16, 60);
    config.stdout_tty = chance(random, 60);
    config.stderr_tty = chance(random, 60);
    config.stdin_tty = chance(random, 40);
    config.legacy_windows = chance(random, 10);
    config.password_ok = chance(random, 70);
    config.pager_ok = chance(random, 50);
    generate_env(random, &config.env);
    assert(config.rows >= 1 and config.rows <= 60);
    assert(config.columns >= 1);
}

fn generate_event(random: std.Random) Event {
    const kind = random.enumValue(EventKind);
    const a = switch (kind) {
        .resize => pick(random, u16, &widths),
        .advance => 1 + random.uintLessThan(u32, 3000),
        .backward => 1 + random.uintLessThan(u32, 5000),
        .jump => 1000 + random.uintLessThan(u32, 3_000_000),
        .input => random.int(u32),
        .fail_writes => 1 + random.uintLessThan(u32, 3),
        .short_writes => 1 + random.uintLessThan(u32, 8),
    };
    assert(a > 0);
    assert(a < 4_000_000 or kind == .input);
    return .{ .kind = kind, .a = a, .b = 1 + random.uintLessThan(u32, 50) };
}

fn generate_step(random: std.Random, step: *Step) void {
    step.* = .{ .kind = random.enumValue(Kind), .seed = random.int(u64) };
    const quiet = chance(random, 55);
    const count: u32 = if (quiet) 0 else 1 + random.uintLessThan(u32, events_max);
    for (0..count) |index| step.events[index] = generate_event(random);
    step.event_count = @intCast(count);
    assert(step.event_count <= events_max);
    assert(count == 0 or step.events[0].a > 0);
}

pub fn generate(seed: u64, steps: u32, scenario: *Scenario) void {
    assert(steps > 0 and steps <= steps_max);
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    generate_config(random, &scenario.config);
    scenario.console_width = if (chance(random, 25)) pick(random, u16, &override_widths) else null;
    scenario.console_height = if (chance(random, 20)) pick(random, u16, &override_widths) else null;
    scenario.no_color = chance(random, 10);
    scenario.color_system = if (chance(random, 10)) random.enumValue(rich.ColorSystem) else null;
    scenario.force_terminal = chance(random, 10);
    scenario.mono_start_ns = @intCast(random.uintLessThan(u64, 1_000_000_000_000));
    const wall_extra: i64 = @intCast(random.uintLessThan(u64, 1_000_000_000_000));
    scenario.wall_start_ns = 1_700_000_000_000_000_000 + wall_extra;
    scenario.host_seed = random.int(u64);
    scenario.step_count = steps;
    for (scenario.steps[0..steps]) |*step| generate_step(random, step);
    assert(scenario.step_count == steps);
    assert(scenario.mono_start_ns >= 0 and scenario.wall_start_ns > 0);
}

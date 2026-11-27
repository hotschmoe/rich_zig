const std = @import("std");
const assert = @import("assert").assert;
const rich = @import("rich_zig");
const sim_host = @import("sim_host.zig");
const gen = @import("sim_generate.zig");
const scan = @import("sim_scan.zig");
const Tracker = @import("fuzz_memory.zig").Tracker;

pub const expected_max: u32 = 1 << 20;
pub const rows_max: u32 = 80;
pub var current_step: u32 = 0;

pub const Variant = struct {
    strip_short_writes: bool = false,
    force_color: bool = false,
    mono_offset_ns: i64 = 0,
};

pub const Record = struct {
    kind: gen.Kind,
    out_start: u32 = 0,
    out_end: u32 = 0,
    err_start: u32 = 0,
    err_end: u32 = 0,
    error_name: []const u8 = "",
    failures: u32 = 0,
    short_writes: u32 = 0,
    accepted_after_failure: u32 = 0,
    width: u16 = 0,
    fit_min: u16 = 0,
    expected_start: u32 = 0,
    expected_length: u32 = 0,
    has_expected: bool = false,
    exact: bool = false,
    secret_length: u32 = 0,
    balanced: bool = false,
    progress: bool = false,
    env_only_colors: bool = false,
    on_stderr: bool = false,
    leaked_bytes: u64 = 0,
};

pub const Run = struct {
    host: sim_host.SimHost,
    records: [gen.steps_max]Record = undefined,
    count: u32 = 0,
    expected: [expected_max]u8 = undefined,
    expected_length: u32 = 0,
    final_leaked_bytes: u64 = 0,
};

const Ctx = struct {
    console: *rich.Console,
    run: *Run,
    record: *Record,
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    random: std.Random,
    content: *gen.Content,

    fn chance(self: *Ctx, percent: u32) bool {
        assert(percent <= 100);
        const hit = self.random.uintLessThan(u32, 100) < percent;
        assert(percent != 0 or !hit);
        return hit;
    }

    fn below(self: *Ctx, limit: u32) u32 {
        assert(limit > 0);
        const value = self.random.uintLessThan(u32, limit);
        assert(value < limit);
        return value;
    }

    fn words(self: *Ctx, count_max: u32) []const u8 {
        assert(count_max > 0);
        const exotic = self.chance(50);
        gen.build_plain(self.random, self.content, 1 + self.below(count_max), exotic);
        assert(self.content.plain_length > 0);
        return self.content.plain_slice();
    }

    fn markup(self: *Ctx, groups_max: u32) []const u8 {
        assert(groups_max > 0);
        const exotic = self.chance(50);
        gen.build_markup(self.random, self.content, 1 + self.below(groups_max), exotic);
        assert(self.content.markup_length > 0);
        return self.content.markup_slice();
    }

    fn keep(self: *Ctx, text: []const u8) ![]const u8 {
        assert(text.len > 0);
        const copy = try self.scratch.dupe(u8, text);
        assert(copy.len == text.len);
        return copy;
    }

    fn expect_bytes(self: *Ctx, bytes: []const u8) void {
        assert(self.run.expected_length <= expected_max);
        const room = expected_max - self.run.expected_length;
        const count: u32 = @intCast(@min(room, bytes.len));
        @memcpy(self.run.expected[self.run.expected_length..][0..count], bytes[0..count]);
        self.record.expected_start = self.run.expected_length;
        self.record.expected_length = count;
        self.record.has_expected = true;
        self.run.expected_length += count;
        assert(self.run.expected_length <= expected_max);
    }

    fn expect_line(self: *Ctx, text: []const u8) void {
        var joined: [gen.content_max + 2]u8 = undefined;
        assert(text.len <= gen.content_max);
        @memcpy(joined[0..text.len], text);
        joined[text.len] = '\n';
        self.expect_bytes(joined[0 .. text.len + 1]);
        assert(self.record.expected_length == text.len + 1);
    }

    fn fit(self: *Ctx, natural: u32) void {
        assert(self.record.fit_min == 0);
        self.record.fit_min = @intCast(@min(natural, std.math.maxInt(u16)));
        assert(self.record.fit_min > 0);
    }
};

fn exec_print_markup(ctx: *Ctx) !void {
    const text = ctx.markup(6);
    assert(ctx.content.plain_length <= ctx.content.markup_length);
    ctx.expect_line(ctx.content.plain_slice());
    assert(ctx.record.has_expected);
    try ctx.console.print(text);
}

fn exec_print_plain(ctx: *Ctx) !void {
    const text = ctx.words(12);
    assert(std.mem.indexOfScalar(u8, text, '\n') == null);
    ctx.expect_line(text);
    assert(ctx.record.has_expected);
    try ctx.console.printPlain(text);
}

fn exec_print_styled(ctx: *Ctx) !void {
    const text = ctx.words(8);
    assert(std.mem.indexOfScalar(u8, text, 0x1b) == null);
    ctx.expect_line(text);
    const red = rich.Color.red;
    const style = rich.Style.empty.bold().foreground(red).background(rich.Color.blue);
    assert(!style.isEmpty());
    try ctx.console.printStyled(text, style);
}

fn exec_rule_title(ctx: *Ctx) !void {
    const title = std.mem.trim(u8, ctx.words(3), " ");
    assert(title.len > 0);
    if (ctx.chance(20)) {
        ctx.fit(1);
        return ctx.console.rule(null);
    }
    ctx.fit(scan.text_width(title) + 2);
    assert(ctx.record.fit_min >= 3);
    try ctx.console.rule(title);
}

fn exec_rule_renderable(ctx: *Ctx) !void {
    const text = std.mem.trim(u8, ctx.words(3), " ");
    assert(text.len > 0);
    var rule = rich.Rule.init();
    ctx.fit(1);
    if (ctx.chance(70)) {
        rule = rule.withTitle(text);
        ctx.record.fit_min = @intCast(@min(scan.text_width(text) + 2, std.math.maxInt(u16)));
    }
    if (ctx.chance(30)) rule = rule.withCharacters("=");
    if (ctx.chance(30)) rule = rule.alignLeft();
    assert(ctx.record.fit_min >= 1);
    try ctx.console.printRenderable(rule);
}

fn exec_panel(ctx: *Ctx) !void {
    const text = ctx.words(8);
    var panel = rich.Panel.fromText(ctx.allocator, text);
    var natural = scan.text_width(text) + 4;
    if (ctx.chance(50)) {
        panel = panel.withTitle("title");
        natural = @max(natural, 11);
    }
    if (ctx.chance(30)) {
        panel = panel.withSubtitle("sub");
        natural = @max(natural, 9);
    }
    switch (ctx.below(5)) {
        0 => panel = panel.square(),
        1 => panel = panel.heavy(),
        2 => panel = panel.double(),
        3 => panel = panel.ascii(),
        else => {},
    }
    if (ctx.chance(30)) {
        panel = panel.withPadding(1, 2, 1, 2);
        natural += 2;
    }
    assert(natural >= 5);
    ctx.fit(natural);
    assert(ctx.record.fit_min >= 5);
    try ctx.console.printRenderable(panel);
}

fn exec_table(ctx: *Ctx) !void {
    var table = rich.Table.init(ctx.allocator);
    defer table.deinit();
    const column_count = 1 + ctx.below(4);
    var widest = std.mem.zeroes([4]u32);
    for (0..column_count) |index| {
        const header = try ctx.keep(std.mem.trim(u8, ctx.words(1), " "));
        _ = table.addColumn(header);
        widest[index] = scan.text_width(header);
    }
    assert(table.columns.items.len == column_count);
    for (0..ctx.below(5)) |_| {
        var cells: [4][]const u8 = undefined;
        for (cells[0..column_count], 0..) |*cell, index| {
            cell.* = try ctx.keep(ctx.words(4));
            widest[index] = @max(widest[index], scan.text_width(cell.*));
        }
        try table.addRow(cells[0..column_count]);
    }
    var natural: u32 = 1 + 3 * column_count;
    for (widest[0..column_count]) |column_width| natural += column_width;
    assert(natural > column_count);
    ctx.fit(natural);
    try ctx.console.printRenderable(table);
}

fn exec_tree(ctx: *Ctx) !void {
    var root = rich.TreeNode.init(ctx.allocator, try ctx.keep(ctx.words(2)));
    defer root.deinit();
    for (0..ctx.below(4)) |_| {
        const child = try root.addChildLabel(try ctx.keep(ctx.words(3)));
        if (ctx.chance(40)) _ = try child.addChildLabel("leaf");
    }
    assert(root.children.items.len < 4);
    assert(root.label.len > 0);
    try ctx.console.printRenderable(rich.Tree.init(root));
}

fn exec_columns(ctx: *Ctx) !void {
    var items: [6][]const u8 = undefined;
    const count = 1 + ctx.below(6);
    var natural: u32 = 1;
    for (items[0..count]) |*item| {
        item.* = try ctx.keep(ctx.words(2));
        natural = @max(natural, scan.text_width(item.*));
    }
    var columns = try rich.Columns.fromText(ctx.allocator, items[0..count]);
    defer columns.deinit();
    assert(columns.items.len == count);
    assert(natural >= 1);
    ctx.fit(natural);
    try ctx.console.printRenderable(columns);
}

fn exec_wrapped_text(ctx: *Ctx) !void {
    var text = try rich.Text.fromMarkup(ctx.allocator, ctx.markup(5));
    defer text.deinit();
    const lines = try text.wrap(ctx.console.width());
    defer ctx.allocator.free(lines);
    defer for (lines) |*line| line.deinit();
    assert(lines.len > 0 or ctx.console.width() == 0 or text.plain.len == 0);
    ctx.fit(2);
    assert(ctx.record.fit_min == 2);
    for (lines) |line| {
        const segments = try line.render(ctx.allocator);
        defer ctx.allocator.free(segments);
        try ctx.console.printSegments(segments);
        try ctx.console.printSegments(&.{rich.Segment.line()});
    }
}

fn exec_nested(ctx: *Ctx) !void {
    var table = rich.Table.init(ctx.allocator);
    defer table.deinit();
    _ = table.addColumn("k");
    _ = table.addColumn("v");
    const cell = try ctx.keep(ctx.words(3));
    try table.addRow(&.{ "one", cell });
    const natural = 7 + 3 + scan.text_width(cell) + 4;
    const inner: usize = @max(ctx.console.width(), 12) - 4;
    const segments = try table.render(inner, ctx.scratch);
    assert(segments.len > 0);
    var panel = rich.Panel.fromRendered(ctx.allocator, segments).withTitle("outer");
    if (ctx.chance(40)) panel = panel.heavy();
    assert(inner >= 8);
    ctx.fit(@max(natural, 12));
    try ctx.console.printRenderable(panel);
}

fn write_segments(ctx: *Ctx, segments: []const rich.Segment) !void {
    assert(segments.len < 100_000);
    assert(ctx.record.error_name.len == 0);
    try ctx.console.printSegments(segments);
    try ctx.console.printSegments(&.{rich.Segment.line()});
}

fn exec_progress_bar(ctx: *Ctx) !void {
    const total = if (ctx.chance(15))
        std.math.maxInt(usize) - ctx.random.uintLessThan(usize, 1000)
    else
        1 + ctx.random.uintLessThan(usize, 5000);
    var bar = rich.ProgressBar.initWithHost(ctx.console.host())
        .withTotal(total)
        .withWidth(ctx.random.uintLessThan(usize, 60))
        .withTiming()
        .withSpeed();
    if (ctx.chance(30)) bar = bar.withDescription("work");
    if (ctx.chance(20)) bar = bar.asIndeterminate();
    ctx.record.progress = true;
    const frames = 1 + ctx.below(4);
    for (0..frames) |_| {
        try ctx.console.host().wait(ctx.random.uintLessThan(u64, 4_000_000_000));
        bar.advance(ctx.random.uintLessThan(usize, if (ctx.chance(40)) 3 else 2000));
        bar.advancePulse();
        const segments = try bar.render(ctx.console.width(), ctx.scratch);
        try write_segments(ctx, segments);
    }
    assert(bar.completed <= bar.total);
    assert(frames <= 4);
}

fn exec_progress_live(ctx: *Ctx) !void {
    const bound = ctx.console.host();
    var group = rich.ProgressGroup.initWithHost(ctx.allocator, bound);
    defer group.deinit();
    const task = try group.addTaskWithTiming("task", 1 + ctx.random.uintLessThan(usize, 300));
    var live = rich.Live.init(ctx.console).withRefreshRate(10 + ctx.random.uintLessThan(u64, 400));
    var display = rich.ProgressDisplay.initWithHost(ctx.allocator, bound, &group)
        .withLive(&live)
        .withRefreshRate(10 + ctx.random.uintLessThan(u64, 400));
    ctx.record.progress = true;
    ctx.record.balanced = true;
    try display.start();
    errdefer display.stop() catch {};
    for (0..1 + ctx.below(5)) |_| {
        task.advance(ctx.random.uintLessThan(usize, 100));
        try display.wait(ctx.random.uintLessThan(u64, 1500));
    }
    try display.stop();
    assert(!display.is_running);
    assert(group.bars.items.len == 1);
}

fn exec_live_text(ctx: *Ctx) !void {
    var text = try rich.Text.fromMarkup(ctx.allocator, ctx.markup(3));
    defer text.deinit();
    const segments = try text.render(ctx.allocator);
    defer ctx.allocator.free(segments);
    var live = rich.Live.init(ctx.console).withRefreshRate(10 + ctx.random.uintLessThan(u64, 300));
    ctx.record.balanced = true;
    ctx.record.progress = true;
    const alternate = ctx.chance(40);
    if (alternate) try ctx.console.enterAltScreen();
    try live.start();
    errdefer live.stop() catch {};
    live.setContent(segments);
    assert(live.content != null);
    try live.wait(ctx.random.uintLessThan(u64, 2000));
    try live.update(segments);
    try live.stop();
    if (alternate) try ctx.console.exitAltScreen();
    assert(!live.is_started);
}

fn exec_log_record(ctx: *Ctx) !void {
    const message = ctx.words(6);
    const format: rich.logging.FormatOptions = .{
        .show_path = ctx.chance(40),
        .timestamp_format = ctx.random.enumValue(rich.logging.FormatOptions.TimestampFormat),
    };
    var handler = rich.RichHandler.initWithHost(ctx.allocator, ctx.console.host(), .{}, format);
    defer handler.deinit();
    ctx.record.env_only_colors = true;
    assert(message.len > 0);
    ctx.expect_bytes(message);
    assert(ctx.record.has_expected);
    try handler.info(message);
    try handler.warn("second");
}

fn exec_console_log(ctx: *Ctx) !void {
    const level = ctx.random.enumValue(rich.LogLevel);
    const value = ctx.below(1000);
    assert(value < 1000);
    assert(ctx.console.capture_buffer == null);
    try ctx.console.log(level, "value {d} done", .{value});
}

fn exec_stderr_log(ctx: *Ctx) !void {
    var buffer: [256]u8 = undefined;
    var writer = rich.host.HostWriter.init(ctx.console.host(), .stderr, &buffer);
    ctx.record.on_stderr = true;
    ctx.record.env_only_colors = true;
    const colors = ctx.chance(50);
    const now_seconds: i64 = ctx.below(2_000_000_000);
    assert(now_seconds >= 0);
    const out = &writer.interface;
    const log = rich.logging.write_log_line;
    try log(out, colors, now_seconds, .info, .default, "n={d}", .{@as(u32, 7)});
    try log(out, colors, now_seconds, .err, .sim, "bad", .{});
    assert(writer.interface.end == 0);
}

fn exec_status_line(ctx: *Ctx) !void {
    const text = ctx.words(4);
    try ctx.console.status(text);
    assert(ctx.console.status_line_active);
    try ctx.console.statusFmt("n={d}", .{ctx.below(100)});
    try ctx.console.clearStatus();
    assert(!ctx.console.status_line_active);
}

fn push_lines(ctx: *Ctx, comptime choices: []const []const u8, count: u32) void {
    assert(count > 0);
    for (0..count) |_| ctx.run.host.push_input(gen.pick(ctx.random, []const u8, choices));
    assert(ctx.run.host.input_length >= ctx.run.host.input_position);
}

fn exec_prompt_text(ctx: *Ctx) !void {
    ctx.record.env_only_colors = true;
    push_lines(ctx, &.{ "alice\n", "\n", "bob\r\n", "x\n" }, 2);
    assert(ctx.run.host.input_length > 0);
    const choices = [_][]const u8{ "alice", "bob" };
    var prompt = rich.Prompt.init(ctx.allocator, "[bold]Name[/]").withDefault("anon");
    if (ctx.chance(40)) prompt = prompt.withChoices(&choices);
    const answer = try prompt.ask_host(ctx.console.host());
    defer ctx.allocator.free(answer);
    assert(answer.len > 0);
}

fn exec_prompt_number(ctx: *Ctx) !void {
    ctx.record.env_only_colors = true;
    push_lines(ctx, &.{ "12\n", "abc\n", "\n", "y\n", "n\n", "3.5\n", "-9\n" }, 3);
    assert(ctx.run.host.input_length > 0);
    const bound = ctx.console.host();
    switch (ctx.below(3)) {
        0 => _ = try rich.IntPrompt.init(ctx.allocator, "N").withMax(100).ask_host(bound),
        1 => _ = try rich.FloatPrompt.init(ctx.allocator, "R").withMin(0).ask_host(bound),
        else => _ = try rich.Confirm.init(ctx.allocator, "Ok").withDefault(true).ask_host(bound),
    }
    assert(ctx.run.host.input_position <= ctx.run.host.input_length);
}

fn exec_prompt_password(ctx: *Ctx) !void {
    ctx.record.env_only_colors = true;
    var secret: [24]u8 = undefined;
    const text = try std.fmt.bufPrint(&secret, "pw{x}", .{ctx.random.int(u32)});
    ctx.run.host.clear_input();
    ctx.run.host.push_input(text);
    ctx.run.host.push_input("\n");
    ctx.expect_bytes(text);
    ctx.record.secret_length = ctx.record.expected_length;
    assert(ctx.record.secret_length == text.len);
    const prompt = rich.Prompt.init(ctx.allocator, "Password").asPassword(true);
    const answer = try prompt.ask_host(ctx.console.host());
    defer ctx.allocator.free(answer);
    assert(std.mem.eql(u8, answer, text));
}

fn exec_paged(ctx: *Ctx) !void {
    var buffer: [1200]u8 = undefined;
    var length: usize = 0;
    for (0..ctx.below(rows_max)) |index| {
        const piece = std.fmt.bufPrint(buffer[length..], "line {d}\n", .{index}) catch break;
        length += piece.len;
    }
    ctx.run.host.push_input("\n\nq");
    ctx.record.exact = !ctx.console.isTty();
    if (ctx.record.exact) ctx.expect_bytes(buffer[0..length]);
    assert(length <= buffer.len);
    assert(ctx.record.exact == !ctx.console.isTty());
    try ctx.console.printPaged(buffer[0..length]);
}

fn dispatch(ctx: *Ctx, kind: gen.Kind) !void {
    assert(!ctx.record.has_expected);
    assert(ctx.record.fit_min == 0);
    switch (kind) {
        .print_markup => try exec_print_markup(ctx),
        .print_plain => try exec_print_plain(ctx),
        .print_styled => try exec_print_styled(ctx),
        .rule_title => try exec_rule_title(ctx),
        .rule_renderable => try exec_rule_renderable(ctx),
        .panel => try exec_panel(ctx),
        .table => try exec_table(ctx),
        .tree => try exec_tree(ctx),
        .columns => try exec_columns(ctx),
        .wrapped_text => try exec_wrapped_text(ctx),
        .nested => try exec_nested(ctx),
        .progress_bar => try exec_progress_bar(ctx),
        .progress_live => try exec_progress_live(ctx),
        .log_record => try exec_log_record(ctx),
        .console_log => try exec_console_log(ctx),
        .stderr_log => try exec_stderr_log(ctx),
        .status_line => try exec_status_line(ctx),
        .prompt_text => try exec_prompt_text(ctx),
        .prompt_number => try exec_prompt_number(ctx),
        .prompt_password => try exec_prompt_password(ctx),
        .paged => try exec_paged(ctx),
        .live_text => try exec_live_text(ctx),
    }
}

fn apply_event(run: *Run, console: *rich.Console, event: gen.Event, variant: Variant) void {
    const host = &run.host;
    const millisecond: i64 = 1_000_000;
    assert(event.a > 0);
    switch (event.kind) {
        .resize => {
            host.config.columns = @intCast(@min(event.a, std.math.maxInt(u16)));
            host.config.rows = @intCast(event.b);
            console.refresh_terminal();
        },
        .advance => {
            host.mono_ns +|= @as(i64, event.a) * millisecond;
            host.wall_ns +|= @as(i64, event.a) * millisecond;
        },
        .backward => host.mono_ns = @max(host.mono_ns - @as(i64, event.a) * millisecond, 0),
        .jump => {
            host.mono_ns +|= @as(i64, event.a) * 1_000_000_000;
            host.wall_ns +|= @as(i64, event.a) * 1_000_000_000;
        },
        .input => host.push_input("ok\n"),
        .fail_writes => host.fail_writes += event.a,
        .short_writes => if (!variant.strip_short_writes) {
            host.short_writes += event.a;
        },
    }
    assert(host.mono_ns >= 0);
}

fn run_step(
    run: *Run,
    console: *rich.Console,
    tracker: *Tracker,
    step: gen.Step,
    variant: Variant,
) void {
    const index = run.count;
    assert(index < gen.steps_max);
    current_step = index;
    if (tracker.live_bytes == 0) tracker.fixed.reset();
    const record = &run.records[index];
    record.* = .{ .kind = step.kind };
    assert(record.error_name.len == 0);
    const host = &run.host;
    for (step.events[0..step.event_count]) |event| apply_event(run, console, event, variant);
    host.begin_step();
    record.out_start = host.out.length;
    record.err_start = host.err.length;
    record.width = console.width();
    var prng = std.Random.DefaultPrng.init(step.seed);
    var content: gen.Content = .{};
    var arena = std.heap.ArenaAllocator.init(tracker.allocator());
    var ctx: Ctx = .{
        .console = console,
        .run = run,
        .record = record,
        .allocator = tracker.allocator(),
        .scratch = arena.allocator(),
        .random = prng.random(),
        .content = &content,
    };
    dispatch(&ctx, step.kind) catch |err| {
        record.error_name = @errorName(err);
    };
    arena.deinit();
    host.fail_writes = 0;
    host.short_writes = 0;
    finish_record(run, record, tracker);
}

fn finish_record(run: *Run, record: *Record, tracker: *Tracker) void {
    const host = &run.host;
    record.out_end = host.out.length;
    record.err_end = host.err.length;
    record.failures = host.ledger.failures;
    record.short_writes = host.ledger.short_writes;
    record.accepted_after_failure = host.ledger.accepted_after_failure;
    record.leaked_bytes = tracker.live_bytes;
    run.count += 1;
    assert(record.out_start <= record.out_end);
    assert(run.count <= gen.steps_max);
}

fn reset_host(run: *Run, scenario: *const gen.Scenario, variant: Variant) void {
    assert(scenario.step_count > 0);
    const host = &run.host;
    run.count = 0;
    run.expected_length = 0;
    host.out.length = 0;
    host.err.length = 0;
    host.out.overflowed = false;
    host.err.overflowed = false;
    host.config = scenario.config;
    host.mono_ns = scenario.mono_start_ns;
    host.wall_ns = scenario.wall_start_ns;
    host.mono_offset_ns = variant.mono_offset_ns;
    host.prng = std.Random.DefaultPrng.init(scenario.host_seed);
    host.input_length = 0;
    host.input_position = 0;
    host.fail_writes = 0;
    host.short_writes = 0;
    if (variant.force_color) force_color(&host.config);
    assert(host.out.length == 0 and host.err.length == 0);
}

pub fn execute(
    scenario: *const gen.Scenario,
    variant: Variant,
    run: *Run,
    tracker: *Tracker,
) void {
    assert(tracker.live_bytes == 0);
    reset_host(run, scenario, variant);
    var console = rich.Console.initWithHost(tracker.allocator(), run.host.host(), .{
        .width = scenario.console_width,
        .height = scenario.console_height,
        .no_color = scenario.no_color and !variant.force_color,
        .color_system = scenario.color_system,
        .force_terminal = scenario.force_terminal,
    });
    for (scenario.steps[0..scenario.step_count]) |step| {
        run_step(run, &console, tracker, step, variant);
    }
    console.deinit();
    run.final_leaked_bytes = tracker.live_bytes;
    assert(run.count == scenario.step_count);
}

fn force_color(config: *sim_host.Config) void {
    assert(config.env.count <= sim_host.env_entries_max);
    var env: sim_host.Env = .{};
    for (config.env.entries[0..config.env.count]) |entry| {
        const name = entry.name[0..entry.name_length];
        if (std.mem.eql(u8, name, "NO_COLOR") or std.mem.eql(u8, name, "FORCE_COLOR")) continue;
        if (std.mem.eql(u8, name, "TERM")) continue;
        env.set(name, entry.value[0..entry.value_length]);
    }
    env.set("FORCE_COLOR", "1");
    env.set("TERM", "xterm-256color");
    config.env = env;
    config.legacy_windows = false;
    assert(env.find("NO_COLOR") == null);
}

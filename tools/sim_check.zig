const std = @import("std");
const assert = @import("assert").assert;
const sim_host = @import("sim_host.zig");
const gen = @import("sim_generate.zig");
const scan = @import("sim_scan.zig");
const sim_run = @import("sim_run.zig");

pub const Check = enum(u8) {
    capture_overflow,
    leak,
    error_typing,
    write_after_failure,
    expected_text,
    secret_leak,
    balance,
    colors,
    fit,
    visible_equal,
    determinism,
    short_write,
    progress_offset,
};

pub const check_count = std.enums.values(Check).len;
pub const kind_count = std.enums.values(gen.Kind).len;
pub const print_max: u32 = 6;
pub const excerpt_max: u32 = 3000;

pub const Coverage = struct {
    kinds: [kind_count]u32 = std.mem.zeroes([kind_count]u32),
    failed_steps: u32 = 0,
    short_steps: u32 = 0,
    error_steps: u32 = 0,
    colored_steps: u32 = 0,
    plain_steps: u32 = 0,
    checked_fits: u32 = 0,

    pub fn add(self: *Coverage, other: Coverage) void {
        assert(self.checked_fits <= std.math.maxInt(u32) - other.checked_fits);
        assert(self.failed_steps <= std.math.maxInt(u32) - other.failed_steps);
        for (&self.kinds, other.kinds) |*total, count| total.* += count;
        self.failed_steps += other.failed_steps;
        self.short_steps += other.short_steps;
        self.error_steps += other.error_steps;
        self.colored_steps += other.colored_steps;
        self.plain_steps += other.plain_steps;
        self.checked_fits += other.checked_fits;
    }
};

pub const Scratch = struct {
    first: []u8,
    second: []u8,
};

pub const Report = struct {
    seed: u64,
    failures: u32 = 0,
    counts: [check_count]u32 = std.mem.zeroes([check_count]u32),
    printed: u32 = 0,
    overflows: u32 = 0,
    coverage: Coverage = .{},
    verbose: bool = false,
    context: []const u8 = "",

    pub fn fail(self: *Report, check: Check, step: u32, record: ?*const sim_run.Record) void {
        assert(step <= gen.steps_max);
        self.failures += 1;
        self.counts[@backingInt(check)] += 1;
        if (self.printed >= print_max) return;
        self.printed += 1;
        const kind = if (record) |item| @tagName(item.kind) else "-";
        const width = if (record) |item| item.width else 0;
        const name = if (record) |item| item.error_name else "";
        std.debug.print("FAIL seed={d} step={d} kind={s} check={s} width={d} error={s}\n", .{
            self.seed, step, kind, @tagName(check), width, name,
        });
        if (!self.verbose) return;
        const shown = self.context[0..@min(self.context.len, excerpt_max)];
        std.debug.print("  output: {f}\n", .{std.zig.fmtString(shown)});
        assert(self.printed <= print_max);
    }
};

fn env_no_color(config: *const sim_host.Config) bool {
    assert(config.env.count <= sim_host.env_entries_max);
    const no_color = config.env.find("NO_COLOR");
    if (no_color != null and no_color.?.len != 0) return true;
    if (config.env.find("FORCE_COLOR") != null) return false;
    if (!config.stdout_tty or config.legacy_windows) return true;
    const term = config.env.find("TERM") orelse return false;
    assert(term.len <= sim_host.env_text_max);
    return std.mem.eql(u8, term, "dumb");
}

fn colors_disabled(scenario: *const gen.Scenario, record: *const sim_run.Record) bool {
    return if (record.env_only_colors)
        env_no_color(&scenario.config)
    else
        scenario.no_color or (scenario.color_system == null and env_no_color(&scenario.config));
}

fn out_slice(run: *const sim_run.Run, record: *const sim_run.Record) []const u8 {
    assert(record.out_start <= record.out_end);
    assert(record.out_end <= run.host.out.length);
    return run.host.out.slice()[record.out_start..record.out_end];
}

fn err_slice(run: *const sim_run.Run, record: *const sim_run.Record) []const u8 {
    assert(record.err_start <= record.err_end);
    assert(record.err_end <= run.host.err.length);
    return run.host.err.slice()[record.err_start..record.err_end];
}

fn expected_slice(run: *const sim_run.Run, record: *const sim_run.Record) []const u8 {
    assert(record.has_expected);
    assert(record.expected_start + record.expected_length <= run.expected_length);
    return run.expected[record.expected_start..][0..record.expected_length];
}

fn error_allowed(record: *const sim_run.Record) bool {
    return record.error_name.len == 0 or
        (std.mem.eql(u8, record.error_name, "EndOfStream") and
            (record.kind == .prompt_text or record.kind == .prompt_number or
                record.kind == .prompt_password));
}

fn check_failures(report: *Report, index: u32, record: *const sim_run.Record) void {
    assert(index < gen.steps_max);
    const failed = record.error_name.len != 0;
    if (record.failures > 0) {
        if (!failed) report.fail(.error_typing, index, record);
        if (record.accepted_after_failure > 0) report.fail(.write_after_failure, index, record);
    } else if (!error_allowed(record)) {
        report.fail(.error_typing, index, record);
    }
    const write_error = std.mem.eql(u8, record.error_name, "WriteFailed");
    if (record.failures > 0 and failed and !write_error) report.fail(.error_typing, index, record);
    if (record.leaked_bytes != 0) report.fail(.leak, index, record);
    assert(report.failures >= report.counts[@backingInt(Check.leak)]);
}

fn check_text(report: *Report, run: *const sim_run.Run, visible: []const u8, index: u32) void {
    const record = &run.records[index];
    assert(index < run.count);
    assert(visible.len <= sim_host.capture_max);
    if (record.secret_length > 0) {
        const secret = expected_slice(run, record);
        if (std.mem.indexOf(u8, out_slice(run, record), secret) != null) {
            report.fail(.secret_leak, index, record);
        }
        return;
    }
    if (!record.has_expected or record.error_name.len != 0) return;
    const expected = expected_slice(run, record);
    if (record.exact) {
        if (!std.mem.eql(u8, out_slice(run, record), expected)) {
            report.fail(.expected_text, index, record);
        }
        return;
    }
    const matched = switch (record.kind) {
        .print_markup, .print_plain, .print_styled => std.mem.eql(u8, visible, expected),
        .log_record => std.mem.indexOf(u8, visible, expected) != null,
        else => true,
    };
    if (!matched) report.fail(.expected_text, index, record);
}

fn check_balance(
    report: *Report,
    index: u32,
    record: *const sim_run.Record,
    states: [2]scan.State,
) void {
    const state = states[0];
    assert(index < gen.steps_max);
    assert(!record.on_stderr or state.sgr_sequences == 0);
    if (state.incomplete or state.sgr_open or state.link_open or state.sync_open) {
        report.fail(.balance, index, record);
    }
    const err_state = states[1];
    if (err_state.incomplete or err_state.sgr_open or err_state.link_open) {
        report.fail(.balance, index, record);
    }
    if (record.balanced and (state.cursor_hidden or state.alt_screen)) {
        report.fail(.balance, index, record);
    }
}

fn check_fit(
    report: *Report,
    record: *const sim_run.Record,
    visible: []const u8,
    index: u32,
) void {
    assert(visible.len <= sim_host.capture_max);
    assert(index < gen.steps_max);
    if (record.fit_min == 0 or record.error_name.len != 0) return;
    const widest = scan.widest_line(visible);
    if (record.width < record.fit_min) {
        if (widest > record.width) report.overflows += 1;
        return;
    }
    report.coverage.checked_fits += 1;
    if (widest > record.width) report.fail(.fit, index, record);
}

fn check_scan(
    report: *Report,
    scenario: *const gen.Scenario,
    run: *const sim_run.Run,
    scratch: Scratch,
    index: u32,
) void {
    const record = &run.records[index];
    assert(index < run.count);
    assert(scratch.first.len == sim_host.capture_max);
    if (record.failures > 0 or (record.error_name.len != 0 and !error_allowed(record))) return;
    var state: scan.State = .{};
    var err_state: scan.State = .{};
    report.context = out_slice(run, record);
    const scanned = scan.scan(out_slice(run, record), &state, scratch.first);
    _ = scan.scan(err_slice(run, record), &err_state, scratch.second);
    const visible = scratch.first[0..scanned.visible_length];
    const sgr_seen = state.sgr_sequences > 0;
    if (sgr_seen) report.coverage.colored_steps += 1 else report.coverage.plain_steps += 1;
    check_balance(report, index, record, .{ state, err_state });
    const colored = state.sgr_sequences + state.link_sequences > 0;
    if (!record.on_stderr and colored and colors_disabled(scenario, record)) {
        report.fail(.colors, index, record);
    }
    check_text(report, run, visible, index);
    check_fit(report, record, visible, index);
}

fn check_visible_equal(
    report: *Report,
    first: *const sim_run.Run,
    second: *const sim_run.Run,
    scratch: Scratch,
    index: u32,
) void {
    assert(index < first.count and index < second.count);
    assert(first != second);
    const left = &first.records[index];
    const right = &second.records[index];
    if (left.failures > 0 or right.failures > 0) return;
    var left_state: scan.State = .{};
    var right_state: scan.State = .{};
    const a = scan.scan(out_slice(first, left), &left_state, scratch.first);
    const b = scan.scan(out_slice(second, right), &right_state, scratch.second);
    const left_text = scratch.first[0..a.visible_length];
    const same = std.mem.eql(u8, left_text, scratch.second[0..b.visible_length]);
    if (!same or !std.mem.eql(u8, left.error_name, right.error_name)) {
        report.fail(.visible_equal, index, left);
    }
}

fn count_record(report: *Report, record: *const sim_run.Record) void {
    const coverage = &report.coverage;
    assert(@backingInt(record.kind) < kind_count);
    coverage.kinds[@backingInt(record.kind)] += 1;
    if (record.failures > 0) coverage.failed_steps += 1;
    if (record.short_writes > 0) coverage.short_steps += 1;
    if (record.error_name.len > 0) coverage.error_steps += 1;
    assert(coverage.kinds[@backingInt(record.kind)] < 1 << 30);
}

pub fn check_run(
    report: *Report,
    scenario: *const gen.Scenario,
    run: *const sim_run.Run,
    scratch: Scratch,
) void {
    assert(run.count == scenario.step_count);
    if (run.host.out.overflowed or run.host.err.overflowed) report.fail(.capture_overflow, 0, null);
    if (run.final_leaked_bytes != 0) report.fail(.leak, run.count, null);
    for (0..run.count) |position| {
        const index: u32 = @intCast(position);
        count_record(report, &run.records[index]);
        check_failures(report, index, &run.records[index]);
        check_scan(report, scenario, run, scratch, index);
    }
    assert(run.final_leaked_bytes == 0 or report.counts[@backingInt(Check.leak)] > 0);
}

pub fn compare_bytes(
    report: *Report,
    check: Check,
    first: *const sim_run.Run,
    second: *const sim_run.Run,
) void {
    assert(first.count == second.count);
    assert(check == .determinism or check == .short_write);
    const same_out = std.mem.eql(u8, first.host.out.slice(), second.host.out.slice());
    const same_err = std.mem.eql(u8, first.host.err.slice(), second.host.err.slice());
    if (!same_out or !same_err) report.fail(check, first.count, null);
}

pub fn compare_colors(
    report: *Report,
    first: *const sim_run.Run,
    second: *const sim_run.Run,
    scratch: Scratch,
) void {
    assert(first.count == second.count);
    assert(scratch.first.len == scratch.second.len);
    for (0..first.count) |position| {
        check_visible_equal(report, first, second, scratch, @intCast(position));
    }
}

pub fn compare_progress(
    report: *Report,
    first: *const sim_run.Run,
    second: *const sim_run.Run,
) void {
    assert(first.count == second.count);
    assert(first != second);
    for (0..first.count) |position| {
        const index: u32 = @intCast(position);
        const left = &first.records[index];
        const right = &second.records[index];
        if (!left.progress) continue;
        const same_bytes = std.mem.eql(u8, out_slice(first, left), out_slice(second, right));
        const same_error = std.mem.eql(u8, left.error_name, right.error_name);
        if (!same_bytes or !same_error) report.fail(.progress_offset, index, left);
    }
}

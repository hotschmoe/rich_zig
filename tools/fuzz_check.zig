const std = @import("std");
const rich = @import("rich_zig");
const workload = @import("fuzz_generate.zig");
const Tracker = @import("fuzz_memory.zig").Tracker;
const assert = @import("assert").assert;

pub const memory_max: u32 = 4 * 1024 * 1024;
pub const Counters = struct {
    accepted: u64 = 0,
    rejected: u64 = 0,
    deterministic: u64 = 0,
    plain_oracle: u64 = 0,
    styled_oracle: u64 = 0,
    utf8: u64 = 0,
    invalid_utf8: u64 = 0,
    escaped: u64 = 0,
    memory_success: u64 = 0,
    memory_failure: u64 = 0,
    hyperlinks: u64 = 0,
    background: u64 = 0,
    ownership: u64 = 0,
    color_forms: [5]u64 = @splat(0),
    text_forms: [10]u64 = @splat(0),
    named_colors: [19]u64 = @splat(0),
    profiles: [workload.profiles]u64 = @splat(0),
    attributes: [13]u64 = @splat(0),
    bracket_positions: [18]u64 = @splat(0),
};

pub fn check(case: *const workload.Case, memory: []u8, counters: *Counters) !void {
    assert(memory.len == 3 * memory_max);
    var first_memory = Tracker{ .fixed = .init(memory[0..memory_max]) };
    var second_memory = Tracker{ .fixed = .init(memory[memory_max..][0..memory_max]) };
    const first = rich.Text.fromMarkup(first_memory.allocator(), case.input.slice());
    const second = rich.Text.fromMarkup(second_memory.allocator(), case.input.slice());
    try compare(case, first, second, counters);
    if (first_memory.live_bytes != 0 or second_memory.live_bytes != 0) return error.MemoryLeak;
    const attempts = first_memory.allocations;
    if (attempts > 1024) return error.AllocationWorkLimit;
    try probe_memory(case, memory[2 * memory_max ..], attempts, counters);
    if (case.expected_error == null)
        counters.ownership += try @import("fuzz_ownership.zig").check(
            case,
            memory[2 * memory_max ..],
        );
    counters.profiles[case.profile] += 1;
    if (case.profile == 13) counters.bracket_positions[case.bracket_position] += 1;
    for (&counters.color_forms, 0..) |*count, bit|
        count.* += @intFromBool(case.color_forms & (@as(u8, 1) << @intCast(bit)) != 0);
    for (&counters.text_forms, 0..) |*count, bit|
        count.* += @intFromBool(case.text_forms & (@as(u16, 1) << @intCast(bit)) != 0);
    for (&counters.named_colors, 0..) |*count, bit|
        count.* += @intFromBool(case.named_colors & (@as(u32, 1) << @intCast(bit)) != 0);
    counters.deterministic += 1;
    assert(counters.accepted + counters.rejected == counters.deterministic);
}

fn compare(
    case: *const workload.Case,
    first_result: anyerror!rich.Text,
    second_result: anyerror!rich.Text,
    counters: *Counters,
) !void {
    assert(case.input.length <= workload.input_max);
    if (first_result) |value| {
        var first = value;
        defer first.deinit();
        var second = second_result catch return error.NondeterministicError;
        defer second.deinit();
        if (case.expected_error != null) return error.AcceptedMalformed;
        if (!std.mem.eql(u8, first.plain, second.plain)) return error.NondeterministicText;
        if (first.spans.len != second.spans.len) return error.NondeterministicSpans;
        for (first.spans, second.spans) |a, b| {
            if (a.start != b.start or a.end != b.end or !styles_equal(a.style, b.style))
                return error.NondeterministicStyle;
        }
        try boundaries(first);
        try plain_and_styles(case, first);
        counters.accepted += 1;
        counters.plain_oracle += 1;
        counters.styled_oracle += @intFromBool(first.spans.len > 0);
        counters.hyperlinks += @intFromBool(case.features & 1 != 0);
        counters.background += @intFromBool(case.features & 2 != 0);
        if (std.unicode.utf8ValidateSlice(first.plain)) {
            counters.utf8 += 1;
        } else {
            counters.invalid_utf8 += 1;
        }
        for (case.runs[0..case.run_count]) |run| {
            for (0..13) |bit| {
                counters.attributes[bit] += @intFromBool(
                    run.style.set_attributes & (@as(u16, 1) << @intCast(bit)) != 0,
                );
            }
        }
    } else |err| {
        if (second_result) |value| {
            var second = value;
            second.deinit();
            return error.NondeterministicAcceptance;
        } else |other| {
            if (err != other) return error.NondeterministicError;
        }
        if (!expected_error(case, err)) return err;
        counters.rejected += 1;
    }
    assert(counters.accepted + counters.rejected > 0);
}

pub fn boundaries(text: rich.Text) !void {
    var end: usize = 0;
    const valid = std.unicode.utf8ValidateSlice(text.plain);
    assert(text.spans.len <= text.plain.len);
    for (text.spans) |span| {
        if (span.start < end or span.start >= span.end or span.end > text.plain.len)
            return error.SpanRange;
        if (valid) {
            if (span.start < text.plain.len and text.plain[span.start] & 0xc0 == 0x80)
                return error.SpanUtf8;
            if (span.end < text.plain.len and text.plain[span.end] & 0xc0 == 0x80)
                return error.SpanUtf8;
        }
        end = span.end;
    }
    assert(end <= text.plain.len);
}

pub fn plain_and_styles(case: *const workload.Case, text: rich.Text) !void {
    assert(case.run_count <= workload.runs_max);
    if (!std.mem.eql(u8, case.plain.slice(), text.plain)) return error.PlainOracle;
    var run_index: u32 = 0;
    var span_index: usize = 0;
    for (0..text.plain.len) |position| {
        while (run_index < case.run_count and position >= case.runs[run_index].end)
            run_index += 1;
        if (run_index == case.run_count) return error.OracleRunMissing;
        while (span_index < text.spans.len and position >= text.spans[span_index].end)
            span_index += 1;
        const in_span = span_index < text.spans.len and
            position >= text.spans[span_index].start;
        const actual = if (in_span) text.spans[span_index].style else rich.Style{};
        if (!styles_equal(actual, case.runs[run_index].style)) return error.StyleOracle;
    }
    assert(text.plain.len == case.plain.length);
}

fn styles_equal(a: rich.Style, b: rich.Style) bool {
    return a.attributes == b.attributes and a.set_attributes == b.set_attributes and
        std.meta.eql(a.color, b.color) and std.meta.eql(a.bgcolor, b.bgcolor) and
        links_equal(a.link, b.link);
}

fn links_equal(a: ?[]const u8, b: ?[]const u8) bool {
    return if (a) |link| if (b) |other| std.mem.eql(u8, link, other) else false else b == null;
}

fn probe_memory(
    case: *const workload.Case,
    memory: []u8,
    attempts: u32,
    counters: *Counters,
) !void {
    assert(memory.len == memory_max);
    assert(attempts <= 1024);
    for (0..attempts + 1) |limit| {
        var tracker = Tracker{ .fixed = .init(memory), .fail_at = @intCast(limit) };
        var parsed = rich.Text.fromMarkup(tracker.allocator(), case.input.slice()) catch |err| {
            if (tracker.live_bytes != 0) return error.MemoryLeakOnError;
            if (err == error.OutOfMemory) {
                counters.memory_failure += 1;
                continue;
            }
            if (!expected_error(case, err)) return err;
            continue;
        };
        parsed.deinit();
        if (tracker.live_bytes != 0) return error.MemoryLeakOnSuccess;
        counters.memory_success += 1;
    }
    for ([_]u32{ 0, 1, 31, 127, 1024 }) |size| {
        var tracker = Tracker{ .fixed = .init(memory[0..size]) };
        try limited_parse(case, &tracker, counters);
    }
    try probe_other_parsers(case, memory, counters);
    try public_functions(case, memory, counters);
}

fn limited_parse(case: *const workload.Case, tracker: *Tracker, counters: *Counters) !void {
    assert(tracker.live_bytes == 0);
    var parsed = rich.Text.fromMarkup(tracker.allocator(), case.input.slice()) catch |err| {
        if (tracker.live_bytes != 0) return error.MemoryLeakOnError;
        if (err != error.OutOfMemory and !expected_error(case, err)) return err;
        counters.memory_failure += @intFromBool(err == error.OutOfMemory);
        return;
    };
    parsed.deinit();
    if (tracker.live_bytes != 0) return error.MemoryLeakOnSuccess;
    counters.memory_success += 1;
    assert(tracker.live_bytes == 0);
}

const Api = enum { themed, tokens, render };

fn probe_other_parsers(case: *const workload.Case, memory: []u8, counters: *Counters) !void {
    assert(memory.len == memory_max);
    for (std.enums.values(Api)) |api| {
        var full = Tracker{ .fixed = .init(memory) };
        observe_api(case, &full, api) catch |err| {
            if (!expected_error(case, err)) return err;
        };
        if (full.live_bytes != 0) return error.MemoryLeakOnSuccess;
        if (full.allocations > 1024) return error.AllocationWorkLimit;
        for (0..full.allocations) |limit| {
            var tracker = Tracker{ .fixed = .init(memory), .fail_at = @intCast(limit) };
            observe_api(case, &tracker, api) catch |err| {
                if (err != error.OutOfMemory and !expected_error(case, err)) return err;
                counters.memory_failure += @intFromBool(err == error.OutOfMemory);
            };
            if (tracker.live_bytes != 0) return error.MemoryLeakOnError;
        }
    }
    assert(counters.memory_failure > 0);
}

fn observe_api(case: *const workload.Case, tracker: *Tracker, api: Api) !void {
    assert(tracker.live_bytes == 0);
    const allocator = tracker.allocator();
    switch (api) {
        .themed => {
            var theme = rich.Theme.init(allocator);
            defer theme.deinit();
            var parsed = try rich.Text.fromMarkupWithTheme(allocator, case.input.slice(), theme);
            defer parsed.deinit();
            try boundaries(parsed);
            try plain_and_styles(case, parsed);
        },
        .tokens => {
            const tokens = try rich.markup.parseMarkup(case.input.slice(), allocator);
            allocator.free(tokens);
        },
        .render => {
            const segments = try rich.markup.render(case.input.slice(), .{}, allocator);
            allocator.free(segments);
        },
    }
    if (case.expected_error != null) return error.AcceptedMalformed;
    assert(tracker.live_bytes == 0);
}

fn public_functions(case: *const workload.Case, memory: []u8, counters: *Counters) !void {
    assert(memory.len == memory_max);
    var fixed = std.heap.FixedBufferAllocator.init(memory);
    const allocator = fixed.allocator();
    const stripped = rich.markup.stripMarkup(case.input.slice(), allocator) catch |err| {
        if (!expected_error(case, err)) return err;
        return;
    };
    defer allocator.free(stripped);
    if (case.expected_error != null) return error.AcceptedMalformed;
    if (!std.mem.eql(u8, stripped, case.plain.slice())) return error.StripOracle;
    const escaped = try rich.markup.escape(case.plain.slice(), allocator);
    defer allocator.free(escaped);
    var literal = try rich.Text.fromMarkup(allocator, escaped);
    defer literal.deinit();
    if (!std.mem.eql(u8, literal.plain, case.plain.slice())) return error.EscapeOracle;
    if (literal.spans.len != 0) return error.EscapedStyle;
    try rendered_text(case, allocator);
    counters.escaped += 1;
    assert(literal.plain.len == case.plain.length);
}

fn rendered_text(case: *const workload.Case, allocator: std.mem.Allocator) !void {
    assert(case.expected_error == null);
    const segments = try rich.markup.render(case.input.slice(), .{}, allocator);
    defer allocator.free(segments);
    const expected_length = case.plain.length;
    var position: usize = 0;
    var run_index: u32 = 0;
    for (segments) |segment| {
        for (segment.text) |byte| {
            if (position >= expected_length) return error.RenderLength;
            const expected = case.plain.bytes[position];
            if (byte != expected) return error.RenderText;
            while (run_index < case.run_count and position >= case.runs[run_index].end)
                run_index += 1;
            if (run_index == case.run_count) return error.OracleRunMissing;
            if (!styles_equal(segment.style orelse .{}, case.runs[run_index].style))
                return error.RenderStyle;
            position += 1;
        }
    }
    if (position != expected_length) return error.RenderLength;
    assert(position == case.plain.length);
}

fn expected_error(case: *const workload.Case, err: anyerror) bool {
    return if (case.expected_error) |expected| err == expected else false;
}

const std = @import("std");
const assert = @import("assert").assert;

pub const State = struct {
    sgr_open: bool = false,
    link_open: bool = false,
    cursor_hidden: bool = false,
    alt_screen: bool = false,
    sync_open: bool = false,
    sgr_sequences: u32 = 0,
    link_sequences: u32 = 0,
    incomplete: bool = false,
};

pub const Scanned = struct { visible_length: u32, truncated: bool };

const Range = struct { low: u32, high: u32 };

const zero_ranges = [_]Range{
    .{ .low = 0x0000, .high = 0x001f },   .{ .low = 0x007f, .high = 0x009f },
    .{ .low = 0x0300, .high = 0x036f },   .{ .low = 0x0483, .high = 0x0489 },
    .{ .low = 0x0591, .high = 0x05bd },   .{ .low = 0x05bf, .high = 0x05bf },
    .{ .low = 0x05c1, .high = 0x05c2 },   .{ .low = 0x05c4, .high = 0x05c5 },
    .{ .low = 0x05c7, .high = 0x05c7 },   .{ .low = 0x0610, .high = 0x061a },
    .{ .low = 0x064b, .high = 0x065f },   .{ .low = 0x0670, .high = 0x0670 },
    .{ .low = 0x06d6, .high = 0x06dc },   .{ .low = 0x06df, .high = 0x06e4 },
    .{ .low = 0x06e7, .high = 0x06e8 },   .{ .low = 0x06ea, .high = 0x06ed },
    .{ .low = 0x0e31, .high = 0x0e31 },   .{ .low = 0x0e34, .high = 0x0e3a },
    .{ .low = 0x0e47, .high = 0x0e4e },   .{ .low = 0x1ab0, .high = 0x1aff },
    .{ .low = 0x1dc0, .high = 0x1dff },   .{ .low = 0x200b, .high = 0x200f },
    .{ .low = 0x2028, .high = 0x202e },   .{ .low = 0x2060, .high = 0x2064 },
    .{ .low = 0x20d0, .high = 0x20ff },   .{ .low = 0xfe00, .high = 0xfe0f },
    .{ .low = 0xfe20, .high = 0xfe2f },   .{ .low = 0xfeff, .high = 0xfeff },
    .{ .low = 0xe0100, .high = 0xe01ef },
};

const wide_ranges = [_]Range{
    .{ .low = 0x1100, .high = 0x115f },   .{ .low = 0x2e80, .high = 0x303e },
    .{ .low = 0x3041, .high = 0x33ff },   .{ .low = 0x3400, .high = 0x4dbf },
    .{ .low = 0x4e00, .high = 0x9fff },   .{ .low = 0xa000, .high = 0xa4cf },
    .{ .low = 0xac00, .high = 0xd7a3 },   .{ .low = 0xf900, .high = 0xfaff },
    .{ .low = 0xfe30, .high = 0xfe6f },   .{ .low = 0xff00, .high = 0xff60 },
    .{ .low = 0xffe0, .high = 0xffe6 },   .{ .low = 0x1f300, .high = 0x1f64f },
    .{ .low = 0x1f900, .high = 0x1f9ff }, .{ .low = 0x20000, .high = 0x3fffd },
};

fn in_ranges(ranges: []const Range, code: u32) bool {
    assert(ranges.len > 0);
    for (ranges) |range| {
        assert(range.low <= range.high);
        if (code >= range.low and code <= range.high) return true;
    }
    return false;
}

pub fn code_width(code: u32) u32 {
    assert(code <= 0x10ffff);
    if (in_ranges(&zero_ranges, code)) return 0;
    if (in_ranges(&wide_ranges, code)) return 2;
    assert(!in_ranges(&zero_ranges, code) and !in_ranges(&wide_ranges, code));
    return 1;
}

const Decoded = struct { length: u32, code: u32 };

fn decode(text: []const u8, index: usize) ?Decoded {
    assert(index < text.len);
    const length = std.unicode.utf8ByteSequenceLength(text[index]) catch return null;
    if (index + length > text.len) return null;
    const code = std.unicode.utf8Decode(text[index..][0..length]) catch return null;
    assert(length >= 1 and length <= 4);
    return .{ .length = length, .code = code };
}

pub fn text_width(text: []const u8) u32 {
    assert(text.len <= std.math.maxInt(u32) / 2);
    var total: u32 = 0;
    var index: usize = 0;
    while (index < text.len) {
        const decoded = decode(text, index) orelse {
            total += 1;
            index += 1;
            continue;
        };
        total += code_width(decoded.code);
        index += decoded.length;
    }
    assert(total <= text.len * 2);
    return total;
}

pub fn widest_line(visible: []const u8) u32 {
    assert(visible.len <= std.math.maxInt(u32));
    var widest: u32 = 0;
    var lines = std.mem.splitScalar(u8, visible, '\n');
    while (lines.next()) |line| widest = @max(widest, text_width(line));
    assert(widest <= visible.len * 2);
    return widest;
}

fn apply_private_mode(state: *State, params: []const u8, enable: bool) void {
    assert(params.len < 64);
    if (std.mem.eql(u8, params, "?25")) state.cursor_hidden = !enable;
    if (std.mem.eql(u8, params, "?1049")) state.alt_screen = enable;
    if (std.mem.eql(u8, params, "?2026")) state.sync_open = enable;
    assert(!state.sync_open or std.mem.eql(u8, params, "?2026") or !enable);
}

fn is_reset(params: []const u8) bool {
    assert(params.len < 64);
    if (params.len == 0) return true;
    for (params) |byte| {
        if (byte != '0' and byte != ';') return false;
    }
    assert(params[0] == '0' or params[0] == ';');
    return true;
}

fn scan_csi(bytes: []const u8, state: *State) usize {
    assert(bytes.len >= 2 and bytes[0] == 0x1b and bytes[1] == '[');
    var end: usize = 2;
    while (end < bytes.len and bytes[end] >= 0x20 and bytes[end] <= 0x3f) end += 1;
    if (end >= bytes.len) {
        state.incomplete = true;
        return bytes.len;
    }
    const params = bytes[2..end];
    switch (bytes[end]) {
        'm' => {
            state.sgr_sequences += 1;
            state.sgr_open = !is_reset(params);
        },
        'h' => apply_private_mode(state, params, true),
        'l' => apply_private_mode(state, params, false),
        else => {},
    }
    assert(end < bytes.len);
    return end + 1;
}

fn scan_osc(bytes: []const u8, state: *State) usize {
    assert(bytes.len >= 2 and bytes[0] == 0x1b and bytes[1] == ']');
    var end: usize = 2;
    while (end < bytes.len) : (end += 1) {
        if (bytes[end] == 0x07) break;
        if (bytes[end] == 0x1b and end + 1 < bytes.len and bytes[end + 1] == '\\') break;
    }
    if (end >= bytes.len) {
        state.incomplete = true;
        return bytes.len;
    }
    const body = bytes[2..end];
    if (std.mem.startsWith(u8, body, "8;")) {
        const separator = std.mem.indexOfScalarPos(u8, body, 2, ';') orelse body.len - 1;
        state.link_sequences += 1;
        state.link_open = separator + 1 < body.len;
    }
    assert(end < bytes.len);
    return if (bytes[end] == 0x07) end + 1 else end + 2;
}

pub fn scan(bytes: []const u8, state: *State, visible: []u8) Scanned {
    assert(visible.len > 0);
    var index: usize = 0;
    var length: u32 = 0;
    var truncated = false;
    while (index < bytes.len) {
        if (bytes[index] != 0x1b) {
            if (length < visible.len) {
                visible[length] = bytes[index];
                length += 1;
            } else {
                truncated = true;
            }
            index += 1;
            continue;
        }
        const rest = bytes[index..];
        if (rest.len < 2) {
            state.incomplete = true;
            break;
        }
        index += switch (rest[1]) {
            '[' => scan_csi(rest, state),
            ']' => scan_osc(rest, state),
            else => 2,
        };
    }
    assert(length <= visible.len);
    return .{ .visible_length = length, .truncated = truncated };
}

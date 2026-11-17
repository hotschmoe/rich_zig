const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;

pub const JsonTheme = struct {
    key_style: Style = Style.empty.foreground(Color.cyan),
    string_style: Style = Style.empty.foreground(Color.green),
    number_style: Style = Style.empty.foreground(Color.magenta),
    bool_style: Style = Style.empty.foreground(Color.yellow),
    null_style: Style = Style.empty.dim(),
    bracket_style: Style = Style.empty,
    colon_style: Style = Style.empty,
    comma_style: Style = Style.empty.dim(),
    ellipsis_style: Style = Style.empty.dim(),

    pub const default: JsonTheme = .{};

    pub const monokai: JsonTheme = .{
        .key_style = Style.empty.foreground(Color.fromRgb(166, 226, 46)),
        .string_style = Style.empty.foreground(Color.fromRgb(230, 219, 116)),
        .number_style = Style.empty.foreground(Color.fromRgb(174, 129, 255)),
        .bool_style = Style.empty.foreground(Color.fromRgb(174, 129, 255)),
        .null_style = Style.empty.foreground(Color.fromRgb(174, 129, 255)),
        .bracket_style = Style.empty,
        .colon_style = Style.empty,
        .comma_style = Style.empty.dim(),
        .ellipsis_style = Style.empty.foreground(Color.fromRgb(117, 113, 94)),
    };
};

pub const Json = struct {
    value: std.json.Value,
    theme: JsonTheme = JsonTheme.default,
    indent: u8 = 2,
    sort_keys: bool = false,
    max_depth: ?usize = null,
    max_string_length: ?usize = null,
    allocator: std.mem.Allocator,
    parsed: ?std.json.Parsed(std.json.Value) = null,

    pub fn init(allocator: std.mem.Allocator, value: std.json.Value) Json {
        return .{
            .value = value,
            .allocator = allocator,
        };
    }

    pub fn fromString(allocator: std.mem.Allocator, json_str: []const u8) !Json {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        return .{
            .value = parsed.value,
            .allocator = allocator,
            .parsed = parsed,
        };
    }

    pub fn deinit(self: *Json) void {
        if (self.parsed) |p| {
            p.deinit();
        }
    }

    pub fn withTheme(self: Json, theme: JsonTheme) Json {
        var j = self;
        j.theme = theme;
        return j;
    }

    pub fn withIndent(self: Json, spaces: u8) Json {
        var j = self;
        j.indent = spaces;
        return j;
    }

    pub fn withSortKeys(self: Json, sort: bool) Json {
        var j = self;
        j.sort_keys = sort;
        return j;
    }

    pub fn withMaxDepth(self: Json, depth: ?usize) Json {
        var j = self;
        j.max_depth = depth;
        return j;
    }

    pub fn withMaxStringLength(self: Json, length: ?usize) Json {
        var j = self;
        j.max_string_length = length;
        return j;
    }

    pub fn render(self: Json, _: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;
        try self.renderValue(&segments, allocator, self.value, 0);
        return segments.toOwnedSlice(allocator);
    }

    fn renderValue(self: Json, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, value: std.json.Value, depth: usize) !void {
        switch (value) {
            .null => try segments.append(allocator, Segment.styled("null", self.theme.null_style)),
            .bool => |b| {
                const text = if (b) "true" else "false";
                try segments.append(allocator, Segment.styled(text, self.theme.bool_style));
            },
            .integer => |i| {
                var buf: [32]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch blk: {
                    buf[0] = '?';
                    break :blk buf[0..1];
                };
                const str = try allocator.dupe(u8, slice);
                try segments.append(allocator, Segment.styled(str, self.theme.number_style));
            },
            .float => |f| {
                var buf: [64]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch blk: {
                    buf[0] = '?';
                    break :blk buf[0..1];
                };
                const str = try allocator.dupe(u8, slice);
                try segments.append(allocator, Segment.styled(str, self.theme.number_style));
            },
            .string => |s| {
                try segments.append(allocator, Segment.styled("\"", self.theme.string_style));
                if (self.max_string_length) |max_len| {
                    if (s.len > max_len) {
                        const truncated = try truncateUtf8(s, max_len, allocator);
                        try segments.append(allocator, Segment.styled(truncated, self.theme.string_style));
                        try segments.append(allocator, Segment.styled("...", self.theme.ellipsis_style));
                    } else {
                        try segments.append(allocator, Segment.styled(s, self.theme.string_style));
                    }
                } else {
                    try segments.append(allocator, Segment.styled(s, self.theme.string_style));
                }
                try segments.append(allocator, Segment.styled("\"", self.theme.string_style));
            },
            .array => |arr| {
                if (self.max_depth) |max_d| {
                    if (depth >= max_d) {
                        try segments.append(allocator, Segment.styled("[...]", self.theme.ellipsis_style));
                        return;
                    }
                }
                try segments.append(allocator, Segment.styled("[", self.theme.bracket_style));
                if (arr.items.len > 0) {
                    try segments.append(allocator, Segment.line());
                    for (arr.items, 0..) |item, i| {
                        try self.renderIndent(segments, allocator, depth + 1);
                        try self.renderValue(segments, allocator, item, depth + 1);
                        if (i < arr.items.len - 1) {
                            try segments.append(allocator, Segment.styled(",", self.theme.comma_style));
                        }
                        try segments.append(allocator, Segment.line());
                    }
                    try self.renderIndent(segments, allocator, depth);
                }
                try segments.append(allocator, Segment.styled("]", self.theme.bracket_style));
            },
            .object => |obj| {
                if (self.max_depth) |max_d| {
                    if (depth >= max_d) {
                        try segments.append(allocator, Segment.styled("{...}", self.theme.ellipsis_style));
                        return;
                    }
                }
                try segments.append(allocator, Segment.styled("{", self.theme.bracket_style));
                if (obj.count() > 0) {
                    try segments.append(allocator, Segment.line());
                    const count = obj.count();

                    if (self.sort_keys) {
                        const keys = try allocator.alloc([]const u8, count);
                        defer allocator.free(keys);
                        var iter = obj.iterator();
                        var k: usize = 0;
                        while (iter.next()) |entry| {
                            keys[k] = entry.key_ptr.*;
                            k += 1;
                        }
                        std.mem.sort([]const u8, keys, {}, struct {
                            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                                return std.mem.order(u8, a, b) == .lt;
                            }
                        }.lessThan);
                        for (keys, 0..) |key, i| {
                            try self.renderKeyValue(segments, allocator, key, obj.get(key).?, depth, i, count);
                        }
                    } else {
                        var iter = obj.iterator();
                        var i: usize = 0;
                        while (iter.next()) |entry| {
                            try self.renderKeyValue(segments, allocator, entry.key_ptr.*, entry.value_ptr.*, depth, i, count);
                            i += 1;
                        }
                    }
                    try self.renderIndent(segments, allocator, depth);
                }
                try segments.append(allocator, Segment.styled("}", self.theme.bracket_style));
            },
            .number_string => |s| {
                try segments.append(allocator, Segment.styled(s, self.theme.number_style));
            },
        }
    }

    fn renderKeyValue(self: Json, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, key: []const u8, value: std.json.Value, depth: usize, index: usize, count: usize) std.mem.Allocator.Error!void {
        try self.renderIndent(segments, allocator, depth + 1);
        try segments.append(allocator, Segment.styled("\"", self.theme.key_style));
        try segments.append(allocator, Segment.styled(key, self.theme.key_style));
        try segments.append(allocator, Segment.styled("\"", self.theme.key_style));
        try segments.append(allocator, Segment.styled(": ", self.theme.colon_style));
        try self.renderValue(segments, allocator, value, depth + 1);
        if (index < count - 1) {
            try segments.append(allocator, Segment.styled(",", self.theme.comma_style));
        }
        try segments.append(allocator, Segment.line());
    }

    fn truncateUtf8(s: []const u8, max_chars: usize, allocator: std.mem.Allocator) ![]const u8 {
        var char_count: usize = 0;
        var byte_index: usize = 0;
        while (byte_index < s.len and char_count < max_chars) {
            const byte = s[byte_index];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
            if (byte_index + char_len > s.len) break;
            byte_index += char_len;
            char_count += 1;
        }
        return allocator.dupe(u8, s[0..byte_index]);
    }

    const max_indent_spaces = 128;
    const indent_buffer: [max_indent_spaces]u8 = @splat(' ');

    fn renderIndent(self: Json, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, depth: usize) !void {
        const total_spaces = depth * self.indent;
        if (total_spaces == 0) return;

        if (total_spaces <= max_indent_spaces) {
            try segments.append(allocator, Segment.plain(indent_buffer[0..total_spaces]));
        } else {
            const spaces = try allocator.alloc(u8, total_spaces);
            @memset(spaces, ' ');
            try segments.append(allocator, Segment.plain(spaces));
        }
    }
};

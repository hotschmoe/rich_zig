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
    };
};

pub const Json = struct {
    value: std.json.Value,
    theme: JsonTheme = JsonTheme.default,
    indent: u8 = 2,
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
                const len = (std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?").len;
                const str = try allocator.dupe(u8, buf[0..len]);
                try segments.append(allocator, Segment.styled(str, self.theme.number_style));
            },
            .float => |f| {
                var buf: [64]u8 = undefined;
                const len = (std.fmt.bufPrint(&buf, "{d}", .{f}) catch "?").len;
                const str = try allocator.dupe(u8, buf[0..len]);
                try segments.append(allocator, Segment.styled(str, self.theme.number_style));
            },
            .string => |s| {
                try segments.append(allocator, Segment.styled("\"", self.theme.string_style));
                try segments.append(allocator, Segment.styled(s, self.theme.string_style));
                try segments.append(allocator, Segment.styled("\"", self.theme.string_style));
            },
            .array => |arr| {
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
                try segments.append(allocator, Segment.styled("{", self.theme.bracket_style));
                if (obj.count() > 0) {
                    try segments.append(allocator, Segment.line());
                    var iter = obj.iterator();
                    var i: usize = 0;
                    const count = obj.count();
                    while (iter.next()) |entry| {
                        try self.renderIndent(segments, allocator, depth + 1);
                        try segments.append(allocator, Segment.styled("\"", self.theme.key_style));
                        try segments.append(allocator, Segment.styled(entry.key_ptr.*, self.theme.key_style));
                        try segments.append(allocator, Segment.styled("\"", self.theme.key_style));
                        try segments.append(allocator, Segment.styled(": ", self.theme.colon_style));
                        try self.renderValue(segments, allocator, entry.value_ptr.*, depth + 1);
                        if (i < count - 1) {
                            try segments.append(allocator, Segment.styled(",", self.theme.comma_style));
                        }
                        try segments.append(allocator, Segment.line());
                        i += 1;
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

    const max_indent_spaces = 128;
    const indent_buffer: *const [max_indent_spaces]u8 = &([1]u8{' '} ** max_indent_spaces);

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

test "JsonTheme.default" {
    const theme = JsonTheme.default;
    try std.testing.expect(theme.key_style.color != null);
}

test "Json.init" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .null = {} };
    const json = Json.init(allocator, value);
    try std.testing.expectEqual(@as(u8, 2), json.indent);
}

test "Json.withTheme" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .null = {} };
    const json = Json.init(allocator, value).withTheme(JsonTheme.monokai);
    try std.testing.expect(json.theme.key_style.color != null);
}

test "Json.withIndent" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .null = {} };
    const json = Json.init(allocator, value).withIndent(4);
    try std.testing.expectEqual(@as(u8, 4), json.indent);
}

test "Json.render null" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .null = {} };
    const json = Json.init(allocator, value);

    const segments = try json.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);
    try std.testing.expectEqualStrings("null", segments[0].text);
}

test "Json.render bool" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .bool = true };
    const json = Json.init(allocator, value);

    const segments = try json.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expectEqualStrings("true", segments[0].text);
}

test "Json.render string" {
    const allocator = std.testing.allocator;
    const value = std.json.Value{ .string = "hello" };
    const json = Json.init(allocator, value);

    const segments = try json.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len >= 3);
    try std.testing.expectEqualStrings("\"", segments[0].text);
    try std.testing.expectEqualStrings("hello", segments[1].text);
    try std.testing.expectEqualStrings("\"", segments[2].text);
}

test "Json.render integer" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const value = std.json.Value{ .integer = 42 };
    const json = Json.init(allocator, value);

    const segments = try json.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
    try std.testing.expectEqualStrings("42", segments[0].text);
}

test "Json.fromString" {
    const allocator = std.testing.allocator;
    var json = try Json.fromString(allocator, "42");
    defer json.deinit();

    try std.testing.expectEqual(@as(i64, 42), json.value.integer);
}

test "Json.render object with properties" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var json = try Json.fromString(allocator,
        \\{"name": "test", "value": 42}
    );
    defer json.deinit();

    const segments = try json.render(80, arena.allocator());
    const text = try @import("../segment.zig").joinText(segments, arena.allocator());

    try std.testing.expect(std.mem.indexOf(u8, text, "name") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "42") != null);
}

test "Json.render array with items" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var json = try Json.fromString(allocator, "[1, 2, 3]");
    defer json.deinit();

    const segments = try json.render(80, arena.allocator());
    const text = try @import("../segment.zig").joinText(segments, arena.allocator());

    try std.testing.expect(std.mem.indexOf(u8, text, "1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "3") != null);
}

test "Json.render nested structure" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var json = try Json.fromString(allocator,
        \\{"outer": {"inner": {"deep": true}}}
    );
    defer json.deinit();

    const segments = try json.render(80, arena.allocator());
    const text = try @import("../segment.zig").joinText(segments, arena.allocator());

    try std.testing.expect(std.mem.indexOf(u8, text, "outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "deep") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "true") != null);
}

test "Json.render deeply nested array" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var json = try Json.fromString(allocator, "[[[[1]]]]");
    defer json.deinit();

    const segments = try json.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
}

test "Json.render mixed nested structure" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var json = try Json.fromString(allocator,
        \\{"items": [{"id": 1}, {"id": 2}], "count": 2}
    );
    defer json.deinit();

    const segments = try json.render(80, arena.allocator());
    const text = try @import("../segment.zig").joinText(segments, arena.allocator());

    try std.testing.expect(std.mem.indexOf(u8, text, "items") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "id") != null);
}

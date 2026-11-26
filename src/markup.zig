const std = @import("std");
const Style = @import("style.zig").Style;
const Segment = @import("segment.zig").Segment;

pub const Tag = struct {
    name: []const u8,
    parameters: ?[]const u8 = null,
    source: []const u8 = "",
};

pub const MarkupToken = union(enum) {
    text: []const u8,
    open_tag: Tag,
    close_tag: ?[]const u8, // null means [/]
};

pub const MarkupError = error{
    UnbalancedBracket,
    InvalidTag,
    UnclosedTag,
    StyleParseError,
} || std.mem.Allocator.Error;

pub fn tag_style(tag: Tag) Style.ParseError!Style {
    if (tag.name.len == 0) return error.UnknownAttribute;
    var numeric = true;
    for (tag.name) |byte| numeric = numeric and std.ascii.isDigit(byte);
    if (numeric) return error.UnknownAttribute;
    return if (std.mem.eql(u8, tag.name, "link") and tag.parameters != null)
        .{ .link = tag.parameters }
    else
        Style.parse(tag.name);
}

pub fn parseMarkup(text: []const u8, allocator: std.mem.Allocator) MarkupError![]MarkupToken {
    var tokens: std.ArrayList(MarkupToken) = .empty;
    errdefer tokens.deinit(allocator);

    var i: usize = 0;
    var text_start: usize = 0;

    while (i < text.len) {
        if (text[i] == '\\' and i + 1 < text.len and (text[i + 1] == '[' or text[i + 1] == ']')) {
            if (i > text_start) {
                try tokens.append(allocator, .{ .text = text[text_start..i] });
            }
            try tokens.append(allocator, .{ .text = text[i + 1 .. i + 2] });
            i += 2;
            text_start = i;
            continue;
        }

        if (text[i] == '[') {
            if (i > text_start) {
                try tokens.append(allocator, .{ .text = text[text_start..i] });
            }

            const end = std.mem.indexOfScalarPos(u8, text, i + 1, ']') orelse
                return MarkupError.UnbalancedBracket;

            const tag_content = text[i + 1 .. end];

            if (tag_content.len == 0) {
                return MarkupError.InvalidTag;
            }

            if (tag_content[0] == '/') {
                const tag_name = if (tag_content.len > 1) tag_content[1..] else null;
                try tokens.append(allocator, .{ .close_tag = tag_name });
            } else {
                if (std.mem.indexOfScalar(u8, tag_content, '=')) |eq_pos| {
                    try tokens.append(allocator, .{ .open_tag = .{
                        .name = tag_content[0..eq_pos],
                        .parameters = tag_content[eq_pos + 1 ..],
                        .source = text[i .. end + 1],
                    } });
                } else {
                    try tokens.append(allocator, .{ .open_tag = .{
                        .name = tag_content,
                        .source = text[i .. end + 1],
                    } });
                }
            }

            i = end + 1;
            text_start = i;
            continue;
        }

        i += 1;
    }

    if (text_start < text.len) {
        try tokens.append(allocator, .{ .text = text[text_start..] });
    }

    return tokens.toOwnedSlice(allocator);
}

/// Segment text and hyperlink URLs borrow the input.
pub fn render(text: []const u8, base_style: Style, allocator: std.mem.Allocator) ![]Segment {
    const tokens = try parseMarkup(text, allocator);
    defer allocator.free(tokens);

    var segments: std.ArrayList(Segment) = .empty;
    errdefer segments.deinit(allocator);

    var style_stack: std.ArrayList(Style) = .empty;
    defer style_stack.deinit(allocator);

    try style_stack.append(allocator, base_style);

    for (tokens) |token| {
        switch (token) {
            .text => |txt| {
                if (txt.len > 0) {
                    try segments.append(allocator, Segment.styled(txt, style_stack.getLast()));
                }
            },
            .open_tag => |tag| {
                const current_style = style_stack.getLast();
                const new_style = tag_style(tag) catch {
                    try segments.append(allocator, Segment.styled(tag.source, current_style));
                    continue;
                };
                try style_stack.append(allocator, current_style.combine(new_style));
            },
            .close_tag => |name| {
                if (name) |value| {
                    _ = tag_style(.{ .name = value }) catch {
                        try segments.append(allocator, Segment.styled(
                            closing_source(value),
                            style_stack.getLast(),
                        ));
                        continue;
                    };
                }
                if (style_stack.items.len > 1) {
                    _ = style_stack.pop();
                }
            },
        }
    }

    return segments.toOwnedSlice(allocator);
}

pub fn closing_source(name: []const u8) []const u8 {
    // A close_tag name is the slice between the source's "[/" and "]".
    return (name.ptr - 2)[0 .. name.len + 3];
}

pub fn escape(text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var count: usize = 0;
    for (text) |c| {
        if (c == '[' or c == ']') count += 1;
    }

    if (count == 0) {
        return try allocator.dupe(u8, text);
    }

    const result = try allocator.alloc(u8, text.len + count);
    var j: usize = 0;
    for (text) |c| {
        if (c == '[' or c == ']') {
            result[j] = '\\';
            j += 1;
        }
        result[j] = c;
        j += 1;
    }

    return result;
}

pub fn stripMarkup(text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const segments = try render(text, .{}, allocator);
    defer allocator.free(segments);
    return @import("segment.zig").joinText(segments, allocator);
}

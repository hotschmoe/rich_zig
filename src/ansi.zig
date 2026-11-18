const std = @import("std");
const Style = @import("style.zig").Style;
const Color = @import("color.zig").Color;
const Text = @import("text.zig").Text;
const Span = @import("text.zig").Span;

pub fn fromAnsi(allocator: std.mem.Allocator, input: []const u8) !Text {
    var plain_buf: std.ArrayList(u8) = .empty;
    defer plain_buf.deinit(allocator);

    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(allocator);

    var current_style = Style.empty;
    var style_start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '\x1b' and input[i + 1] == '[') {
            if (!current_style.isEmpty() and plain_buf.items.len > style_start) {
                try spans.append(allocator, .{
                    .start = style_start,
                    .end = plain_buf.items.len,
                    .style = current_style,
                });
            }

            i += 2; // skip ESC [
            var params: std.ArrayList(u16) = .empty;
            defer params.deinit(allocator);

            var current_param: u16 = 0;
            var has_param = false;

            while (i < input.len) {
                const c = input[i];
                if (c >= '0' and c <= '9') {
                    current_param = current_param * 10 + @as(u16, @intCast(c - '0'));
                    has_param = true;
                    i += 1;
                } else if (c == ';') {
                    try params.append(allocator, if (has_param) current_param else 0);
                    current_param = 0;
                    has_param = false;
                    i += 1;
                } else {
                    if (has_param) {
                        try params.append(allocator, current_param);
                    }
                    if (c == 'm') {
                        current_style = applySgr(current_style, params.items);
                    }
                    i += 1;
                    break;
                }
            }

            style_start = plain_buf.items.len;
            continue;
        }

        if (i + 1 < input.len and input[i] == '\x1b' and input[i + 1] == ']') {
            i += 2;
            while (i < input.len) {
                if (input[i] == '\x07') {
                    i += 1;
                    break;
                }
                if (i + 1 < input.len and input[i] == '\x1b' and input[i + 1] == '\\') {
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        try plain_buf.append(allocator, input[i]);
        i += 1;
    }

    if (!current_style.isEmpty() and plain_buf.items.len > style_start) {
        try spans.append(allocator, .{
            .start = style_start,
            .end = plain_buf.items.len,
            .style = current_style,
        });
    }

    return .{
        .plain = try plain_buf.toOwnedSlice(allocator),
        .spans = try spans.toOwnedSlice(allocator),
        .style = Style.empty,
        .allocator = allocator,
        .owns_plain = true,
        .owns_spans = true,
    };
}

pub fn stripAnsi(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '\x1b') {
            i += 1;
            if (i >= input.len) break;

            if (input[i] == '[') {
                i += 1;
                while (i < input.len and input[i] >= 0x20 and input[i] < 0x40) : (i += 1) {}
                if (i < input.len) i += 1; // skip final byte
                continue;
            }
            if (input[i] == ']') {
                i += 1;
                while (i < input.len) {
                    if (input[i] == '\x07') {
                        i += 1;
                        break;
                    }
                    if (i + 1 < input.len and input[i] == '\x1b' and input[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
                continue;
            }
            i += 1;
            continue;
        }

        try result.append(allocator, input[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

fn applySgr(base: Style, params: []const u16) Style {
    var style = base;

    if (params.len == 0) {
        return Style.empty;
    }

    const standard_colors = [_]Color{
        Color.black, Color.red,     Color.green, Color.yellow,
        Color.blue,  Color.magenta, Color.cyan,  Color.white,
    };
    const bright_colors = [_]Color{
        Color.bright_black, Color.bright_red,     Color.bright_green, Color.bright_yellow,
        Color.bright_blue,  Color.bright_magenta, Color.bright_cyan,  Color.bright_white,
    };

    var i: usize = 0;
    while (i < params.len) {
        const code = params[i];
        switch (code) {
            0 => style = Style.empty,
            1 => style = style.bold(),
            2 => style = style.dim(),
            3 => style = style.italic(),
            4 => style = style.underline(),
            5 => style = style.blink(),
            7 => style = style.reverse(),
            8 => style = style.conceal(),
            9 => style = style.strike(),
            21 => style = style.underline2(),
            22 => style = style.notBold().notDim(),
            23 => style = style.notItalic(),
            24 => style = style.notUnderline(),
            25 => style = style.notBlink(),
            27 => style = style.notReverse(),
            28 => style = style.notConceal(),
            29 => style = style.notStrike(),
            53 => style = style.overline(),
            55 => style = style.notOverline(),

            30...37 => style.color = standard_colors[code - 30],
            40...47 => style.bgcolor = standard_colors[code - 40],
            90...97 => style.color = bright_colors[code - 90],
            100...107 => style.bgcolor = bright_colors[code - 100],

            38 => {
                if (i + 1 < params.len) {
                    if (params[i + 1] == 5 and i + 2 < params.len) {
                        style.color = Color.from256(@truncate(params[i + 2]));
                        i += 2;
                    } else if (params[i + 1] == 2 and i + 4 < params.len) {
                        style.color = Color.fromRgb(@truncate(params[i + 2]), @truncate(params[i + 3]), @truncate(params[i + 4]));
                        i += 4;
                    }
                }
            },
            48 => {
                if (i + 1 < params.len) {
                    if (params[i + 1] == 5 and i + 2 < params.len) {
                        style.bgcolor = Color.from256(@truncate(params[i + 2]));
                        i += 2;
                    } else if (params[i + 1] == 2 and i + 4 < params.len) {
                        style.bgcolor = Color.fromRgb(@truncate(params[i + 2]), @truncate(params[i + 3]), @truncate(params[i + 4]));
                        i += 4;
                    }
                }
            },

            39 => style.color = null,
            49 => style.bgcolor = null,
            else => {},
        }
        i += 1;
    }

    return style;
}

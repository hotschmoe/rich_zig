const std = @import("std");
const rich = @import("rich_zig");
const assert = @import("assert").assert;

pub const input_max: u32 = 65536;
pub const runs_max: u32 = 512;
pub const profiles: u32 = 19;
pub const Buffer = struct {
    bytes: [input_max]u8 = undefined,
    length: u32 = 0,

    pub fn write(self: *Buffer, bytes: []const u8) !void {
        assert(self.length <= input_max);
        if (bytes.len > input_max - self.length) return error.InputLimit;
        @memcpy(self.bytes[self.length..][0..bytes.len], bytes);
        self.length += @intCast(bytes.len);
        assert(self.length <= input_max);
    }

    pub fn slice(self: *const Buffer) []const u8 {
        return self.bytes[0..self.length];
    }
};
pub const Run = struct { end: u32, style: rich.Style };
pub const Case = struct {
    input: Buffer = .{},
    plain: Buffer = .{},
    link_url: Buffer = .{},
    runs: [runs_max]Run = undefined,
    run_count: u32 = 0,
    profile: u32 = 0,
    features: u16 = 0,
    color_forms: u8 = 0,
    text_forms: u16 = 0,
    named_colors: u32 = 0,
    bracket_position: u8 = 0,
    expected_error: ?anyerror = null,

    pub fn text(self: *Case, bytes: []const u8, style: rich.Style) !void {
        assert(self.run_count <= runs_max);
        if (self.run_count == runs_max) return error.RunLimit;
        for (bytes) |byte| {
            if (byte == '[' or byte == ']') try self.input.write("\\");
            try self.input.write(&.{byte});
        }
        try self.plain.write(bytes);
        self.runs[self.run_count] = .{ .end = self.plain.length, .style = style };
        self.run_count += 1;
        assert(self.input.length >= self.plain.length);
    }

    pub fn literal(self: *Case, bytes: []const u8, style: rich.Style) !void {
        assert(self.run_count < runs_max);
        try self.input.write(bytes);
        try self.plain.write(bytes);
        self.runs[self.run_count] = .{ .end = self.plain.length, .style = style };
        self.run_count += 1;
        assert(self.input.length >= self.plain.length);
    }
};
const attributes = [_][]const u8{
    "bold",    "dim",    "italic",   "underline",  "blink", "blink2",   "reverse",
    "conceal", "strike", "overline", "underline2", "frame", "encircle",
};
const aliases = [_][]const u8{
    "b",     "d",        "i", "u", "blink", "blink2", "r", "conceal", "s", "o", "uu",
    "frame", "encircle",
};
const names = [_][]const u8{
    "black",        "red",            "green",        "yellow",
    "blue",         "magenta",        "cyan",         "white",
    "bright_black", "bright_red",     "bright_green", "bright_yellow",
    "bright_blue",  "bright_magenta", "bright_cyan",  "bright_white",
    "gray",         "grey",           "default",
};
const texts = [_][]const u8{
    "plain",
    "",
    "[]",
    "\\tail",
    "\n\t",
    "caf\xc3\xa9",
    "\xe4\xb8\xad\xe6\x96\x87",
    "\xd7\xa9\xd7\x9c\xd7\x95\xd7\x9d",
    "e\xcc\x81",
    "\xf0\x9f\x8c\x8d",
};

pub fn generate(case: *Case, random: std.Random, number: u32) !void {
    case.* = .{ .profile = number % profiles };
    assert(case.run_count == 0);
    switch (case.profile) {
        0...5 => try styled(case, random),
        6 => try nested(case, random),
        7 => try long_run(case, random),
        16, 17 => try bracketed(case),
        18 => try inherited_link(case, random),
        else => try damaged(case, random, number),
    }
    assert(case.input.length <= input_max);
}

fn styled(case: *Case, random: std.Random) !void {
    assert(case.profile <= 5);
    const count = 1 + random.uintLessThan(u32, 12);
    for (0..count) |_| {
        var style = rich.Style{};
        try case.input.write("[");
        const background = case.profile >= 2 and case.profile <= 4 and random.boolean();
        if (background) try case.input.write("on ");
        try style_form(case, random, &style);
        if (background) {
            style.bgcolor = style.color;
            style.color = null;
            case.features |= 2;
        }
        try case.input.write("]");
        const text_index = random.uintLessThan(u4, texts.len);
        case.text_forms |= @as(u16, 1) << text_index;
        try case.text(texts[text_index], style);
        try case.input.write("[/]");
    }
    assert(case.run_count == count);
}

fn style_form(case: *Case, random: std.Random, style: *rich.Style) !void {
    assert(case.profile <= 5);
    var buffer: [128]u8 = undefined;
    const index = random.uintLessThan(u32, attributes.len);
    const bit = @as(u16, 1) << @as(u4, @intCast(index));
    switch (case.profile) {
        0, 1 => {
            if (case.profile == 1) try case.input.write("not ");
            const list = if (random.boolean()) &attributes else &aliases;
            try case.input.write(list[index]);
            style.set_attributes = bit;
            style.attributes = if (case.profile == 0) bit else 0;
        },
        2 => {
            const color = random.uintLessThan(u8, names.len);
            case.named_colors |= @as(u32, 1) << @as(u5, @intCast(color));
            case.color_forms |= 1;
            try case.input.write(names[color]);
            style.color = if (color == 18) .{ .color_type = .default } else .{
                .color_type = .standard,
                .number = if (color >= 16) 8 else color,
            };
        },
        3 => {
            const r = random.int(u8);
            const g = random.int(u8);
            const b = random.int(u8);
            const hex = random.boolean();
            case.color_forms |= if (hex) @as(u8, 2) else 4;
            const tag = if (hex)
                try std.fmt.bufPrint(&buffer, "#{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b })
            else
                try std.fmt.bufPrint(&buffer, "rgb({d},{d},{d})", .{ r, g, b });
            try case.input.write(tag);
            style.color = .{ .color_type = .truecolor, .triplet = .{ .r = r, .g = g, .b = b } };
        },
        4 => {
            const number = random.int(u8);
            const wrapped = random.boolean();
            case.color_forms |= if (wrapped) @as(u8, 8) else 16;
            const tag = if (wrapped)
                try std.fmt.bufPrint(&buffer, "color({d})", .{number})
            else
                try std.fmt.bufPrint(&buffer, "bold {d}", .{number});
            try case.input.write(tag);
            style.color = .{ .color_type = .eight_bit, .number = number };
            if (!wrapped) {
                style.attributes = 1;
                style.set_attributes = 1;
            }
        },
        5 => try combined_form(case, random, style),
        else => return error.InvalidProfile,
    }
    assert(style.set_attributes & ~@as(u16, 8191) == 0);
}

fn combined_form(case: *Case, random: std.Random, style: *rich.Style) !void {
    assert(case.profile == 5);
    if (random.boolean()) {
        try case.input.write("link=https://example.invalid/path");
        style.link = "https://example.invalid/path";
        case.features |= 1;
    } else {
        try case.input.write("bold red on blue");
        style.* = .{
            .attributes = 1,
            .set_attributes = 1,
            .color = .{ .color_type = .standard, .number = 1 },
            .bgcolor = .{ .color_type = .standard, .number = 4 },
        };
        case.features |= 2;
    }
    assert(style.link != null or style.bgcolor != null);
}

fn nested(case: *Case, random: std.Random) !void {
    assert(case.profile == 6);
    const depth = 1 + random.uintLessThan(u32, 32);
    for (0..depth) |_| try case.input.write("[bold]");
    try case.text(texts[random.uintLessThan(u32, texts.len)], .{
        .attributes = 1,
        .set_attributes = 1,
    });
    try case.input.write("[italic]");
    try case.text("overlap", .{ .attributes = 5, .set_attributes = 5 });
    try case.input.write("[not bold red]");
    try case.text("clear bold", .{
        .attributes = 4,
        .set_attributes = 5,
        .color = .{ .color_type = .standard, .number = 1 },
    });
    try case.input.write("[bold on blue]");
    try case.text("restore bold", .{
        .attributes = 5,
        .set_attributes = 5,
        .color = .{ .color_type = .standard, .number = 1 },
        .bgcolor = .{ .color_type = .standard, .number = 4 },
    });
    try case.input.write("[/][/]");
    try case.input.write("[/bold]");
    try case.text("pop", .{ .attributes = 1, .set_attributes = 1 });
    for (0..depth) |_| try case.input.write("[/]");
    try case.text("tail", .{});
    assert(case.run_count == 6);
}

fn long_run(case: *Case, random: std.Random) !void {
    assert(case.profile == 7);
    var bytes: [32768]u8 = @splat('x');
    const length = 16384 + random.uintLessThan(u32, 16385);
    try case.input.write("[underline][not bold]");
    try case.text(bytes[0..length], .{ .attributes = 8, .set_attributes = 9 });
    try case.input.write("[/][/]");
    assert(case.plain.length == length);
}

fn damaged(case: *Case, random: std.Random, number: u32) !void {
    assert(case.profile >= 8 and case.profile < profiles);
    switch (case.profile) {
        8 => {
            try case.input.write("[bold]");
            try case.text("unclosed", .{ .attributes = 1, .set_attributes = 1 });
        },
        9 => {
            try case.literal("[/missing]", .{});
            try case.input.write("[/][ ][/]");
            try case.text("stray", .{});
        },
        10 => {
            try case.literal("[unknown_style][another_style]", .{});
            try case.text("unknown", .{});
            try case.input.write("[/][/]");
        },
        11 => {
            const bad = [_][]const u8{
                "#zzzzzz", "rgb(256,0,0)", "color(999)", "-1", "rgb(1,2,3,4)",
            };
            var buffer: [128]u8 = undefined;
            const tag = try std.fmt.bufPrint(&buffer, "[{s}]", .{
                bad[random.uintLessThan(u32, bad.len)],
            });
            try case.literal(tag, .{});
            try case.text("bad color", .{});
            try case.input.write("[/]");
        },
        12 => {
            try case.text("truncated", .{});
            try case.input.write("\\");
            try case.plain.write("\\");
            case.runs[0].end += 1;
        },
        13 => {
            const position = (number / profiles) % 18;
            case.bracket_position = @intCast(position);
            const base = "0123456789abcdefg";
            try case.input.write(base[0..position]);
            try case.input.write("[");
            try case.input.write(base[position..]);
            case.expected_error = error.UnbalancedBracket;
        },
        14 => {
            try case.input.write("[red]");
            try case.text("\xff\xc0\xaf\xe2\x82\x80", .{
                .color = .{ .color_type = .standard, .number = 1 },
            });
            try case.input.write("[/]");
        },
        15 => {
            try case.input.write("[]");
            case.expected_error = error.InvalidTag;
        },
        else => return error.InvalidProfile,
    }
    assert(case.input.length > 0);
}

fn bracketed(case: *Case) !void {
    assert(case.profile == 16 or case.profile == 17);
    const style: rich.Style = if (case.profile == 17)
        .{ .attributes = 1, .set_attributes = 1 }
    else
        .{};
    if (case.profile == 17) try case.input.write("[bold]");
    const literals = [_][]const u8{
        "[OK]",
        "[WARN]",
        "[FAIL]",
        "[1]",
        "[index]",
        "[[nested]]",
        "[/tmp]",
        "[1,2,3]",
        "[\"value\",null,true]",
        "[=value]",
        "[[bold]]",
    };
    for (literals) |literal| try case.literal(literal, style);
    if (case.profile == 17) {
        try case.input.write("[red]");
        var red = style;
        red.color = .{ .color_type = .standard, .number = 1 };
        try case.literal("[OK][/tmp]", red);
        try case.input.write("[/italic]");
        try case.literal("[index]", style);
        try case.input.write("[/]");
    }
    assert(case.run_count >= literals.len);
}

fn inherited_link(case: *Case, random: std.Random) !void {
    assert(case.profile == 18);
    var bytes: [32768]u8 = @splat('x');
    const length = 24000 + random.uintLessThan(u32, 8000);
    try case.link_url.write("https://example.invalid/");
    try case.link_url.write(bytes[0..length]);
    const link = case.link_url.slice();
    try case.input.write("[link=");
    try case.input.write(link);
    try case.input.write("]");
    const count = 96 + random.uintLessThan(u32, 32);
    for (0..count) |_| {
        try case.input.write("[bold]");
        try case.text("x", .{ .attributes = 1, .set_attributes = 1, .link = link });
        try case.input.write("[/]");
    }
    try case.text("[OK]", .{ .link = link });
    case.features |= 1;
    assert(case.run_count == count + 1);
}

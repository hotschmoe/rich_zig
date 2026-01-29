const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const cells = @import("../cells.zig");
const BoxStyle = @import("../box.zig").BoxStyle;

pub const JustifyMethod = enum {
    left,
    center,
    right,
};

pub const Overflow = enum {
    fold,
    ellipsis,
    crop,
};

pub const AlternatingStyles = struct {
    even: Style,
    odd: Style,
};

pub const Column = struct {
    header: []const u8,
    justify: JustifyMethod = .left,
    style: Style = Style.empty,
    header_style: Style = Style.empty,
    width: ?usize = null,
    min_width: ?usize = null,
    max_width: ?usize = null,
    no_wrap: bool = false,
    ratio: ?u8 = null,
    overflow: Overflow = .fold,
    ellipsis: []const u8 = "...",

    pub fn init(header: []const u8) Column {
        return .{ .header = header };
    }

    pub fn withJustify(self: Column, j: JustifyMethod) Column {
        var c = self;
        c.justify = j;
        return c;
    }

    pub fn withWidth(self: Column, w: usize) Column {
        var c = self;
        c.width = w;
        return c;
    }

    pub fn withMinWidth(self: Column, w: usize) Column {
        var c = self;
        c.min_width = w;
        return c;
    }

    pub fn withMaxWidth(self: Column, w: usize) Column {
        var c = self;
        c.max_width = w;
        return c;
    }

    pub fn withStyle(self: Column, s: Style) Column {
        var c = self;
        c.style = s;
        return c;
    }

    pub fn withHeaderStyle(self: Column, s: Style) Column {
        var c = self;
        c.header_style = s;
        return c;
    }

    pub fn withRatio(self: Column, r: u8) Column {
        var c = self;
        c.ratio = r;
        return c;
    }

    pub fn withOverflow(self: Column, o: Overflow) Column {
        var c = self;
        c.overflow = o;
        return c;
    }

    pub fn withEllipsis(self: Column, e: []const u8) Column {
        var c = self;
        c.ellipsis = e;
        return c;
    }

    pub fn withNoWrap(self: Column, nw: bool) Column {
        var c = self;
        c.no_wrap = nw;
        return c;
    }
};

pub const Table = struct {
    columns: std.ArrayList(Column),
    rows: std.ArrayList([]const []const u8),
    title: ?[]const u8 = null,
    title_style: Style = Style.empty,
    caption: ?[]const u8 = null,
    caption_style: Style = Style.empty,
    caption_justify: JustifyMethod = .center,
    header_style: Style = Style.empty,
    border_style: Style = Style.empty,
    box_style: BoxStyle = BoxStyle.square,
    show_header: bool = true,
    show_edge: bool = true,
    show_lines: bool = false,
    padding: struct { left: u8, right: u8 } = .{ .left = 1, .right = 1 },
    row_styles: std.ArrayList(?Style),
    alternating_styles: ?AlternatingStyles = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .columns = std.ArrayList(Column).empty,
            .rows = std.ArrayList([]const []const u8).empty,
            .row_styles = std.ArrayList(?Style).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        self.columns.deinit(self.allocator);
        for (self.rows.items) |row| {
            self.allocator.free(row);
        }
        self.rows.deinit(self.allocator);
        self.row_styles.deinit(self.allocator);
    }

    pub fn withTitle(self: *Table, title: []const u8) *Table {
        self.title = title;
        return self;
    }

    pub fn withColumn(self: *Table, col: Column) *Table {
        self.columns.append(self.allocator, col) catch {};
        return self;
    }

    pub fn addColumn(self: *Table, header: []const u8) *Table {
        return self.withColumn(Column.init(header));
    }

    pub fn addRow(self: *Table, row: []const []const u8) !void {
        const row_copy = try self.allocator.alloc([]const u8, row.len);
        @memcpy(row_copy, row);
        try self.rows.append(self.allocator, row_copy);
        try self.row_styles.append(self.allocator, null);
    }

    pub fn addRowStyled(self: *Table, row: []const []const u8, style: Style) !void {
        const row_copy = try self.allocator.alloc([]const u8, row.len);
        @memcpy(row_copy, row);
        try self.rows.append(self.allocator, row_copy);
        try self.row_styles.append(self.allocator, style);
    }

    pub fn withRowStyle(self: *Table, row_index: usize, style: Style) *Table {
        if (row_index < self.row_styles.items.len) {
            self.row_styles.items[row_index] = style;
        }
        return self;
    }

    pub fn withAlternatingStyles(self: *Table, even: Style, odd: Style) *Table {
        self.alternating_styles = .{ .even = even, .odd = odd };
        return self;
    }

    pub fn withBoxStyle(self: *Table, style: BoxStyle) *Table {
        self.box_style = style;
        return self;
    }

    pub fn withHeaderStyle(self: *Table, style: Style) *Table {
        self.header_style = style;
        return self;
    }

    pub fn withBorderStyle(self: *Table, style: Style) *Table {
        self.border_style = style;
        return self;
    }

    pub fn withCaption(self: *Table, caption_text: []const u8) *Table {
        self.caption = caption_text;
        return self;
    }

    pub fn withCaptionStyle(self: *Table, style: Style) *Table {
        self.caption_style = style;
        return self;
    }

    pub fn withCaptionJustify(self: *Table, justify: JustifyMethod) *Table {
        self.caption_justify = justify;
        return self;
    }

    pub fn render(self: Table, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        if (self.columns.items.len == 0) {
            return segments.toOwnedSlice(allocator);
        }

        const col_widths = try self.calculateColumnWidths(max_width, allocator);
        defer allocator.free(col_widths);

        const b = self.box_style;

        if (self.show_edge) {
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.top_left, b.horizontal, b.top_right, b.top_tee);
        }

        if (self.show_header) {
            try self.renderHeaderRow(&segments, allocator, col_widths, b);
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.left_tee, b.horizontal, b.right_tee, b.cross);
        }

        for (self.rows.items, 0..) |row, idx| {
            try self.renderDataRow(&segments, allocator, row, col_widths, b, idx);
            if (self.show_lines and idx < self.rows.items.len - 1) {
                try self.renderHorizontalBorder(&segments, allocator, col_widths, b.left_tee, b.horizontal, b.right_tee, b.cross);
            }
        }

        if (self.show_edge) {
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.bottom_left, b.horizontal, b.bottom_right, b.bottom_tee);
        }

        if (self.caption) |caption_text| {
            try self.renderCaption(&segments, allocator, col_widths, caption_text);
        }

        return segments.toOwnedSlice(allocator);
    }

    fn calculateColumnWidths(self: Table, max_width: usize, allocator: std.mem.Allocator) ![]usize {
        var widths = try allocator.alloc(usize, self.columns.items.len);

        for (self.columns.items, 0..) |col, i| {
            widths[i] = cells.cellLen(col.header);
        }

        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                if (i < widths.len) {
                    const cell_width = cells.cellLen(cell);
                    if (cell_width > widths[i]) {
                        widths[i] = cell_width;
                    }
                }
            }
        }

        for (self.columns.items, 0..) |col, i| {
            if (col.width) |w| {
                widths[i] = w;
            } else {
                if (col.min_width) |min| {
                    if (widths[i] < min) widths[i] = min;
                }
                if (col.max_width) |max| {
                    if (widths[i] > max) widths[i] = max;
                }
            }
        }

        var has_ratio = false;
        var total_ratio: usize = 0;
        for (self.columns.items) |col| {
            if (col.ratio) |r| {
                has_ratio = true;
                total_ratio += r;
            }
        }

        if (has_ratio and total_ratio > 0) {
            const borders_width: usize = if (self.show_edge) 2 else 0;
            const separators_width: usize = if (self.columns.items.len > 1) self.columns.items.len - 1 else 0;
            const overhead = borders_width + separators_width;

            var fixed_width: usize = 0;
            for (self.columns.items, 0..) |col, i| {
                if (col.ratio == null) {
                    fixed_width += widths[i] + self.padding.left + self.padding.right;
                }
            }

            const available = if (max_width > overhead + fixed_width) max_width - overhead - fixed_width else 0;

            for (self.columns.items, 0..) |col, i| {
                if (col.ratio) |r| {
                    const ratio_width = (available * r) / total_ratio;
                    const content_width = if (ratio_width > self.padding.left + self.padding.right)
                        ratio_width - self.padding.left - self.padding.right
                    else
                        0;
                    widths[i] = content_width;
                }
            }
        }

        for (widths) |*w| {
            w.* += self.padding.left + self.padding.right;
        }

        return widths;
    }

    fn renderHorizontalBorder(
        self: Table,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
        widths: []usize,
        left: []const u8,
        horizontal: []const u8,
        right: []const u8,
        cross: []const u8,
    ) !void {
        try segments.append(allocator, Segment.styled(left, self.border_style));

        for (widths, 0..) |w, i| {
            for (0..w) |_| {
                try segments.append(allocator, Segment.styled(horizontal, self.border_style));
            }
            if (i < widths.len - 1) {
                try segments.append(allocator, Segment.styled(cross, self.border_style));
            }
        }

        try segments.append(allocator, Segment.styled(right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderHeaderRow(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, widths: []usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));

        for (self.columns.items, 0..) |col, i| {
            const combined_style = self.header_style.combine(col.header_style);
            try self.renderCell(segments, allocator, col.header, widths[i], col.justify, combined_style, col);
            if (i < self.columns.items.len - 1) {
                try segments.append(allocator, Segment.styled(b.vertical, self.border_style));
            }
        }

        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderDataRow(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, row: []const []const u8, widths: []usize, b: BoxStyle, row_idx: usize) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));

        const row_style = self.getRowStyle(row_idx);

        for (self.columns.items, 0..) |col, i| {
            const cell = if (i < row.len) row[i] else "";

            var effective_style = col.style;
            if (row_style) |rs| {
                effective_style = rs.combine(col.style);
            }

            try self.renderCell(segments, allocator, cell, widths[i], col.justify, effective_style, col);
            if (i < self.columns.items.len - 1) {
                try segments.append(allocator, Segment.styled(b.vertical, self.border_style));
            }
        }

        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn getRowStyle(self: Table, row_idx: usize) ?Style {
        if (row_idx < self.row_styles.items.len) {
            if (self.row_styles.items[row_idx]) |explicit_style| {
                return explicit_style;
            }
        }

        if (self.alternating_styles) |alt| {
            return if (row_idx % 2 == 0) alt.even else alt.odd;
        }

        return null;
    }

    fn renderCell(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, text: []const u8, width: usize, justify: JustifyMethod, style: Style, col: Column) !void {
        const content_width = if (width > self.padding.left + self.padding.right)
            width - self.padding.left - self.padding.right
        else
            0;

        var display_text = text;
        const text_width = cells.cellLen(text);

        if (col.no_wrap and text_width > content_width) {
            switch (col.overflow) {
                .fold => {},
                .ellipsis => {
                    const ellipsis_len = cells.cellLen(col.ellipsis);
                    if (content_width > ellipsis_len) {
                        const truncate_width = content_width - ellipsis_len;
                        const byte_pos = cells.cellToByteIndex(text, truncate_width);
                        display_text = text[0..byte_pos];
                    } else {
                        display_text = col.ellipsis;
                    }
                },
                .crop => {
                    const byte_pos = cells.cellToByteIndex(text, content_width);
                    display_text = text[0..byte_pos];
                },
            }
        }

        const display_width = cells.cellLen(display_text);
        const padding_total = if (content_width > display_width) content_width - display_width else 0;

        const needs_ellipsis = col.no_wrap and col.overflow == .ellipsis and text_width > content_width;
        const ellipsis_width = if (needs_ellipsis) cells.cellLen(col.ellipsis) else 0;
        const adjusted_padding = if (needs_ellipsis and padding_total >= ellipsis_width)
            padding_total - ellipsis_width
        else if (needs_ellipsis)
            0
        else
            padding_total;

        const left_pad: usize = switch (justify) {
            .left => self.padding.left,
            .right => self.padding.left + adjusted_padding,
            .center => self.padding.left + adjusted_padding / 2,
        };
        const right_pad = if (width > left_pad + display_width + (if (needs_ellipsis) ellipsis_width else 0))
            width - left_pad - display_width - (if (needs_ellipsis) ellipsis_width else 0)
        else
            0;

        try self.renderSpaces(segments, allocator, left_pad);
        try segments.append(allocator, Segment.styledOptional(display_text, if (style.isEmpty()) null else style));

        if (needs_ellipsis) {
            try segments.append(allocator, Segment.styledOptional(col.ellipsis, if (style.isEmpty()) null else style));
        }

        try self.renderSpaces(segments, allocator, right_pad);
    }

    fn renderSpaces(_: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, count: usize) !void {
        for (0..count) |_| {
            try segments.append(allocator, Segment.plain(" "));
        }
    }

    fn renderCaption(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, widths: []usize, caption_text: []const u8) !void {
        var total_width: usize = 0;
        for (widths) |w| {
            total_width += w;
        }
        if (widths.len > 1) {
            total_width += widths.len - 1;
        }
        if (self.show_edge) {
            total_width += 2;
        }

        const caption_len = cells.cellLen(caption_text);
        const padding_total = if (total_width > caption_len) total_width - caption_len else 0;

        const left_pad: usize = switch (self.caption_justify) {
            .left => 0,
            .center => padding_total / 2,
            .right => padding_total,
        };
        const right_pad = padding_total - left_pad;

        try self.renderSpaces(segments, allocator, left_pad);
        try segments.append(allocator, Segment.styledOptional(caption_text, if (self.caption_style.isEmpty()) null else self.caption_style));
        try self.renderSpaces(segments, allocator, right_pad);
        try segments.append(allocator, Segment.line());
    }
};

test "Table.init" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 0), table.columns.items.len);
}

test "Table.addColumn" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("Name").addColumn("Value");

    try std.testing.expectEqual(@as(usize, 2), table.columns.items.len);
    try std.testing.expectEqualStrings("Name", table.columns.items[0].header);
}

test "Table.addRow" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("A").addColumn("B");
    try table.addRow(&.{ "1", "2" });
    try table.addRow(&.{ "3", "4" });

    try std.testing.expectEqual(@as(usize, 2), table.rows.items.len);
}

test "Table.render basic" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("Name").addColumn("Value");
    try table.addRow(&.{ "foo", "bar" });

    const segments = try table.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);
}

test "Column justify methods" {
    const col = Column.init("Test").withJustify(.center).withWidth(10);
    try std.testing.expectEqual(JustifyMethod.center, col.justify);
    try std.testing.expectEqual(@as(?usize, 10), col.width);
}

test "Table.withCaption" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withCaption("Table Caption");

    try std.testing.expectEqualStrings("Table Caption", table.caption.?);
}

test "Table.withCaptionStyle" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withCaptionStyle(Style.empty.italic());

    try std.testing.expect(table.caption_style.hasAttribute(.italic));
}

test "Table.withCaptionJustify" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withCaptionJustify(.right);

    try std.testing.expectEqual(JustifyMethod.right, table.caption_justify);
}

test "Table.render with caption" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("A").addColumn("B").withCaption("My Caption");
    try table.addRow(&.{ "1", "2" });

    const segments = try table.render(80, allocator);
    defer allocator.free(segments);

    var found_caption = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "My Caption") != null) {
            found_caption = true;
            break;
        }
    }
    try std.testing.expect(found_caption);
}

test "Column.withRatio" {
    const col = Column.init("Test").withRatio(2);
    try std.testing.expectEqual(@as(?u8, 2), col.ratio);
}

test "Column.withOverflow" {
    const col = Column.init("Test").withOverflow(.ellipsis);
    try std.testing.expectEqual(Overflow.ellipsis, col.overflow);
}

test "Column.withEllipsis" {
    const col = Column.init("Test").withEllipsis("..");
    try std.testing.expectEqualStrings("..", col.ellipsis);
}

test "Table.withAlternatingStyles" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withAlternatingStyles(Style.empty.dim(), Style.empty.bold());

    try std.testing.expect(table.alternating_styles != null);
    try std.testing.expect(table.alternating_styles.?.even.hasAttribute(.dim));
    try std.testing.expect(table.alternating_styles.?.odd.hasAttribute(.bold));
}

test "Table.addRowStyled" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("A");
    try table.addRowStyled(&.{"1"}, Style.empty.bold());

    try std.testing.expectEqual(@as(usize, 1), table.rows.items.len);
    try std.testing.expect(table.row_styles.items[0] != null);
    try std.testing.expect(table.row_styles.items[0].?.hasAttribute(.bold));
}

test "Table.withRowStyle" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("A");
    try table.addRow(&.{"1"});
    _ = table.withRowStyle(0, Style.empty.italic());

    try std.testing.expect(table.row_styles.items[0] != null);
    try std.testing.expect(table.row_styles.items[0].?.hasAttribute(.italic));
}

test "Table.render with alternating styles" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.addColumn("A");
    _ = table.withAlternatingStyles(Style.empty.dim(), Style.empty.bold());
    try table.addRow(&.{"row0"});
    try table.addRow(&.{"row1"});
    try table.addRow(&.{"row2"});

    const segments = try table.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);
}

test "Table.render with ratio columns" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withColumn(Column.init("A").withRatio(1));
    _ = table.withColumn(Column.init("B").withRatio(2));
    _ = table.withColumn(Column.init("C").withRatio(1));
    try table.addRow(&.{ "one", "two", "three" });

    const segments = try table.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);
}

test "Table.render with overflow ellipsis" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();

    _ = table.withColumn(Column.init("Col").withWidth(8).withNoWrap(true).withOverflow(.ellipsis));
    try table.addRow(&.{"This is a very long text"});

    const segments = try table.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);

    var found_ellipsis = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "...") != null) {
            found_ellipsis = true;
            break;
        }
    }
    try std.testing.expect(found_ellipsis);
}

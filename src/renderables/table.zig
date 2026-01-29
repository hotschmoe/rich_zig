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

pub const Column = struct {
    header: []const u8,
    justify: JustifyMethod = .left,
    style: Style = Style.empty,
    header_style: Style = Style.empty,
    width: ?usize = null,
    min_width: ?usize = null,
    max_width: ?usize = null,
    no_wrap: bool = false,

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
};

pub const Table = struct {
    columns: std.ArrayList(Column),
    rows: std.ArrayList([]const []const u8),
    title: ?[]const u8 = null,
    title_style: Style = Style.empty,
    header_style: Style = Style.empty,
    border_style: Style = Style.empty,
    box_style: BoxStyle = BoxStyle.square,
    show_header: bool = true,
    show_edge: bool = true,
    show_lines: bool = false,
    padding: struct { left: u8, right: u8 } = .{ .left = 1, .right = 1 },
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .columns = std.ArrayList(Column).empty,
            .rows = std.ArrayList([]const []const u8).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        self.columns.deinit(self.allocator);
        for (self.rows.items) |row| {
            self.allocator.free(row);
        }
        self.rows.deinit(self.allocator);
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

    pub fn render(self: Table, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        if (self.columns.items.len == 0) {
            return segments.toOwnedSlice(allocator);
        }

        // Calculate column widths
        const col_widths = try self.calculateColumnWidths(max_width, allocator);
        defer allocator.free(col_widths);

        const b = self.box_style;

        // Top border
        if (self.show_edge) {
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.top_left, b.horizontal, b.top_right, b.top_tee);
        }

        // Header
        if (self.show_header) {
            try self.renderHeaderRow(&segments, allocator, col_widths, b);
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.left_tee, b.horizontal, b.right_tee, b.cross);
        }

        // Data rows
        for (self.rows.items, 0..) |row, idx| {
            try self.renderDataRow(&segments, allocator, row, col_widths, b);
            if (self.show_lines and idx < self.rows.items.len - 1) {
                try self.renderHorizontalBorder(&segments, allocator, col_widths, b.left_tee, b.horizontal, b.right_tee, b.cross);
            }
        }

        // Bottom border
        if (self.show_edge) {
            try self.renderHorizontalBorder(&segments, allocator, col_widths, b.bottom_left, b.horizontal, b.bottom_right, b.bottom_tee);
        }

        return segments.toOwnedSlice(allocator);
    }

    fn calculateColumnWidths(self: Table, max_width: usize, allocator: std.mem.Allocator) ![]usize {
        var widths = try allocator.alloc(usize, self.columns.items.len);

        // Start with header widths
        for (self.columns.items, 0..) |col, i| {
            widths[i] = cells.cellLen(col.header);
        }

        // Check data widths
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

        // Apply column constraints
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

        // Add padding
        for (widths) |*w| {
            w.* += self.padding.left + self.padding.right;
        }

        _ = max_width; // TODO: shrink to fit

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
            var j: usize = 0;
            while (j < w) : (j += 1) {
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
            try self.renderCell(segments, allocator, col.header, widths[i], col.justify, combined_style);
            if (i < self.columns.items.len - 1) {
                try segments.append(allocator, Segment.styled(b.vertical, self.border_style));
            }
        }

        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderDataRow(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, row: []const []const u8, widths: []usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));

        for (self.columns.items, 0..) |col, i| {
            const cell = if (i < row.len) row[i] else "";
            try self.renderCell(segments, allocator, cell, widths[i], col.justify, col.style);
            if (i < self.columns.items.len - 1) {
                try segments.append(allocator, Segment.styled(b.vertical, self.border_style));
            }
        }

        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderCell(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, text: []const u8, width: usize, justify: JustifyMethod, style: Style) !void {
        const text_width = cells.cellLen(text);
        const content_width = if (width > self.padding.left + self.padding.right)
            width - self.padding.left - self.padding.right
        else
            0;
        const padding_total = if (content_width > text_width) content_width - text_width else 0;

        const left_pad: usize = switch (justify) {
            .left => self.padding.left,
            .right => self.padding.left + padding_total,
            .center => self.padding.left + padding_total / 2,
        };
        const right_pad = if (width > left_pad + text_width) width - left_pad - text_width else 0;

        try self.renderSpaces(segments, allocator, left_pad);
        try segments.append(allocator, Segment.styledOptional(text, if (style.isEmpty()) null else style));
        try self.renderSpaces(segments, allocator, right_pad);
    }

    fn renderSpaces(self: Table, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, count: usize) !void {
        _ = self;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try segments.append(allocator, Segment.plain(" "));
        }
    }
};

// Tests
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

const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const segment_mod = @import("../segment.zig");
const Style = @import("../style.zig").Style;

pub const SizeConstraint = union(enum) {
    ratio: u8,
    fixed: usize,
    min: usize,
    auto,
};

pub const SplitDirection = enum {
    horizontal,
    vertical,
};

pub const SplitterConfig = struct {
    visible: bool = false,
    char: []const u8 = "\u{2502}",
    horizontal_char: []const u8 = "\u{2500}",
    style: ?Style = null,
};

pub const SplitContent = union(enum) {
    segments: []const Segment,
    split: *Split,
};

pub const SplitChild = struct {
    content: SplitContent,
    constraint: SizeConstraint = .auto,
    name: ?[]const u8 = null,
};

pub const Split = struct {
    direction: SplitDirection,
    children: std.ArrayList(SplitChild),
    allocator: std.mem.Allocator,
    splitter: SplitterConfig = .{},
    name_index: std.StringHashMap(usize),

    pub fn horizontal(allocator: std.mem.Allocator) Split {
        return .{
            .direction = .horizontal,
            .children = std.ArrayList(SplitChild).empty,
            .allocator = allocator,
            .name_index = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn vertical(allocator: std.mem.Allocator) Split {
        return .{
            .direction = .vertical,
            .children = std.ArrayList(SplitChild).empty,
            .allocator = allocator,
            .name_index = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Split) void {
        self.children.deinit(self.allocator);
        self.name_index.deinit();
    }

    pub fn withSplitter(self: Split) Split {
        var s = self;
        s.splitter.visible = true;
        return s;
    }

    pub fn withSplitterChar(self: Split, char: []const u8) Split {
        var s = self;
        s.splitter.char = char;
        s.splitter.visible = true;
        return s;
    }

    pub fn withSplitterStyle(self: Split, style: Style) Split {
        var s = self;
        s.splitter.style = style;
        s.splitter.visible = true;
        return s;
    }

    pub fn add(self: *Split, content: []const Segment) *Split {
        self.children.append(self.allocator, .{
            .content = .{ .segments = content },
            .constraint = .auto,
        }) catch {};
        return self;
    }

    pub fn addNamed(self: *Split, name: []const u8, content: []const Segment) *Split {
        const index = self.children.items.len;
        self.children.append(self.allocator, .{
            .content = .{ .segments = content },
            .constraint = .auto,
            .name = name,
        }) catch {};
        self.name_index.put(name, index) catch {};
        return self;
    }

    pub fn addSplit(self: *Split, nested: *Split) *Split {
        self.children.append(self.allocator, .{
            .content = .{ .split = nested },
            .constraint = .auto,
        }) catch {};
        return self;
    }

    pub fn addSplitNamed(self: *Split, name: []const u8, nested: *Split) *Split {
        const index = self.children.items.len;
        self.children.append(self.allocator, .{
            .content = .{ .split = nested },
            .constraint = .auto,
            .name = name,
        }) catch {};
        self.name_index.put(name, index) catch {};
        return self;
    }

    pub fn addWithRatio(self: *Split, content: []const Segment, ratio: u8) *Split {
        self.children.append(self.allocator, .{
            .content = .{ .segments = content },
            .constraint = .{ .ratio = ratio },
        }) catch {};
        return self;
    }

    pub fn addWithMinSize(self: *Split, content: []const Segment, min_size: usize) *Split {
        self.children.append(self.allocator, .{
            .content = .{ .segments = content },
            .constraint = .{ .min = min_size },
        }) catch {};
        return self;
    }

    pub fn addWithFixedSize(self: *Split, content: []const Segment, size: usize) *Split {
        self.children.append(self.allocator, .{
            .content = .{ .segments = content },
            .constraint = .{ .fixed = size },
        }) catch {};
        return self;
    }

    pub fn getRegionIndex(self: Split, name: []const u8) ?usize {
        return self.name_index.get(name);
    }

    pub fn getRegion(self: Split, name: []const u8) ?*SplitChild {
        const index = self.name_index.get(name) orelse return null;
        if (index < self.children.items.len) {
            return &self.children.items[index];
        }
        return null;
    }

    pub fn updateRegion(self: *Split, name: []const u8, content: []const Segment) bool {
        const index = self.name_index.get(name) orelse return false;
        if (index < self.children.items.len) {
            self.children.items[index].content = .{ .segments = content };
            return true;
        }
        return false;
    }

    pub fn updateRegionIndex(self: *Split, index: usize, content: []const Segment) void {
        if (index < self.children.items.len) {
            self.children.items[index].content = .{ .segments = content };
        }
    }

    pub fn render(self: Split, max_width: usize, allocator: std.mem.Allocator) std.mem.Allocator.Error![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        if (self.children.items.len == 0) {
            return segments.toOwnedSlice(allocator);
        }

        switch (self.direction) {
            .vertical => try self.renderVertical(&segments, max_width, allocator),
            .horizontal => try self.renderHorizontal(&segments, max_width, allocator),
        }

        return segments.toOwnedSlice(allocator);
    }

    fn renderVertical(self: Split, segments: *std.ArrayList(Segment), max_width: usize, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        for (self.children.items, 0..) |child, i| {
            switch (child.content) {
                .segments => |segs| {
                    for (segs) |seg| {
                        try segments.append(allocator, seg);
                    }
                },
                .split => |nested| {
                    const nested_segs = try nested.render(max_width, allocator);
                    defer allocator.free(nested_segs);
                    for (nested_segs) |seg| {
                        try segments.append(allocator, seg);
                    }
                },
            }
            if (i < self.children.items.len - 1) {
                try segments.append(allocator, Segment.line());
                if (self.splitter.visible) {
                    try segments.append(allocator, Segment.styledOptional(self.splitter.horizontal_char, self.splitter.style));
                    try segments.append(allocator, Segment.line());
                }
            }
        }
    }

    fn renderHorizontal(self: Split, segments: *std.ArrayList(Segment), max_width: usize, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        if (self.children.items.len == 0) return;

        const splitter_width: usize = if (self.splitter.visible) 1 else 0;
        const total_splitter_width = if (self.children.items.len > 1) splitter_width * (self.children.items.len - 1) else 0;
        const content_width = if (max_width > total_splitter_width) max_width - total_splitter_width else 0;

        const widths = try self.calculateWidths(content_width, allocator);
        defer allocator.free(widths);

        const child_lines = try allocator.alloc([][]const Segment, self.children.items.len);
        defer allocator.free(child_lines);

        const rendered_nested = try allocator.alloc(?[]const Segment, self.children.items.len);
        defer allocator.free(rendered_nested);

        var max_lines: usize = 0;

        for (self.children.items, 0..) |child, i| {
            rendered_nested[i] = null;
            const content_segs = switch (child.content) {
                .segments => |segs| segs,
                .split => |nested| blk: {
                    const nested_segs = try nested.render(widths[i], allocator);
                    rendered_nested[i] = nested_segs;
                    break :blk nested_segs;
                },
            };
            child_lines[i] = try segment_mod.splitIntoLines(content_segs, allocator);
            if (child_lines[i].len > max_lines) {
                max_lines = child_lines[i].len;
            }
        }
        defer {
            for (child_lines) |lines| {
                allocator.free(lines);
            }
            for (rendered_nested) |maybe_segs| {
                if (maybe_segs) |segs| {
                    allocator.free(segs);
                }
            }
        }

        for (0..max_lines) |line_idx| {
            for (self.children.items, 0..) |_, col| {
                if (col > 0 and self.splitter.visible) {
                    try segments.append(allocator, Segment.styledOptional(self.splitter.char, self.splitter.style));
                }

                const col_width = widths[col];
                const line = if (line_idx < child_lines[col].len) child_lines[col][line_idx] else &[_]Segment{};

                const adjusted = try segment_mod.adjustLineLength(line, col_width, ' ', allocator);
                for (adjusted) |seg| {
                    try segments.append(allocator, seg);
                }
                allocator.free(adjusted);
            }
            try segments.append(allocator, Segment.line());
        }
    }

    fn calculateWidths(self: Split, max_width: usize, allocator: std.mem.Allocator) ![]usize {
        var widths = try allocator.alloc(usize, self.children.items.len);

        var total_ratio: usize = 0;
        var fixed_width: usize = 0;
        var auto_count: usize = 0;

        for (self.children.items, 0..) |child, i| {
            switch (child.constraint) {
                .ratio => |r| total_ratio += r,
                .fixed => |f| {
                    widths[i] = f;
                    fixed_width += f;
                },
                .min => |m| {
                    widths[i] = m;
                    fixed_width += m;
                },
                .auto => auto_count += 1,
            }
        }

        const remaining = if (max_width > fixed_width) max_width - fixed_width else 0;
        var ratio_used: usize = 0;

        if (total_ratio > 0) {
            for (self.children.items, 0..) |child, i| {
                if (child.constraint == .ratio) {
                    widths[i] = (remaining * child.constraint.ratio) / total_ratio;
                    ratio_used += widths[i];
                }
            }
        }

        if (auto_count > 0) {
            const auto_width = (remaining - ratio_used) / auto_count;
            for (self.children.items, 0..) |child, i| {
                if (child.constraint == .auto) {
                    widths[i] = auto_width;
                }
            }
        }

        return widths;
    }
};

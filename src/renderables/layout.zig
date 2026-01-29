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

pub const SplitChild = struct {
    content: []const Segment,
    constraint: SizeConstraint = .auto,
};

pub const Split = struct {
    direction: SplitDirection,
    children: std.ArrayList(SplitChild),
    allocator: std.mem.Allocator,

    pub fn horizontal(allocator: std.mem.Allocator) Split {
        return .{
            .direction = .horizontal,
            .children = std.ArrayList(SplitChild).empty,
            .allocator = allocator,
        };
    }

    pub fn vertical(allocator: std.mem.Allocator) Split {
        return .{
            .direction = .vertical,
            .children = std.ArrayList(SplitChild).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Split) void {
        self.children.deinit(self.allocator);
    }

    pub fn add(self: *Split, content: []const Segment) *Split {
        self.children.append(self.allocator, .{
            .content = content,
            .constraint = .auto,
        }) catch {};
        return self;
    }

    pub fn addWithRatio(self: *Split, content: []const Segment, ratio: u8) *Split {
        self.children.append(self.allocator, .{
            .content = content,
            .constraint = .{ .ratio = ratio },
        }) catch {};
        return self;
    }

    pub fn addWithMinSize(self: *Split, content: []const Segment, min_size: usize) *Split {
        self.children.append(self.allocator, .{
            .content = content,
            .constraint = .{ .min = min_size },
        }) catch {};
        return self;
    }

    pub fn addWithFixedSize(self: *Split, content: []const Segment, size: usize) *Split {
        self.children.append(self.allocator, .{
            .content = content,
            .constraint = .{ .fixed = size },
        }) catch {};
        return self;
    }

    pub fn render(self: Split, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        if (self.children.items.len == 0) {
            return segments.toOwnedSlice(allocator);
        }

        switch (self.direction) {
            .vertical => try self.renderVertical(&segments, allocator),
            .horizontal => try self.renderHorizontal(&segments, max_width, allocator),
        }

        return segments.toOwnedSlice(allocator);
    }

    fn renderVertical(self: Split, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator) !void {
        for (self.children.items, 0..) |child, i| {
            for (child.content) |seg| {
                try segments.append(allocator, seg);
            }
            if (i < self.children.items.len - 1) {
                try segments.append(allocator, Segment.line());
            }
        }
    }

    fn renderHorizontal(self: Split, segments: *std.ArrayList(Segment), max_width: usize, allocator: std.mem.Allocator) !void {
        if (self.children.items.len == 0) return;

        const widths = try self.calculateWidths(max_width, allocator);
        defer allocator.free(widths);

        const child_lines = try allocator.alloc([][]const Segment, self.children.items.len);
        defer allocator.free(child_lines);

        var max_lines: usize = 0;

        for (self.children.items, 0..) |child, i| {
            child_lines[i] = try segment_mod.splitIntoLines(child.content, allocator);
            if (child_lines[i].len > max_lines) {
                max_lines = child_lines[i].len;
            }
        }
        defer {
            for (child_lines) |lines| {
                allocator.free(lines);
            }
        }

        for (0..max_lines) |line_idx| {
            for (self.children.items, 0..) |_, col| {
                const col_width = widths[col];
                const line = if (line_idx < child_lines[col].len) child_lines[col][line_idx] else &[_]Segment{};

                const adjusted = try segment_mod.adjustLineLength(line, col_width, ' ', allocator);
                defer {
                    for (adjusted) |seg| {
                        if (seg.text.len > 0 and seg.style == null) {
                            var is_original = false;
                            for (line) |orig| {
                                if (std.mem.eql(u8, seg.text, orig.text)) {
                                    is_original = true;
                                    break;
                                }
                            }
                            if (!is_original) {
                                allocator.free(@constCast(seg.text));
                            }
                        }
                    }
                    allocator.free(adjusted);
                }

                for (adjusted) |seg| {
                    try segments.append(allocator, seg);
                }
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

test "Split.horizontal" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    try std.testing.expectEqual(SplitDirection.horizontal, split.direction);
}

test "Split.vertical" {
    const allocator = std.testing.allocator;
    var split = Split.vertical(allocator);
    defer split.deinit();

    try std.testing.expectEqual(SplitDirection.vertical, split.direction);
}

test "Split.add" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    const segs1 = [_]Segment{Segment.plain("Left")};
    const segs2 = [_]Segment{Segment.plain("Right")};

    _ = split.add(&segs1).add(&segs2);

    try std.testing.expectEqual(@as(usize, 2), split.children.items.len);
}

test "Split.addWithRatio" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    const segs = [_]Segment{Segment.plain("Content")};
    _ = split.addWithRatio(&segs, 2);

    try std.testing.expectEqual(SizeConstraint{ .ratio = 2 }, split.children.items[0].constraint);
}

test "Split.addWithMinSize" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    const segs = [_]Segment{Segment.plain("Content")};
    _ = split.addWithMinSize(&segs, 10);

    try std.testing.expectEqual(SizeConstraint{ .min = 10 }, split.children.items[0].constraint);
}

test "Split.addWithFixedSize" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    const segs = [_]Segment{Segment.plain("Content")};
    _ = split.addWithFixedSize(&segs, 20);

    try std.testing.expectEqual(SizeConstraint{ .fixed = 20 }, split.children.items[0].constraint);
}

test "Split.render vertical" {
    const allocator = std.testing.allocator;
    var split = Split.vertical(allocator);
    defer split.deinit();

    const segs1 = [_]Segment{Segment.plain("Top")};
    const segs2 = [_]Segment{Segment.plain("Bottom")};
    _ = split.add(&segs1).add(&segs2);

    const segments = try split.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);

    var found_top = false;
    var found_bottom = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "Top")) found_top = true;
        if (std.mem.eql(u8, seg.text, "Bottom")) found_bottom = true;
    }
    try std.testing.expect(found_top);
    try std.testing.expect(found_bottom);
}

test "Split.render empty" {
    const allocator = std.testing.allocator;
    var split = Split.horizontal(allocator);
    defer split.deinit();

    const segments = try split.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 0), segments.len);
}

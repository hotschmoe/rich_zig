const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;

pub const LabelContent = union(enum) {
    text: []const u8,
    segments: []const Segment,

    pub fn getText(self: LabelContent) []const u8 {
        return switch (self) {
            .text => |t| t,
            .segments => |segs| if (segs.len > 0) segs[0].text else "",
        };
    }
};

pub const KV = struct {
    key: []const u8,
    value: KVValue,

    pub const KVValue = union(enum) {
        string: []const u8,
        nested: []const KV,
    };

    pub fn string(key: []const u8, val: []const u8) KV {
        return .{ .key = key, .value = .{ .string = val } };
    }

    pub fn nested(key: []const u8, children: []const KV) KV {
        return .{ .key = key, .value = .{ .nested = children } };
    }
};

pub const TreeGuide = struct {
    vertical: []const u8 = "\u{2502}",
    horizontal: []const u8 = "\u{2500}\u{2500}",
    corner: []const u8 = "\u{2514}",
    tee: []const u8 = "\u{251C}",
    space: []const u8 = "   ",
};

pub const TreeNode = struct {
    label: []const u8,
    label_content: ?LabelContent = null,
    children: std.ArrayList(TreeNode),
    style: Style = Style.empty,
    guide_style: Style = Style.empty,
    expanded: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, label: []const u8) TreeNode {
        return .{
            .label = label,
            .children = std.ArrayList(TreeNode).empty,
            .allocator = allocator,
        };
    }

    pub fn initWithSegments(allocator: std.mem.Allocator, segments: []const Segment) TreeNode {
        return .{
            .label = if (segments.len > 0) segments[0].text else "",
            .label_content = .{ .segments = segments },
            .children = std.ArrayList(TreeNode).empty,
            .allocator = allocator,
        };
    }

    pub fn getLabelContent(self: TreeNode) LabelContent {
        if (self.label_content) |content| {
            return content;
        }
        return .{ .text = self.label };
    }

    pub fn deinit(self: *TreeNode) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
    }

    pub fn addChild(self: *TreeNode, child: TreeNode) !void {
        try self.children.append(self.allocator, child);
    }

    pub fn addChildLabel(self: *TreeNode, label: []const u8) !*TreeNode {
        try self.children.append(self.allocator, TreeNode.init(self.allocator, label));
        return &self.children.items[self.children.items.len - 1];
    }

    pub fn withStyle(self: TreeNode, s: Style) TreeNode {
        var n = self;
        n.style = s;
        return n;
    }

    pub fn withGuideStyle(self: TreeNode, s: Style) TreeNode {
        var n = self;
        n.guide_style = s;
        return n;
    }

    pub fn collapsed(self: TreeNode) TreeNode {
        var n = self;
        n.expanded = false;
        return n;
    }

    pub fn addFromKV(self: *TreeNode, items: []const KV) !void {
        for (items) |item| {
            var child = TreeNode.init(self.allocator, item.key);
            switch (item.value) {
                .string => |val| _ = try child.addChildLabel(val),
                .nested => |nested_items| try child.addFromKV(nested_items),
            }
            try self.children.append(self.allocator, child);
        }
    }
};

pub const Tree = struct {
    root: TreeNode,
    guide: TreeGuide = .{},
    hide_root: bool = false,

    pub fn init(root: TreeNode) Tree {
        return .{ .root = root };
    }

    pub fn withGuide(self: Tree, guide: TreeGuide) Tree {
        var t = self;
        t.guide = guide;
        return t;
    }

    pub fn hideRoot(self: Tree) Tree {
        var t = self;
        t.hide_root = true;
        return t;
    }

    pub fn render(self: Tree, _: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        if (!self.hide_root) {
            try renderLabel(&segments, allocator, &self.root);
            try segments.append(allocator, Segment.line());
        }

        // Track ancestor levels: true = has more siblings (show vertical), false = last child (show space)
        var levels: std.ArrayList(bool) = .empty;
        defer levels.deinit(allocator);

        try self.renderChildren(&segments, allocator, &self.root, &levels);

        return segments.toOwnedSlice(allocator);
    }

    fn renderLabel(segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, node: *const TreeNode) !void {
        const content = node.getLabelContent();
        switch (content) {
            .text => |t| {
                try segments.append(allocator, Segment.styled(t, node.style));
            },
            .segments => |segs| {
                for (segs) |seg| {
                    const combined_style = if (seg.style) |s| node.style.combine(s) else node.style;
                    try segments.append(allocator, Segment.styledOptional(seg.text, if (combined_style.isEmpty()) null else combined_style));
                }
            },
        }
    }

    fn renderChildren(self: Tree, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, node: *const TreeNode, levels: *std.ArrayList(bool)) !void {
        if (!node.expanded) return;

        for (node.children.items, 0..) |*child, i| {
            const is_last = (i == node.children.items.len - 1);

            // Render prefix based on ancestor levels (uses static string refs, no lifetime issues)
            for (levels.items) |has_more_siblings| {
                if (has_more_siblings) {
                    try segments.append(allocator, Segment.styled(self.guide.vertical, node.guide_style));
                    try segments.append(allocator, Segment.plain("  "));
                } else {
                    try segments.append(allocator, Segment.plain(self.guide.space));
                }
            }

            const guide_char = if (is_last) self.guide.corner else self.guide.tee;
            try segments.append(allocator, Segment.styled(guide_char, node.guide_style));
            try segments.append(allocator, Segment.styled(self.guide.horizontal, node.guide_style));
            try segments.append(allocator, Segment.plain(" "));

            try renderLabel(segments, allocator, child);
            try segments.append(allocator, Segment.line());

            // Recurse
            if (child.children.items.len > 0 and child.expanded) {
                try levels.append(allocator, !is_last);
                try self.renderChildren(segments, allocator, child, levels);
                _ = levels.pop();
            }
        }
    }
};

// Tests

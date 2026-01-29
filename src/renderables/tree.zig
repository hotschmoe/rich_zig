const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;

pub const TreeGuide = struct {
    vertical: []const u8 = "\u{2502}",
    horizontal: []const u8 = "\u{2500}\u{2500}",
    corner: []const u8 = "\u{2514}",
    tee: []const u8 = "\u{251C}",
    space: []const u8 = "   ",
};

pub const TreeNode = struct {
    label: []const u8,
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

    pub fn render(self: Tree, width: usize, allocator: std.mem.Allocator) ![]Segment {
        _ = width;
        var segments: std.ArrayList(Segment) = .empty;

        if (!self.hide_root) {
            try segments.append(allocator, Segment.styled(self.root.label, self.root.style));
            try segments.append(allocator, Segment.line());
        }

        try self.renderChildren(&segments, allocator, &self.root, "");

        return segments.toOwnedSlice(allocator);
    }

    fn renderChildren(self: Tree, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, node: *const TreeNode, prefix: []const u8) !void {
        if (!node.expanded) return;

        for (node.children.items, 0..) |*child, i| {
            const is_last = (i == node.children.items.len - 1);

            // Prefix
            try segments.append(allocator, Segment.plain(prefix));

            // Guide character
            if (is_last) {
                try segments.append(allocator, Segment.styled(self.guide.corner, node.guide_style));
            } else {
                try segments.append(allocator, Segment.styled(self.guide.tee, node.guide_style));
            }
            try segments.append(allocator, Segment.styled(self.guide.horizontal, node.guide_style));
            try segments.append(allocator, Segment.plain(" "));

            // Label
            try segments.append(allocator, Segment.styled(child.label, child.style));
            try segments.append(allocator, Segment.line());

            // Recurse
            if (child.children.items.len > 0 and child.expanded) {
                // Build new prefix
                var new_prefix_list: std.ArrayList(u8) = .empty;
                defer new_prefix_list.deinit(allocator);
                try new_prefix_list.appendSlice(allocator, prefix);

                if (is_last) {
                    try new_prefix_list.appendSlice(allocator, self.guide.space);
                } else {
                    try new_prefix_list.appendSlice(allocator, self.guide.vertical);
                    try new_prefix_list.appendSlice(allocator, "  ");
                }

                try self.renderChildren(segments, allocator, child, new_prefix_list.items);
            }
        }
    }
};

// Tests
test "TreeNode.init" {
    const allocator = std.testing.allocator;
    var node = TreeNode.init(allocator, "root");
    defer node.deinit();

    try std.testing.expectEqualStrings("root", node.label);
    try std.testing.expectEqual(@as(usize, 0), node.children.items.len);
}

test "TreeNode.addChildLabel" {
    const allocator = std.testing.allocator;
    var root = TreeNode.init(allocator, "root");
    defer root.deinit();

    _ = try root.addChildLabel("child1");
    _ = try root.addChildLabel("child2");

    try std.testing.expectEqual(@as(usize, 2), root.children.items.len);
    try std.testing.expectEqualStrings("child1", root.children.items[0].label);
}

test "Tree.init" {
    const allocator = std.testing.allocator;
    var root = TreeNode.init(allocator, "root");
    defer root.deinit();

    const tree = Tree.init(root);
    try std.testing.expect(!tree.hide_root);
}

test "Tree.render basic" {
    const allocator = std.testing.allocator;
    var root = TreeNode.init(allocator, "root");
    defer root.deinit();

    _ = try root.addChildLabel("child1");
    _ = try root.addChildLabel("child2");

    const tree = Tree.init(root);
    const segments = try tree.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);

    // Verify root label is present
    var found_root = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "root")) {
            found_root = true;
            break;
        }
    }
    try std.testing.expect(found_root);
}

test "Tree.hideRoot" {
    const allocator = std.testing.allocator;
    var root = TreeNode.init(allocator, "root");
    defer root.deinit();

    _ = try root.addChildLabel("child");

    const tree = Tree.init(root).hideRoot();
    const segments = try tree.render(80, allocator);
    defer allocator.free(segments);

    // Root label should not be present
    for (segments) |seg| {
        try std.testing.expect(!std.mem.eql(u8, seg.text, "root"));
    }
}

pub const panel = @import("panel.zig");
pub const Panel = panel.Panel;

pub const table = @import("table.zig");
pub const Table = table.Table;
pub const Column = table.Column;

pub const rule = @import("rule.zig");
pub const Rule = rule.Rule;

pub const progress = @import("progress.zig");
pub const ProgressBar = progress.ProgressBar;
pub const Spinner = progress.Spinner;

pub const tree = @import("tree.zig");
pub const Tree = tree.Tree;
pub const TreeNode = tree.TreeNode;

test {
    _ = @import("panel.zig");
    _ = @import("table.zig");
    _ = @import("rule.zig");
    _ = @import("progress.zig");
    _ = @import("tree.zig");
}

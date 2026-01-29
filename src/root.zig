//! rich_zig - A Zig port of Python's Rich library for terminal formatting
//!
//! This library provides beautiful terminal output with:
//! - Styled text with colors and attributes
//! - Unicode-aware text handling
//! - Markup parsing for easy styling
//! - Renderables: panels, tables, progress bars, trees
//!
//! ## Quick Start
//! ```zig
//! const rich = @import("rich_zig");
//! const std = @import("std");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     var console = rich.Console.init(allocator);
//!     defer console.deinit();
//!     try console.print("[bold red]Hello[/] [green]World[/]!");
//! }
//! ```

const std = @import("std");

// Phase 1: Core types
pub const color = @import("color.zig");
pub const Color = color.Color;
pub const ColorType = color.ColorType;
pub const ColorSystem = color.ColorSystem;
pub const ColorTriplet = color.ColorTriplet;

pub const cells = @import("cells.zig");

pub const style = @import("style.zig");
pub const Style = style.Style;
pub const StyleAttribute = style.StyleAttribute;

pub const segment = @import("segment.zig");
pub const Segment = segment.Segment;
pub const ControlCode = segment.ControlCode;
pub const ControlType = segment.ControlType;

// Phase 2: Text and Markup
pub const box = @import("box.zig");
pub const BoxStyle = box.BoxStyle;

pub const markup = @import("markup.zig");

pub const text = @import("text.zig");
pub const Text = text.Text;
pub const Span = text.Span;

// Phase 3: Terminal and Console
pub const terminal = @import("terminal.zig");
pub const TerminalInfo = terminal.TerminalInfo;

pub const console = @import("console.zig");
pub const Console = console.Console;
pub const ConsoleOptions = console.ConsoleOptions;

// Phase 4: Renderables
pub const renderables = @import("renderables/mod.zig");
pub const Panel = renderables.Panel;
pub const Table = renderables.Table;
pub const Column = renderables.Column;
pub const Rule = renderables.Rule;
pub const ProgressBar = renderables.ProgressBar;
pub const Spinner = renderables.Spinner;
pub const Tree = renderables.Tree;
pub const TreeNode = renderables.TreeNode;

// Re-export tests from all modules
test {
    // Phase 1
    _ = @import("color.zig");
    _ = @import("cells.zig");
    _ = @import("style.zig");
    _ = @import("segment.zig");

    // Phase 2
    _ = @import("box.zig");
    _ = @import("markup.zig");
    _ = @import("text.zig");

    // Phase 3
    _ = @import("terminal.zig");
    _ = @import("console.zig");

    // Phase 4
    _ = @import("renderables/mod.zig");
}

// Basic library functionality tests
test "basic style creation" {
    const s = Style.empty.bold().foreground(Color.red);
    try std.testing.expect(s.hasAttribute(.bold));
    try std.testing.expect(s.color != null);
}

test "basic segment creation" {
    const seg = Segment.styled("Hello", Style.empty.bold());
    try std.testing.expectEqual(@as(usize, 5), seg.cellLength());
}

test "basic cell width" {
    try std.testing.expectEqual(@as(usize, 5), cells.cellLen("Hello"));
    try std.testing.expectEqual(@as(usize, 4), cells.cellLen("\u{4E2D}\u{6587}")); // 2 CJK = 4 cells
}

test "basic text from markup" {
    const allocator = std.testing.allocator;
    var t = try Text.fromMarkup(allocator, "[bold]Hello[/]");
    defer t.deinit();
    try std.testing.expectEqualStrings("Hello", t.plain);
}

test "basic box style" {
    try std.testing.expectEqualStrings("+", BoxStyle.ascii.top_left);
    try std.testing.expectEqualStrings("\u{256D}", BoxStyle.rounded.top_left);
}

test "basic console creation" {
    const allocator = std.testing.allocator;
    var c = Console.init(allocator);
    defer c.deinit();
    try std.testing.expect(c.width() > 0);
}

test "basic panel creation" {
    const allocator = std.testing.allocator;
    const panel = Panel.fromText(allocator, "Test");
    try std.testing.expectEqualStrings("Test", panel.content.text);
}

test "basic table creation" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();
    _ = table.addColumn("A").addColumn("B");
    try std.testing.expectEqual(@as(usize, 2), table.columns.items.len);
}

//! Table Example - Tables, columns, rows, and styling
//!
//! Run with: zig build example-table

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Basic table
    try console.print("[bold]Basic Table:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();

        _ = table.addColumn("Name");
        _ = table.addColumn("Language");
        _ = table.addColumn("Stars");

        try table.addRow(&.{ "rich_zig", "Zig", "1,234" });
        try table.addRow(&.{ "ziglang", "Zig", "12,345" });
        try table.addRow(&.{ "rich", "Python", "45,678" });

        try console.printRenderable(table);
    }
    try console.print("");

    // Table with title
    try console.print("[bold]Table with Title:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();

        _ = table.withTitle("Popular Projects");
        _ = table.addColumn("Project");
        _ = table.addColumn("Description");

        try table.addRow(&.{ "Zig", "A systems programming language" });
        try table.addRow(&.{ "rich_zig", "Terminal formatting library" });
        try table.addRow(&.{ "zls", "Zig Language Server" });

        try console.printRenderable(table);
    }
    try console.print("");

    // Table with styled columns using withColumn
    try console.print("[bold]Styled Columns:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();

        _ = table.withColumn(rich.Column.init("Item").withStyle(rich.Style.empty.bold().foreground(rich.Color.cyan)));
        _ = table.withColumn(rich.Column.init("Qty").withStyle(rich.Style.empty.foreground(rich.Color.yellow)));
        _ = table.withColumn(rich.Column.init("Price").withStyle(rich.Style.empty.foreground(rich.Color.green)));

        try table.addRow(&.{ "Apples", "10", "$2.50" });
        try table.addRow(&.{ "Oranges", "5", "$3.00" });
        try table.addRow(&.{ "Bananas", "12", "$1.80" });

        try console.printRenderable(table);
    }
    try console.print("");

    // Table with different box style
    try console.print("[bold]Double Border Style:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();

        _ = table.withBoxStyle(rich.BoxStyle.double);
        _ = table.addColumn("Status");
        _ = table.addColumn("Count");

        try table.addRow(&.{ "Active", "42" });
        try table.addRow(&.{ "Pending", "7" });
        try table.addRow(&.{ "Completed", "156" });

        try console.printRenderable(table);
    }
    try console.print("");

    // Table with styled cells using CellContent
    try console.print("[bold]Styled Cell Content:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();

        _ = table.addColumn("Service");
        _ = table.addColumn("Status");

        // Use CellContent.segments for styled cell content
        const online_segs = [_]rich.Segment{
            rich.Segment.styled("Online", rich.Style.empty.foreground(rich.Color.green)),
        };
        const degraded_segs = [_]rich.Segment{
            rich.Segment.styled("Degraded", rich.Style.empty.foreground(rich.Color.yellow)),
        };
        const offline_segs = [_]rich.Segment{
            rich.Segment.styled("Offline", rich.Style.empty.foreground(rich.Color.red)),
        };

        try table.addRowRich(&.{ .{ .text = "Database" }, .{ .segments = &online_segs } });
        try table.addRowRich(&.{ .{ .text = "Cache" }, .{ .segments = &degraded_segs } });
        try table.addRowRich(&.{ .{ .text = "API" }, .{ .segments = &offline_segs } });

        try console.printRenderable(table);
    }
}

const std = @import("std");
const rich = @import("rich_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var console = rich.Console.init(allocator, io, init.minimal.environ);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Advanced Table Example").withCharacters("="));
    try console.print("");

    try console.print("[bold]Table with Caption:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();
        _ = table.addColumn("Item").addColumn("Price").withCaption("Shopping List");
        try table.addRow(&.{ "Apple", "$1.50" });
        try table.addRow(&.{ "Bread", "$2.00" });
        try table.addRow(&.{ "Milk", "$3.25" });
        try console.printRenderable(table);
    }
    try console.print("");

    try console.print("[bold]Table with Footer:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();
        _ = table.addColumn("Item").addColumn("Price");
        try table.addRow(&.{ "Apple", "$1.00" });
        try table.addRow(&.{ "Banana", "$0.50" });
        try table.addRow(&.{ "Orange", "$0.75" });
        _ = table.withFooter(&.{ "Total", "$2.25" });
        try console.printRenderable(table);
    }
    try console.print("");

    try console.print("[bold]Table with Alternating Rows:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();
        _ = table.addColumn("ID").addColumn("Name").addColumn("Status");
        _ = table.withAlternatingStyles(rich.Style.empty, rich.Style.empty.dim());
        try table.addRow(&.{ "1", "Alice", "Active" });
        try table.addRow(&.{ "2", "Bob", "Pending" });
        try table.addRow(&.{ "3", "Carol", "Active" });
        try table.addRow(&.{ "4", "Dave", "Inactive" });
        try console.printRenderable(table);
    }
    try console.print("");

    try console.print("[bold]Table with Cell Spanning:[/]");
    {
        var table = rich.Table.init(allocator);
        defer table.deinit();
        _ = table.addColumn("A").addColumn("B").addColumn("C");

        try table.addSpannedRow(&.{
            rich.Cell.text("Spans 2 columns").withColspan(2),
            rich.Cell.text("C1"),
        });

        try table.addSpannedRow(&.{
            rich.Cell.text("Spans 2 rows").withRowspan(2),
            rich.Cell.text("B2"),
            rich.Cell.text("C2"),
        });

        try table.addSpannedRow(&.{
            rich.Cell.text("B3"),
            rich.Cell.text("C3"),
        });

        try console.printRenderable(table);
    }
}

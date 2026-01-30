//! Traceback Example - Error traceback rendering
//!
//! Run with: zig build example-traceback

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Traceback Example").withCharacters("="));
    try console.print("");

    // Basic traceback
    try console.print("[bold]Basic Traceback:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var tb = rich.Traceback.init(arena.allocator());
        tb = tb.withMessage("Connection refused")
            .withErrorName("NetworkError");

        try tb.addFrame(rich.StackFrame{
            .function = "connect",
            .file = "src/network/client.zig",
            .line = 142,
            .column = 8,
        });
        try tb.addFrame(rich.StackFrame{
            .function = "initSession",
            .file = "src/session.zig",
            .line = 56,
            .column = 12,
        });
        try tb.addFrame(rich.StackFrame{
            .function = "main",
            .file = "src/main.zig",
            .line = 23,
            .column = 4,
        });

        try console.printRenderable(&tb);
    }
    try console.print("");

    // Traceback with more context
    try console.print("[bold]Detailed Traceback:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var tb = rich.Traceback.init(arena.allocator());
        tb = tb.withMessage("Index out of bounds: index 10, len 5")
            .withErrorName("IndexError");

        try tb.addFrame(rich.StackFrame{
            .function = "get",
            .file = "src/collections/array_list.zig",
            .line = 234,
            .column = 17,
        });
        try tb.addFrame(rich.StackFrame{
            .function = "processItems",
            .file = "src/processor.zig",
            .line = 89,
            .column = 24,
        });
        try tb.addFrame(rich.StackFrame{
            .function = "runBatch",
            .file = "src/batch.zig",
            .line = 45,
            .column = 8,
        });
        try tb.addFrame(rich.StackFrame{
            .function = "execute",
            .file = "src/executor.zig",
            .line = 112,
            .column = 12,
        });

        try console.printRenderable(&tb);
    }
}

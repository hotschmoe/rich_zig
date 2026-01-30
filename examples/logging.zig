//! Logging Example - RichHandler for styled log output
//!
//! Run with: zig build example-logging

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("[bold]RichHandler Logging:[/]");
    try console.print("");

    // Create a RichHandler for styled log output
    var handler = rich.logging.RichHandler.init(allocator);
    defer handler.deinit();

    // Log at different levels
    try handler.emit(rich.logging.LogRecord.init(.debug, "Starting application initialization"));
    try handler.emit(rich.logging.LogRecord.init(.info, "Configuration loaded successfully"));
    try handler.emit(rich.logging.LogRecord.init(.info, "Connected to database on localhost:5432"));
    try handler.emit(rich.logging.LogRecord.init(.warn, "Cache size approaching limit (85% full)"));
    try handler.emit(rich.logging.LogRecord.init(.err, "Failed to connect to metrics service"));
    try handler.emit(rich.logging.LogRecord.init(.info, "Graceful degradation: metrics disabled"));
    try handler.emit(rich.logging.LogRecord.init(.debug, "Worker pool initialized with 4 threads"));
    try handler.emit(rich.logging.LogRecord.init(.info, "Server listening on port 8080"));

    try console.print("");
    try console.print("[dim]Log levels: debug, info, warn, err[/]");
}

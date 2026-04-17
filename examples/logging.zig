//! Logging Example - RichHandler for styled log output
//!
//! Run with: zig build example-logging

const std = @import("std");
const rich = @import("rich_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var console = rich.Console.init(allocator, io, init.minimal.environ);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Logging Example").withCharacters("="));
    try console.print("");

    try console.print("[bold]RichHandler Logging:[/]");
    try console.print("");

    // Create a RichHandler for styled log output
    var handler = rich.logging.RichHandler.init(io, allocator, init.minimal.environ);
    defer handler.deinit();

    // Log at different levels
    try handler.emit(rich.logging.LogRecord.init(io, .debug, "Starting application initialization"));
    try handler.emit(rich.logging.LogRecord.init(io, .info, "Configuration loaded successfully"));
    try handler.emit(rich.logging.LogRecord.init(io, .info, "Connected to database on localhost:5432"));
    try handler.emit(rich.logging.LogRecord.init(io, .warn, "Cache size approaching limit (85% full)"));
    try handler.emit(rich.logging.LogRecord.init(io, .err, "Failed to connect to metrics service"));
    try handler.emit(rich.logging.LogRecord.init(io, .info, "Graceful degradation: metrics disabled"));
    try handler.emit(rich.logging.LogRecord.init(io, .debug, "Worker pool initialized with 4 threads"));
    try handler.emit(rich.logging.LogRecord.init(io, .info, "Server listening on port 8080"));

    try console.print("");
    try console.print("[dim]Log levels: debug, info, warn, err[/]");
}

//! Terminal Example - Terminal detection, cell widths, and console features
//!
//! Run with: zig build example-terminal

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    // Enable UTF-8 and virtual terminal on Windows
    _ = rich.terminal.enableUtf8();
    _ = rich.terminal.enableVirtualTerminal();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.printRenderable(rich.Rule.init().withTitle("Terminal Example").withCharacters("="));
    try console.print("");

    try console.print("[bold]Terminal Detection:[/]");

    // Detect terminal capabilities
    const term_info = rich.terminal.detect();

    var buf: [128]u8 = undefined;
    const size_str = std.fmt.bufPrint(&buf, "  Size: {d}x{d}", .{ term_info.width, term_info.height }) catch "  Size: ?x?";
    try console.printPlain(size_str);

    const color_str = std.fmt.bufPrint(&buf, "  Color system: {s}", .{@tagName(term_info.color_system)}) catch "  Color system: ?";
    try console.printPlain(color_str);

    const tty_str = std.fmt.bufPrint(&buf, "  Is TTY: {}", .{term_info.is_tty}) catch "  Is TTY: ?";
    try console.printPlain(tty_str);
    try console.print("");

    // Console width
    try console.print("[bold]Console Width:[/]");
    const width_str = std.fmt.bufPrint(&buf, "  Console width: {d} columns", .{console.width()}) catch "  Console width: ?";
    try console.printPlain(width_str);
    try console.print("");

    // Cell width calculation (important for Unicode/CJK alignment)
    try console.print("[bold]Cell Width Calculation:[/]");
    const hello_str = std.fmt.bufPrint(&buf, "  \"Hello\" = {d} cells", .{rich.cells.cellLen("Hello")}) catch "";
    try console.printPlain(hello_str);

    try console.printPlain("  CJK characters (2 cells each):");
    const cjk1 = std.fmt.bufPrint(&buf, "    \"\u{4E2D}\u{6587}\" = {d} cells", .{rich.cells.cellLen("\u{4E2D}\u{6587}")}) catch "";
    try console.printPlain(cjk1);

    const cjk2 = std.fmt.bufPrint(&buf, "    \"\u{65E5}\u{672C}\" = {d} cells", .{rich.cells.cellLen("\u{65E5}\u{672C}")}) catch "";
    try console.printPlain(cjk2);

    const emoji_str = std.fmt.bufPrint(&buf, "  Emoji: \"\u{1F600}\" = {d} cells", .{rich.cells.cellLen("\u{1F600}")}) catch "";
    try console.printPlain(emoji_str);
    try console.print("");

    // Color ANSI code generation
    try console.print("[bold]Color ANSI Codes:[/]");
    var code_buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&code_buf);

    try rich.Color.red.getAnsiCodes(true, stream.writer());
    const red_str = std.fmt.bufPrint(&buf, "  Red foreground codes: {s}", .{stream.getWritten()}) catch "";
    try console.printPlain(red_str);

    stream.reset();
    try rich.Color.fromRgb(100, 200, 50).getAnsiCodes(true, stream.writer());
    const rgb_str = std.fmt.bufPrint(&buf, "  RGB(100,200,50) codes: {s}", .{stream.getWritten()}) catch "";
    try console.printPlain(rgb_str);
    try console.print("");

    // Console logging methods
    try console.print("[bold]Console Logging:[/]");
    try console.logDebug("This is a debug message", .{});
    try console.logInfo("This is an info message", .{});
    try console.logWarn("This is a warning message", .{});
    try console.logErr("This is an error message", .{});
}

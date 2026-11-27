const std = @import("std");
const rich = @import("rich_zig");
const assert = @import("assert").assert;

const references = block: {
    @setEvalBranchQuota(2000000);
    const containers_max = 4096;
    const functions_max = 4096;
    var functions: [functions_max]?*const anyopaque = @splat(null);
    functions[0] = @ptrCast(&generic_paths);
    var function_count: u32 = 1;
    var queue: [containers_max]type = undefined;
    queue[0] = rich;
    var count: u32 = 1;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const container = queue[index];
        for (std.meta.declarations(container)) |name| {
            const value = @field(container, name);
            _ = &@field(container, name);
            if (@typeInfo(@TypeOf(value)) == .@"fn") {
                if (!@typeInfo(@TypeOf(value)).@"fn".is_generic) {
                    if (function_count == functions_max)
                        @compileError("Public function reference limit");
                    functions[function_count] = @ptrCast(&@field(container, name));
                    function_count += 1;
                }
            }
            if (@TypeOf(value) != type) continue;
            switch (@typeInfo(value)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => {},
                else => continue,
            }
            var seen = false;
            for (queue[0..count]) |previous| {
                if (value == previous) seen = true;
            }
            if (seen) continue;
            if (count == containers_max) @compileError("Public declaration container limit");
            queue[count] = value;
            count += 1;
        }
    }
    break :block functions;
};

pub fn main() void {
    std.mem.doNotOptimizeAway(&references);
}

fn generic_paths(console: *rich.Console, writer: *std.Io.Writer) !void {
    assert(console.write_buffer.len > 0);
    assert(writer.end <= writer.buffer.len);
    const allocator = console.allocator;
    try rich.Style.empty.bold().renderAnsi(.truecolor, writer);
    try rich.Style.renderReset(writer);
    try rich.Style.renderHyperlinkEnd(writer);
    try rich.Color.red.getAnsiCodes(true, writer);
    try rich.Segment.plain("segment").render(writer, .truecolor);
    try (rich.ControlCode{ .bell = {} }).toEscapeSequence(writer);
    try rich.beginSyncOutput(writer);
    try rich.endSyncOutput(writer);
    try console.printRenderable(rich.Rule.init());
    try console.log(.info, "{s}", .{"message"});
    try console.logDebug("{d}", .{@as(u32, 1)});
    try console.logInfo("{d}", .{@as(u32, 1)});
    try console.logWarn("{d}", .{@as(u32, 1)});
    try console.logErr("{d}", .{@as(u32, 1)});
    try console.statusFmt("{d}", .{@as(u32, 1)});
    _ = try rich.Measurement.measureRenderable(rich.Rule.init(), 80, allocator);
    _ = try rich.Measurement.measureRenderable(rich.Json.init(allocator, .null), 80, allocator);
    var stops = [_]rich.ColorTriplet{
        .{ .r = 0, .g = 0, .b = 0 },
        .{ .r = 255, .g = 255, .b = 255 },
    };
    var colors: [8]rich.ColorTriplet = undefined;
    rich.gradient(&stops, &colors, false);
    rich.gradient(&stops, &colors, true);
    const Scoped = rich.logging.scopedLog(.declarations);
    Scoped.debug("{d}", .{@as(u32, 1)});
    Scoped.info("{d}", .{@as(u32, 1)});
    Scoped.warn("{d}", .{@as(u32, 1)});
    Scoped.err("{d}", .{@as(u32, 1)});
    var pretty = rich.Pretty.init(allocator);
    try pretty_paths(&pretty);
}

fn pretty_paths(pretty: *rich.Pretty) !void {
    const allocator = pretty.allocator;
    assert(pretty.current_depth == 0);
    _ = try pretty.format(.{
        @as(u32, 1),
        @as(f32, 1.5),
        true,
        null,
        @as(?u8, 1),
        error.Sample,
        rich.LogLevel.info,
        [_]u16{ 1, 2 },
        "text",
        @as([]const u16, &.{ 1, 2 }),
        rich.MarkupError,
        rich.LabelContent{ .text = "label" },
    });
    _ = try rich.pretty.pretty(allocator, @as(u8, 1));
    _ = try rich.pretty.prettyWithOptions(allocator, @as(u8, 1), .{});
    assert(pretty.current_depth == 0);
}

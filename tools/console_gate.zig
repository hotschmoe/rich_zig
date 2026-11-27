const std = @import("std");
const assert = @import("assert").assert;

const output_max: u32 = 2 * 1024 * 1024;
const memory_max: u32 = 32 * 1024 * 1024;
const modes = 5;
const Context = struct {
    io: std.Io,
    environment: *const std.process.Environ.Map,
    memory: []u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 8) return error.ExpectedSevenPrograms;
    const memory = try allocator.alloc(u8, memory_max);
    var environments: [modes]std.process.Environ.Map = undefined;
    for (&environments, 0..) |*environment, mode| {
        environment.* = try init.environ_map.clone(allocator);
        try environment.put("NO_COLOR", if (mode == 1 or mode == 2) "1" else "");
        _ = environment.swapRemove("FORCE_COLOR");
        if (mode <= 1) try environment.put("FORCE_COLOR", "1");
        try environment.put("TERM", if (mode == 3) "dumb" else "xterm-256color");
    }
    try std.Io.Dir.cwd().createDirPath(init.io, "zig-out/gate");
    for (args[1..]) |program| {
        for (&environments, 0..) |*environment, mode| {
            try compare_runs(.{
                .io = init.io,
                .environment = environment,
                .memory = memory,
            }, program, @intCast(mode));
        }
    }
}

fn compare_runs(context: Context, program: []const u8, mode: u32) !void {
    assert(context.memory.len == memory_max);
    assert(mode < modes);
    assert(context.environment.contains("FORCE_COLOR") == (mode <= 1));
    const no_color = context.environment.get("NO_COLOR") orelse @panic("gate NO_COLOR missing");
    assert(std.mem.eql(u8, no_color, if (mode == 1 or mode == 2) "1" else ""));
    var fixed = std.heap.FixedBufferAllocator.init(context.memory);
    const allocator = fixed.allocator();
    const piped = try std.process.run(allocator, context.io, .{
        .argv = &.{program},
        .environ_map = context.environment,
        .stdout_limit = .limited(output_max),
        .stderr_limit = .limited(output_max),
    });
    if (!piped.term.success()) return error.ProgramFailed;
    const colored = has_sgr(piped.stdout) or has_sgr(piped.stderr);
    if (mode != 0 and colored) return error.UnwantedColor;
    var name_buffer: [512]u8 = undefined;
    const prefix = try std.fmt.bufPrint(&name_buffer, "zig-out/gate/{s}-{d}", .{
        std.fs.path.stem(program), mode,
    });
    var output_buffer: [528]u8 = undefined;
    var error_buffer: [528]u8 = undefined;
    const output_path = try std.fmt.bufPrint(&output_buffer, "{s}.stdout.file", .{prefix});
    const error_path = try std.fmt.bufPrint(&error_buffer, "{s}.stderr.file", .{prefix});
    const directory = std.Io.Dir.cwd();
    const output = try directory.createFile(context.io, output_path, .{});
    defer output.close(context.io);
    const errors = try directory.createFile(context.io, error_path, .{});
    defer errors.close(context.io);
    var child = try std.process.spawn(context.io, .{
        .argv = &.{program},
        .environ_map = context.environment,
        .stdin = .ignore,
        .stdout = .{ .file = output },
        .stderr = .{ .file = errors },
    });
    defer child.kill(context.io);
    if (!(try child.wait(context.io)).success()) return error.ProgramFailed;
    try compare_stream(context, output_path, piped.stdout);
    try compare_stream(context, error_path, piped.stderr);
    std.debug.print("gate {s} mode={d} stdout={d} stderr={d}: equal\n", .{
        std.fs.path.stem(program), mode, piped.stdout.len, piped.stderr.len,
    });
}

fn compare_stream(context: Context, path: []const u8, piped: []const u8) !void {
    assert(piped.len <= output_max);
    assert(std.mem.endsWith(u8, path, ".file"));
    var bytes: [output_max + 1]u8 = undefined;
    const directory = std.Io.Dir.cwd();
    const actual = try directory.readFile(context.io, path, &bytes);
    if (actual.len > output_max) return error.OutputLimit;
    if (!std.mem.eql(u8, actual, piped)) return error.RedirectedOutputDiffers;
    var name_buffer: [528]u8 = undefined;
    const pipe_path = try std.fmt.bufPrint(&name_buffer, "{s}.pipe", .{path[0 .. path.len - 5]});
    try directory.writeFile(context.io, .{ .sub_path = pipe_path, .data = piped });
}

fn has_sgr(bytes: []const u8) bool {
    assert(bytes.len <= output_max);
    var index: usize = 0;
    while (index + 1 < bytes.len) : (index += 1) {
        if (bytes[index] != 0x1b or bytes[index + 1] != '[') continue;
        const start = index + 2;
        for (bytes[start..]) |byte| {
            if (byte == 'm') return true;
            if (!std.ascii.isDigit(byte) and byte != ';' and byte != ':') break;
        }
    }
    assert(index <= bytes.len);
    return false;
}

const std = @import("std");
const workload = @import("fuzz_generate.zig");
const checker = @import("fuzz_check.zig");
const Watch = @import("fuzz_watch.zig").Watch;
const assert = @import("assert").assert;
const iterations_max: u32 = 10000000;
const Options = struct { seed: u64 = 1, iterations: u32 = 512, replay: ?[]const u8 = null };
const Context = struct {
    io: std.Io,
    options: Options,
    number: u32 = 0,
    case: *workload.Case,
};
var active: ?*Context = null;
pub const panic = std.debug.FullPanic(panic_handler);

fn panic_handler(message: []const u8, address: ?usize) noreturn {
    assert(message.len > 0);
    _ = address;
    if (active) |context| save_failure(context, message) catch |err| {
        std.debug.print("saving panic failed: {s}\n", .{@errorName(err)});
    };
    std.debug.print("panic: {s}\n", .{message});
    assert(active == null or active.?.case.input.length <= workload.input_max);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var options = try parse_options(args);
    const memory = try init.arena.allocator().alloc(u8, 3 * checker.memory_max);
    @memset(memory[0..checker.memory_max], 0xa5);
    @memset(memory[checker.memory_max..][0..checker.memory_max], 0x5a);
    const case = try init.arena.allocator().create(workload.Case);
    var context = Context{ .io = init.io, .options = options, .case = case };
    if (options.replay) |file| try load_failure(&context, file);
    options = context.options;
    active = &context;
    defer active = null;
    var watch = Watch{ .io = init.io };
    try watch.start();
    defer watch.deinit();
    var counters = checker.Counters{};
    const started = std.Io.Clock.awake.now(init.io);
    std.debug.print("fuzz seed={d} iterations={d} fixed_buffer_bytes={d}\n", .{
        options.seed, options.iterations, checker.memory_max,
    });
    for (0..options.iterations) |index| {
        if (options.replay == null) {
            context.number = @intCast(index);
            try generate(&context);
        }
        watch.arm(case.input.length);
        const result = checker.check(case, memory, &counters);
        watch.finish();
        result catch |err| {
            try save_failure(&context, @errorName(err));
            return err;
        };
    }
    const elapsed = started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
    print_counters(counters, options.iterations, elapsed);
    if (options.replay == null) try verify_coverage(counters);
    assert(counters.deterministic == options.iterations);
    assert(counters.accepted + counters.rejected == options.iterations);
}

fn parse_options(args: []const []const u8) !Options {
    assert(args.len > 0);
    var options = Options{};
    var index: u32 = 1;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len) return error.MissingArgument;
        const name = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, name, "--seed")) {
            options.seed = try std.fmt.parseInt(u64, value, 0);
        } else if (std.mem.eql(u8, name, "--iterations")) {
            options.iterations = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--replay")) {
            options.replay = value;
        } else return error.UnknownArgument;
    }
    if (options.replay != null) options.iterations = 1;
    if (options.iterations == 0 or options.iterations > iterations_max) return error.IterationLimit;
    assert(options.iterations <= iterations_max);
    return options;
}

fn generate(context: *Context) !void {
    assert(context.number < iterations_max);
    var random = std.Random.DefaultPrng.init(
        context.options.seed +% @as(u64, context.number) *% 0x9e3779b97f4a7c15,
    );
    try workload.generate(context.case, random.random(), context.number);
    assert(context.case.profile == context.number % workload.profiles);
}

fn save_failure(context: *const Context, reason: []const u8) !void {
    assert(context.case.input.length <= workload.input_max);
    var filename: [160]u8 = undefined;
    const file = try std.fmt.bufPrint(&filename, "zig-out/fuzz/seed-{d}-case-{d}.markup", .{
        context.options.seed, context.number,
    });
    std.debug.print("FAIL seed={d} case={d} reason={s} replay={s}\n", .{
        context.options.seed, context.number, reason, file,
    });
    try std.Io.Dir.cwd().createDirPath(context.io, "zig-out/fuzz");
    try std.Io.Dir.cwd().writeFile(context.io, .{
        .sub_path = file,
        .data = context.case.input.slice(),
    });
    var metadata_name: [176]u8 = undefined;
    const metadata = try std.fmt.bufPrint(&metadata_name, "{s}.seed", .{file});
    var buffer: [80]u8 = undefined;
    const data = try std.fmt.bufPrint(&buffer, "{d}\n{d}\n", .{
        context.options.seed, context.number,
    });
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = metadata, .data = data });
    assert(file.len < filename.len);
}

fn load_failure(context: *Context, file: []const u8) !void {
    var name: [4096]u8 = undefined;
    const metadata = try std.fmt.bufPrint(&name, "{s}.seed", .{file});
    var buffer: [80]u8 = undefined;
    const data = try std.Io.Dir.cwd().readFile(context.io, metadata, &buffer);
    var lines = std.mem.splitScalar(u8, data, '\n');
    const seed = lines.next() orelse return error.BadReplay;
    context.options.seed = try std.fmt.parseInt(u64, seed, 10);
    const number = lines.next() orelse return error.BadReplay;
    context.number = try std.fmt.parseInt(u32, number, 10);
    if (context.number >= iterations_max) return error.IterationLimit;
    try generate(context);
    var bytes: [workload.input_max + 1]u8 = undefined;
    const input = try std.Io.Dir.cwd().readFile(context.io, file, &bytes);
    if (!std.mem.eql(u8, input, context.case.input.slice())) return error.ReplayGeneratorChanged;
    assert(context.options.iterations == 1);
    assert(context.case.input.length == input.len);
}

fn verify_coverage(counters: checker.Counters) !void {
    assert(counters.accepted + counters.rejected == counters.deterministic);
    assert(counters.plain_oracle == counters.accepted);
    inline for (comptime std.meta.fieldNames(checker.Counters)) |name| {
        const value = @field(counters, name);
        if (@TypeOf(value) == u64) {
            if (value == 0) return error.CoverageGap;
        } else {
            for (value) |count| if (count == 0) return error.CoverageGap;
        }
    }
}

fn print_counters(counters: checker.Counters, iterations: u32, elapsed_ns: i96) void {
    assert(iterations > 0);
    assert(counters.deterministic == iterations);
    inline for (comptime std.meta.fieldNames(checker.Counters)) |name| {
        std.debug.print("{s}={any}\n", .{ name, @field(counters, name) });
    }
    const seconds = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) / 1000000000;
    std.debug.print("cases={d} seconds={d:.3} cases_per_second={d:.0}\n", .{
        iterations, seconds, @as(f64, @floatFromInt(iterations)) / seconds,
    });
}

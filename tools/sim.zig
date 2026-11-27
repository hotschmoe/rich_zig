const std = @import("std");
const assert = @import("assert").assert;
const sim_host = @import("sim_host.zig");
const gen = @import("sim_generate.zig");
const sim_run = @import("sim_run.zig");
const sim_check = @import("sim_check.zig");
const Tracker = @import("fuzz_memory.zig").Tracker;

const seeds_max: u32 = 10_000_000;
const tracker_bytes: usize = 48 * 1024 * 1024;
const offset_ns: i64 = 7_000_000_000_000;

const Options = struct {
    seed: u64 = 1,
    steps: u32 = 40,
    seeds: u32 = 1,
    replay: ?[]const u8 = null,
    cross_process: bool = false,
    verbose: bool = false,
};

const Workspace = struct {
    scenario: *gen.Scenario,
    first: *sim_run.Run,
    second: *sim_run.Run,
    tracker: Tracker,
    scratch: sim_check.Scratch,
};

var active_seed: u64 = 0;
var active_steps: u32 = 0;
pub const panic = std.debug.FullPanic(panic_handler);

fn panic_handler(message: []const u8, address: ?usize) noreturn {
    assert(message.len > 0);
    assert(active_steps <= gen.steps_max);
    std.debug.print("replay: zig build sim -- --seed {d} --steps {d} (step {d})\n", .{
        active_seed, active_steps, sim_run.current_step,
    });
    std.debug.defaultPanic(message, address);
}

fn parse_options(args: []const []const u8) !Options {
    assert(args.len > 0);
    var options: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const name = args[index];
        if (std.mem.eql(u8, name, "--cross-process")) {
            options.cross_process = true;
            continue;
        }
        if (std.mem.eql(u8, name, "--verbose")) {
            options.verbose = true;
            continue;
        }
        index += 1;
        if (index >= args.len) return error.MissingArgument;
        const value = args[index];
        if (std.mem.eql(u8, name, "--seed")) {
            options.seed = try std.fmt.parseInt(u64, value, 0);
        } else if (std.mem.eql(u8, name, "--steps")) {
            options.steps = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--seeds")) {
            options.seeds = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--replay")) {
            options.replay = value;
        } else return error.UnknownArgument;
    }
    if (options.steps == 0 or options.steps > gen.steps_max) return error.StepLimit;
    if (options.seeds == 0 or options.seeds > seeds_max) return error.SeedLimit;
    assert(options.steps <= gen.steps_max);
    return options;
}

fn create_run(allocator: std.mem.Allocator) !*sim_run.Run {
    assert(sim_host.capture_max > 0);
    const run = try allocator.create(sim_run.Run);
    run.host = .{
        .config = .{},
        .out = .{ .bytes = try allocator.alloc(u8, sim_host.capture_max) },
        .err = .{ .bytes = try allocator.alloc(u8, sim_host.capture_max) },
        .prng = std.Random.DefaultPrng.init(0),
    };
    run.count = 0;
    assert(run.host.out.bytes.len == sim_host.capture_max);
    return run;
}

fn create_workspace(allocator: std.mem.Allocator) !Workspace {
    const memory = try allocator.alloc(u8, tracker_bytes);
    assert(memory.len == tracker_bytes);
    assert(tracker_bytes >= 16 * 1024 * 1024);
    return .{
        .scenario = try allocator.create(gen.Scenario),
        .first = try create_run(allocator),
        .second = try create_run(allocator),
        .tracker = .{ .fixed = std.heap.FixedBufferAllocator.init(memory) },
        .scratch = .{
            .first = try allocator.alloc(u8, sim_host.capture_max),
            .second = try allocator.alloc(u8, sim_host.capture_max),
        },
    };
}

fn execute(work: *Workspace, run: *sim_run.Run, variant: sim_run.Variant) void {
    assert(work.first != work.second);
    work.tracker.fixed.reset();
    work.tracker.live_bytes = 0;
    sim_run.execute(work.scenario, variant, run, &work.tracker);
    assert(run.count == work.scenario.step_count);
}

fn digest(run: *const sim_run.Run) u64 {
    assert(run.count > 0);
    var hasher = std.hash.Wyhash.init(0x72696368);
    hasher.update(run.host.out.slice());
    hasher.update(run.host.err.slice());
    assert(run.host.out.length <= sim_host.capture_max);
    return hasher.final();
}

fn run_seed(work: *Workspace, seed: u64, steps: u32, report: *sim_check.Report) u64 {
    assert(steps > 0 and steps <= gen.steps_max);
    active_seed = seed;
    active_steps = steps;
    gen.generate(seed, steps, work.scenario);
    execute(work, work.first, .{});
    sim_check.check_run(report, work.scenario, work.first, work.scratch);
    const first_digest = digest(work.first);
    execute(work, work.second, .{});
    sim_check.compare_bytes(report, .determinism, work.first, work.second);
    execute(work, work.second, .{ .strip_short_writes = true });
    sim_check.compare_bytes(report, .short_write, work.first, work.second);
    execute(work, work.second, .{ .force_color = true });
    sim_check.compare_colors(report, work.first, work.second, work.scratch);
    execute(work, work.second, .{ .mono_offset_ns = offset_ns });
    sim_check.compare_progress(report, work.first, work.second);
    assert(report.seed == seed);
    return first_digest;
}

fn child_digest(init: std.process.Init, seed: u64, steps: u32) !u64 {
    assert(steps > 0 and steps <= gen.steps_max);
    const allocator = init.arena.allocator();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try std.process.executablePath(init.io, &path_buffer);
    var seed_text: [24]u8 = undefined;
    var steps_text: [24]u8 = undefined;
    const argv = [_][]const u8{
        path_buffer[0..path_length],
        "--seed",
        try std.fmt.bufPrint(&seed_text, "{d}", .{seed}),
        "--steps",
        try std.fmt.bufPrint(&steps_text, "{d}", .{steps}),
    };
    const result = try std.process.run(allocator, init.io, .{ .argv = &argv });
    assert(argv.len == 5);
    var lines = std.mem.splitScalar(u8, result.stderr, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "digest ")) continue;
        return try std.fmt.parseInt(u64, line["digest ".len..], 16);
    }
    return error.ChildDigestMissing;
}

fn save_failure(init: std.process.Init, seed: u64, steps: u32) !void {
    assert(steps > 0 and steps <= gen.steps_max);
    var name: [96]u8 = undefined;
    var body: [64]u8 = undefined;
    const file = try std.fmt.bufPrint(&name, "zig-out/sim/seed-{d}.sim", .{seed});
    const data = try std.fmt.bufPrint(&body, "seed {d}\nsteps {d}\n", .{ seed, steps });
    try std.Io.Dir.cwd().createDirPath(init.io, "zig-out/sim");
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = file, .data = data });
    assert(data.len > 0);
    std.debug.print("replay: zig build sim -- --replay {s}\n", .{file});
}

fn load_replay(init: std.process.Init, options: *Options, file: []const u8) !void {
    assert(file.len > 0);
    var buffer: [128]u8 = undefined;
    const data = try std.Io.Dir.cwd().readFile(init.io, file, &buffer);
    var lines = std.mem.splitScalar(u8, data, '\n');
    const seed_line = lines.next() orelse return error.BadReplay;
    const steps_line = lines.next() orelse return error.BadReplay;
    if (!std.mem.startsWith(u8, seed_line, "seed ")) return error.BadReplay;
    if (!std.mem.startsWith(u8, steps_line, "steps ")) return error.BadReplay;
    options.seed = try std.fmt.parseInt(u64, seed_line["seed ".len..], 10);
    options.steps = try std.fmt.parseInt(u32, steps_line["steps ".len..], 10);
    options.seeds = 1;
    if (options.steps == 0 or options.steps > gen.steps_max) return error.StepLimit;
    assert(options.seeds == 1);
}

fn print_coverage(coverage: sim_check.Coverage) void {
    assert(coverage.checked_fits <= coverage.plain_steps + coverage.colored_steps);
    assert(coverage.short_steps <= coverage.plain_steps + coverage.colored_steps);
    std.debug.print("coverage failed_steps={d} short_steps={d} error_steps={d}", .{
        coverage.failed_steps, coverage.short_steps, coverage.error_steps,
    });
    std.debug.print(" colored={d} plain={d} fits={d}\n", .{
        coverage.colored_steps, coverage.plain_steps, coverage.checked_fits,
    });
    for (coverage.kinds, 0..) |count, kind| {
        const kind_value: gen.Kind = @fromBackingInt(@intCast(kind));
        std.debug.print("  {s}={d}", .{ @tagName(kind_value), count });
    }
    std.debug.print("\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    assert(args.len > 0);
    var options = try parse_options(args);
    if (options.replay) |file| try load_replay(init, &options, file);
    var work = try create_workspace(allocator);
    var failed_seeds: u32 = 0;
    var overflows: u32 = 0;
    var coverage: sim_check.Coverage = .{};
    var totals = std.mem.zeroes([sim_check.check_count]u32);
    for (0..options.seeds) |offset| {
        const seed = options.seed +% offset;
        var report: sim_check.Report = .{ .seed = seed, .verbose = options.verbose };
        if (options.seeds > 1) report.printed = sim_check.print_max -| 1;
        const result = run_seed(&work, seed, options.steps, &report);
        var failures = report.failures;
        if (options.cross_process and try child_digest(init, seed, options.steps) != result) {
            std.debug.print("FAIL seed={d} check=cross_process\n", .{seed});
            failures += 1;
        }
        if (options.seeds == 1) std.debug.print("digest {x}\n", .{result});
        for (report.counts, 0..) |count, check| totals[check] += count;
        overflows += report.overflows;
        coverage.add(report.coverage);
        if (failures == 0) continue;
        failed_seeds += 1;
        if (options.seeds == 1 or failed_seeds <= 20) {
            std.debug.print("seed {d} failed\n", .{seed});
        }
        if (options.replay == null and failed_seeds <= 20) {
            try save_failure(init, seed, options.steps);
        }
    }
    for (totals, 0..) |count, check| {
        if (count == 0) continue;
        const name = @tagName(@as(sim_check.Check, @fromBackingInt(@intCast(check))));
        std.debug.print("check {s}: {d}\n", .{ name, count });
    }
    print_coverage(coverage);
    std.debug.print("sim seeds={d} steps={d} failed={d} wider_than_terminal={d}\n", .{
        options.seeds, options.steps, failed_seeds, overflows,
    });
    assert(failed_seeds <= options.seeds);
    if (failed_seeds > 0) return error.SimulationFailed;
}

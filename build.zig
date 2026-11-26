const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("rich_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("assert", b.createModule(.{ .root_source_file = b.path("src/assert.zig") }));
    const version_options = b.addOptions();
    const base: []const u8 = @import("build.zig.zon").version;
    _ = std.SemanticVersion.parse(base) catch @panic("build.zig.zon .version is not valid semver");
    const meta = b.option([]const u8, "version-meta", "Semver build metadata appended as +<meta>");
    const version = if (meta) |value| b.fmt("{s}+{s}", .{ base, value }) else base;
    version_options.addOption([]const u8, "version", version);
    version_options.addOption([]const u8, "manifest_version", base);
    mod.addOptions("build_options", version_options);
    if (b.pkg_hash.len != 0) return;

    const exe = b.addExecutable(.{
        .name = "rich_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rich_zig", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run all examples");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_demo_step = b.step("demo", "Run the main demo only");
    run_demo_step.dependOn(&run_cmd.step);

    run_cmd.addPassthruArgs();

    const test_step = b.step("test", "Build and run the blocking end-to-end examples");
    const checks = add_checks(b, mod, target);
    test_step.dependOn(&checks.fuzz.step);
    run_cmd.step.dependOn(&checks.tidy.step);
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&checks.console_gate.step);
    checks.console_gate.addArtifactArg(exe);
    const heavy_step = b.step("test-heavy", "Run the complete example suite");

    add_examples(.{
        .builder = b,
        .module = mod,
        .target = target,
        .optimize = optimize,
        .console_gate = checks.console_gate,
        .heavy_step = heavy_step,
        .run_step = run_step,
        .tidy_step = &checks.tidy.step,
    });
}

const ExampleBuild = struct {
    builder: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    console_gate: *std.Build.Step.Run,
    heavy_step: *std.Build.Step,
    run_step: *std.Build.Step,
    tidy_step: *std.Build.Step,
};

fn add_examples(config: ExampleBuild) void {
    const b = config.builder;

    const examples = [_][]const u8{
        "hello",
        "panel",
        "table",
        "progress",
        "tree",
        "layout",
        "json_syntax",
        "terminal",
        "markdown",
        "split",
        "traceback",
        "logging",
        "advanced_table",
        "advanced_panel",
        "advanced_progress",
        "advanced_syntax",
        "color_features",
    };

    var prev_step: *std.Build.Step = b.getInstallStep();

    for (examples) |name| {
        const example_exe = b.addExecutable(.{
            .name = b.fmt("example-{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = config.target,
                .optimize = config.optimize,
                .imports = &.{
                    .{ .name = "rich_zig", .module = config.module },
                },
            }),
        });

        b.installArtifact(example_exe);

        const chained_run = b.addRunArtifact(example_exe);
        chained_run.step.dependOn(b.getInstallStep());
        chained_run.step.dependOn(prev_step);
        prev_step = &chained_run.step;

        const standalone_run = b.addRunArtifact(example_exe);
        standalone_run.step.dependOn(b.getInstallStep());
        standalone_run.step.dependOn(config.tidy_step);

        const blocking_names = [_][]const u8{
            "hello", "panel", "table", "tree", "json_syntax", "markdown", "advanced_syntax",
        };
        for (blocking_names) |blocking| {
            if (std.mem.eql(u8, name, blocking)) config.console_gate.addArtifactArg(example_exe);
        }

        const step_name = b.fmt("example-{s}", .{name});
        const example_step = b.step(step_name, b.fmt("Run the {s} example", .{name}));
        example_step.dependOn(&standalone_run.step);
    }

    config.run_step.dependOn(prev_step);
    config.heavy_step.dependOn(prev_step);
}

const Checks = struct {
    tidy: *std.Build.Step.Run,
    fuzz: *std.Build.Step.Run,
    console_gate: *std.Build.Step.Run,
};

fn add_checks(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget) Checks {
    const owned_assert = mod.import_table.get("assert").?;
    const names = [_][]const u8{ "tidy", "fuzz", "console_gate" };
    var executables: [names.len]*std.Build.Step.Compile = undefined;
    var runs: [names.len]*std.Build.Step.Run = undefined;
    for (names, 0..) |name, index| {
        executables[index] = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("tools/{s}.zig", .{name})),
                .target = if (index == 1) target else b.graph.host,
                .optimize = if (index == 1) .ReleaseSafe else .Debug,
                .imports = &.{
                    .{ .name = "rich_zig", .module = mod },
                    .{ .name = "assert", .module = owned_assert },
                },
            }),
        });
        runs[index] = b.addRunArtifact(executables[index]);
        runs[index].has_side_effects = true;
        runs[index].setCwd(b.path("."));
    }
    runs[0].addPassthruArgs();
    b.step("tidy", "Check TigerStyle ratchets").dependOn(&runs[0].step);
    runs[1].addPassthruArgs();
    b.step("fuzz", "Run seeded markup oracle").dependOn(&runs[1].step);
    const short_run = b.addRunArtifact(executables[1]);
    short_run.has_side_effects = true;
    short_run.setCwd(b.path("."));
    short_run.addArgs(&.{ "--seed", "1", "--iterations", "512" });
    short_run.step.dependOn(&runs[0].step);
    const heavy_run = b.addRunArtifact(executables[1]);
    heavy_run.has_side_effects = true;
    heavy_run.setCwd(b.path("."));
    heavy_run.addArgs(&.{ "--seed", "0x72696368", "--iterations", "200000" });
    b.step("fuzz-heavy", "Run background markup campaign").dependOn(&heavy_run.step);
    runs[2].step.dependOn(&runs[0].step);
    runs[2].step.dependOn(b.getInstallStep());
    add_declarations(b, mod);
    return .{ .tidy = runs[0], .fuzz = short_run, .console_gate = runs[2] };
}

fn add_declarations(b: *std.Build, mod: *std.Build.Module) void {
    const owned_assert = mod.import_table.get("assert").?;
    const targets = [_]std.Build.ResolvedTarget{
        b.graph.host,
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }),
        b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos }),
    };
    const step = b.step("declarations", "Compile the public API for host, Windows and macOS");
    for (targets) |target| {
        const library = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = .Debug,
        });
        library.addImport("build_options", mod.import_table.get("build_options").?);
        library.addImport("assert", owned_assert);
        const exe = b.addExecutable(.{
            .name = b.fmt("declarations-{s}", .{@tagName(target.result.os.tag)}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/declarations.zig"),
                .target = target,
                .optimize = .Debug,
                .imports = &.{
                    .{ .name = "rich_zig", .module = library },
                    .{ .name = "assert", .module = owned_assert },
                },
            }),
        });
        step.dependOn(&exe.step);
        b.installArtifact(exe);
    }
    b.top_level_steps.get("test").?.step.dependOn(step);
}

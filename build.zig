const std = @import("std");

/// See docs/VERSIONING.md for version metadata.
fn versionString(b: *std.Build) []const u8 {
    const base: []const u8 = @import("build.zig.zon").version;
    _ = std.SemanticVersion.parse(base) catch @panic("build.zig.zon .version is not valid semver");
    const meta = b.option([]const u8, "version-meta", "Semver build metadata appended as +<meta>") orelse return base;
    return b.fmt("{s}+{s}", .{ base, meta });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("rich_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    const version_options = b.addOptions();
    version_options.addOption([]const u8, "version", versionString(b));
    version_options.addOption([]const u8, "manifest_version", @import("build.zig.zon").version);
    mod.addOptions("build_options", version_options);

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
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_cmd.step);
    const heavy_step = b.step("test-heavy", "Run the complete example suite");

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
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "rich_zig", .module = mod },
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

        for ([_][]const u8{ "hello", "panel", "table", "tree", "json_syntax", "markdown", "advanced_syntax" }) |blocking| {
            if (std.mem.eql(u8, name, blocking)) test_step.dependOn(&standalone_run.step);
        }

        const example_step = b.step(b.fmt("example-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        example_step.dependOn(&standalone_run.step);
    }

    run_step.dependOn(prev_step);
    heavy_step.dependOn(prev_step);
}

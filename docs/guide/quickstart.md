# Quickstart Guide

Get up and running with rich_zig in 5 minutes.

## Installation

Add rich_zig to your project using `zig fetch`:

```bash
zig fetch --save https://github.com/yourusername/rich_zig/archive/refs/tags/v1.0.0.tar.gz
```

Then add to your `build.zig`:

```zig
const rich_zig = b.dependency("rich_zig", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("rich_zig", rich_zig.module("rich_zig"));
```

## Hello World

```zig
const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = try rich.Console.init(allocator);
    defer console.deinit();

    try console.print("Hello, [bold cyan]rich_zig[/]!", .{});
}
```

Output: Hello, **rich_zig**! (with cyan color and bold styling)

## Styled Text

rich_zig uses BBCode-like markup syntax for inline styling:

```zig
try console.print("[bold]Bold text[/]", .{});
try console.print("[red]Red text[/]", .{});
try console.print("[bold red on white]Bold red text on white background[/]", .{});
try console.print("[italic dim]Subtle italic text[/]", .{});
try console.print("[link=https://ziglang.org]Visit Zig[/link]", .{});
```

Styles can be combined: `[bold italic underline red]`

Available styles:
- **Weight**: `bold`, `dim`
- **Emphasis**: `italic`, `underline`, `strikethrough`
- **Colors**: `red`, `green`, `blue`, `yellow`, `magenta`, `cyan`, `white`, `black`
- **Background**: `on red`, `on blue`, etc.
- **Links**: `[link=URL]text[/link]`

Close any style with `[/]` or use specific closing tags like `[/bold]`.

## Your First Panel

Panels add visual structure to your output:

```zig
const Panel = rich.renderables.Panel;

var panel = try Panel.fromText(allocator, "This is a simple panel");
defer panel.deinit();

panel.title = try allocator.dupe(u8, "My First Panel");
defer allocator.free(panel.title.?);

try console.printRenderable(panel);
```

Output:
```
╭─ My First Panel ─╮
│ This is a simple │
│ panel            │
╰──────────────────╯
```

## Semantic Panels (New in v1.0.0)

Use semantic panel constructors for common message types:

```zig
const Panel = rich.renderables.Panel;

// Information panel (blue)
var info = try Panel.info(allocator, "Database connected successfully");
defer info.deinit();
try console.printRenderable(info);

// Warning panel (yellow)
var warning = try Panel.warning(allocator, "Cache size approaching limit");
defer warning.deinit();
try console.printRenderable(warning);

// Error panel (red)
var err_panel = try Panel.err(allocator, "Failed to load configuration");
defer err_panel.deinit();
try console.printRenderable(err_panel);

// Success panel (green)
var success = try Panel.success(allocator, "Build completed in 2.3s");
defer success.deinit();
try console.printRenderable(success);
```

These panels come pre-styled with appropriate colors, icons, and box styles.

## Building a Table

Create structured data displays with tables:

```zig
const Table = rich.renderables.Table;

// Create table with column headers
var table = try Table.init(allocator);
defer table.deinit();

try table.addColumn("Name");
try table.addColumn("Language");
try table.addColumn("Stars");

// Add rows
try table.addRow(&.{ "rich_zig", "Zig", "1,234" });
try table.addRow(&.{ "ziglang", "Zig", "12,345" });
try table.addRow(&.{ "rich", "Python", "45,678" });

// Optional: set table properties
table.title = try allocator.dupe(u8, "Popular Projects");

try console.printRenderable(table);
```

Output:
```
┌──────────┬──────────┬────────┐
│   Name   │ Language │ Stars  │
├──────────┼──────────┼────────┤
│ rich_zig │   Zig    │ 1,234  │
│ ziglang  │   Zig    │ 12,345 │
│ rich     │  Python  │ 45,678 │
└──────────┴──────────┴────────┘
```

## Progress Bars

Show progress for long-running operations:

```zig
const Progress = rich.renderables.Progress;
const std = @import("std");

var progress = try Progress.init(allocator);
defer progress.deinit();

const task_id = try progress.addTask("Downloading...", 100);

// Simulate work
var i: usize = 0;
while (i <= 100) : (i += 10) {
    try progress.update(task_id, i);
    try console.printRenderable(progress);
    std.time.sleep(100 * std.time.ns_per_ms);
}
```

Output (animated):
```
Downloading... ████████████░░░░░░░░ 60% 60/100
```

## Using the Prelude (New in v1.0.0)

For quick scripts and prototyping, use the prelude to import common items:

```zig
const std = @import("std");
const prelude = @import("rich_zig").prelude;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = try prelude.Console.init(allocator);
    defer console.deinit();

    // All common types available without namespace prefixes
    var panel = try prelude.Panel.success(allocator, "Quick and easy!");
    defer panel.deinit();
    try console.printRenderable(panel);

    var table = try prelude.Table.init(allocator);
    defer table.deinit();
    try table.addColumn("Feature");
    try table.addColumn("Available");
    try table.addRow(&.{ "Console", "✓" });
    try table.addRow(&.{ "Panel", "✓" });
    try table.addRow(&.{ "Table", "✓" });
    try console.printRenderable(table);
}
```

The prelude exports:
- `Console`
- `Panel`, `Table`, `Rule`, `Tree`, `Progress`
- `Color`, `Style`, `Text`
- `box` (box drawing styles)

## Next Steps

Now that you've mastered the basics, explore:

- **Full API Reference**: `/docs/api/` - Complete documentation for all modules
- **Advanced Guide**: `/docs/guide/advanced.md` - Custom renderables, layout system, live displays
- **Examples**: `/src/main.zig` - Comprehensive demo showing all features
- **Architecture**: `/docs/architecture.md` - Understanding the 4-phase rendering pipeline

Happy coding with rich_zig!

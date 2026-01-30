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

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("Hello, [bold cyan]rich_zig[/]!");
}
```

Output: Hello, **rich_zig**! (with cyan color and bold styling)

## Styled Text

rich_zig uses BBCode-like markup syntax for inline styling:

```zig
try console.print("[bold]Bold text[/]");
try console.print("[red]Red text[/]");
try console.print("[bold red on white]Bold red text on white background[/]");
try console.print("[italic dim]Subtle italic text[/]");
try console.print("[link=https://ziglang.org]Visit Zig[/link]");
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
const Panel = rich.Panel;

const panel = Panel.fromText(allocator, "This is a simple panel")
    .withTitle("My First Panel");

try console.printRenderable(panel);
```

Output:
```
+-- My First Panel --+
| This is a simple   |
| panel              |
+--------------------+
```

## Semantic Panels

Use semantic panel constructors for common message types:

```zig
const Panel = rich.Panel;

// Information panel (blue)
const info = Panel.info(allocator, "Database connected successfully");
try console.printRenderable(info);

// Warning panel (yellow)
const warning = Panel.warning(allocator, "Cache size approaching limit");
try console.printRenderable(warning);

// Error panel (red)
const err_panel = Panel.err(allocator, "Failed to load configuration");
try console.printRenderable(err_panel);

// Success panel (green)
const success = Panel.success(allocator, "Build completed in 2.3s");
try console.printRenderable(success);
```

These panels come pre-styled with appropriate colors, icons, and box styles.

## Building a Table

Create structured data displays with tables:

```zig
const Table = rich.Table;

// Create table with column headers
var table = Table.init(allocator);
defer table.deinit();

_ = table.addColumn("Name");
_ = table.addColumn("Language");
_ = table.addColumn("Stars");

// Add rows
try table.addRow(&.{ "rich_zig", "Zig", "1,234" });
try table.addRow(&.{ "ziglang", "Zig", "12,345" });
try table.addRow(&.{ "rich", "Python", "45,678" });

// Optional: set table title
_ = table.withTitle("Popular Projects");

try console.printRenderable(table);
```

Output:
```
+----------+----------+--------+
|   Name   | Language | Stars  |
+----------+----------+--------+
| rich_zig |   Zig    | 1,234  |
| ziglang  |   Zig    | 12,345 |
| rich     |  Python  | 45,678 |
+----------+----------+--------+
```

## Progress Bars

Show progress for long-running operations:

```zig
const ProgressBar = rich.ProgressBar;

// Simple progress bar
const bar = ProgressBar.init()
    .withDescription("Downloading...")
    .withCompleted(60)
    .withTotal(100)
    .withWidth(30);

const segments = try bar.render(80, allocator);
defer allocator.free(segments);
try console.printSegments(segments);
```

Output:
```
Downloading...  ==================--------  60%
```

For multiple concurrent tasks, use `ProgressGroup`:

```zig
const ProgressGroup = rich.ProgressGroup;

var group = ProgressGroup.init(allocator);
defer group.deinit();

_ = try group.addTask("Download", 100);
_ = try group.addTask("Extract", 100);

// Update progress
group.bars.items[0].completed = 80;
group.bars.items[1].completed = 30;

try console.printRenderable(group);
```

## Using the Prelude

For quick scripts and prototyping, use the prelude to import common items:

```zig
const std = @import("std");
const prelude = @import("rich_zig").prelude;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = prelude.Console.init(allocator);
    defer console.deinit();

    // All common types available without namespace prefixes
    const panel = prelude.Panel.success(allocator, "Quick and easy!");
    try console.printRenderable(panel);

    var table = prelude.Table.init(allocator);
    defer table.deinit();
    _ = table.addColumn("Feature");
    _ = table.addColumn("Available");
    try table.addRow(&.{ "Console", "[check]" });
    try table.addRow(&.{ "Panel", "[check]" });
    try table.addRow(&.{ "Table", "[check]" });
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

- **Full API Reference**: `/docs/api.md` - Complete documentation for all modules
- **Advanced Guide**: `/docs/guide/advanced.md` - Custom renderables, layout system, live displays
- **Examples**: `/examples/` - Working example files for each feature
- **Demo**: Run `zig build run` to see all features in action

Happy coding with rich_zig!

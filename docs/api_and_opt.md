# API Documentation & Optimization Plan

Post-v1.0.0 roadmap for developer experience, documentation, and codebase optimization.

---

## Executive Summary

**Current State (v1.0.0):**
- 20.6K lines across 28 Zig files
- ~100 public types exported via root.zig
- Good README with installation instructions
- Inconsistent API patterns in places
- Several large monolithic files (markdown: 3.2K, syntax: 2.5K, table: 1.7K)

**Design Philosophy:**

rich_zig is not a wrapper or direct port - it's a **Zig-native terminal library** that provides familiar ergonomics for developers who've used Rich-style libraries. We leverage Zig's unique strengths:

- **Comptime**: Zero-cost abstractions, compile-time validation, generated builders
- **Explicit Allocators**: Clear ownership, no hidden allocations, arena-friendly
- **Error Unions**: Semantic errors that can be handled precisely
- **Value Semantics**: Immutable builders that are predictable and thread-safe

The API should feel intuitive to developers familiar with terminal styling libraries while being idiomatically Zig.

**Goals:**
1. Create comprehensive API documentation (manual + auto-generated)
2. Update README with v1.0.0 installation details
3. Refactor large files into smaller, focused modules
4. Leverage Zig's comptime and type reflection for better DX
5. Standardize API patterns across all modules

---

## Table of Contents

1. [API Design Principles](#1-api-design-principles)
2. [API Documentation Strategy](#2-api-documentation-strategy)
3. [README Updates](#3-readme-updates)
4. [File & Directory Optimization](#4-file--directory-optimization)
5. [Developer Experience Improvements](#5-developer-experience-improvements)
6. [Leveraging Zig's Strengths](#6-leveraging-zigs-strengths)
7. [Implementation Roadmap](#7-implementation-roadmap)

---

## 1. API Design Principles

### 1.1 The rich_zig Way

These principles guide all API decisions:

**Explicit over Implicit**
```zig
// Zig way: allocator is explicit, ownership is clear
var console = Console.init(allocator);
defer console.deinit();

// NOT: hidden global state or implicit allocation
```

**Predictable Value Semantics**
```zig
// Builders return new values - no hidden mutation
const panel = Panel.fromText(allocator, "content")
    .withTitle("Title")      // Returns new Panel
    .withWidth(40)           // Returns new Panel
    .rounded();              // Returns new Panel

// Original is unchanged, chain is predictable
```

**Errors Are Values**
```zig
// Handle specific errors, not catch-all exceptions
const result = console.print(user_input) catch |err| switch (err) {
    error.UnmatchedTag => fallback_print(user_input),
    error.InvalidColor => log_warning("bad color"),
    else => return err,
};
```

**Comptime When Possible**
```zig
// Catch mistakes at compile time, not runtime
const style = Style.parse("bold red") catch unreachable;  // Comptime-known string
const color = Color.fromName("purple") orelse @compileError("unknown color");
```

### 1.2 Familiar Patterns, Zig Implementation

| Pattern | Why It's Familiar | Zig Advantage |
|---------|-------------------|---------------|
| `console.print("[bold]text[/]")` | BBCode-like markup | Comptime parsing possible |
| `.withTitle().withWidth()` | Fluent builders | Value semantics, no mutation |
| `Panel`, `Table`, `Tree` | Rich-style components | Zero-cost renderables |
| `render(width) ![]Segment` | Lazy rendering | Caller controls allocation |

### 1.3 Memory Model

```
Construction           Rendering              Output
     |                     |                    |
     v                     v                    v
  [Panel]  ------>  render(width)  ------>  []Segment
     |                     |                    |
  stores              uses stored           caller owns
  allocator           allocator             returned slice
```

**Rules:**
1. Allocator passed at construction, stored in struct
2. `render()` uses stored allocator, returns owned slice
3. Caller must free returned segments (or use arena)
4. Content strings are borrowed, not copied (caller manages lifetime)

---

## 2. API Documentation Strategy

### 2.1 Manual API Documentation (api.md)

Create `docs/api.md` organized by architectural phase:

```
docs/api.md
  |-- Phase 1: Core Types (Color, Style, Segment, Cells)
  |-- Phase 2: Text & Markup (Text, Span, BoxStyle, Markup)
  |-- Phase 3: Terminal & Console (Terminal, Console, Options)
  |-- Phase 4: Renderables (Panel, Table, Tree, Progress, etc.)
  |-- Phase 5: Utilities (Logging, Prompt, Emoji)
```

**Documentation Template for Each Type:**

```markdown
### Panel

**Module:** `rich_zig.Panel`
**File:** `src/renderables/panel.zig`

#### Overview
Bordered boxes with optional title, subtitle, and configurable box styles.

#### Construction
| Constructor | Description | Allocates |
|------------|-------------|-----------|
| `fromText(alloc, text)` | Plain text content | No |
| `fromStyledText(alloc, text)` | Pre-styled Text object | No |
| `fromSegments(alloc, segs)` | Pre-rendered segments | No |

#### Builder Methods
| Method | Returns | Description |
|--------|---------|-------------|
| `.withTitle(str)` | `Panel` | Set panel title |
| `.withSubtitle(str)` | `Panel` | Set panel subtitle |
| `.withWidth(n)` | `Panel` | Set explicit width |
| `.rounded()` | `Panel` | Use rounded box style |

#### Rendering
```zig
const segments = try panel.render(max_width, allocator);
defer allocator.free(segments);
```

#### Memory
- Panel does NOT own content (caller manages lifetime)
- `render()` returns owned slice (caller must free)

#### Example
```zig
const panel = Panel.fromText(allocator, "Hello!")
    .withTitle("Greeting")
    .rounded();
try console.printRenderable(panel);
```
```

### 2.2 Auto-Generated Documentation (Stretch Goal)

**Approach: Zig Comptime Reflection**

Zig's `@typeInfo` allows introspecting types at compile time. Create a doc generator:

```zig
// tools/docgen.zig
const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var output = std.ArrayList(u8).init(allocator);
    const writer = output.writer();

    // Generate docs for exported types
    try generateTypeDoc(writer, rich.Panel, "Panel");
    try generateTypeDoc(writer, rich.Table, "Table");
    try generateTypeDoc(writer, rich.Console, "Console");
    // ...

    try std.fs.cwd().writeFile("docs/api_generated.md", output.items);
}

fn generateTypeDoc(writer: anytype, comptime T: type, name: []const u8) !void {
    const info = @typeInfo(T);

    try writer.print("## {s}\n\n", .{name});

    // Document struct fields
    if (info == .@"struct") {
        try writer.writeAll("### Fields\n\n");
        try writer.writeAll("| Field | Type | Default |\n");
        try writer.writeAll("|-------|------|--------|\n");

        inline for (info.@"struct".fields) |field| {
            const default = if (field.default_value) |_| "yes" else "required";
            try writer.print("| `{s}` | `{s}` | {s} |\n", .{
                field.name,
                @typeName(field.type),
                default,
            });
        }

        // Document public functions
        try writer.writeAll("\n### Methods\n\n");
        const decls = info.@"struct".decls;
        inline for (decls) |decl| {
            if (decl.is_pub) {
                try writer.print("- `{s}`\n", .{decl.name});
            }
        }
    }
}
```

**Limitations:**
- Doc comments are NOT available via `@typeInfo` (Zig limitation)
- Function signatures require manual extraction
- Best used as a scaffold, not replacement for manual docs

**Recommendation:** Use comptime to generate a type catalog with links to source, then manually document key types.

### 2.3 Documentation Structure

```
docs/
  |-- api.md              # Complete API reference (manual)
  |-- api_generated.md    # Auto-generated type catalog (stretch)
  |-- guide/
  |     |-- quickstart.md       # 5-minute getting started
  |     |-- console.md          # Console deep dive
  |     |-- tables.md           # Table patterns
  |     |-- styling.md          # Color & style guide
  |     |-- renderables.md      # All renderables overview
  |-- internals/
        |-- architecture.md     # Phase structure, dependencies
        |-- memory.md           # Allocation patterns
        |-- extending.md        # Adding new renderables
```

---

## 3. README Updates

### 3.1 Installation Section Improvements

Current installation is good but missing v1.0.0 specifics:

```markdown
## Installation

### Quick Start (Zig 0.15.2+)

```bash
# Add rich_zig to your project
zig fetch --save git+https://github.com/hotschmoe-zig/rich_zig.git#v1.0.0
```

This adds rich_zig to your `build.zig.zon` dependencies.

### build.zig Configuration

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rich_zig = b.dependency("rich_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
            },
        }),
    });

    b.installArtifact(exe);
}
```

### Version Pinning

Pin to a specific version (recommended for production):

```bash
# Pin to v1.0.0
zig fetch --save git+https://github.com/hotschmoe-zig/rich_zig.git#v1.0.0

# Or specify in build.zig.zon manually:
.dependencies = .{
    .rich_zig = .{
        .url = "git+https://github.com/hotschmoe-zig/rich_zig.git#v1.0.0",
        .hash = "1220...", // Run `zig build` to get hash
    },
},
```

### Verify Installation

```zig
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    try console.print("[bold green]rich_zig v1.0.0 installed successfully![/]");
}
```
```

### 3.2 Quick Reference Card

Add a quick reference section for common operations:

```markdown
## Quick Reference

| Task | Code |
|------|------|
| Print styled text | `try console.print("[bold red]Error![/]")` |
| Create panel | `Panel.fromText(alloc, "text").withTitle("T")` |
| Create table | `Table.init(alloc).withColumn(Column.init("A"))` |
| Add table row | `try table.addRowCells(.{ "a", "b", "c" })` |
| Progress bar | `ProgressBar.init().withCompleted(50).withTotal(100)` |
| Horizontal rule | `Rule.init().withTitle("Section")` |
| Tree node | `TreeNode.init(alloc, "root")` |
| Style composition | `Style.empty.bold().fg(Color.red)` |
```

---

## 4. File & Directory Optimization

### 4.1 Current Large Files Analysis

| File | Lines | Complexity | Priority |
|------|-------|------------|----------|
| `markdown.zig` | 3,186 | High (parser + renderer + themes) | P0 |
| `syntax.zig` | 2,518 | High (lexer + highlighter + languages) | P0 |
| `table.zig` | 1,659 | Medium (columns + rows + rendering) | P1 |
| `progress.zig` | 1,595 | Medium (bars + spinners + groups) | P1 |
| `logging.zig` | 1,307 | Medium (handlers + formatters) | P2 |
| `console.zig` | 1,283 | Medium (I/O + capture + export) | P2 |
| `text.zig` | 1,030 | Low (spans + wrapping) | P3 |

### 4.2 Refactoring Strategy: markdown.zig (3,186 lines)

**Current Structure:**
- Inline parser (block + inline elements)
- Theme definitions
- Renderer
- Code block handling (uses syntax.zig)

**Proposed Split:**

```
src/renderables/markdown/
  |-- mod.zig           # Public API, re-exports (~100 lines)
  |-- parser.zig        # Block + inline parsing (~1,200 lines)
  |-- renderer.zig      # Segment generation (~800 lines)
  |-- theme.zig         # Theme definitions (~300 lines)
  |-- elements.zig      # AST node types (~200 lines)
```

**Benefits:**
- Faster incremental compilation
- Easier testing of parser vs renderer
- Theme customization without touching parser
- Clear separation of concerns

**Migration Path:**
1. Extract types to `elements.zig`
2. Extract themes to `theme.zig`
3. Split parser logic to `parser.zig`
4. Move rendering to `renderer.zig`
5. Update `mod.zig` to re-export public API
6. Update imports in `root.zig`

### 4.3 Refactoring Strategy: syntax.zig (2,518 lines)

**Current Structure:**
- Language definitions (zig, json, python, etc.)
- Tokenizer per language
- Highlighter
- Theme system

**Proposed Split:**

```
src/renderables/syntax/
  |-- mod.zig           # Public API (~100 lines)
  |-- highlighter.zig   # Main highlighting logic (~600 lines)
  |-- theme.zig         # Color themes (~200 lines)
  |-- tokenizer.zig     # Generic tokenization (~400 lines)
  |-- languages/
        |-- mod.zig     # Language registry (~100 lines)
        |-- zig.zig     # Zig language rules (~200 lines)
        |-- json.zig    # JSON rules (~100 lines)
        |-- python.zig  # Python rules (~200 lines)
        |-- ...
```

**Comptime Optimization:**
Language definitions can be comptime-generated lookup tables:

```zig
// languages/mod.zig
pub const Language = enum {
    zig, json, python, javascript, rust, go, c, cpp,

    pub fn keywords(self: Language) []const []const u8 {
        return switch (self) {
            .zig => comptime &.{ "const", "var", "fn", "pub", "if", "else", ... },
            .json => comptime &.{},
            .python => comptime &.{ "def", "class", "import", "from", "if", "else", ... },
            // ...
        };
    }

    pub fn fromExtension(ext: []const u8) ?Language {
        const map = comptime std.StaticStringMap(Language).initComptime(.{
            .{ ".zig", .zig },
            .{ ".json", .json },
            .{ ".py", .python },
            .{ ".js", .javascript },
            // ...
        });
        return map.get(ext);
    }
};
```

### 4.4 Refactoring Strategy: table.zig (1,659 lines)

**Proposed Split:**

```
src/renderables/table/
  |-- mod.zig           # Public Table API (~200 lines)
  |-- column.zig        # Column definition & rendering (~400 lines)
  |-- row.zig           # Row handling & cell rendering (~400 lines)
  |-- layout.zig        # Width calculation & distribution (~400 lines)
  |-- style.zig         # Table theming (~200 lines)
```

### 4.5 Directory Structure After Optimization

```
src/
  |-- root.zig
  |-- main.zig
  |
  |-- core/                 # Phase 1 (NEW grouping)
  |     |-- mod.zig
  |     |-- color.zig
  |     |-- style.zig
  |     |-- segment.zig
  |     |-- cells.zig
  |
  |-- text/                 # Phase 2 (NEW grouping)
  |     |-- mod.zig
  |     |-- markup.zig
  |     |-- text.zig
  |     |-- box.zig
  |
  |-- terminal/             # Phase 3 (NEW grouping)
  |     |-- mod.zig
  |     |-- terminal.zig
  |     |-- console.zig
  |
  |-- renderables/          # Phase 4 (existing, reorganized)
  |     |-- mod.zig
  |     |-- panel.zig
  |     |-- rule.zig
  |     |-- tree.zig
  |     |-- align.zig
  |     |-- padding.zig
  |     |-- columns.zig
  |     |-- layout.zig
  |     |-- live.zig
  |     |-- json.zig
  |     |-- table/          # Split from table.zig
  |     |     |-- mod.zig
  |     |     |-- column.zig
  |     |     |-- row.zig
  |     |     |-- layout.zig
  |     |-- progress/       # Split from progress.zig
  |     |     |-- mod.zig
  |     |     |-- bar.zig
  |     |     |-- spinner.zig
  |     |     |-- group.zig
  |     |-- markdown/       # Split from markdown.zig
  |     |     |-- mod.zig
  |     |     |-- parser.zig
  |     |     |-- renderer.zig
  |     |     |-- theme.zig
  |     |-- syntax/         # Split from syntax.zig
  |           |-- mod.zig
  |           |-- highlighter.zig
  |           |-- theme.zig
  |           |-- languages/
  |
  |-- extras/               # Phase 5 (NEW grouping)
        |-- mod.zig
        |-- logging.zig
        |-- prompt.zig
        |-- emoji.zig
```

**IMPORTANT:** Restructuring directories is a breaking change for anyone importing internal modules. Public API via `root.zig` remains stable.

---

## 5. Developer Experience Improvements

### 5.1 API Consistency: Standardize on Value Semantics

**Current State (Inconsistent):**
```zig
// Table: reference-based, mutates in place
_ = table.addColumn("A");         // Returns *Table

// Panel: value-based, returns new copy
const panel = panel.withTitle("T"); // Returns Panel
```

**Target State (Consistent Value Semantics):**
```zig
// ALL builders return values - predictable, thread-safe, composable
const table = Table.init(allocator)
    .addColumn(Column.header("Name").style(Style.empty.bold()))
    .addColumn(Column.header("Value").justify(.right));

const panel = Panel.fromText(allocator, "content")
    .withTitle("Title")
    .rounded();
```

**Why Value Semantics for Zig:**
- No hidden mutation - easier to reason about
- Thread-safe by default - can pass between threads
- Comptime-friendly - more optimization opportunities
- Matches Zig's philosophy of explicitness

**Exception: Data Population Phase**

For adding rows to tables (often in loops), mutation is appropriate:

```zig
// Configuration phase: value semantics (fluent)
var table = Table.init(allocator)
    .addColumn(Column.header("Name"))
    .addColumn(Column.header("Value"));

// Data phase: mutation (practical for loops)
for (items) |item| {
    try table.addRow(.{ item.name, item.value });  // Mutates
}
```

### 5.2 Allocator Pattern: Store Once

**Current (Redundant):**
```zig
const panel = Panel.fromText(allocator, "text");
const segs = try panel.render(80, allocator);  // Why pass again?
```

**Target (Store at Construction):**
```zig
pub const Panel = struct {
    allocator: Allocator,
    content: Content,
    // ...

    pub fn render(self: Panel, max_width: usize) ![]Segment {
        // Uses self.allocator internally
        return try renderInternal(self.allocator, self.content, max_width);
    }
};

// Usage becomes cleaner
const segs = try panel.render(80);
defer panel.allocator.free(segs);
```

**When to Pass Allocator Explicitly:**
- Arena allocation for batch operations (Live displays)
- Cross-allocator scenarios (rare)

```zig
// Live rendering with arena - explicit allocator override
pub fn renderWith(self: Panel, max_width: usize, arena: Allocator) ![]Segment {
    return try renderInternal(arena, self.content, max_width);
}
```

### 5.3 Semantic Error Types

Leverage Zig's error unions for precise error handling:

```zig
// src/errors.zig
pub const MarkupError = error{
    UnmatchedTag,           // [bold without closing [/]
    InvalidColorName,       // [unknown_color]
    InvalidStyleAttribute,  // [notareal]
    NestedTagMismatch,      // [bold][italic][/bold]
};

pub const RenderError = error{
    OutOfMemory,
    InvalidWidth,           // Width too small for content
    ContentTooLarge,        // Exceeds max dimensions
};

pub const TableError = error{
    ColumnCountMismatch,    // Row has wrong number of cells
    InvalidSpan,            // Colspan/rowspan out of bounds
    OutOfMemory,
};
```

**Usage enables precise handling:**
```zig
const result = markup.parse(user_input) catch |err| switch (err) {
    error.UnmatchedTag => {
        // Show helpful error with position
        try console.print("[red]Error:[/] Unmatched tag at position {d}", .{pos});
        return;
    },
    error.InvalidColorName => {
        // Fall back to unstyled
        try console.print(stripMarkup(user_input));
        return;
    },
    else => return err,
};
```

### 5.4 Convenience Constructors

Common patterns should be one-liners:

```zig
// Panel semantic constructors
pub fn info(allocator: Allocator, text: []const u8) Panel {
    return fromText(allocator, text)
        .withBorderStyle(Style.empty.fg(Color.blue))
        .rounded();
}

pub fn warning(allocator: Allocator, text: []const u8) Panel {
    return fromText(allocator, text)
        .withBorderStyle(Style.empty.fg(Color.yellow))
        .withTitle("Warning")
        .rounded();
}

pub fn err(allocator: Allocator, text: []const u8) Panel {
    return fromText(allocator, text)
        .withBorderStyle(Style.empty.fg(Color.red))
        .withTitle("Error")
        .rounded();
}

pub fn success(allocator: Allocator, text: []const u8) Panel {
    return fromText(allocator, text)
        .withBorderStyle(Style.empty.fg(Color.green))
        .withTitle("Success")
        .rounded();
}
```

**Usage:**
```zig
try console.printRenderable(Panel.err(allocator, "File not found"));
try console.printRenderable(Panel.success(allocator, "Build complete"));
```

### 5.5 Prelude Module for Quick Start

```zig
// src/prelude.zig - Common imports for rapid prototyping
pub const Console = @import("console.zig").Console;
pub const Panel = @import("renderables/panel.zig").Panel;
pub const Table = @import("renderables/table.zig").Table;
pub const Tree = @import("renderables/tree.zig").Tree;
pub const Rule = @import("renderables/rule.zig").Rule;
pub const Progress = @import("renderables/progress.zig");
pub const Style = @import("style.zig").Style;
pub const Color = @import("color.zig").Color;
pub const Text = @import("text.zig").Text;

// Style shortcuts
pub const bold = Style.empty.bold();
pub const italic = Style.empty.italic();
pub const dim = Style.empty.dim();
pub const underline = Style.empty.underline();
```

**Usage:**
```zig
const rich = @import("rich_zig").prelude;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("[bold green]Hello, rich_zig![/]");
    try console.printRenderable(rich.Panel.info(allocator, "Welcome"));
}
```

### 5.6 Renderable Protocol

All renderables implement a consistent interface:

```zig
// The Renderable Protocol
// Any type with this signature can be rendered to console:
pub fn render(self: Self, max_width: usize) ![]Segment

// Built-in renderables: Panel, Table, Tree, Rule, Progress, Markdown, Syntax, etc.
```

**Creating Custom Renderables:**
```zig
const Counter = struct {
    allocator: Allocator,
    label: []const u8,
    value: u32,

    pub fn init(allocator: Allocator, label: []const u8, value: u32) Counter {
        return .{ .allocator = allocator, .label = label, .value = value };
    }

    pub fn render(self: Counter, max_width: usize) ![]Segment {
        _ = max_width;
        var segments = std.ArrayList(Segment).init(self.allocator);

        try segments.append(.{
            .text = self.label,
            .style = Style.empty.bold(),
        });

        var buf: [20]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&buf, ": {d}", .{self.value});
        try segments.append(.{
            .text = try self.allocator.dupe(u8, num_str),
            .style = Style.empty.fg(Color.cyan),
        });

        return segments.toOwnedSlice();
    }
};

// Usage
const counter = Counter.init(allocator, "Items", 42);
try console.printRenderable(counter);
```

---

## 6. Leveraging Zig's Strengths

These are the features that make rich_zig better than a simple port - they're only possible in Zig.

### 6.1 Comptime Builder Generation

Instead of 60+ handwritten builder methods, generate them at compile time:

```zig
fn BuilderMixin(comptime Self: type, comptime fields: anytype) type {
    return struct {
        pub usingnamespace blk: {
            var decls = struct {};
            inline for (fields) |field| {
                const name = "with" ++ capitalize(field.name);
                decls = @Type(.{ .@"struct" = .{
                    .decls = decls.decls ++ .{
                        .{ .name = name, .val = struct {
                            pub fn f(self: Self, value: field.type) Self {
                                var copy = self;
                                @field(copy, field.name) = value;
                                return copy;
                            }
                        }.f },
                    },
                }});
            }
            break :blk decls;
        };
    };
}

// Usage - define once, get all builders free
pub const Panel = struct {
    title: ?[]const u8 = null,
    subtitle: ?[]const u8 = null,
    width: ?usize = null,
    padding: Padding = .{},
    box_style: BoxStyle = .rounded,

    pub usingnamespace BuilderMixin(Panel, .{
        .{ .name = "title", .type = []const u8 },
        .{ .name = "subtitle", .type = []const u8 },
        .{ .name = "width", .type = usize },
        .{ .name = "padding", .type = Padding },
        .{ .name = "box_style", .type = BoxStyle },
    });
    // Automatically generates: withTitle, withSubtitle, withWidth, withPadding, withBoxStyle
};
```

### 6.2 Comptime Markup Validation

For static markup strings, validate at compile time:

```zig
pub fn comptimeMarkup(comptime markup: []const u8) CompiledMarkup {
    comptime {
        var parser = MarkupParser.init(markup);
        const result = parser.parse() catch |err| {
            @compileError("Invalid markup: " ++ @errorName(err) ++ " in: " ++ markup);
        };
        return result;
    }
}

// Usage - errors caught at compile time, zero runtime cost
const welcome = comptimeMarkup("[bold green]Welcome![/]");
try console.printCompiled(welcome);

// This won't compile:
// const bad = comptimeMarkup("[bold unclosed");  // Compile error!
```

### 6.3 Static String Maps

Replace runtime string matching with O(1) comptime-generated lookups:

```zig
// color.zig - Named color lookup
const named_colors = std.StaticStringMap(Color).initComptime(.{
    .{ "black", Color.black },
    .{ "red", Color.red },
    .{ "green", Color.green },
    .{ "yellow", Color.yellow },
    .{ "blue", Color.blue },
    .{ "magenta", Color.magenta },
    .{ "cyan", Color.cyan },
    .{ "white", Color.white },
    .{ "bright_red", Color.bright_red },
    .{ "bright_green", Color.bright_green },
    // ... all 256 color names
});

pub fn fromName(name: []const u8) ?Color {
    return named_colors.get(name);  // O(1) lookup, no allocation
}

// Language extension mapping for syntax highlighting
const extension_map = std.StaticStringMap(Language).initComptime(.{
    .{ ".zig", .zig },
    .{ ".json", .json },
    .{ ".py", .python },
    .{ ".js", .javascript },
    .{ ".ts", .typescript },
    .{ ".rs", .rust },
    .{ ".go", .go },
    .{ ".c", .c },
    .{ ".h", .c },
    .{ ".cpp", .cpp },
    .{ ".hpp", .cpp },
});
```

### 6.4 Comptime Interface Verification

Catch missing methods at compile time, not runtime:

```zig
pub fn Renderable(comptime T: type) type {
    // Compile-time interface check
    comptime {
        if (!@hasDecl(T, "render")) {
            @compileError(@typeName(T) ++ " must have render(usize) ![]Segment method");
        }

        const render_fn = @typeInfo(@TypeOf(@field(T, "render"))).@"fn";
        if (render_fn.params.len != 2) {  // self + max_width
            @compileError(@typeName(T) ++ ".render must take (self, max_width: usize)");
        }
    }

    return struct {
        pub fn renderToConsole(self: T, console: *Console) !void {
            const segments = try self.render(console.width);
            defer console.allocator.free(segments);
            try console.writeSegments(segments);
        }

        pub fn renderToString(self: T, allocator: Allocator, width: usize) ![]u8 {
            const segments = try self.render(width);
            defer allocator.free(segments);
            return try segmentsToString(allocator, segments);
        }
    };
}

// Any type with render() automatically gets renderToConsole, renderToString
pub const Panel = struct {
    // ...
    pub fn render(self: Panel, max_width: usize) ![]Segment { ... }
    pub usingnamespace Renderable(Panel);
};

pub const Table = struct {
    // ...
    pub fn render(self: Table, max_width: usize) ![]Segment { ... }
    pub usingnamespace Renderable(Table);
};
```

### 6.5 Arena Allocation for Live Displays

Real-time rendering benefits from arena allocation - batch free in O(1):

```zig
pub const LiveContext = struct {
    arena: std.heap.ArenaAllocator,
    console: *Console,

    pub fn init(console: *Console) LiveContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(console.allocator),
            .console = console,
        };
    }

    pub fn deinit(self: *LiveContext) void {
        self.arena.deinit();
    }

    /// Render a frame - all allocations use arena
    pub fn frame(self: *LiveContext, renderable: anytype) !void {
        // Reset arena - free all previous frame's allocations in O(1)
        _ = self.arena.reset(.retain_capacity);

        // Render to arena allocator
        const segments = try renderable.renderWith(
            self.console.width,
            self.arena.allocator(),
        );

        // Write to console (segments valid until next frame() call)
        try self.console.writeSegments(segments);
    }
};

// Usage for progress bars, spinners, live updates
var live = LiveContext.init(&console);
defer live.deinit();

for (0..100) |i| {
    const progress = ProgressBar.init().withCompleted(i).withTotal(100);
    try live.frame(progress);  // No per-frame allocations!
    std.time.sleep(50 * std.time.ns_per_ms);
}
```

### 6.6 Comptime Language Definitions

Syntax highlighting rules as comptime data - zero runtime parsing:

```zig
pub const Language = enum {
    zig, json, python, javascript, rust, go, c, cpp,

    pub fn keywords(self: Language) []const []const u8 {
        return switch (self) {
            .zig => comptime &.{
                "const", "var", "fn", "pub", "if", "else", "while",
                "for", "switch", "return", "try", "catch", "defer",
                "comptime", "inline", "struct", "enum", "union",
            },
            .python => comptime &.{
                "def", "class", "import", "from", "if", "else", "elif",
                "while", "for", "return", "try", "except", "with", "as",
                "lambda", "yield", "async", "await",
            },
            .rust => comptime &.{
                "fn", "let", "mut", "const", "if", "else", "match",
                "while", "for", "loop", "return", "struct", "enum",
                "impl", "trait", "pub", "use", "mod", "async", "await",
            },
            // ...
        };
    }

    pub fn operators(self: Language) []const []const u8 {
        return switch (self) {
            .zig => comptime &.{ "=>", "->", "++", "**", "..", ".*", ".?" },
            .rust => comptime &.{ "=>", "->", "::", "..", "..=", "?" },
            // ...
        };
    }

    pub fn commentPrefix(self: Language) []const u8 {
        return switch (self) {
            .zig, .rust, .go, .c, .cpp, .javascript => "//",
            .python => "#",
            .json => "",  // No comments in JSON
        };
    }
};
```

### 6.7 Compile-Time Style Composition

Styles can be composed at compile time for zero-cost theming:

```zig
pub const Theme = struct {
    pub const monokai = struct {
        pub const keyword = comptime Style.empty.fg(Color.fromHex("#F92672")).bold();
        pub const string = comptime Style.empty.fg(Color.fromHex("#E6DB74"));
        pub const comment = comptime Style.empty.fg(Color.fromHex("#75715E")).italic();
        pub const function = comptime Style.empty.fg(Color.fromHex("#A6E22E"));
        pub const number = comptime Style.empty.fg(Color.fromHex("#AE81FF"));
    };

    pub const dracula = struct {
        pub const keyword = comptime Style.empty.fg(Color.fromHex("#FF79C6")).bold();
        pub const string = comptime Style.empty.fg(Color.fromHex("#F1FA8C"));
        pub const comment = comptime Style.empty.fg(Color.fromHex("#6272A4")).italic();
        pub const function = comptime Style.empty.fg(Color.fromHex("#50FA7B"));
        pub const number = comptime Style.empty.fg(Color.fromHex("#BD93F9"));
    };
};

// Usage - theme selection has zero runtime cost
const syntax = Syntax.init(allocator, code, .zig)
    .withTheme(Theme.monokai);  // Comptime theme, no allocation
```

---

## 7. Implementation Roadmap

### Phase A: Quick Wins (No Breaking Changes)

These can be shipped immediately without affecting existing users:

| Task | Priority | Description |
|------|----------|-------------|
| Add prelude module | P0 | Create `src/prelude.zig` with common exports |
| Add Panel convenience constructors | P0 | `.info()`, `.warning()`, `.err()`, `.success()` |
| Add semantic error types | P1 | `src/errors.zig` with MarkupError, RenderError, TableError |
| Document renderable protocol | P1 | How to create custom renderables |
| Add StaticStringMap for colors | P1 | O(1) color name lookup |

### Phase B: API Consistency (Minor Breaking)

These improve the API but may require user code changes:

| Task | Priority | Description |
|------|----------|-------------|
| Store allocator in renderables | P0 | Simplify `render()` signature to just `render(width)` |
| Standardize builder return types | P0 | All builders return value copies, not `*Self` |
| Add Column builder for Table | P1 | `Column.header("Name").style(...).justify(...)` |
| Split Table API: config vs data | P1 | Fluent for columns, mutation for rows |

### Phase C: Documentation

| Task | Priority | Description |
|------|----------|-------------|
| Create docs/api.md skeleton | P0 | Type reference organized by phase |
| Create docs/guide/quickstart.md | P0 | 5-minute getting started |
| Document Console API | P0 | Print, log, capture, export |
| Document Panel, Table, Tree | P0 | Core renderables |
| Document all renderables | P1 | Rule, Progress, Syntax, Markdown, etc. |
| Update README with v1.0.0 details | P0 | Installation, version pinning |
| Add quick reference card | P1 | Common operations cheat sheet |

### Phase D: Large File Refactoring

| Task | Priority | Description |
|------|----------|-------------|
| Split markdown.zig (3.2K lines) | P0 | parser.zig, renderer.zig, theme.zig, elements.zig |
| Split syntax.zig (2.5K lines) | P0 | highlighter.zig, theme.zig, tokenizer.zig, languages/ |
| Split table.zig (1.7K lines) | P1 | column.zig, row.zig, layout.zig, style.zig |
| Split progress.zig (1.6K lines) | P1 | bar.zig, spinner.zig, group.zig |
| Update imports in root.zig | P0 | Maintain public API stability |
| Verify all tests pass | P0 | No regressions |

### Phase E: Comptime Optimizations

| Task | Priority | Description |
|------|----------|-------------|
| Implement BuilderMixin | P2 | Comptime-generated builder methods |
| Add comptime markup validation | P2 | `comptimeMarkup("[bold]text[/]")` |
| Implement comptime themes | P2 | Zero-cost theme composition |
| Arena allocation for Live | P2 | O(1) frame reset |
| Create docgen tool (stretch) | P3 | Comptime type introspection for docs |

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Largest file (lines) | 3,186 | <800 |
| Files >1000 lines | 7 | 0 |
| Documented public types | ~20% | 100% |
| Build time (cold) | TBD | -20% |
| Example code in docs | ~10 | 50+ |

---

## Appendix: File Line Counts

**Core Modules:**
- root.zig: 214
- color.zig: 433
- style.zig: 505
- segment.zig: 545
- cells.zig: 419
- text.zig: 1,030
- markup.zig: 288
- box.zig: 296
- console.zig: 1,283
- terminal.zig: 226
- emoji.zig: 389
- logging.zig: 1,307
- prompt.zig: 726
- main.zig: 693

**Renderables:**
- mod.zig: 90
- panel.zig: 575
- table.zig: 1,659
- progress.zig: 1,595
- rule.zig: 150
- tree.zig: 409
- align.zig: 260
- padding.zig: 184
- columns.zig: 372
- layout.zig: 601
- live.zig: 321
- json.zig: 499
- syntax.zig: 2,518
- markdown.zig: 3,186

**Total:** ~20,600 lines

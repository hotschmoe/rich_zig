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

**Goals:**
1. Create comprehensive API documentation (manual + auto-generated)
2. Update README with v1.0.0 installation details
3. Refactor large files into smaller, focused modules
4. Leverage Zig's comptime and type reflection for better DX

---

## Table of Contents

1. [API Documentation Strategy](#1-api-documentation-strategy)
2. [README Updates](#2-readme-updates)
3. [File & Directory Optimization](#3-file--directory-optimization)
4. [Developer Experience Improvements](#4-developer-experience-improvements)
5. [Leveraging Zig's Strengths](#5-leveraging-zigs-strengths)
6. [Implementation Roadmap](#6-implementation-roadmap)

---

## 1. API Documentation Strategy

### 1.1 Manual API Documentation (api.md)

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

### 1.2 Auto-Generated Documentation (Stretch Goal)

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

### 1.3 Documentation Structure

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

## 2. README Updates

### 2.1 Installation Section Improvements

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

### 2.2 Quick Reference Card

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

## 3. File & Directory Optimization

### 3.1 Current Large Files Analysis

| File | Lines | Complexity | Priority |
|------|-------|------------|----------|
| `markdown.zig` | 3,186 | High (parser + renderer + themes) | P0 |
| `syntax.zig` | 2,518 | High (lexer + highlighter + languages) | P0 |
| `table.zig` | 1,659 | Medium (columns + rows + rendering) | P1 |
| `progress.zig` | 1,595 | Medium (bars + spinners + groups) | P1 |
| `logging.zig` | 1,307 | Medium (handlers + formatters) | P2 |
| `console.zig` | 1,283 | Medium (I/O + capture + export) | P2 |
| `text.zig` | 1,030 | Low (spans + wrapping) | P3 |

### 3.2 Refactoring Strategy: markdown.zig (3,186 lines)

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

### 3.3 Refactoring Strategy: syntax.zig (2,518 lines)

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

### 3.4 Refactoring Strategy: table.zig (1,659 lines)

**Proposed Split:**

```
src/renderables/table/
  |-- mod.zig           # Public Table API (~200 lines)
  |-- column.zig        # Column definition & rendering (~400 lines)
  |-- row.zig           # Row handling & cell rendering (~400 lines)
  |-- layout.zig        # Width calculation & distribution (~400 lines)
  |-- style.zig         # Table theming (~200 lines)
```

### 3.5 Directory Structure After Optimization

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

## 4. Developer Experience Improvements

### 4.1 API Consistency Fixes

**Issue 1: Table returns `*Table`, Panel returns `Panel`**

```zig
// Current (inconsistent)
pub fn withTitle(self: *Table, title: []const u8) *Table  // Table
pub fn withTitle(self: Panel, title: []const u8) Panel    // Panel
```

**Recommendation:** Standardize on value-returning builders where struct size is reasonable (<256 bytes).

**Issue 2: Allocator passed at construction AND render**

```zig
// Current (redundant)
const panel = Panel.fromText(allocator, "text");
const segs = try panel.render(80, allocator);  // Why pass again?
```

**Recommendation:** Store allocator in struct, use stored allocator in render:

```zig
// Improved
pub fn render(self: Panel, max_width: usize) ![]Segment {
    // Uses self.allocator
}
```

### 4.2 Error Type Improvements

Add semantic error sets:

```zig
// src/errors.zig (NEW)
pub const RenderError = error{
    OutOfMemory,
    InvalidDimensions,
    ContentTooLarge,
};

pub const MarkupError = error{
    UnmatchedTag,
    InvalidColorName,
    InvalidAttribute,
};

pub const ParseError = error{
    UnexpectedToken,
    InvalidSyntax,
    UnsupportedFeature,
};
```

### 4.3 Convenience Constructors

Add shorthand constructors for common patterns:

```zig
// Panel shortcuts
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

pub fn errorPanel(allocator: Allocator, text: []const u8) Panel {
    return fromText(allocator, text)
        .withBorderStyle(Style.empty.fg(Color.red))
        .withTitle("Error")
        .rounded();
}
```

### 4.4 Type Discovery

Add a "prelude" for common imports:

```zig
// src/prelude.zig
pub const Console = @import("console.zig").Console;
pub const Panel = @import("renderables/panel.zig").Panel;
pub const Table = @import("renderables/table.zig").Table;
pub const Rule = @import("renderables/rule.zig").Rule;
pub const Style = @import("style.zig").Style;
pub const Color = @import("color.zig").Color;

// Common style shortcuts
pub const bold = Style.empty.bold();
pub const italic = Style.empty.italic();
pub const red = Style.empty.fg(Color.red);
pub const green = Style.empty.fg(Color.green);
pub const blue = Style.empty.fg(Color.blue);
```

Usage:
```zig
const rich = @import("rich_zig").prelude;

var console = rich.Console.init(allocator);
try console.print(rich.bold.render("Hello"));
```

---

## 5. Leveraging Zig's Strengths

### 5.1 Comptime Type Generation

**Builder Method Generation:**

Instead of 60+ handwritten builder methods, use comptime:

```zig
fn BuilderMixin(comptime Self: type, comptime fields: []const struct { name: []const u8, type: type }) type {
    return struct {
        inline for (fields) |field| {
            pub fn @("with" ++ capitalize(field.name))(self: Self, value: field.type) Self {
                var copy = self;
                @field(copy, field.name) = value;
                return copy;
            }
        }
    };
}

// Usage
pub const Panel = struct {
    title: ?[]const u8 = null,
    width: ?usize = null,
    // ...

    pub usingnamespace BuilderMixin(Panel, .{
        .{ .name = "title", .type = []const u8 },
        .{ .name = "width", .type = usize },
    });
};
```

### 5.2 Comptime Validation

Validate configurations at compile time:

```zig
pub fn initWithOptions(allocator: Allocator, comptime options: Options) Console {
    comptime {
        if (options.width != null and options.width.? < 10) {
            @compileError("Console width must be >= 10");
        }
        if (options.tab_size > 16) {
            @compileError("Tab size cannot exceed 16");
        }
    }
    // ...
}
```

### 5.3 Static String Maps for Lookups

Replace runtime string matching with comptime maps:

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
    // 256-color names...
});

pub fn fromName(name: []const u8) ?Color {
    return named_colors.get(name);
}
```

### 5.4 Generic Renderable Interface

Use Zig's duck typing for renderables:

```zig
pub fn Renderable(comptime T: type) type {
    // Compile-time interface check
    comptime {
        if (!@hasDecl(T, "render")) {
            @compileError(@typeName(T) ++ " must have render() method");
        }
    }

    return struct {
        pub fn renderToConsole(self: T, console: *Console) !void {
            const segments = try self.render(console.width, console.allocator);
            defer console.allocator.free(segments);
            try console.writeSegments(segments);
        }
    };
}

// Auto-add renderToConsole to all renderables
pub const Panel = struct {
    // ...
    pub usingnamespace Renderable(Panel);
};
```

### 5.5 Segment Pooling with ArenaAllocator

For real-time rendering (Live displays), use arena allocation:

```zig
pub const LiveContext = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: Allocator) LiveContext {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn render(self: *LiveContext, renderable: anytype) ![]Segment {
        // All allocations go to arena
        return renderable.render(self.arena.allocator());
    }

    pub fn reset(self: *LiveContext) void {
        // Free all segments at once - O(1)
        _ = self.arena.reset(.retain_capacity);
    }
};
```

---

## 6. Implementation Roadmap

### Phase A: Documentation (Week 1-2)

| Task | Priority | Effort |
|------|----------|--------|
| Create docs/api.md skeleton | P0 | 2h |
| Document Console API | P0 | 3h |
| Document Panel, Table, Tree | P0 | 4h |
| Document all renderables | P1 | 6h |
| Create docs/guide/quickstart.md | P0 | 2h |
| Update README with v1.0.0 details | P0 | 1h |
| Add quick reference card | P1 | 1h |

### Phase B: Large File Refactoring (Week 3-4)

| Task | Priority | Effort |
|------|----------|--------|
| Split markdown.zig | P0 | 8h |
| Split syntax.zig | P0 | 6h |
| Split table.zig | P1 | 4h |
| Split progress.zig | P1 | 4h |
| Update imports in root.zig | P0 | 1h |
| Verify all tests pass | P0 | 2h |

### Phase C: API Improvements (Week 5-6)

| Task | Priority | Effort |
|------|----------|--------|
| Standardize builder return types | P1 | 4h |
| Remove redundant allocator params | P1 | 3h |
| Add semantic error types | P2 | 2h |
| Add convenience constructors | P2 | 2h |
| Add prelude module | P2 | 1h |

### Phase D: Comptime Optimizations (Week 7-8)

| Task | Priority | Effort |
|------|----------|--------|
| Implement BuilderMixin | P2 | 4h |
| Add StaticStringMap for colors | P2 | 2h |
| Add comptime validation | P3 | 2h |
| Implement segment pooling | P3 | 4h |
| Create docgen tool (stretch) | P3 | 8h |

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

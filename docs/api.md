# API Reference

## Overview

This document provides comprehensive API documentation for `rich_zig`, organized by development phases:

- **Phase 1**: Core types (Color, Style, Segment, Cells)
- **Phase 2**: Text and markup processing
- **Phase 3**: Terminal interaction and console
- **Phase 4**: Rich renderables (Panel, Table, Tree, etc.)
- **Phase 5**: Utilities (Logging, Prompts, Emoji)

Each renderable implements the core rendering interface:
```zig
fn render(self: Self, max_width: usize, allocator: std.mem.Allocator) ![]Segment
```

---

## Phase 1: Core Types

### Color

**Module:** `rich_zig.Color`
**File:** `src/color.zig`

#### Overview

Represents terminal colors with support for standard 16-color palettes, 256-color mode, and 24-bit truecolor RGB. Handles color downgrading for terminal compatibility.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Color.default` | Terminal default color (no explicit color set) |
| `Color.black`, `Color.red`, etc. | Standard 16 colors (0-15) |
| `Color.bright_black`, `Color.bright_red`, etc. | Bright variants (8-15) |
| `Color.fromRgb(r: u8, g: u8, b: u8)` | Creates truecolor from RGB values |
| `Color.fromHex(hex_str: []const u8)` | Parses hex color string ("#RRGGBB" or "RRGGBB") |
| `Color.from256(number: u8)` | Creates 256-color palette entry |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `downgrade(target: ColorSystem)` | `Color` | Converts color to lower color system if needed |
| `getTriplet()` | `?ColorTriplet` | Gets RGB approximation of any color type |
| `getAnsiCodes(foreground: bool, writer)` | `!void` | Writes ANSI escape codes for this color |
| `eql(other: Color)` | `bool` | Tests color equality |

#### Types

```zig
pub const ColorType = enum {
    default, standard, eight_bit, truecolor
};

pub const ColorSystem = enum(u8) {
    standard = 1,      // 16 colors
    eight_bit = 2,     // 256 colors
    truecolor = 3,     // RGB 24-bit
};

pub const ColorTriplet = struct {
    r: u8, g: u8, b: u8,

    pub fn hex(self: ColorTriplet) [7]u8;
    pub fn blend(c1: ColorTriplet, c2: ColorTriplet, t: f32) ColorTriplet;
    pub fn eql(self: ColorTriplet, other: ColorTriplet) bool;
};
```

#### Example

```zig
const std = @import("std");
const Color = @import("rich_zig").Color;

// Standard colors
const red = Color.red;
const bright_green = Color.bright_green;

// Truecolor
const orange = Color.fromRgb(255, 128, 0);
const purple = try Color.fromHex("#800080");

// 256-color palette
const salmon = Color.from256(210);

// Downgrade for compatibility
const downgraded = orange.downgrade(.standard); // Converts to nearest 16-color
```

---

### Style

**Module:** `rich_zig.Style`
**File:** `src/style.zig`

#### Overview

Encapsulates text styling attributes including colors, text decorations (bold, italic, underline, etc.), and hyperlinks. Styles can be combined, with later styles overriding earlier ones.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Style.empty` | Empty style with no attributes |
| `Style.parse(definition: []const u8)` | Parses style from string (e.g., "bold red on white") |

#### Modifier Methods (Fluent API)

All modifier methods return a new `Style` for chaining.

| Method | Description |
|--------|-------------|
| `bold()`, `notBold()` | Enable/disable bold text |
| `dim()`, `notDim()` | Enable/disable dim/faint text |
| `italic()`, `notItalic()` | Enable/disable italic text |
| `underline()`, `notUnderline()` | Enable/disable underline |
| `blink()`, `notBlink()` | Enable/disable blinking text |
| `reverse()`, `notReverse()` | Enable/disable reverse video |
| `conceal()`, `notConceal()` | Enable/disable concealed text |
| `strike()`, `notStrike()` | Enable/disable strikethrough |
| `strikethrough()` | Alias for `strike()` |
| `overline()`, `notOverline()` | Enable/disable overline |
| `foreground(c: Color)`, `fg(c: Color)` | Set foreground color |
| `background(c: Color)`, `bg(c: Color)` | Set background color |
| `hyperlink(url: []const u8)` | Add hyperlink (OSC 8) |

#### Core Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `hasAttribute(attr: StyleAttribute)` | `bool` | Check if attribute is enabled |
| `combine(other: Style)` | `Style` | Merge styles (other takes precedence) |
| `renderAnsi(color_system: ColorSystem, writer)` | `!void` | Write ANSI escape sequence |
| `eql(other: Style)` | `bool` | Test equality |
| `isEmpty()` | `bool` | Check if style has any attributes set |

#### Example

```zig
const Style = @import("rich_zig").Style;
const Color = @import("rich_zig").Color;

// Fluent API chaining
const style1 = Style.empty
    .bold()
    .italic()
    .fg(Color.red)
    .bg(Color.white);

// Parse from string
const style2 = try Style.parse("bold underline blue on yellow");

// Combine styles
const combined = style1.combine(style2); // style2 attributes override style1

// Check attributes
if (combined.hasAttribute(.bold)) {
    // bold is set
}
```

---

### Segment

**Module:** `rich_zig.Segment`
**File:** `src/segment.zig`

#### Overview

The atomic rendering unit in rich_zig. A segment is text with optional styling or a control code. All renderables produce segments as output.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Segment.plain(text: []const u8)` | Text with no styling |
| `Segment.styled(text: []const u8, style: Style)` | Text with explicit style |
| `Segment.styledOptional(text: []const u8, style: ?Style)` | Text with optional style |
| `Segment.controlSegment(code: ControlCode)` | Terminal control sequence |
| `Segment.line()` | Newline segment |
| `Segment.space()` | Single space segment |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `cellLength()` | `usize` | Display width in terminal cells |
| `isControl()` | `bool` | Check if segment is a control code |
| `isEmpty()` | `bool` | Check if segment has no content |
| `isWhitespace()` | `bool` | Check if only whitespace |
| `splitCells(pos: usize)` | `struct { Segment, Segment }` | Split at cell position |
| `withStyle(new_style: Style)` | `Segment` | Create copy with new style |
| `withoutStyle()` | `Segment` | Create copy without style |
| `render(writer, color_system)` | `!void` | Render to writer with ANSI codes |

#### Module Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `stripStyles(segments: []const Segment, allocator)` | `![]Segment` | Remove all styles from segments |
| `joinText(segments: []const Segment, allocator)` | `![]u8` | Extract plain text |
| `totalCellLength(segments: []const Segment)` | `usize` | Sum of all segment widths |
| `splitIntoLines(segments: []const Segment, allocator)` | `![][]const Segment` | Split on newline segments |
| `maxLineWidth(lines: []const []const Segment)` | `usize` | Maximum line width |
| `adjustLineLength(segments, target_length, pad_char, allocator)` | `![]Segment` | Pad or truncate to target length |

#### Control Codes

```zig
pub const ControlCode = union(enum) {
    bell, carriage_return, home, clear,
    show_cursor, hide_cursor,
    enable_alt_screen, disable_alt_screen,
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_backward: u16,
    cursor_move_to_column: u16,
    cursor_move_to: struct { x: u16, y: u16 },
    erase_in_line: u8,
    set_window_title: []const u8,
};
```

#### Example

```zig
const Segment = @import("rich_zig").Segment;
const Style = @import("rich_zig").Style;

// Basic segments
const plain = Segment.plain("Hello");
const styled = Segment.styled("World", Style.empty.bold().fg(Color.red));
const newline = Segment.line();

// Measure and manipulate
const width = plain.cellLength(); // 5

const split_result = plain.splitCells(2);
// split_result[0].text == "He"
// split_result[1].text == "llo"

// Control sequences
const clear = Segment.controlSegment(.clear);
const move = Segment.controlSegment(.{ .cursor_move_to = .{ .x = 10, .y = 5 } });
```

---

### Cells

**Module:** `rich_zig.cells`
**File:** `src/cells.zig`

#### Overview

Unicode-aware text width calculation. Handles CJK wide characters (2 cells), combining marks (0 cells), and standard characters (1 cell).

#### Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getCharacterCellSize(codepoint: u21)` | `u2` | Width of single Unicode codepoint (0, 1, or 2) |
| `cellLen(text: []const u8)` | `usize` | Display width of UTF-8 string |
| `cellToByteIndex(text: []const u8, cell_pos: usize)` | `usize` | Convert cell position to byte index |
| `truncate(text: []const u8, max_width: usize, ellipsis: []const u8)` | `[]const u8` | Truncate text to fit width, optionally with ellipsis |
| `setLen(text: []const u8, width: usize, pad_char: u8, allocator)` | `![]u8` | Pad or truncate text to exact width (allocates) |

#### Character Width Rules

- **0 cells**: Control characters, zero-width spaces, combining marks
- **1 cell**: ASCII, Latin, most Unicode
- **2 cells**: CJK characters, full-width forms, emoji

#### Example

```zig
const cells = @import("rich_zig").cells;

// Width calculation
const width1 = cells.cellLen("Hello"); // 5
const width2 = cells.cellLen("中文"); // 4 (2 CJK chars * 2 cells each)
const width3 = cells.cellLen("e\u{0301}"); // 1 (e + combining acute accent)

// Byte/cell conversion
const byte_idx = cells.cellToByteIndex("Hello World", 6); // Index of 'W'

// Truncation
const truncated = cells.truncate("Hello World", 8, "...");
// Result: "Hello" (8 - 3 for "..." = 5 cells)

// Padding/truncating with allocation
const padded = try cells.setLen("Hi", 5, ' ', allocator);
defer allocator.free(padded);
// Result: "Hi   "
```

---

## Phase 2: Text & Markup

### Text

**Module:** `rich_zig.Text`
**File:** `src/text.zig`

[TODO: Document Text type - styled text with span support]

### Markup

**Module:** `rich_zig.markup`
**File:** `src/markup.zig`

[TODO: Document markup parser - BBCode-like syntax for inline styling]

### BoxStyle

**Module:** `rich_zig.BoxStyle`
**File:** `src/box.zig`

[TODO: Document box drawing styles - rounded, square, heavy, double, ASCII]

---

## Phase 3: Terminal & Console

### Terminal

**Module:** `rich_zig.terminal`
**File:** `src/terminal.zig`

[TODO: Document terminal detection - color support, size, TTY detection]

### Console

**Module:** `rich_zig.Console`
**File:** `src/console.zig`

#### Overview

Main interface for terminal output. Handles styling, rendering, logging, status lines, and user input.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Console.init(allocator: std.mem.Allocator)` | Create with default options |
| `Console.initWithOptions(allocator, options: ConsoleOptions)` | Create with custom options |

#### ConsoleOptions

```zig
pub const ConsoleOptions = struct {
    width: ?u16 = null,              // Override terminal width
    height: ?u16 = null,             // Override terminal height
    color_system: ?ColorSystem = null, // Force color system
    force_terminal: bool = false,    // Treat as TTY even if not
    no_color: bool = false,          // Disable colors
    tab_size: u8 = 8,                // Tab width
    record: bool = false,            // Enable capture buffer
};
```

#### Terminal Info Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `width()` | `u16` | Terminal width in columns |
| `height()` | `u16` | Terminal height in rows |
| `colorSystem()` | `ColorSystem` | Active color system |
| `isTty()` | `bool` | Check if output is a terminal |

#### Output Methods

| Method | Description |
|--------|-------------|
| `print(text_markup: []const u8)` | Print text with markup, add newline |
| `printPlain(text: []const u8)` | Print plain text without styling, add newline |
| `printStyled(text: []const u8, style: Style)` | Print with explicit style, add newline |
| `printText(txt: Text)` | Print Text object (no automatic newline) |
| `printSegments(segments: []const Segment)` | Print pre-rendered segments |
| `rule(title_opt: ?[]const u8)` | Print horizontal rule with optional title |
| `clear()` | Clear screen |
| `bell()` | Emit terminal bell |

#### Cursor & Screen Control

| Method | Description |
|--------|-------------|
| `showCursor()` | Make cursor visible |
| `hideCursor()` | Make cursor invisible |
| `clearLine()` | Clear current line |
| `enterAltScreen()` | Switch to alternate screen buffer |
| `exitAltScreen()` | Return to main screen buffer |
| `setTitle(title: []const u8)` | Set terminal window title |

#### Status Line

| Method | Description |
|--------|-------------|
| `status(message: []const u8)` | Display ephemeral status line |
| `statusFmt(comptime fmt: []const u8, args)` | Display formatted status |
| `clearStatus()` | Clear current status line |

#### Logging

```zig
pub const LogLevel = enum { debug, info, warn, err };
```

| Method | Description |
|--------|-------------|
| `log(level: LogLevel, comptime fmt: []const u8, args)` | Log with timestamp and level |
| `logDebug(comptime fmt: []const u8, args)` | Log at debug level |
| `logInfo(comptime fmt: []const u8, args)` | Log at info level |
| `logWarn(comptime fmt: []const u8, args)` | Log at warn level |
| `logErr(comptime fmt: []const u8, args)` | Log at error level |

#### Input/Prompts

```zig
pub const InputOptions = struct {
    default: ?[]const u8 = null,
    password: bool = false,
    show_default: bool = true,
    validator: ?*const fn ([]const u8) InputValidationResult = null,
    max_length: ?usize = null,
};

pub const InputValidationResult = union(enum) {
    valid,
    invalid: []const u8, // Error message
};
```

| Method | Returns | Description |
|--------|---------|-------------|
| `input(prompt_text: []const u8)` | `![]u8` | Prompt for user input (plain text) |
| `inputWithOptions(prompt_text, options)` | `![]u8` | Prompt with validation and options |
| `prompt(prompt_markup: []const u8)` | `![]u8` | Prompt with styled markup |
| `promptWithOptions(prompt_markup, options)` | `![]u8` | Prompt with markup and options |

#### Export/Paging

| Method | Returns | Description |
|--------|---------|-------------|
| `exportText(segments, allocator)` | `![]u8` | Extract plain text from segments |
| `exportHtml(segments, allocator)` | `![]u8` | Export segments as HTML |
| `exportSvg(segments, allocator, options)` | `![]u8` | Export segments as SVG |
| `pager()` | `Pager` | Create default pager |
| `pagerWithOptions(options: PagerOptions)` | `Pager` | Create pager with options |
| `printPaged(content: []const u8)` | `!void` | Print content with pagination |
| `printSegmentsPaged(segments)` | `!void` | Print segments with pagination |

#### Capture

| Method | Returns | Description |
|--------|---------|-------------|
| `beginCapture()` | `void` | Start capturing output |
| `endCapture()` | `?[]const u8` | Stop capturing and return buffer |
| `exportCapture()` | `?[]u8` | Get copy of current capture buffer |

#### Example

```zig
const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Basic output
    try console.print("[bold red]Error:[/] Something went wrong");
    try console.printPlain("Plain text");
    try console.rule("Section");

    // Status line
    try console.status("Processing...");
    std.time.sleep(1 * std.time.ns_per_s);
    try console.clearStatus();

    // Logging
    try console.logInfo("Application started", .{});
    try console.logWarn("Disk space low: {d}%", .{15});

    // Input
    const name = try console.input("Enter your name");
    defer allocator.free(name);

    const age_str = try console.inputWithOptions("Enter your age", .{
        .validator = &validateAge,
        .max_length = 3,
    });
    defer allocator.free(age_str);
}

fn validateAge(input: []const u8) rich.Console.InputValidationResult {
    const age = std.fmt.parseInt(u8, input, 10) catch {
        return .{ .invalid = "Must be a number" };
    };
    if (age < 1 or age > 120) {
        return .{ .invalid = "Age must be 1-120" };
    }
    return .valid;
}
```

### ConsoleOptions

[Documented inline above]

---

## Phase 4: Renderables

### Panel

**Module:** `rich_zig.Panel`
**File:** `src/renderables/panel.zig`

#### Overview

Draws a bordered box around content with optional title and subtitle. Supports various box styles, padding, and overflow control.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Panel.fromText(allocator, text: []const u8)` | Create from plain text |
| `Panel.fromStyledText(allocator, txt: Text)` | Create from styled Text |
| `Panel.fromSegments(allocator, segs: []const Segment)` | Create from pre-rendered segments |
| `Panel.fromRendered(allocator, segs: []const Segment)` | Alias for `fromSegments` |
| `Panel.info(allocator, text: []const u8)` | Blue bordered info panel |
| `Panel.warning(allocator, text: []const u8)` | Yellow bordered warning panel with title |
| `Panel.err(allocator, text: []const u8)` | Red bordered error panel with title |
| `Panel.success(allocator, text: []const u8)` | Green bordered success panel with title |

#### Modifier Methods (Fluent API)

| Method | Description |
|--------|-------------|
| `withTitle(title: []const u8)` | Set title (displayed in top border) |
| `withSubtitle(subtitle: []const u8)` | Set subtitle (displayed in bottom border) |
| `withWidth(w: usize)` | Set fixed width |
| `withHeight(h: usize)` | Set fixed height |
| `withVerticalOverflow(v: VOverflow)` | Set overflow behavior (`.clip`, `.visible`, `.ellipsis`) |
| `withPadding(top: u8, right: u8, bottom: u8, left: u8)` | Set internal padding |
| `withBorderStyle(s: Style)` | Set style for border characters |
| `withTitleStyle(s: Style)` | Set style for title |
| `withTitleAlignment(alignment: Alignment)` | Title alignment (`.left`, `.center`, `.right`) |
| `withSubtitleAlignment(alignment: Alignment)` | Subtitle alignment |
| `rounded()` | Use rounded box style |
| `square()` | Use square box style |
| `heavy()` | Use heavy box style |
| `double()` | Use double-line box style |
| `ascii()` | Use ASCII box style |

#### Types

```zig
pub const Alignment = enum { left, center, right };
pub const VOverflow = enum { clip, visible, ellipsis };
```

#### Example

```zig
const Panel = @import("rich_zig").Panel;
const Style = @import("rich_zig").Style;
const Color = @import("rich_zig").Color;

var panel = Panel.fromText(allocator, "Hello, World!")
    .withTitle("Greeting")
    .withSubtitle("Example")
    .withWidth(40)
    .withHeight(10)
    .withPadding(1, 2, 1, 2)
    .withBorderStyle(Style.empty.fg(Color.cyan))
    .withTitleStyle(Style.empty.bold())
    .withTitleAlignment(.left)
    .rounded();

const segments = try panel.render(80, allocator);
defer allocator.free(segments);

try console.printSegments(segments);
```

---

### Table

**Module:** `rich_zig.Table`
**File:** `src/renderables/table.zig`

#### Overview

Flexible table rendering with support for headers, footers, multiple row types, column sizing, cell spanning, and alternating row styles.

#### Construction

```zig
var table = Table.init(allocator);
defer table.deinit();
```

#### Configuration Methods (Fluent API)

| Method | Returns | Description |
|--------|---------|-------------|
| `withTitle(title: []const u8)` | `*Table` | Set table title |
| `withColumn(col: Column)` | `*Table` | Add column with configuration |
| `addColumn(header: []const u8)` | `*Table` | Add column with header only |
| `withBoxStyle(style: BoxStyle)` | `*Table` | Set box drawing style |
| `withHeaderStyle(style: Style)` | `*Table` | Set header row style |
| `withBorderStyle(style: Style)` | `*Table` | Set border color/style |
| `withCaption(caption_text: []const u8)` | `*Table` | Add caption below table |
| `withCaptionStyle(style: Style)` | `*Table` | Set caption text style |
| `withCaptionJustify(justify: JustifyMethod)` | `*Table` | Align caption |
| `withAlternatingStyles(even: Style, odd: Style)` | `*Table` | Set alternating row styles |
| `withRowStyle(row_index: usize, style: Style)` | `*Table` | Override specific row style |
| `withCollapsePadding(collapse: bool)` | `*Table` | Remove cell padding |
| `withFooter(footer_row: []const []const u8)` | `*Table` | Add footer row |
| `withFooterStyle(style: Style)` | `*Table` | Set footer style |

#### Row Methods

| Method | Description |
|--------|-------------|
| `addRow(row: []const []const u8)` | Add plain text row |
| `addRowStyled(row: []const []const u8, style: Style)` | Add row with style |
| `addRowRich(row: []const CellContent)` | Add row with mixed content types |
| `addRowRichStyled(row: []const CellContent, style: Style)` | Add rich row with style |
| `addSpannedRow(row: []const Cell)` | Add row with cell spanning |
| `addSpannedRowStyled(row: []const Cell, style: Style)` | Add spanned row with style |

#### Column Configuration

```zig
pub const Column = struct {
    // ...

    pub fn init(header: []const u8) Column;
    pub fn withJustify(self: Column, j: JustifyMethod) Column;
    pub fn withWidth(self: Column, w: usize) Column;
    pub fn withMinWidth(self: Column, w: usize) Column;
    pub fn withMaxWidth(self: Column, w: usize) Column;
    pub fn withStyle(self: Column, s: Style) Column;
    pub fn withHeaderStyle(self: Column, s: Style) Column;
    pub fn withRatio(self: Column, r: u8) Column; // Proportional width
    pub fn withOverflow(self: Column, o: Overflow) Column;
    pub fn withEllipsis(self: Column, e: []const u8) Column;
    pub fn withNoWrap(self: Column, nw: bool) Column;
};

pub const JustifyMethod = enum { left, center, right };
pub const Overflow = enum { fold, ellipsis, crop };
```

#### Cell Spanning

```zig
pub const Cell = struct {
    // ...

    pub fn text(t: []const u8) Cell;
    pub fn segments(segs: []const Segment) Cell;
    pub fn withColspan(self: Cell, span: u8) Cell;
    pub fn withRowspan(self: Cell, span: u8) Cell;
    pub fn withStyle(self: Cell, s: Style) Cell;
    pub fn withJustify(self: Cell, j: JustifyMethod) Cell;
};
```

#### Example

```zig
const Table = @import("rich_zig").Table;
const Column = @import("rich_zig").Column;
const Cell = @import("rich_zig").Cell;

var table = Table.init(allocator);
defer table.deinit();

// Configure columns
_ = table
    .withColumn(Column.init("Name").withWidth(20))
    .withColumn(Column.init("Status").withJustify(.center))
    .withColumn(Column.init("Progress").withRatio(2))
    .withHeaderStyle(Style.empty.bold().fg(Color.cyan))
    .withAlternatingStyles(Style.empty.dim(), Style.empty);

// Add rows
try table.addRow(&.{ "Server A", "Running", "85%" });
try table.addRow(&.{ "Server B", "Stopped", "0%" });

// Add spanning row
try table.addSpannedRow(&.{
    Cell.text("Summary").withColspan(2).withStyle(Style.empty.bold()),
    Cell.text("42.5%"),
});

const segments = try table.render(80, allocator);
defer allocator.free(segments);

try console.printSegments(segments);
```

---

### Column

[Documented inline with Table above]

### Tree

**Module:** `rich_zig.Tree`
**File:** `src/renderables/tree.zig`

[TODO: Document Tree and TreeNode - hierarchical tree structures]

### TreeNode

[TODO: Document node manipulation and styling]

### Rule

**Module:** `rich_zig.Rule`
**File:** `src/renderables/rule.zig`

[TODO: Document horizontal rules with optional titles]

### ProgressBar

**Module:** `rich_zig.ProgressBar`
**File:** `src/renderables/progress.zig`

[TODO: Document progress bars with customizable styles]

### Spinner

[TODO: Document animated spinners]

### ProgressGroup

[TODO: Document multiple concurrent progress indicators]

### Padding

**Module:** `rich_zig.Padding`
**File:** `src/renderables/padding.zig`

[TODO: Document adding padding around renderables]

### Align

**Module:** `rich_zig.Align`
**File:** `src/renderables/align.zig`

[TODO: Document alignment wrapper for renderables]

### Columns

**Module:** `rich_zig.Columns`
**File:** `src/renderables/columns.zig`

[TODO: Document column layout for multiple renderables]

### Layout

**Module:** `rich_zig.Layout`
**File:** `src/renderables/layout.zig`

[TODO: Document flexible layout system]

### Live

**Module:** `rich_zig.Live`
**File:** `src/renderables/live.zig`

[TODO: Document live-updating displays]

### JSON

**Module:** `rich_zig.JSON`
**File:** `src/renderables/json.zig`

[TODO: Document pretty-printed JSON rendering]

### Syntax

**Module:** `rich_zig.Syntax`
**File:** `src/renderables/syntax.zig`

[TODO: Document syntax highlighting]

### Markdown

**Module:** `rich_zig.Markdown`
**File:** `src/renderables/markdown.zig`

[TODO: Document markdown rendering]

---

## Phase 5: Utilities

### Logging

**Module:** `rich_zig.Console` (methods)
**File:** `src/console.zig`

Documented inline with Console above (see logging section).

### Prompt

**Module:** `rich_zig.Console` (methods)
**File:** `src/console.zig`

Documented inline with Console above (see input/prompts section).

### Emoji

**Module:** `rich_zig.emoji`
**File:** `src/emoji.zig`

[TODO: Document emoji replacement and handling]

---

## Error Types

### Core Errors

**Color Errors:**
```zig
error.InvalidHexColor  // Malformed hex color string
```

**Style Errors:**
```zig
error.UnknownColor         // Color name not recognized
error.UnknownAttribute     // Style attribute not recognized
error.InvalidHexColor      // (propagated from Color)
error.InvalidColorNumber   // Invalid 256-color index
```

**Input Errors:**
```zig
error.ValidationFailed  // Input failed validation
error.InputCancelled    // User cancelled input
error.EndOfStream       // Input stream closed
error.OutOfMemory       // Allocation failed
```

### Standard Zig Errors

Most API functions can return standard Zig errors:
- `error.OutOfMemory` - Allocation failed
- File I/O errors (when applicable)

### Error Handling Pattern

```zig
const result = api_call() catch |err| switch (err) {
    error.OutOfMemory => {
        // Handle allocation failure
        return err;
    },
    error.InvalidHexColor => {
        // Handle specific error
        std.log.warn("Invalid color, using default", .{});
        // Fallback behavior
    },
    else => return err, // Propagate unexpected errors
};
```

---

## Common Patterns

### Allocator Threading

All APIs requiring allocation take an explicit `allocator` parameter. Callers are responsible for cleanup:

```zig
const segments = try renderable.render(max_width, allocator);
defer allocator.free(segments);
```

### Builder Pattern

Most configuration uses fluent chaining:

```zig
const panel = Panel.fromText(allocator, "content")
    .withTitle("Title")
    .withWidth(30)
    .rounded();
```

### Segment Ownership

- Renderables produce owned segment slices
- Caller must free the slice (but not individual segment contents unless explicitly allocated)
- Text within segments is typically borrowed from original input

### Style Combining

Styles combine with later styles overriding earlier ones:

```zig
const base = Style.empty.bold().fg(Color.red);
const overlay = Style.empty.italic().fg(Color.blue);
const result = base.combine(overlay);
// result is: bold, italic, blue foreground
```

---

## Version History

- **v1.0.0**: First stable release
- **v0.10.0**: Current development version

For detailed change history, see CHANGELOG.md.

---

## See Also

- [README.md](../README.md) - Project overview and quick start
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System design and internals
- [EXAMPLES.md](./EXAMPLES.md) - Usage examples and recipes
- [api_and_opt.md](./api_and_opt.md) - API roadmap and optimization plans

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
    pub fn toHsl(self: ColorTriplet) struct { h: f32, s: f32, l: f32 };
    pub fn fromHsl(h: f32, s: f32, l: f32) ColorTriplet;
    pub fn blendHsl(c1: ColorTriplet, c2: ColorTriplet, t: f32) ColorTriplet;
    pub fn luminance(self: ColorTriplet) f64;
    pub fn contrastRatio(self: ColorTriplet, other: ColorTriplet) f64;
    pub fn wcagLevel(self: ColorTriplet, other: ColorTriplet) WcagLevel;
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

### AdaptiveColor

**Module:** `rich_zig.AdaptiveColor`
**File:** `src/color.zig`

#### Overview

Colors that bundle multiple representations (truecolor, 256-color, standard) and resolve to the best match for a given terminal's color system. When a higher-fidelity representation isn't available, falls back gracefully.

#### Construction

| Constructor | Description |
|------------|-------------|
| `AdaptiveColor.init(truecolor, eight_bit, standard)` | Create with explicit fallbacks |
| `AdaptiveColor.fromRgb(r, g, b)` | Create from RGB with auto-computed fallbacks |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `resolve(system: ColorSystem)` | `Color` | Get the best color for the given system |

#### Example

```zig
const rich = @import("rich_zig");

// Explicit fallback chain
const sunset = rich.AdaptiveColor.init(
    rich.Color.fromRgb(255, 100, 50),  // Truecolor
    rich.Color.from256(208),            // 256-color
    rich.Color.yellow,                  // 16-color
);
const resolved = sunset.resolve(.standard); // Returns Color.yellow

// Auto-computed fallbacks from RGB
const sky = rich.AdaptiveColor.fromRgb(0, 180, 255);
const best = sky.resolve(console.colorSystem());
```

---

### HSL Color Operations

**Module:** `rich_zig.ColorTriplet`
**File:** `src/color.zig`

#### Overview

HSL (Hue, Saturation, Lightness) color space operations on `ColorTriplet` for perceptually smooth color blending and manipulation. Uses shortest-arc hue interpolation for natural transitions.

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `toHsl()` | `struct { h, s, l: f32 }` | Convert RGB to HSL (h: 0-360, s/l: 0-1) |
| `fromHsl(h, s, l)` | `ColorTriplet` | Convert HSL back to RGB |
| `blendHsl(c1, c2, t)` | `ColorTriplet` | Blend two colors in HSL space (t: 0.0-1.0) |

#### Example

```zig
const rich = @import("rich_zig");

const red = rich.ColorTriplet{ .r = 255, .g = 0, .b = 0 };
const green = rich.ColorTriplet{ .r = 0, .g = 255, .b = 0 };

// HSL blend produces perceptually smooth transitions
const mid = rich.ColorTriplet.blendHsl(red, green, 0.5);

// Convert to/from HSL
const hsl = red.toHsl(); // h=0, s=1, l=0.5
const back = rich.ColorTriplet.fromHsl(hsl.h, hsl.s, hsl.l);
```

---

### Multi-Stop Gradient

**Module:** `rich_zig.gradient`
**File:** `src/color.zig`

#### Overview

Generates N colors distributed across arbitrary color stops, with support for both RGB and HSL interpolation modes.

#### Function

```zig
pub fn gradient(
    stops: []const ColorTriplet,
    output: []ColorTriplet,
    comptime use_hsl: bool,
) void
```

| Parameter | Description |
|-----------|-------------|
| `stops` | Array of color stops to interpolate between |
| `output` | Output buffer filled with interpolated colors |
| `use_hsl` | `true` for HSL interpolation (smoother), `false` for RGB |

#### Example

```zig
const rich = @import("rich_zig");

const stops = [_]rich.ColorTriplet{
    .{ .r = 255, .g = 0, .b = 0 },   // Red
    .{ .r = 255, .g = 255, .b = 0 }, // Yellow
    .{ .r = 0, .g = 255, .b = 0 },   // Green
    .{ .r = 0, .g = 0, .b = 255 },   // Blue
};

var rainbow: [40]rich.ColorTriplet = undefined;
rich.gradient(&stops, &rainbow, true); // HSL interpolation
```

---

### WCAG Contrast

**Module:** `rich_zig.ColorTriplet`
**File:** `src/color.zig`

#### Overview

WCAG 2.0 contrast ratio calculation and accessibility level checking. Useful for ensuring text/background color pairs meet accessibility standards.

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `luminance()` | `f64` | Relative luminance per sRGB spec (0.0-1.0) |
| `contrastRatio(other)` | `f64` | WCAG contrast ratio (1.0-21.0) |
| `wcagLevel(other)` | `WcagLevel` | Accessibility conformance level |

#### WcagLevel

```zig
pub const WcagLevel = enum { fail, aa_large, aa, aaa };
```

| Level | Minimum Ratio | Use Case |
|-------|--------------|----------|
| `aaa` | 7.0:1 | Enhanced contrast (all text) |
| `aa` | 4.5:1 | Normal text |
| `aa_large` | 3.0:1 | Large text only (18pt+ or 14pt+ bold) |
| `fail` | Below 3.0:1 | Does not meet WCAG requirements |

#### Example

```zig
const white = rich.ColorTriplet{ .r = 255, .g = 255, .b = 255 };
const black = rich.ColorTriplet{ .r = 0, .g = 0, .b = 0 };

const ratio = white.contrastRatio(black);  // 21.0
const level = white.wcagLevel(black);      // .aaa

const gray = rich.ColorTriplet{ .r = 128, .g = 128, .b = 128 };
const level2 = gray.wcagLevel(white);      // .aa (ratio ~3.95:1)
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
const width2 = cells.cellLen("\u{4E2D}\u{6587}"); // 4 (2 CJK chars * 2 cells each)
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

#### Overview

Styled text with span-based formatting. Stores plain text content alongside style spans that define formatting for specific character ranges.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Text.init(allocator)` | Create empty text |
| `Text.fromPlain(allocator, text)` | Create from plain string (borrowed) |
| `Text.fromPlainOwned(allocator, text)` | Create from string (allocator owns copy) |
| `Text.fromMarkup(allocator, text)` | Parse BBCode-like markup syntax |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `deinit()` | `void` | Free owned resources |
| `cellLength()` | `usize` | Display width in terminal cells |
| `len()` | `usize` | Byte length of plain text |
| `isEmpty()` | `bool` | Check if text is empty |
| `render(allocator)` | `![]Segment` | Render to segments |

#### Types

```zig
pub const Span = struct {
    start: usize,
    end: usize,
    style: Style,
};
```

#### Example

```zig
const Text = @import("rich_zig").Text;

// Parse markup
var text = try Text.fromMarkup(allocator, "[bold red]Hello[/] [italic]World[/]!");
defer text.deinit();

// Render to segments
const segments = try text.render(allocator);
defer allocator.free(segments);

// Measure
const width = text.cellLength(); // 12
```

---

### Markup

**Module:** `rich_zig.markup`
**File:** `src/markup.zig`

#### Overview

BBCode-like markup parser for inline text styling. Supports nested tags, escaped brackets, and tag parameters.

#### Syntax

- **Open tag**: `[bold]`, `[red]`, `[bold red on white]`
- **Close tag**: `[/]` (closes any) or `[/bold]` (specific)
- **Escaped brackets**: `\[` and `\]`
- **Parameters**: `[link=https://example.com]text[/link]`

#### Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `parseMarkup(text, allocator)` | `![]MarkupToken` | Parse markup into tokens |
| `render(text, base_style, allocator)` | `![]Segment` | Parse and render to segments |
| `escape(text, allocator)` | `![]u8` | Escape brackets in text |

#### Types

```zig
pub const MarkupToken = union(enum) {
    text: []const u8,
    open_tag: Tag,
    close_tag: ?[]const u8, // null means [/]
};

pub const Tag = struct {
    name: []const u8,
    parameters: ?[]const u8 = null,
};
```

#### Example

```zig
const markup = @import("rich_zig").markup;

// Render styled text
const segments = try markup.render("[bold]Hello[/] [red]World[/]", Style.empty, allocator);
defer allocator.free(segments);

// Escape user input
const escaped = try markup.escape("Use [brackets] safely", allocator);
defer allocator.free(escaped);
// Result: "Use \\[brackets\\] safely"
```

---

### BoxStyle

**Module:** `rich_zig.BoxStyle`
**File:** `src/box.zig`

#### Overview

Defines box drawing characters for borders on panels, tables, and other bordered content. Provides predefined styles and supports custom character sets.

#### Predefined Styles

| Style | Description | Characters |
|-------|-------------|------------|
| `BoxStyle.rounded` | Rounded corners | Curved Unicode corners |
| `BoxStyle.square` | Square corners | Standard box drawing |
| `BoxStyle.heavy` | Heavy/thick lines | Bold box drawing |
| `BoxStyle.double` | Double lines | Double-line box drawing |
| `BoxStyle.ascii` | ASCII only | `+`, `-`, `|` |
| `BoxStyle.minimal` | Lines only | No corners, horizontal lines |
| `BoxStyle.simple` | Very minimal | Space corners |

#### Custom Boxes

```zig
pub const CustomChars = struct {
    top_left: []const u8 = "+",
    top_right: []const u8 = "+",
    bottom_left: []const u8 = "+",
    bottom_right: []const u8 = "+",
    horizontal: []const u8 = "-",
    vertical: []const u8 = "|",
    left: []const u8 = "|",
    right: []const u8 = "|",
    cross: []const u8 = "+",
    top_tee: []const u8 = "+",
    bottom_tee: []const u8 = "+",
    left_tee: []const u8 = "+",
    right_tee: []const u8 = "+",
};

pub fn custom(chars: CustomChars) BoxStyle;
```

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getHorizontal(width, allocator)` | `![]u8` | Generate horizontal line of given width |

#### Example

```zig
const BoxStyle = @import("rich_zig").BoxStyle;

// Use predefined style
const panel = Panel.fromText(allocator, "content").rounded();

// Custom box style
const custom = BoxStyle.custom(.{
    .top_left = "*",
    .top_right = "*",
    .horizontal = "=",
    .vertical = "!",
});
```

---

## Phase 3: Terminal & Console

### Terminal

**Module:** `rich_zig.terminal`
**File:** `src/terminal.zig`

#### Overview

Detects terminal capabilities including size, color support, TTY status, and Unicode support. Cross-platform support for POSIX and Windows.

#### Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `detect()` | `TerminalInfo` | Detect terminal capabilities |
| `enableVirtualTerminal()` | `bool` | Enable ANSI on Windows |
| `enableUtf8()` | `bool` | Enable UTF-8 on Windows |

#### Types

```zig
pub const TerminalInfo = struct {
    width: u16 = 80,
    height: u16 = 24,
    color_system: ColorSystem = .standard,
    is_tty: bool = false,
    supports_unicode: bool = true,
    supports_hyperlinks: bool = false,
    term: ?[]const u8 = null,
    term_program: ?[]const u8 = null,
    supports_sync_output: bool = false,
    background_mode: BackgroundMode = .unknown,
};
```

#### BackgroundMode

```zig
pub const BackgroundMode = enum { dark, light, unknown };
```

Terminal background detection based on environment heuristics (COLORFGBG, TERM_PROGRAM). Useful for choosing light-on-dark vs dark-on-light color schemes.

#### Synchronized Output

```zig
pub const sync_output_begin: []const u8 = "\x1b[?2026h";
pub const sync_output_end: []const u8 = "\x1b[?2026l";

pub fn beginSyncOutput(writer: anytype) !void;
pub fn endSyncOutput(writer: anytype) !void;
```

DEC private mode 2026 for atomic frame rendering. Console uses this opportunistically on TTY output to prevent screen tearing during multi-segment writes. Terminals that don't support it safely ignore the sequences.

#### Environment Variables

- `NO_COLOR`: Disables color output
- `FORCE_COLOR`: Forces color output even when not a TTY
- `TERM`: Terminal type (used for capability detection)
- `TERM_PROGRAM`: Terminal program name
- `COLORTERM`: Color capability hint

#### Example

```zig
const terminal = @import("rich_zig").terminal;

const info = terminal.detect();
std.debug.print("Terminal: {d}x{d}\n", .{ info.width, info.height });
std.debug.print("Color: {s}\n", .{ @tagName(info.color_system) });
std.debug.print("TTY: {}\n", .{ info.is_tty });
```

---

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
| `printRenderable(renderable: anytype)` | Render and print any renderable type |
| `rule(title_opt: ?[]const u8)` | Print horizontal rule with optional title |
| `clear()` | Clear screen |
| `bell()` | Emit terminal bell |

> **Note:** `printSegments` automatically wraps output with synchronized output sequences (DEC mode 2026) when writing to a TTY. This prevents screen tearing during multi-line renders. Non-TTY output (pipes, files) is unaffected.

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

    // Renderable output
    const panel = rich.Panel.fromText(allocator, "Content").withTitle("Title");
    try console.printRenderable(panel);

    // Logging
    try console.logInfo("Application started", .{});
    try console.logWarn("Disk space low: {d}%", .{15});
}
```

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

#### Example

```zig
const Panel = @import("rich_zig").Panel;

const panel = Panel.fromText(allocator, "Hello, World!")
    .withTitle("Greeting")
    .withWidth(40)
    .withBorderStyle(Style.empty.fg(Color.cyan))
    .rounded();

try console.printRenderable(panel);
```

---

### Table

**Module:** `rich_zig.Table`
**File:** `src/renderables/table/table.zig`

#### Overview

Flexible table rendering with support for headers, footers, multiple row types, column sizing, cell spanning, and alternating row styles.

Table uses pointer returns (`*Table`) for configuration methods because it owns allocated collections (columns, rows). This differs from Panel/Rule which use value returns for borrowed content.

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
| `withAlternatingStyles(even: Style, odd: Style)` | `*Table` | Set alternating row styles |
| `withFooter(footer_row: []const []const u8)` | `*Table` | Add footer row |

#### Row Methods

| Method | Description |
|--------|-------------|
| `addRow(row: []const []const u8)` | Add plain text row |
| `addRowStyled(row: []const []const u8, style: Style)` | Add row with style |
| `addSpannedRow(row: []const Cell)` | Add row with cell spanning |

#### Column Configuration

```zig
pub const Column = struct {
    pub fn init(header: []const u8) Column;
    pub fn withJustify(self: Column, j: JustifyMethod) Column;
    pub fn withWidth(self: Column, w: usize) Column;
    pub fn withMinWidth(self: Column, w: usize) Column;
    pub fn withMaxWidth(self: Column, w: usize) Column;
    pub fn withStyle(self: Column, s: Style) Column;
    pub fn withRatio(self: Column, r: u8) Column;
};

pub const JustifyMethod = enum { left, center, right };
```

#### Cell Spanning

```zig
pub const Cell = struct {
    pub fn text(t: []const u8) Cell;
    pub fn withColspan(self: Cell, span: u8) Cell;
    pub fn withRowspan(self: Cell, span: u8) Cell;
    pub fn withStyle(self: Cell, s: Style) Cell;
};
```

#### Example

```zig
const Table = @import("rich_zig").Table;
const Cell = @import("rich_zig").Cell;

var table = Table.init(allocator);
defer table.deinit();

_ = table.addColumn("Name").addColumn("Status").addColumn("Progress");
_ = table.withAlternatingStyles(Style.empty, Style.empty.dim());

try table.addRow(&.{ "Server A", "Running", "85%" });
try table.addRow(&.{ "Server B", "Stopped", "0%" });

// Spanning row
try table.addSpannedRow(&.{
    Cell.text("Summary").withColspan(2).withStyle(Style.empty.bold()),
    Cell.text("42.5%"),
});

try console.printRenderable(table);
```

---

### Tree

**Module:** `rich_zig.Tree`
**File:** `src/renderables/tree.zig`

#### Overview

Renders hierarchical tree structures with customizable guide characters and node styling.

#### TreeNode

| Constructor | Description |
|------------|-------------|
| `TreeNode.init(allocator, label)` | Create node with text label |
| `TreeNode.initWithSegments(allocator, segments)` | Create node with styled segments |

| Method | Returns | Description |
|--------|---------|-------------|
| `deinit()` | `void` | Free node and all children |
| `addChild(child: TreeNode)` | `!void` | Add existing node as child |
| `addChildLabel(label: []const u8)` | `!*TreeNode` | Add new child by label, returns pointer |
| `withStyle(style: Style)` | `TreeNode` | Set node style |
| `withGuideStyle(style: Style)` | `TreeNode` | Set guide line style |
| `collapsed()` | `TreeNode` | Set node as collapsed |

#### Tree

| Constructor | Description |
|------------|-------------|
| `Tree.init(root: TreeNode)` | Create tree from root node |

| Method | Returns | Description |
|--------|---------|-------------|
| `withGuide(guide: TreeGuide)` | `Tree` | Set guide characters |
| `hideRoot()` | `Tree` | Hide root node, show only children |

#### TreeGuide

```zig
pub const TreeGuide = struct {
    vertical: []const u8 = "|",
    horizontal: []const u8 = "--",
    corner: []const u8 = "`-",
    tee: []const u8 = "+-",
    space: []const u8 = "   ",
};
```

#### Example

```zig
const Tree = @import("rich_zig").Tree;
const TreeNode = @import("rich_zig").TreeNode;

var root = TreeNode.init(allocator, "project");
defer root.deinit();

const src = try root.addChildLabel("src");
_ = try src.addChildLabel("main.zig");
_ = try src.addChildLabel("lib.zig");
_ = try root.addChildLabel("build.zig");

const tree = Tree.init(root);
try console.printRenderable(tree);
```

---

### Rule

**Module:** `rich_zig.Rule`
**File:** `src/renderables/rule.zig`

#### Overview

Horizontal line/divider with optional centered, left, or right-aligned title.

#### Construction

```zig
const rule = Rule.init();
```

#### Modifier Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withTitle(title: []const u8)` | `Rule` | Set title text |
| `withStyle(style: Style)` | `Rule` | Set line style |
| `withTitleStyle(style: Style)` | `Rule` | Set title style |
| `withCharacters(chars: []const u8)` | `Rule` | Set line character(s) |
| `alignLeft()` | `Rule` | Left-align title |
| `alignCenter()` | `Rule` | Center title (default) |
| `alignRight()` | `Rule` | Right-align title |

#### Example

```zig
const Rule = @import("rich_zig").Rule;

const rule = Rule.init()
    .withTitle("Section")
    .withStyle(Style.empty.fg(Color.cyan))
    .alignLeft();

try console.printRenderable(rule);
```

---

### ProgressBar

**Module:** `rich_zig.ProgressBar`
**File:** `src/renderables/progress/bar.zig`

#### Overview

Single progress bar with customizable appearance, timing info, and indeterminate mode.

#### Construction

```zig
const bar = ProgressBar.init();
```

#### Modifier Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withCompleted(n: usize)` | `ProgressBar` | Set completed count |
| `withTotal(n: usize)` | `ProgressBar` | Set total count |
| `withWidth(w: usize)` | `ProgressBar` | Set bar width |
| `withDescription(text: []const u8)` | `ProgressBar` | Set description text |
| `withCompleteStyle(style: Style)` | `ProgressBar` | Set completed portion style |
| `withIncompleteStyle(style: Style)` | `ProgressBar` | Set incomplete portion style |
| `withTiming()` | `ProgressBar` | Enable elapsed/ETA display |
| `withElapsed()` | `ProgressBar` | Enable elapsed time display |
| `withEta()` | `ProgressBar` | Enable ETA display |
| `withSpeed()` | `ProgressBar` | Enable speed display |
| `asIndeterminate()` | `ProgressBar` | Set indeterminate mode |
| `withTransient(bool)` | `ProgressBar` | Hide when complete |

#### State Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `percentage()` | `f64` | Get completion percentage |
| `isFinished()` | `bool` | Check if completed >= total |
| `advance(amount: usize)` | `void` | Increment completed |
| `advancePulse()` | `void` | Advance indeterminate animation |
| `reset()` | `void` | Reset to zero |

#### Example

```zig
const ProgressBar = @import("rich_zig").ProgressBar;

const bar = ProgressBar.init()
    .withDescription("Downloading")
    .withCompleted(75)
    .withTotal(100)
    .withWidth(30)
    .withTiming();

const segments = try bar.render(80, allocator);
defer allocator.free(segments);
try console.printSegments(segments);
```

---

### Spinner

**Module:** `rich_zig.Spinner`
**File:** `src/renderables/progress/spinner.zig`

#### Overview

Animated spinner indicator for operations with unknown duration.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Spinner.init()` | Default braille spinner |
| `Spinner.dots()` | Dots animation |
| `Spinner.line()` | ASCII line spinner (`-\|/`) |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withStyle(style: Style)` | `Spinner` | Set spinner style |
| `advance()` | `void` | Move to next frame |
| `render(allocator)` | `![]Segment` | Render current frame |

#### Example

```zig
const Spinner = @import("rich_zig").Spinner;

var spinner = Spinner.init().withStyle(Style.empty.fg(Color.cyan));

// Animation loop
while (!done) {
    const segments = try spinner.render(allocator);
    defer allocator.free(segments);
    try console.printSegments(segments);
    spinner.advance();
    std.time.sleep(100 * std.time.ns_per_ms);
}
```

---

### ProgressGroup

**Module:** `rich_zig.ProgressGroup`
**File:** `src/renderables/progress/group.zig`

#### Overview

Multiple concurrent progress bars displayed together.

#### Construction

```zig
var group = ProgressGroup.init(allocator);
defer group.deinit();
```

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `addTask(description, total)` | `!*ProgressBar` | Add new progress bar |
| `addTaskWithTiming(description, total)` | `!*ProgressBar` | Add bar with timing enabled |
| `addBar(bar: ProgressBar)` | `!*ProgressBar` | Add configured bar |
| `allFinished()` | `bool` | Check if all bars complete |
| `visibleCount()` | `usize` | Count of non-hidden bars |

#### Example

```zig
const ProgressGroup = @import("rich_zig").ProgressGroup;

var group = ProgressGroup.init(allocator);
defer group.deinit();

const dl = try group.addTask("Download", 100);
const extract = try group.addTask("Extract", 100);

// Update progress
dl.completed = 75;
extract.completed = 30;

try console.printRenderable(group);
```

---

### Padding

**Module:** `rich_zig.Padding`
**File:** `src/renderables/padding.zig`

#### Overview

Wraps content with configurable padding on all sides.

#### Construction

```zig
const padding = Padding.init(content_segments);
```

#### Modifier Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `uniform(n: u8)` | `Padding` | Set equal padding all sides |
| `horizontal(n: u8)` | `Padding` | Set left and right padding |
| `vertical(n: u8)` | `Padding` | Set top and bottom padding |
| `withPadding(top, right, bottom, left)` | `Padding` | Set individual padding |
| `withStyle(style: Style)` | `Padding` | Set background style |

#### Example

```zig
const Padding = @import("rich_zig").Padding;

const content = [_]Segment{Segment.plain("Content")};
const padded = Padding.init(&content)
    .uniform(2)
    .withStyle(Style.empty.bg(Color.blue));

try console.printRenderable(padded);
```

---

### Align

**Module:** `rich_zig.Align`
**File:** `src/renderables/align.zig`

#### Overview

Aligns content horizontally and/or vertically within a specified area.

#### Construction

```zig
const aligned = Align.init(content_segments);
```

#### Modifier Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `left()` | `Align` | Left horizontal alignment |
| `center()` | `Align` | Center horizontal alignment |
| `right()` | `Align` | Right horizontal alignment |
| `top()` | `Align` | Top vertical alignment |
| `middle()` | `Align` | Middle vertical alignment |
| `bottom()` | `Align` | Bottom vertical alignment |
| `withWidth(w: usize)` | `Align` | Set target width |
| `withHeight(h: usize)` | `Align` | Set target height |
| `withPadStyle(style: Style)` | `Align` | Set padding fill style |

#### Example

```zig
const Align = @import("rich_zig").Align;

const content = [_]Segment{Segment.plain("Centered")};
const aligned = Align.init(&content)
    .center()
    .withWidth(40);

try console.printRenderable(aligned);
```

---

### Columns

**Module:** `rich_zig.Columns`
**File:** `src/renderables/columns.zig`

#### Overview

Arranges multiple items in a column layout, like a multi-column newspaper.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Columns.init(allocator, items)` | Create from segment arrays |
| `Columns.fromText(allocator, texts)` | Create from text strings |

#### Modifier Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withColumnCount(count: usize)` | `Columns` | Set number of columns |
| `withPadding(gap: u8)` | `Columns` | Set gap between columns |
| `withEqualWidth(equal: bool)` | `Columns` | Force equal column widths |
| `withExpand(exp: bool)` | `Columns` | Expand to fill width |
| `withMinWidth(w: usize)` | `Columns` | Set minimum column width |
| `withMaxWidth(w: usize)` | `Columns` | Set maximum column width |
| `left()`, `center()`, `right()` | `Columns` | Set content alignment |

#### Example

```zig
const Columns = @import("rich_zig").Columns;

const texts = [_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4" };
const columns = (try Columns.fromText(allocator, &texts))
    .withColumnCount(2)
    .withEqualWidth(true)
    .withPadding(4);

try console.printRenderable(columns);
```

---

### Split (Layout)

**Module:** `rich_zig.Split`
**File:** `src/renderables/layout.zig`

#### Overview

Divides space into regions with horizontal or vertical splits. Supports ratio-based, fixed, and minimum size constraints.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Split.horizontal(allocator)` | Create horizontal split (side-by-side) |
| `Split.vertical(allocator)` | Create vertical split (stacked) |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `deinit()` | `void` | Free resources |
| `add(content: []const Segment)` | `*Split` | Add region with auto size |
| `addNamed(name, content)` | `*Split` | Add named region |
| `addWithRatio(content, ratio)` | `*Split` | Add region with ratio |
| `addWithMinSize(content, min)` | `*Split` | Add region with minimum size |
| `addWithFixedSize(content, size)` | `*Split` | Add region with fixed size |
| `addSplit(nested: *Split)` | `*Split` | Add nested split |
| `withSplitter()` | `Split` | Show separator between regions |

#### Example

```zig
const Split = @import("rich_zig").Split;

var split = Split.horizontal(allocator);
defer split.deinit();

const left = [_]Segment{Segment.plain("Left")};
const right = [_]Segment{Segment.plain("Right")};

_ = split.addWithRatio(&left, 1).addWithRatio(&right, 2);

try console.printRenderable(split);
```

---

### Live

**Module:** `rich_zig.Live`
**File:** `src/renderables/live.zig`

#### Overview

Live-updating display that refreshes content in place. Useful for progress indicators, dashboards, and real-time updates.

#### Construction

```zig
var live = Live.init(&console);
```

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withRefreshRate(ms: u64)` | `Live` | Set minimum refresh interval |
| `withOverflow(mode: OverflowMode)` | `Live` | Set overflow behavior |
| `withMaxLines(lines: ?usize)` | `Live` | Set maximum display lines |
| `start()` | `!void` | Begin live display (hides cursor) |
| `stop()` | `!void` | End live display (shows cursor) |
| `update(segments: []const Segment)` | `!void` | Update displayed content |
| `forceUpdate(segments)` | `!void` | Update ignoring rate limit |
| `setContent(segments)` | `void` | Set content for auto-refresh |
| `startAutoRefresh(allocator)` | `!void` | Begin background refresh |
| `stopAutoRefresh()` | `void` | Stop background refresh |

#### Example

```zig
const Live = @import("rich_zig").Live;

var live = Live.init(&console).withRefreshRate(100);
try live.start();
defer live.stop() catch {};

while (!done) {
    const segments = try renderable.render(80, allocator);
    defer allocator.free(segments);
    try live.update(segments);
    std.time.sleep(100 * std.time.ns_per_ms);
}
```

---

### Json

**Module:** `rich_zig.Json`
**File:** `src/renderables/json.zig`

#### Overview

Pretty-prints JSON data with syntax highlighting and configurable formatting.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Json.init(allocator, value)` | Create from std.json.Value |
| `Json.fromString(allocator, json_str)` | Parse and create from string |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `deinit()` | `void` | Free parsed JSON if owned |
| `withTheme(theme: JsonTheme)` | `Json` | Set color theme |
| `withIndent(spaces: u8)` | `Json` | Set indentation width |
| `withSortKeys(sort: bool)` | `Json` | Sort object keys |
| `withMaxDepth(depth: ?usize)` | `Json` | Limit nesting depth |
| `withMaxStringLength(len: ?usize)` | `Json` | Truncate long strings |

#### JsonTheme

```zig
pub const JsonTheme = struct {
    key_style: Style,
    string_style: Style,
    number_style: Style,
    bool_style: Style,
    null_style: Style,
    bracket_style: Style,

    pub const default: JsonTheme;
    pub const monokai: JsonTheme;
};
```

#### Example

```zig
const Json = @import("rich_zig").Json;

var json = try Json.fromString(allocator,
    \\{"name": "rich_zig", "version": "1.0.0"}
);
defer json.deinit();

const styled = json.withIndent(4).withTheme(JsonTheme.monokai);
try console.printRenderable(styled);
```

---

### Syntax

**Module:** `rich_zig.Syntax`
**File:** `src/renderables/syntax/highlighter.zig`

#### Overview

Syntax highlighting for source code with language detection, line numbers, and theming.

#### Construction

| Constructor | Description |
|------------|-------------|
| `Syntax.init(allocator, code)` | Create from code string |
| `Syntax.fromFile(allocator, code, filename)` | Auto-detect language from filename |
| `Syntax.loadFile(allocator, path)` | Load and highlight file from disk |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `deinit()` | `void` | Free loaded file content |
| `withLanguage(lang: Language)` | `Syntax` | Set language explicitly |
| `withAutoDetect(filename: ?[]const u8)` | `Syntax` | Auto-detect language |
| `withTheme(theme: SyntaxTheme)` | `Syntax` | Set color theme |
| `withLineNumbers()` | `Syntax` | Show line numbers |
| `withStartLine(line: usize)` | `Syntax` | Set starting line number |
| `withWordWrap()` | `Syntax` | Enable word wrapping |
| `withTabSize(size: u8)` | `Syntax` | Set tab expansion width |
| `withIndentGuides()` | `Syntax` | Show indent guides |
| `withHighlightLines(lines: []const usize)` | `Syntax` | Highlight specific lines |

#### Supported Languages

```zig
pub const Language = enum {
    plain, zig, rust, python, javascript, typescript,
    c, cpp, java, go, ruby, bash, json, yaml, toml,
    html, css, sql, markdown,

    pub fn fromExtension(ext: []const u8) Language;
    pub fn detect(filename: ?[]const u8, content: []const u8) Language;
};
```

#### Example

```zig
const Syntax = @import("rich_zig").Syntax;

const code =
    \\const std = @import("std");
    \\pub fn main() void {
    \\    std.debug.print("Hello!\n", .{});
    \\}
;

const syntax = Syntax.init(allocator, code)
    .withLanguage(.zig)
    .withLineNumbers()
    .withTheme(SyntaxTheme.monokai);

try console.printRenderable(syntax);
```

---

### Markdown

**Module:** `rich_zig.Markdown`
**File:** `src/renderables/markdown/markdown.zig`

#### Overview

Renders Markdown to styled terminal output with support for headers, lists, code blocks, tables, and inline formatting.

#### Construction

```zig
const md = Markdown.init(source_text);
```

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `withTheme(theme: MarkdownTheme)` | `Markdown` | Set styling theme |

#### Supported Syntax

- **Headers**: `# H1`, `## H2`, `### H3`, etc.
- **Bold**: `**text**` or `__text__`
- **Italic**: `*text*` or `_text_`
- **Strikethrough**: `~~text~~`
- **Inline code**: `` `code` ``
- **Code blocks**: Fenced with ``` (language optional)
- **Links**: `[text](url)`
- **Images**: `![alt](url)` (shows alt text)
- **Lists**: Unordered (`-`, `*`) and ordered (`1.`)
- **Task lists**: `- [x]` and `- [ ]`
- **Blockquotes**: `> text`
- **Horizontal rules**: `---`, `***`, `___`
- **Tables**: GFM table syntax

#### Example

```zig
const Markdown = @import("rich_zig").Markdown;

const md = Markdown.init(
    \\# Title
    \\
    \\This has **bold** and *italic* text.
    \\
    \\```zig
    \\const x = 42;
    \\```
);

try console.printRenderable(md);
```

---

## Phase 5: Utilities

### Emoji

**Module:** `rich_zig.emoji`
**File:** `src/emoji.zig`

#### Overview

Maps emoji shortcodes to Unicode emoji characters. Use `:emoji_name:` syntax in markup.

#### Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `emoji_map.get(name)` | `?[]const u8` | Look up emoji by name |

#### Common Shortcodes

| Shortcode | Emoji | Shortcode | Emoji |
|-----------|-------|-----------|-------|
| `smile` | :smile: | `check` | :heavy_check_mark: |
| `thumbsup` | :+1: | `x` | :x: |
| `rocket` | :rocket: | `fire` | :fire: |
| `star` | :star: | `warning` | :warning: |
| `heart` | :heart: | `sparkles` | :sparkles: |

#### Example

```zig
const emoji = @import("rich_zig").emoji;

if (emoji.emoji_map.get("rocket")) |rocket| {
    std.debug.print("{s} Launch!\n", .{rocket});
}

// In markup
try console.print(":rocket: Launch!");
```

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

- **v1.4.1**: Documentation updates, opportunistic sync output on TTY
- **v1.4.0**: AdaptiveColor, HSL blending, multi-stop gradients, WCAG contrast, synchronized output, background detection
- **v1.3.0**: Markdown rendering, syntax highlighting, JSON pretty-printing
- **v1.0.0**: First stable release

For detailed change history, see CHANGELOG.md.

---

## See Also

- [README.md](../README.md) - Project overview and quick start
- [quickstart.md](./guide/quickstart.md) - Getting started guide
- [examples/](../examples/) - Working example code

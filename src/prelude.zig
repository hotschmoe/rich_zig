const color_mod = @import("color.zig");
const style_mod = @import("style.zig");
const text_mod = @import("text.zig");
const box_mod = @import("box.zig");
const console_mod = @import("console.zig");
const renderables_mod = @import("renderables/mod.zig");
const measure_mod = @import("measure.zig");
const theme_mod = @import("theme.zig");
const pretty_mod = @import("pretty.zig");
const highlighter_mod = @import("highlighter.zig");
const ansi_mod = @import("ansi.zig");

pub const Color = color_mod.Color;
pub const ColorType = color_mod.ColorType;
pub const ColorTriplet = color_mod.ColorTriplet;
pub const Style = style_mod.Style;
pub const Text = text_mod.Text;
pub const Span = text_mod.Span;
pub const Measurement = measure_mod.Measurement;
pub const Theme = theme_mod.Theme;
pub const Pretty = pretty_mod.Pretty;
pub const Highlighter = highlighter_mod.Highlighter;

pub const fromAnsi = ansi_mod.fromAnsi;
pub const stripAnsi = ansi_mod.stripAnsi;

pub const Console = console_mod.Console;
pub const ConsoleOptions = console_mod.ConsoleOptions;

pub const box = box_mod;
pub const BoxStyle = box_mod.BoxStyle;

pub const Panel = renderables_mod.Panel;
pub const Table = renderables_mod.Table;
pub const Column = renderables_mod.Column;
pub const Tree = renderables_mod.Tree;
pub const TreeNode = renderables_mod.TreeNode;
pub const Rule = renderables_mod.Rule;
pub const Padding = renderables_mod.Padding;
pub const Align = renderables_mod.Align;
pub const Columns = renderables_mod.Columns;
pub const Live = renderables_mod.Live;
pub const Json = renderables_mod.Json;
pub const Syntax = renderables_mod.Syntax;
pub const Markdown = renderables_mod.Markdown;

pub const Progress = struct {
    pub const Bar = renderables_mod.ProgressBar;
    pub const Group = renderables_mod.ProgressGroup;
    pub const Display = renderables_mod.ProgressDisplay;
    pub const Spinner = renderables_mod.Spinner;
    pub const SpeedUnit = renderables_mod.SpeedUnit;
};

pub const Alignment = renderables_mod.Alignment;
pub const HAlign = renderables_mod.HAlign;
pub const VAlign = renderables_mod.VAlign;
pub const JustifyMethod = renderables_mod.JustifyMethod;
pub const Overflow = renderables_mod.Overflow;

pub const bold = Style.empty.bold();
pub const italic = Style.empty.italic();
pub const dim = Style.empty.dim();
pub const underline = Style.empty.underline();
pub const strikethrough = Style.empty.strikethrough();
pub const reverse = Style.empty.reverse();
pub const blink = Style.empty.blink();
pub const hidden = Style.empty.hidden();

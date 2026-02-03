const std = @import("std");
const rich = @import("rich_zig");

const Color = rich.Color;
const Style = rich.Style;
const Panel = rich.Panel;
const Table = rich.Table;
const Text = rich.Text;
const BoxStyle = rich.BoxStyle;
const Column = rich.Column;

// Theme Colors (Solarized-ish light theme)
const C_BG_HEX = "#FDF6E3"; // Base3
const C_FG_HEX = "#657B83"; // Base00
const C_STRONG_HEX = "#002B36"; // Base03
const C_ACCENT_HEX = "#268BD2"; // Blue
const C_FOOTER_BG = "#002B36"; // Base03
const C_FOOTER_FG = "#93A1A1"; // Base1
const C_DIM_HEX = "#93A1A1"; // Base1

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // We use an arena for all example allocations to simplify cleanup
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const result_allocator = arena.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();
    const width = console.width();

    // -- STYLES --
    const strong_color = try Color.fromHex(C_STRONG_HEX);
    const footer_bg = try Color.fromHex(C_FOOTER_BG);
    const footer_fg = try Color.fromHex(C_FOOTER_FG);

    // Default text style for the "page"
    // Note: Terminals usually control the main background, but we can style our components.
    // const page_style = Style.empty.fg(fg_color);

    // Custom Dashed Box Style for "encode()"
    const dashed_box = BoxStyle.custom(.{
        .top_left = "┌",
        .top_right = "┐",
        .bottom_left = "└",
        .bottom_right = "┘",
        .horizontal = "╌",
        .vertical = "╎",
    });

    // -- HEADER SECTION --
    // We use a 2-column table to layout the Title (Left) and Logo (Right)
    var header = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true)
        .withExpand(true);

    _ = header.withColumn(Column.init("").withRatio(8)); // Title takes most space
    _ = header.withColumn(Column.init("").withWidth(10).withJustify(.right)); // Logo

    // Styled Title
    const title_txt = try Text.fromMarkup(result_allocator, "[bold " ++ C_STRONG_HEX ++ "]Token-Oriented Object Notation[/]");

    // Logo "TO\nON"
    // We render this as a mini-table or just text with newline
    const logo_markup = "[bold " ++ C_STRONG_HEX ++ "]TO\nON[/][bold " ++ C_ACCENT_HEX ++ "]▀[/]";
    const logo_txt = try Text.fromMarkup(result_allocator, logo_markup);

    try header.addRowRich(&.{ .{ .styled_text = title_txt }, .{ .styled_text = logo_txt } });

    // -- SEPARATOR --
    // A rule with a special style to mimic the line
    const sep_style = Style.empty.fg(strong_color);
    const rule = rich.Rule.init().withStyle(sep_style);

    // -- SUBTITLE --
    const subtitle = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]Compact, human-readable serialization of JSON data for LLM prompts[/]\n");

    // -- WORKFLOW DIAGRAM --
    // Row 1: "Workflow:  [JSON] -> [encode()] -> [TOON] -> LLM"
    // We use a table to align these elements perfectly.
    var flow_grid = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true);

    // Define columns for each element
    _ = flow_grid.addColumn(""); // Label "Workflow:"
    _ = flow_grid.addColumn(""); // [JSON]
    _ = flow_grid.addColumn(""); // ->
    _ = flow_grid.addColumn(""); // [encode()]
    _ = flow_grid.addColumn(""); // ->
    _ = flow_grid.addColumn(""); // [TOON]
    _ = flow_grid.addColumn(""); // ->
    _ = flow_grid.addColumn(""); // LLM

    // Create Components
    const lbl_flow = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]Workflow:     [/]");

    // JSON Box
    const txt_json = try Text.fromMarkup(result_allocator, " [" ++ C_STRONG_HEX ++ "]JSON[/] ");
    const p_json = Panel.fromStyledText(result_allocator, txt_json)
        .withWidth(8) // Fixed width
        .square()
        .withBorderStyle(Style.empty.fg(strong_color));

    // Arrow
    const arrow = try Text.fromMarkup(result_allocator, " ──→ ");

    // encode() Box (Dashed + Italic)
    const txt_enc = try Text.fromMarkup(result_allocator, "[italic " ++ C_DIM_HEX ++ "] encode() [/]");
    var p_enc = Panel.fromStyledText(result_allocator, txt_enc)
        .withWidth(12)
        .withBorderStyle(Style.empty.fg(try Color.fromHex(C_DIM_HEX)));
    p_enc.box_style = dashed_box; // Manual override

    // TOON Box
    const txt_toon = try Text.fromMarkup(result_allocator, " [" ++ C_STRONG_HEX ++ "]TOON[/] ");
    const p_toon = Panel.fromStyledText(result_allocator, txt_toon)
        .withWidth(8)
        .square()
        .withBorderStyle(Style.empty.fg(strong_color));

    // LLM Block
    // We simulate the solid block with reverse video
    const txt_llm = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "] LLM [/][bold " ++ C_STRONG_HEX ++ "]_ [/]");

    // Add elements to grid
    // Note: Table needs CellContent. We must render Panels to Segments first.
    // For simplicity, we just pass the text representation for simple items,
    // but for Panels we need to render them.

    // Helper to render panel to segments
    const segs_json = try p_json.render(8, result_allocator);
    const segs_enc = try p_enc.render(12, result_allocator);
    const segs_toon = try p_toon.render(8, result_allocator);

    try flow_grid.addRowRich(&.{ .{ .styled_text = lbl_flow }, .{ .segments = segs_json }, .{ .styled_text = arrow }, .{ .segments = segs_enc }, .{ .styled_text = arrow }, .{ .segments = segs_toon }, .{ .styled_text = arrow }, .{ .styled_text = txt_llm } });

    // -- TOKENS STATS --
    // Row 2: "ø Tokens: [======] ----> [===] ///  30-60% less"
    // We'll reuse the grid structure or make a new one.

    var token_grid = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true);

    _ = token_grid.addColumn(""); // Label
    _ = token_grid.addColumn(""); // Bar 1
    _ = token_grid.addColumn(""); // Arrow
    _ = token_grid.addColumn(""); // Bar 2
    _ = token_grid.addColumn(""); // Label 2

    const lbl_tok = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]ø Tokens:     [/]");

    // Bar 1: Solid Dark Blue
    // We use a Progress Bar or just styled space segments
    // Bar 1: Solid Dark Blue
    // We use a Progress Bar or just styled space segments
    // Note: ProgressBar usually renders backgrounds. We can mock it with a panel of full blocks.
    // Note: ProgressBar usually renders backgrounds. We can mock it with a panel of full blocks.
    const bar1_txt = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "]                  [/]");

    // Long arrow
    const long_arrow = try Text.fromMarkup(result_allocator, " ──────────────────→ ");

    // Bar 2: Split (Solid | Hatched)
    // 50% Solid, 50% Hatched
    const bar2_txt = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "]      [/][bg " ++ C_BG_HEX ++ " fg " ++ C_DIM_HEX ++ "]//////[/]");

    // Result Text
    const res_txt = try Text.fromMarkup(result_allocator, "  [" ++ C_FG_HEX ++ "]≈30-60% less[/]");

    try token_grid.addRowRich(&.{ .{ .styled_text = lbl_tok }, .{ .styled_text = bar1_txt }, .{ .styled_text = long_arrow }, .{ .styled_text = bar2_txt }, .{ .styled_text = res_txt } });

    // -- CODE SNIPPET --
    const cmd_txt = try Text.fromMarkup(result_allocator, "[" ++ C_STRONG_HEX ++ "]► Try it:              [/][italic " ++ C_FG_HEX ++ "]npx @toon-format/cli *.json[/]");

    // -- FOOTER --
    // Blue background panel with stats
    var footer_table = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true)
        .withExpand(true);

    // Stats columns
    _ = footer_table.withColumn(Column.init("").withRatio(3)); // Chart
    _ = footer_table.withColumn(Column.init("").withRatio(3)); // Accuracy
    _ = footer_table.withColumn(Column.init("").withRatio(4)); // Features

    // Chart Content
    // "TOON -> [===]"
    // "JSON -> [======]"
    // We'll use simple text bars for this demo
    const chart_txt = try Text.fromMarkup(result_allocator, "avg tokens\n" ++
        "[" ++ C_FOOTER_FG ++ "]TOON → [" ++ C_ACCENT_HEX ++ "]███[/][dim]///////[/][/]\n" ++
        "[" ++ C_FOOTER_FG ++ "]JSON → [" ++ C_BG_HEX ++ " reverse]      [/][/]");

    // Accuracy Content
    const acc_txt = try Text.fromMarkup(result_allocator, "retrieval accuracy\n" ++
        "[" ++ C_FOOTER_FG ++ "]◆═════════→  73.9%[/]\n" ++
        "[" ++ C_FOOTER_FG ++ "]◆═════════→  69.7%[/]");

    // Features Content
    const feat_txt = try Text.fromMarkup(result_allocator, "best for\n" ++
        "[" ++ C_BG_HEX ++ "]repeated structure • tables[/]\n" ++
        "[" ++ C_BG_HEX ++ "]varying fields • deep trees[/]");

    try footer_table.addRowRich(&.{
        .{ .styled_text = chart_txt },
        .{ .styled_text = acc_txt },
        .{ .styled_text = feat_txt },
    });

    // Render Footer Table to segments to put in Panel
    // We assume width matches console
    const footer_segs = try footer_table.render(width - 4, result_allocator);

    var footer_panel = Panel.fromRendered(result_allocator, footer_segs)
        .withStyle(Style.empty.bg(footer_bg).fg(footer_fg))
        .withPadding(1, 2, 1, 2)
        .withWidth(width) // Full width
        .square();
    // Customize border to be hidden or same color
    const footer_border = Style.empty.bg(footer_bg).fg(footer_bg);
    footer_panel = footer_panel.withBorderStyle(footer_border);

    // -- MAIN RENDER --
    // We print everything sequentially
    try console.print("\n"); // Margin top
    try console.printRenderable(header);
    try console.printRenderable(rule);
    try console.printRenderable(subtitle);
    try console.print("\n");

    // We indent the main body slightly
    const body_padding = rich.Padding.init(0, 4, 0, 4);

    // Print Workflow
    try console.printRenderable(body_padding.wrap(flow_grid));
    try console.print("\n");

    // Print Token stats
    try console.printRenderable(body_padding.wrap(token_grid));
    try console.print("\n");

    // Print Command
    try console.printRenderable(body_padding.wrap(Text.init(result_allocator, ""))); // Spacer
    try console.printRenderable(body_padding.wrap(cmd_txt));
    try console.print("\n\n");

    // Print Footer
    try console.printRenderable(footer_panel);
    try console.print("\n");
}

const std = @import("std");
const rich = @import("rich_zig");

const Color = rich.Color;
const Style = rich.Style;
const Panel = rich.Panel;
const Table = rich.Table;
const Text = rich.Text;
const BoxStyle = rich.BoxStyle;
const Column = rich.Column;

const C_BG_HEX = "#FDF6E3";
const C_FG_HEX = "#657B83";
const C_STRONG_HEX = "#002B36";
const C_ACCENT_HEX = "#268BD2";
const C_FOOTER_BG = "#002B36";
const C_FOOTER_FG = "#93A1A1";
const C_DIM_HEX = "#93A1A1";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const result_allocator = arena.allocator();

    var console = rich.Console.init(allocator, io, init.minimal.environ);
    defer console.deinit();
    const width = console.width();

    const strong_color = try Color.fromHex(C_STRONG_HEX);
    const footer_bg = try Color.fromHex(C_FOOTER_BG);
    const footer_fg = try Color.fromHex(C_FOOTER_FG);

    const dashed_box = BoxStyle.custom(.{
        .top_left = "┌",
        .top_right = "┐",
        .bottom_left = "└",
        .bottom_right = "┘",
        .horizontal = "╌",
        .vertical = "╎",
    });

    var header = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true)
        .withExpand(true);

    _ = header.withColumn(Column.init("").withRatio(8));
    _ = header.withColumn(Column.init("").withWidth(10).withJustify(.right));

    const title_txt = try Text.fromMarkup(result_allocator, "[bold " ++ C_STRONG_HEX ++ "]Token-Oriented Object Notation[/]");

    const logo_markup = "[bold " ++ C_STRONG_HEX ++ "]TO\nON[/][bold " ++ C_ACCENT_HEX ++ "]▀[/]";
    const logo_txt = try Text.fromMarkup(result_allocator, logo_markup);

    try header.addRowRich(&.{ .{ .styled_text = title_txt }, .{ .styled_text = logo_txt } });

    const sep_style = Style.empty.fg(strong_color);
    const rule = rich.Rule.init().withStyle(sep_style);

    const subtitle = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]Compact, human-readable serialization of JSON data for LLM prompts[/]\n");

    var flow_grid = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true);

    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");
    _ = flow_grid.addColumn("");

    const lbl_flow = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]Workflow:     [/]");

    const txt_json = try Text.fromMarkup(result_allocator, " [" ++ C_STRONG_HEX ++ "]JSON[/] ");
    const p_json = Panel.fromStyledText(result_allocator, txt_json)
        .withWidth(8)
        .square()
        .withBorderStyle(Style.empty.fg(strong_color));

    const arrow = try Text.fromMarkup(result_allocator, " ──→ ");

    const txt_enc = try Text.fromMarkup(result_allocator, "[italic " ++ C_DIM_HEX ++ "] encode() [/]");
    var p_enc = Panel.fromStyledText(result_allocator, txt_enc)
        .withWidth(12)
        .withBorderStyle(Style.empty.fg(try Color.fromHex(C_DIM_HEX)));
    p_enc.box_style = dashed_box;

    const txt_toon = try Text.fromMarkup(result_allocator, " [" ++ C_STRONG_HEX ++ "]TOON[/] ");
    const p_toon = Panel.fromStyledText(result_allocator, txt_toon)
        .withWidth(8)
        .square()
        .withBorderStyle(Style.empty.fg(strong_color));

    const txt_llm = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "] LLM [/][bold " ++ C_STRONG_HEX ++ "]_ [/]");

    const segs_json = try p_json.render(8, result_allocator);
    const segs_enc = try p_enc.render(12, result_allocator);
    const segs_toon = try p_toon.render(8, result_allocator);

    try flow_grid.addRowRich(&.{ .{ .styled_text = lbl_flow }, .{ .segments = segs_json }, .{ .styled_text = arrow }, .{ .segments = segs_enc }, .{ .styled_text = arrow }, .{ .segments = segs_toon }, .{ .styled_text = arrow }, .{ .styled_text = txt_llm } });

    var token_grid = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true);

    _ = token_grid.addColumn("");
    _ = token_grid.addColumn("");
    _ = token_grid.addColumn("");
    _ = token_grid.addColumn("");
    _ = token_grid.addColumn("");

    const lbl_tok = try Text.fromMarkup(result_allocator, "[" ++ C_FG_HEX ++ "]ø Tokens:     [/]");

    const bar1_txt = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "]                  [/]");

    const long_arrow = try Text.fromMarkup(result_allocator, " ──────────────────→ ");

    const bar2_txt = try Text.fromMarkup(result_allocator, "[reverse " ++ C_STRONG_HEX ++ "]      [/][bg " ++ C_BG_HEX ++ " fg " ++ C_DIM_HEX ++ "]//////[/]");

    const res_txt = try Text.fromMarkup(result_allocator, "  [" ++ C_FG_HEX ++ "]≈30-60% less[/]");

    try token_grid.addRowRich(&.{ .{ .styled_text = lbl_tok }, .{ .styled_text = bar1_txt }, .{ .styled_text = long_arrow }, .{ .styled_text = bar2_txt }, .{ .styled_text = res_txt } });

    const cmd_txt = try Text.fromMarkup(result_allocator, "[" ++ C_STRONG_HEX ++ "]► Try it:              [/][italic " ++ C_FG_HEX ++ "]npx @toon-format/cli *.json[/]");

    var footer_table = Table.init(result_allocator)
        .withBoxStyle(BoxStyle.none)
        .withCollapsePadding(true)
        .withExpand(true);

    _ = footer_table.withColumn(Column.init("").withRatio(3));
    _ = footer_table.withColumn(Column.init("").withRatio(3));
    _ = footer_table.withColumn(Column.init("").withRatio(4));

    const chart_txt = try Text.fromMarkup(result_allocator, "avg tokens\n" ++
        "[" ++ C_FOOTER_FG ++ "]TOON → [" ++ C_ACCENT_HEX ++ "]███[/][dim]///////[/][/]\n" ++
        "[" ++ C_FOOTER_FG ++ "]JSON → [" ++ C_BG_HEX ++ " reverse]      [/][/]");

    const acc_txt = try Text.fromMarkup(result_allocator, "retrieval accuracy\n" ++
        "[" ++ C_FOOTER_FG ++ "]◆═════════→  73.9%[/]\n" ++
        "[" ++ C_FOOTER_FG ++ "]◆═════════→  69.7%[/]");

    const feat_txt = try Text.fromMarkup(result_allocator, "best for\n" ++
        "[" ++ C_BG_HEX ++ "]repeated structure • tables[/]\n" ++
        "[" ++ C_BG_HEX ++ "]varying fields • deep trees[/]");

    try footer_table.addRowRich(&.{
        .{ .styled_text = chart_txt },
        .{ .styled_text = acc_txt },
        .{ .styled_text = feat_txt },
    });

    const footer_segs = try footer_table.render(width - 4, result_allocator);

    var footer_panel = Panel.fromRendered(result_allocator, footer_segs)
        .withStyle(Style.empty.bg(footer_bg).fg(footer_fg))
        .withPadding(1, 2, 1, 2)
        .withWidth(width)
        .square();
    const footer_border = Style.empty.bg(footer_bg).fg(footer_bg);
    footer_panel = footer_panel.withBorderStyle(footer_border);

    try console.print("\n");
    try console.printRenderable(header);
    try console.printRenderable(rule);
    try console.printRenderable(subtitle);
    try console.print("\n");

    const body_padding = rich.Padding.init(0, 4, 0, 4);

    try console.printRenderable(body_padding.wrap(flow_grid));
    try console.print("\n");

    try console.printRenderable(body_padding.wrap(token_grid));
    try console.print("\n");

    try console.printRenderable(body_padding.wrap(Text.init(result_allocator, "")));
    try console.printRenderable(body_padding.wrap(cmd_txt));
    try console.print("\n\n");

    try console.printRenderable(footer_panel);
    try console.print("\n");
}

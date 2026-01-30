pub const theme_mod = @import("theme.zig");
pub const HeaderLevel = theme_mod.HeaderLevel;
pub const MarkdownTheme = theme_mod.MarkdownTheme;

pub const elements_mod = @import("elements.zig");
pub const Header = elements_mod.Header;
pub const CodeBlock = elements_mod.CodeBlock;

pub const markdown_mod = @import("markdown.zig");
pub const Markdown = markdown_mod.Markdown;

test {
    _ = @import("theme.zig");
    _ = @import("elements.zig");
    _ = @import("markdown.zig");
}

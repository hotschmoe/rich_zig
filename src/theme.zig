const std = @import("std");
const Style = @import("style.zig").Style;
const Color = @import("color.zig").Color;

/// A named style registry for consistent theming across renderables.
///
/// Themes allow defining reusable named styles (e.g. "warning", "info",
/// "error.message") that can be referenced by name throughout the application.
/// Console resolves these names during markup processing.
pub const Theme = struct {
    styles: std.StringHashMap(Style),
    inherit: bool,

    pub fn init(allocator: std.mem.Allocator) Theme {
        return .{
            .styles = std.StringHashMap(Style).init(allocator),
            .inherit = true,
        };
    }

    pub fn deinit(self: *Theme) void {
        self.styles.deinit();
    }

    /// Define a named style.
    pub fn define(self: *Theme, name: []const u8, style: Style) !void {
        try self.styles.put(name, style);
    }

    /// Resolve a style name. Returns null if not found.
    pub fn get(self: Theme, name: []const u8) ?Style {
        return self.styles.get(name);
    }

    /// Check if a style name is defined.
    pub fn contains(self: Theme, name: []const u8) bool {
        return self.styles.contains(name);
    }

    /// Return the number of defined styles.
    pub fn count(self: Theme) usize {
        return self.styles.count();
    }

    /// Merge another theme into this one. The other theme's styles
    /// take precedence on conflict.
    pub fn merge(self: *Theme, other: Theme) !void {
        var it = other.styles.iterator();
        while (it.next()) |entry| {
            try self.styles.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    /// Create a default theme with common semantic style names.
    pub fn default(allocator: std.mem.Allocator) !Theme {
        var t = Theme.init(allocator);
        errdefer t.deinit();

        // Semantic styles
        try t.define("info", Style.empty.foreground(Color.cyan));
        try t.define("warning", Style.empty.foreground(Color.yellow));
        try t.define("error", Style.empty.foreground(Color.red).bold());
        try t.define("success", Style.empty.foreground(Color.green));
        try t.define("danger", Style.empty.foreground(Color.red).bold());

        // Text emphasis
        try t.define("em", Style.empty.italic());
        try t.define("strong", Style.empty.bold());
        try t.define("code", Style.empty.foreground(Color.fromRgb(230, 219, 116)).dim());

        // Data types (for pretty printing / repr highlighting)
        try t.define("repr.number", Style.empty.foreground(Color.cyan).bold());
        try t.define("repr.string", Style.empty.foreground(Color.green));
        try t.define("repr.bool", Style.empty.foreground(Color.fromRgb(255, 85, 85)).italic());
        try t.define("repr.none", Style.empty.foreground(Color.magenta).italic());
        try t.define("repr.url", Style.empty.foreground(Color.blue).underline());
        try t.define("repr.path", Style.empty.foreground(Color.fromRgb(174, 129, 255)));

        // Log levels
        try t.define("log.debug", Style.empty.dim());
        try t.define("log.info", Style.empty.foreground(Color.cyan));
        try t.define("log.warning", Style.empty.foreground(Color.yellow));
        try t.define("log.error", Style.empty.foreground(Color.red).bold());

        // Structural
        try t.define("title", Style.empty.bold());
        try t.define("subtitle", Style.empty.dim());
        try t.define("header", Style.empty.bold().underline());
        try t.define("muted", Style.empty.dim());
        try t.define("link", Style.empty.foreground(Color.blue).underline());

        return t;
    }
};

// Tests

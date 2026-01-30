//! Tree Example - Tree structures for hierarchical data
//!
//! Run with: zig build example-tree

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Basic tree structure
    try console.print("[bold]File System Tree:[/]");
    {
        var root = rich.TreeNode.init(allocator, "project/");
        defer root.deinit();

        // Add src directory with children
        const src = try root.addChildLabel("src/");
        _ = try src.addChildLabel("main.zig");
        _ = try src.addChildLabel("lib.zig");
        const utils = try src.addChildLabel("utils/");
        _ = try utils.addChildLabel("helpers.zig");
        _ = try utils.addChildLabel("math.zig");

        // Add docs directory
        const docs = try root.addChildLabel("docs/");
        _ = try docs.addChildLabel("README.md");
        _ = try docs.addChildLabel("API.md");

        // Add top-level files
        _ = try root.addChildLabel("build.zig");
        _ = try root.addChildLabel("build.zig.zon");

        const tree = rich.Tree.init(root);
        try console.printRenderable(tree);
    }
    try console.print("");

    // Styled tree with markup
    try console.print("[bold]Styled Tree (with colored labels):[/]");
    {
        var root = rich.TreeNode.init(allocator, "Application")
            .withStyle(rich.Style.empty.bold().foreground(rich.Color.cyan));
        defer root.deinit();

        var models = try root.addChildLabel("Models");
        models.style = rich.Style.empty.foreground(rich.Color.yellow);
        _ = try models.addChildLabel("User");
        _ = try models.addChildLabel("Product");
        _ = try models.addChildLabel("Order");

        var views = try root.addChildLabel("Views");
        views.style = rich.Style.empty.foreground(rich.Color.green);
        _ = try views.addChildLabel("HomeView");
        _ = try views.addChildLabel("ProductView");

        var controllers = try root.addChildLabel("Controllers");
        controllers.style = rich.Style.empty.foreground(rich.Color.magenta);
        _ = try controllers.addChildLabel("AuthController");
        _ = try controllers.addChildLabel("ApiController");

        const tree = rich.Tree.init(root);
        try console.printRenderable(tree);
    }
    try console.print("");

    // Organization chart style tree
    try console.print("[bold]Organization Chart:[/]");
    {
        var root = rich.TreeNode.init(allocator, "CEO");
        defer root.deinit();

        const cto = try root.addChildLabel("CTO");
        const engineering = try cto.addChildLabel("Engineering");
        _ = try engineering.addChildLabel("Backend Team");
        _ = try engineering.addChildLabel("Frontend Team");
        _ = try cto.addChildLabel("DevOps");

        const cfo = try root.addChildLabel("CFO");
        _ = try cfo.addChildLabel("Accounting");
        _ = try cfo.addChildLabel("Finance");

        const coo = try root.addChildLabel("COO");
        _ = try coo.addChildLabel("Operations");
        _ = try coo.addChildLabel("HR");

        const tree = rich.Tree.init(root);
        try console.printRenderable(tree);
    }
}

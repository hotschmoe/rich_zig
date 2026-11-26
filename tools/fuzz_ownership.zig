const std = @import("std");
const rich = @import("rich_zig");
const workload = @import("fuzz_generate.zig");
const checker = @import("fuzz_check.zig");
const Tracker = @import("fuzz_memory.zig").Tracker;
const assert = @import("assert").assert;

pub fn check(case: *const workload.Case, memory: []u8) !u64 {
    assert(memory.len == checker.memory_max);
    assert(case.expected_error == null);
    var input: [workload.input_max]u8 = undefined;
    for ([_]bool{ false, true }) |themed| {
        var tracker = Tracker{ .fixed = .init(memory) };
        const allocator = tracker.allocator();
        var copied = copied: {
            @memcpy(input[0..case.input.length], case.input.slice());
            var theme = rich.Theme.init(allocator);
            defer theme.deinit();
            if (themed) {
                try theme.define("bold", .{ .attributes = 1, .set_attributes = 1 });
                try theme.define("link", .{ .attributes = 1, .set_attributes = 1 });
            }
            var parsed = if (themed)
                try rich.Text.fromMarkupWithTheme(allocator, input[0..case.input.length], theme)
            else
                try rich.Text.fromMarkup(allocator, input[0..case.input.length]);
            defer parsed.deinit();
            @memset(input[0..case.input.length], 0xa5);
            try checker.boundaries(parsed);
            try checker.plain_and_styles(case, parsed);
            const clone = try parsed.clone();
            @memset(@constCast(parsed.plain), 0xdd);
            @memset(@constCast(parsed.owned_links), 0xdd);
            @memset(std.mem.sliceAsBytes(@constCast(parsed.spans)), 0xdd);
            break :copied clone;
        };
        try checker.boundaries(copied);
        try checker.plain_and_styles(case, copied);
        copied.deinit();
        if (tracker.live_bytes != 0) return error.OwnershipLeak;
    }
    return 2;
}

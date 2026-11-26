const std = @import("std");
const assert = @import("assert").assert;

pub const Tracker = struct {
    fixed: std.heap.FixedBufferAllocator,
    live_bytes: u64 = 0,
    allocations: u32 = 0,
    fail_at: u32 = std.math.maxInt(u32),

    pub fn allocator(self: *Tracker) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = allocate,
            .resize = resize,
            .remap = std.mem.Allocator.noRemap,
            .free = release,
        } };
    }

    fn allocate(pointer: *anyopaque, size: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Tracker = @ptrCast(@alignCast(pointer));
        assert(size > 0);
        if (self.allocations >= self.fail_at) return null;
        self.allocations += 1;
        const bytes = self.fixed.allocator().rawAlloc(size, alignment, ra) orelse return null;
        self.live_bytes += size;
        assert(self.live_bytes <= self.fixed.buffer.len);
        return bytes;
    }

    fn resize(
        pointer: *anyopaque,
        bytes: []u8,
        alignment: std.mem.Alignment,
        size: usize,
        ra: usize,
    ) bool {
        const self: *Tracker = @ptrCast(@alignCast(pointer));
        assert(self.live_bytes >= bytes.len);
        if (size > bytes.len) return false;
        if (!self.fixed.allocator().rawResize(bytes, alignment, size, ra)) return false;
        self.live_bytes = self.live_bytes - bytes.len + size;
        assert(self.live_bytes <= self.fixed.buffer.len);
        return true;
    }

    fn release(pointer: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *Tracker = @ptrCast(@alignCast(pointer));
        assert(self.live_bytes >= bytes.len);
        assert(self.fixed.ownsSlice(bytes));
        self.fixed.allocator().rawFree(bytes, alignment, ra);
        self.live_bytes -= bytes.len;
    }
};

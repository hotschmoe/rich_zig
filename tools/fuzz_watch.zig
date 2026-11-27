const std = @import("std");
const assert = @import("assert").assert;

const ticks_max: u32 = 17280000;
pub const Watch = struct {
    io: std.Io,
    phase: std.atomic.Value(u64) = .init(0),
    ticket: u64 = 0,
    deadline_ms: std.atomic.Value(i64) = .init(0),
    stop: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    pub fn start(self: *Watch) !void {
        assert(self.thread == null);
        self.thread = try std.Thread.spawn(.{}, monitor, .{self});
        assert(self.thread != null);
    }

    pub fn deinit(self: *Watch) void {
        assert(self.phase.load(.acquire) % 2 == 0);
        self.stop.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.thread = null;
        assert(self.stop.load(.acquire));
    }

    pub fn arm(self: *Watch, bytes: u32) void {
        assert(self.phase.load(.acquire) % 2 == 0);
        const now = std.Io.Clock.awake.now(self.io).toMilliseconds();
        self.deadline_ms.store(now + 100 + @as(i64, bytes / 10), .release);
        self.ticket = self.phase.fetchAdd(1, .acq_rel) + 1;
        assert(self.ticket % 2 == 1);
        assert(self.deadline_ms.load(.acquire) > now);
    }

    pub fn finish(self: *Watch) void {
        assert(self.thread != null);
        if (self.phase.cmpxchgStrong(self.ticket, self.ticket + 1, .acq_rel, .acquire) != null) {
            self.thread.?.join();
            @panic("watchdog exited without terminating timed-out parser");
        }
        assert(self.phase.load(.acquire) == self.ticket + 1);
    }

    fn monitor(self: *Watch) void {
        assert(self.deadline_ms.load(.acquire) >= 0);
        for (0..ticks_max) |_| {
            if (self.stop.load(.acquire)) return;
            std.Io.sleep(self.io, .fromMilliseconds(5), .awake) catch |err| {
                std.debug.panic("watchdog sleep failed: {s}", .{@errorName(err)});
            };
            const ticket = self.phase.load(.acquire);
            const deadline = self.deadline_ms.load(.acquire);
            const now = std.Io.Clock.awake.now(self.io).toMilliseconds();
            if (ticket % 2 == 1 and now > deadline) {
                if (self.phase.cmpxchgStrong(ticket, ticket + 1, .acq_rel, .acquire) == null)
                    @panic("WorkLimit: 100 ms + 100 us per input byte");
            }
        }
        std.debug.print("FAIL: watchdog duration limit\n", .{});
        std.process.exit(1);
    }
};

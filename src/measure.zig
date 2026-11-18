const std = @import("std");

pub const Measurement = struct {
    minimum: usize,
    maximum: usize,

    pub fn init(minimum: usize, maximum: usize) Measurement {
        return .{
            .minimum = minimum,
            .maximum = @max(minimum, maximum),
        };
    }

    pub const zero: Measurement = .{ .minimum = 0, .maximum = 0 };

    pub fn clamp(self: Measurement, max_width: usize) Measurement {
        return .{
            .minimum = @min(self.minimum, max_width),
            .maximum = @min(self.maximum, max_width),
        };
    }

    pub fn union_(a: Measurement, b: Measurement) Measurement {
        return .{
            .minimum = @max(a.minimum, b.minimum),
            .maximum = @max(a.maximum, b.maximum),
        };
    }

    pub fn intersection(a: Measurement, b: Measurement) Measurement {
        return .{
            .minimum = @max(a.minimum, b.minimum),
            .maximum = @min(a.maximum, b.maximum),
        };
    }

    pub fn pad(self: Measurement, amount: usize) Measurement {
        const total = amount * 2;
        return .{
            .minimum = self.minimum + total,
            .maximum = self.maximum + total,
        };
    }

    pub fn fromText(text: []const u8) Measurement {
        const cells = @import("cells.zig");
        var max_line: usize = 0;
        var max_word: usize = 0;
        var current_line: usize = 0;
        var current_word: usize = 0;

        var i: usize = 0;
        while (i < text.len) {
            const byte = text[i];
            if (byte == '\n') {
                if (current_line > max_line) max_line = current_line;
                if (current_word > max_word) max_word = current_word;
                current_line = 0;
                current_word = 0;
                i += 1;
                continue;
            }
            if (byte == ' ' or byte == '\t') {
                if (current_word > max_word) max_word = current_word;
                current_word = 0;
                current_line += 1;
                i += 1;
                continue;
            }

            const cp_len = std.unicode.utf8ByteSequenceLength(byte) catch {
                i += 1;
                current_line += 1;
                current_word += 1;
                continue;
            };
            if (i + cp_len > text.len) break;

            const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
                i += 1;
                current_line += 1;
                current_word += 1;
                continue;
            };

            const w = cells.getCharacterCellSize(cp);
            current_line += w;
            current_word += w;
            i += cp_len;
        }

        if (current_line > max_line) max_line = current_line;
        if (current_word > max_word) max_word = current_word;

        return .{
            .minimum = max_word,
            .maximum = max_line,
        };
    }

    pub fn measureRenderable(renderable: anytype, max_width: usize, allocator: std.mem.Allocator) !Measurement {
        if (@hasDecl(@TypeOf(renderable), "measure")) {
            return renderable.measure(max_width, allocator);
        }
        const segment_mod = @import("segment.zig");
        const segments = try renderable.render(max_width, allocator);
        defer allocator.free(segments);
        const lines = try segment_mod.splitIntoLines(segments, allocator);
        defer allocator.free(lines);
        const width = segment_mod.maxLineWidth(lines);
        return Measurement.init(width, width);
    }
};

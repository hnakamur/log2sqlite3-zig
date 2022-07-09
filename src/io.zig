const std = @import("std");
const testing = std.testing;

pub fn LineReader(comptime buffer_size: usize) type {
    return struct {
        buffer: [buffer_size]u8 = undefined,
        n: usize = 0,
        pos: usize = 0,
        leftover: usize = 0,
        eof: bool = false,

        const Self = @This();

        pub fn readLine(self: *Self, reader: anytype) !?[]const u8 {
            if (self.eof) {
                return null;
            }

            while (true) {
                if (self.pos < self.n) {
                    if (std.mem.indexOfScalarPos(u8, self.buffer[0..self.n], self.pos, '\n')) |lf_pos| {
                        const line = self.buffer[self.pos..lf_pos];
                        self.pos = lf_pos + 1;
                        return line;
                    }

                    if (self.pos == 0 and self.n == self.buffer.len) {
                        return error.TooLongLine;
                    }

                    if (self.eof) {
                        return self.buffer[self.pos..self.n];
                    }

                    std.mem.copy(u8, self.buffer[0..], self.buffer[self.pos..self.n]);
                    self.leftover = self.n - self.pos;
                }

                self.n = try reader.read(self.buffer[self.leftover..]);
                if (self.n == 0) {
                    self.eof = true;
                    if (self.leftover == 0) {
                        return null;
                    }
                }
                self.n += self.leftover;
                self.leftover = 0;
                self.pos = 0;
            }
        }
    };
}

test "LineReader" {
    testing.log_level = .debug;
    {
        const input = "no_newline";
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        var line_reader = LineReader(4096){};
        try testing.expectEqualStrings(input, (try line_reader.readLine(reader)).?);
        try testing.expectEqual(@as(?[]const u8, null), try line_reader.readLine(reader));
    }
    {
        const input = "line1\nline2";
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        var line_reader = LineReader(8){};
        try testing.expectEqualStrings("line1", (try line_reader.readLine(reader)).?);
        try testing.expectEqualStrings("line2", (try line_reader.readLine(reader)).?);
        try testing.expectEqual(@as(?[]const u8, null), try line_reader.readLine(reader));
    }
    {
        const input = "line1\nline2\n";
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        var line_reader = LineReader(8){};
        try testing.expectEqualStrings("line1", (try line_reader.readLine(reader)).?);
        try testing.expectEqualStrings("line2", (try line_reader.readLine(reader)).?);
        try testing.expectEqual(@as(?[]const u8, null), try line_reader.readLine(reader));
    }
    {
        const input = "1\n1234567\n";
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        var line_reader = LineReader(8){};
        try testing.expectEqualStrings("1", (try line_reader.readLine(reader)).?);
        try testing.expectEqualStrings("1234567", (try line_reader.readLine(reader)).?);
        try testing.expectEqual(@as(?[]const u8, null), try line_reader.readLine(reader));
    }
    {
        const input = "foo\nlong";
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();
        var line_reader = LineReader(4){};
        try testing.expectEqualStrings("foo", (try line_reader.readLine(reader)).?);
        try testing.expectError(error.TooLongLine, line_reader.readLine(reader));
    }
}

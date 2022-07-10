const std = @import("std");
const testing = std.testing;

pub const ParseResult = struct {
    pub const Range = struct {
        start: u32 = 0,
        len: u32 = 0,
    };

    // line followed by unescaped strings.
    line_buf: std.ArrayListUnmanaged(u8) = .{},

    labels: std.ArrayListUnmanaged([]const u8) = .{},
    values: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.labels.deinit(allocator);
        self.values.deinit(allocator);
        self.line_buf.deinit(allocator);
    }

    fn setLine(self: *ParseResult, allocator: std.mem.Allocator, line: []const u8) !void {
        self.labels.items.len = 0;
        self.values.items.len = 0;
        self.line_buf.items.len = 0;
        try self.line_buf.appendSlice(allocator, line);
    }

    fn appendLabel(self: *ParseResult, allocator: std.mem.Allocator, old_line_buf_items_ptr: *u8, range: Range) !void {
        self.fixLabelsAndValues(old_line_buf_items_ptr);
        try self.labels.append(allocator, self.slice_unchecked(range));
    }

    fn appendValue(self: *ParseResult, allocator: std.mem.Allocator, old_line_buf_items_ptr: *u8, range: Range) !void {
        self.fixLabelsAndValues(old_line_buf_items_ptr);
        try self.values.append(allocator, self.slice_unchecked(range));
    }

    fn fixLabelsAndValues(self: *ParseResult, old_line_buf_items_ptr: *u8) void {
        const ptr_diff = @ptrToInt(&self.line_buf.items[0]) -% @ptrToInt(old_line_buf_items_ptr);
        if (ptr_diff == 0) {
            return;
        }
        for (self.labels.items) |*label| {
            label.ptr += ptr_diff;
        }
        for (self.values.items) |*value| {
            value.ptr += ptr_diff;
        }
    }

    fn slice_unchecked(self: *const ParseResult, range: Range) []const u8 {
        return self.line_buf.items[range.start .. range.start + range.len];
    }
};

pub fn eqlStringList(list1: []const []const u8, list2: []const []const u8) bool {
    if (list1.len != list2.len) {
        return false;
    }
    for (list1) |item1, i| {
        if (!std.mem.eql(u8, item1, list2[i])) {
            return false;
        }
    }
    return true;
}

test "eqlStringList" {
    testing.log_level = .debug;

    var list1 = &[_][]const u8{ "foo", "bar" };
    var list2 = &[_][]const u8{ "foo", "bar" };
    try testing.expect(eqlStringList(list1, list2));
}

pub fn startsWithPos(string: []const u8, start_index: usize, prefix: []const u8) bool {
    return start_index + prefix.len <= string.len and
        std.mem.startsWith(u8, string[start_index..], prefix);
}

fn expectPrefixPos(input: []const u8, start_index: usize, prefix: []const u8) !usize {
    if (startsWithPos(input, start_index, prefix)) {
        return start_index + prefix.len;
    }
    return error.InvalidJson;
}

inline fn hexCharToDigit(c: u8) !u8 {
    return std.fmt.charToDigit(c, 16) catch error.InvalidJson;
}

fn fourHexCharsToCodepoint(input: []const u8, start_index: usize, out_cp: *u21) !usize {
    if (start_index + 4 > input.len) {
        return error.InvalidJson;
    }
    out_cp.* =
        (@as(u21, try hexCharToDigit(input[start_index])) << 12) |
        (@as(u21, try hexCharToDigit(input[start_index + 1])) << 8) |
        (@as(u21, try hexCharToDigit(input[start_index + 2])) << 4) |
        @as(u21, try hexCharToDigit(input[start_index + 3]));
    return start_index + 4;
}

fn parseStringPos(
    allocator: std.mem.Allocator,
    line_buf: *std.ArrayListUnmanaged(u8),
    line_len: usize,
    start_index: usize,
    out_range: *ParseResult.Range,
) !usize {
    const start = try expectPrefixPos(line_buf.items, start_index, "\"");
    if (std.mem.indexOfAnyPos(u8, line_buf.items, start, "\"\\")) |pos| {
        if (line_buf.items[pos] == '"') {
            out_range.* = .{
                .start = @intCast(u32, start),
                .len = @intCast(u32, pos - start),
            };
            return pos + 1;
        }

        const unescaped_start = line_buf.items.len;
        try line_buf.ensureUnusedCapacity(allocator, pos - start);
        line_buf.appendSliceAssumeCapacity(line_buf.items[start..pos]);
        var i: usize = pos;
        while (i < line_len) : (i += 1) {
            var b = line_buf.items[i];
            switch (b) {
                '"' => {
                    i += 1;
                    break;
                },
                '\\' => {
                    i += 1;
                    if (i == line_len) {
                        return error.InvalidJson;
                    }
                    b = line_buf.items[i];
                    switch (b) {
                        '"', '\\', '/' => {
                            try line_buf.append(allocator, b);
                        },
                        'b' => {
                            try line_buf.append(allocator, '\x08');
                        },
                        'f' => {
                            try line_buf.append(allocator, '\x0C');
                        },
                        'r' => {
                            try line_buf.append(allocator, '\r');
                        },
                        't' => {
                            try line_buf.append(allocator, '\t');
                        },
                        'u' => {
                            var c: u21 = undefined;
                            i = try fourHexCharsToCodepoint(line_buf.items, i + 1, &c);
                            if (c >= 0xD800 and c < 0xDC00) {
                                i = try expectPrefixPos(line_buf.items, i, "\\u");
                                var c2: u21 = undefined;
                                i = try fourHexCharsToCodepoint(line_buf.items, i, &c2);
                                c = 0x10000 + (((c & 0x03FF) << 10) | (c2 & 0x03FF));
                            } else {
                                i -= 1;
                            }
                            var buf: [4]u8 = undefined;
                            const c_len = try std.unicode.utf8Encode(c, &buf);
                            try line_buf.appendSlice(allocator, buf[0..c_len]);
                        },
                        else => return error.InvalidJson,
                    }
                },
                else => try line_buf.append(allocator, b),
            }
        }
        out_range.* = .{
            .start = @intCast(u32, unescaped_start),
            .len = @intCast(u32, line_buf.items.len - unescaped_start),
        };
        return i;
    } else return error.InvalidJson;
}

test "parseStringPos" {
    testing.log_level = .debug;
    const allocator = std.testing.allocator;

    {
        const input =
            \\"foo"
        ;
        var got_range: ParseResult.Range = undefined;
        var line_buf = std.ArrayListUnmanaged(u8){};
        try line_buf.appendSlice(allocator, input);
        defer line_buf.deinit(allocator);
        const got_pos = try parseStringPos(allocator, &line_buf, input.len, 0, &got_range);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqual(@as(u32, "\"".len), got_range.start);
        try testing.expectEqualStrings(
            "foo",
            line_buf.items[got_range.start .. got_range.start + got_range.len],
        );
    }
    {
        const input =
            \\"foo\"\\\/\b\f\r\t\u3042"
        ;
        var got_range: ParseResult.Range = undefined;
        var line_buf = std.ArrayListUnmanaged(u8){};
        try line_buf.appendSlice(allocator, input);
        defer line_buf.deinit(allocator);
        const got_pos = try parseStringPos(allocator, &line_buf, input.len, 0, &got_range);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqual(input.len, got_range.start);
        try testing.expectEqualStrings(
            "foo\"\\/\x08\x0C\r\t\xE3\x81\x82",
            line_buf.items[got_range.start .. got_range.start + got_range.len],
        );
    }
    {
        const input =
            \\"foo\"\\\/\b\f\r\t\u3042\uD834\uDD1E"
        ;
        var got_range: ParseResult.Range = undefined;
        var line_buf = std.ArrayListUnmanaged(u8){};
        try line_buf.appendSlice(allocator, input);
        defer line_buf.deinit(allocator);
        const got_pos = try parseStringPos(allocator, &line_buf, input.len, 0, &got_range);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqual(input.len, got_range.start);
        try testing.expectEqualStrings(
            "foo\"\\/\x08\x0C\r\t\xE3\x81\x82\xF0\x9D\x84\x9E",
            line_buf.items[got_range.start .. got_range.start + got_range.len],
        );
    }
    {
        const input =
            \\"foo""\\"
        ;
        var got_range: ParseResult.Range = undefined;
        var line_buf = std.ArrayListUnmanaged(u8){};
        try line_buf.appendSlice(allocator, input);
        defer line_buf.deinit(allocator);

        const got_pos = try parseStringPos(allocator, &line_buf, input.len, 0, &got_range);
        try testing.expectEqual("\"foo\"".len, got_pos);
        try testing.expectEqual(@as(u32, "\"".len), got_range.start);
        try testing.expectEqualStrings(
            "foo",
            line_buf.items[got_range.start .. got_range.start + got_range.len],
        );

        var got_range2: ParseResult.Range = undefined;
        const got_pos2 = try parseStringPos(allocator, &line_buf, input.len, "\"foo\"".len, &got_range2);
        try testing.expectEqual(input.len, got_pos2);
        try testing.expectEqual(input.len, got_range2.start);
        try testing.expectEqualStrings(
            "\\",
            line_buf.items[got_range2.start .. got_range2.start + got_range2.len],
        );
    }
}

pub fn parseLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    out_result: *ParseResult,
) !usize {
    var i = try expectPrefixPos(line, 0, "{");
    try out_result.setLine(allocator, line);

    var range: ParseResult.Range = undefined;
    while (true) {
        var old_line_buf_items_ptr = &out_result.line_buf.items[0];
        i = try parseStringPos(allocator, &out_result.line_buf, line.len, i, &range);
        try out_result.appendLabel(allocator, old_line_buf_items_ptr, range);

        i = try expectPrefixPos(out_result.line_buf.items, i, ":");

        old_line_buf_items_ptr = &out_result.line_buf.items[0];
        i = try parseStringPos(allocator, &out_result.line_buf, line.len, i, &range);
        try out_result.appendValue(allocator, old_line_buf_items_ptr, range);

        if (startsWithPos(out_result.line_buf.items, i, ",")) {
            i += 1;
        } else {
            break;
        }
    }

    return try expectPrefixPos(out_result.line_buf.items, i, "}");
}

test "parseLine" {
    const allocator = std.testing.allocator;
    var result = ParseResult{};
    defer result.deinit(allocator);
    const input =
        \\{"foo":"123","bar":"GET \/ HTTP\/1.1"}
    ;
    const pos = try parseLine(allocator, input, &result);

    const want_labels = [_][]const u8{ "foo", "bar" };
    const want_values = [_][]const u8{ "123", "GET / HTTP/1.1" };
    try std.testing.expectEqual(input.len, pos);
    try std.testing.expect(eqlStringList(want_labels[0..], result.labels.items));
    try std.testing.expect(eqlStringList(want_values[0..], result.values.items));
}

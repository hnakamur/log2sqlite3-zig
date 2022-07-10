const std = @import("std");
const testing = std.testing;

pub const ParseResult = struct {
    pub const Range = struct {
        start: u32 = 0,
        len: u32 = 0,
    };

    // line followed by unescaped strings.
    line_buf: std.ArrayListUnmanaged(u8) = .{},

    label_ranges: std.ArrayListUnmanaged(Range) = .{},
    value_ranges: std.ArrayListUnmanaged(Range) = .{},

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.label_ranges.deinit(allocator);
        self.value_ranges.deinit(allocator);
        self.line_buf.deinit(allocator);
    }

    pub fn setLine(self: *ParseResult, allocator: std.mem.Allocator, line: []const u8) !void {
        self.label_ranges.items.len = 0;
        self.value_ranges.items.len = 0;
        self.line_buf.items.len = 0;
        try self.line_buf.appendSlice(allocator, line);
    }

    pub fn appendUnescapedString(self: *ParseResult, allocator: std.mem.Allocator, s: []const u8) !u32 {
        const start = self.line_buf.items.len;
        try self.line_buf.appendSlice(allocator, s);
        return @intCast(u32, start);
    }

    pub fn slice_unchecked(self: *const ParseResult, range: Range) []const u8 {
        return self.line_buf.items[range.start .. range.start + range.len];
    }

    pub fn eqlLabels(self: *const ParseResult, other: *const ParseResult) bool {
        if (self.label_ranges.items.len != other.label_ranges.items.len) {
            return false;
        }
        for (self.label_ranges.items) |r, i| {
            if (!std.mem.eql(
                u8,
                self.slice_unchecked(r),
                other.slice_unchecked(other.label_ranges.items[i]),
            )) {
                return false;
            }
        }
        return true;
    }

    pub fn eqlValues(self: *const ParseResult, other: *const ParseResult) bool {
        if (self.value_ranges.items.len != other.value_ranges.items.len) {
            return false;
        }
        for (self.value_ranges.items) |r, i| {
            if (!std.mem.eql(
                u8,
                self.slice_unchecked(r),
                other.slice_unchecked(other.value_ranges.items[i]),
            )) {
                return false;
            }
        }
        return true;
    }
};

pub const StringList = std.ArrayListUnmanaged([]const u8);

pub fn deinitStringListItems(list: *StringList, allocator: std.mem.Allocator) void {
    for (list.items) |item| allocator.free(item);
}

pub fn deinitStringList(list: *StringList, allocator: std.mem.Allocator) void {
    deinitStringListItems(list, allocator);
    list.deinit(allocator);
}

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

fn parseString(
    allocator: std.mem.Allocator,
    input: []const u8,
    out_string: *[]const u8,
) !usize {
    const start = try expectPrefixPos(input, 0, "\"");
    if (std.mem.indexOfAnyPos(u8, input, start, "\"\\")) |pos| {
        if (input[pos] == '"') {
            out_string.* = try allocator.dupe(u8, input[start..pos]);
            return pos + 1;
        }

        var bytes = std.ArrayListUnmanaged(u8){};
        errdefer bytes.deinit(allocator);
        try bytes.appendSlice(allocator, input[start..pos]);
        var i: usize = pos;
        while (i < input.len) : (i += 1) {
            switch (input[i]) {
                '"' => {
                    i += 1;
                    break;
                },
                '\\' => {
                    i += 1;
                    if (i == input.len) {
                        return error.InvalidJson;
                    }
                    switch (input[i]) {
                        '"', '\\', '/' => {
                            try bytes.append(allocator, input[i]);
                        },
                        'b' => {
                            try bytes.append(allocator, '\x08');
                        },
                        'f' => {
                            try bytes.append(allocator, '\x0C');
                        },
                        'r' => {
                            try bytes.append(allocator, '\r');
                        },
                        't' => {
                            try bytes.append(allocator, '\t');
                        },
                        'u' => {
                            var c: u21 = undefined;
                            i = try fourHexCharsToCodepoint(input, i + 1, &c);
                            if (c >= 0xD800 and c < 0xDC00) {
                                i = try expectPrefixPos(input, i, "\\u");
                                var c2: u21 = undefined;
                                i = try fourHexCharsToCodepoint(input, i, &c2);
                                c = 0x10000 + (((c & 0x03FF) << 10) | (c2 & 0x03FF));
                            } else {
                                i -= 1;
                            }
                            var buf: [4]u8 = undefined;
                            const c_len = try std.unicode.utf8Encode(c, &buf);
                            try bytes.appendSlice(allocator, buf[0..c_len]);
                        },
                        else => return error.InvalidJson,
                    }
                },
                else => try bytes.append(allocator, input[i]),
            }
        }
        out_string.* = bytes.toOwnedSlice(allocator);
        return i;
    } else return error.InvalidJson;
}

test "parseString" {
    testing.log_level = .debug;
    const allocator = std.testing.allocator;

    {
        const input =
            \\"foo"
        ;
        var got: []const u8 = "";
        defer allocator.free(got);
        const got_pos = try parseString(allocator, input, &got);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqualStrings("foo", got);
    }
    {
        const input =
            \\"foo\"\\\/\b\f\r\t\u3042"
        ;
        var got: []const u8 = "";
        defer allocator.free(got);
        const got_pos = try parseString(allocator, input, &got);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqualStrings("foo\"\\/\x08\x0C\r\t\xE3\x81\x82", got);
    }
    {
        const input =
            \\"foo\"\\\/\b\f\r\t\u3042\uD834\uDD1E"
        ;
        var got: []const u8 = "";
        defer allocator.free(got);
        const got_pos = try parseString(allocator, input, &got);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqualStrings("foo\"\\/\x08\x0C\r\t\xE3\x81\x82\xF0\x9D\x84\x9E", got);
    }
}

fn parseStringPos(
    allocator: std.mem.Allocator,
    input: []const u8,
    start_index: usize,
    out_string: *[]const u8,
) !usize {
    return (try parseString(allocator, input[start_index..], out_string)) + start_index;
}

fn parseStringPos2(
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

test "parseStringPos2" {
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
        const got_pos = try parseStringPos2(allocator, &line_buf, input.len, 0, &got_range);
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
        const got_pos = try parseStringPos2(allocator, &line_buf, input.len, 0, &got_range);
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
        const got_pos = try parseStringPos2(allocator, &line_buf, input.len, 0, &got_range);
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

        const got_pos = try parseStringPos2(allocator, &line_buf, input.len, 0, &got_range);
        try testing.expectEqual("\"foo\"".len, got_pos);
        try testing.expectEqual(@as(u32, "\"".len), got_range.start);
        try testing.expectEqualStrings(
            "foo",
            line_buf.items[got_range.start .. got_range.start + got_range.len],
        );

        var got_range2: ParseResult.Range = undefined;
        const got_pos2 = try parseStringPos2(allocator, &line_buf, input.len, "\"foo\"".len, &got_range2);
        try testing.expectEqual(input.len, got_pos2);
        try testing.expectEqual(input.len, got_range2.start);
        try testing.expectEqualStrings(
            "\\",
            line_buf.items[got_range2.start .. got_range2.start + got_range2.len],
        );
    }
}

pub fn parseLine2(
    allocator: std.mem.Allocator,
    line: []const u8,
    out_result: *ParseResult,
) !usize {
    var i = try expectPrefixPos(line, 0, "{");
    try out_result.setLine(allocator, line);

    var range: ParseResult.Range = undefined;
    while (true) {
        i = try parseStringPos2(allocator, &out_result.line_buf, line.len, i, &range);
        try out_result.label_ranges.append(allocator, range);

        i = try expectPrefixPos(out_result.line_buf.items, i, ":");

        i = try parseStringPos2(allocator, &out_result.line_buf, line.len, i, &range);
        try out_result.value_ranges.append(allocator, range);

        if (startsWithPos(out_result.line_buf.items, i, ",")) {
            i += 1;
        } else {
            break;
        }
    }

    return try expectPrefixPos(out_result.line_buf.items, i, "}");
}

test "parseLine2" {
    const allocator = std.testing.allocator;
    var result = ParseResult{};
    defer result.deinit(allocator);
    const input =
        \\{"foo":"123","bar":"GET \/ HTTP\/1.1"}
    ;
    const pos = try parseLine2(allocator, input, &result);

    var want_labels_and_values = try allocator.dupe(u8, "foo123barGET / HTTP/1.1");
    defer allocator.free(want_labels_and_values);
    var label_ranges = [_]ParseResult.Range{
        .{ .start = 0, .len = 3 },
        .{ .start = 6, .len = 3 },
    };
    var value_ranges = [_]ParseResult.Range{
        .{ .start = 3, .len = 3 },
        .{ .start = 9, .len = 14 },
    };
    var want_result = ParseResult{
        .line_buf = .{
            .items = want_labels_and_values,
            .capacity = want_labels_and_values.len,
        },
        .label_ranges = .{
            .items = label_ranges[0..],
            .capacity = 2,
        },
        .value_ranges = .{
            .items = value_ranges[0..],
            .capacity = 2,
        },
    };
    try std.testing.expectEqual(input.len, pos);
    try std.testing.expect(result.eqlLabels(&want_result));
    try std.testing.expect(result.eqlValues(&want_result));
}

pub fn parseLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    labels: *StringList,
    values: *StringList,
) !usize {
    var i = try expectPrefixPos(line, 0, "{");

    while (true) {
        {
            var s: []const u8 = "";
            errdefer allocator.free(s);
            i = try parseStringPos(allocator, line, i, &s);
            try labels.append(allocator, s);
        }

        i = try expectPrefixPos(line, i, ":");

        {
            var s: []const u8 = "";
            errdefer allocator.free(s);
            i = try parseStringPos(allocator, line, i, &s);
            try values.append(allocator, s);
        }

        if (startsWithPos(line, i, ",")) {
            i += 1;
        } else {
            break;
        }
    }

    return try expectPrefixPos(line, i, "}");
}

test "parseLine" {
    const allocator = std.testing.allocator;
    var labels = StringList{};
    defer deinitStringList(&labels, allocator);
    var values = StringList{};
    defer deinitStringList(&values, allocator);
    const input =
        \\{"foo":"123","bar":"GET \/ HTTP\/1.1"}
    ;
    const pos = try parseLine(allocator, input, &labels, &values);

    const want_labels = &[_][]const u8{ "foo", "bar" };
    const want_values = &[_][]const u8{ "123", "GET / HTTP/1.1" };
    try std.testing.expectEqual(input.len, pos);
    try std.testing.expect(eqlStringList(want_labels, labels.items[0..]));
    try std.testing.expect(eqlStringList(want_values, values.items[0..]));
}

const std = @import("std");
const testing = std.testing;

pub const StringList = std.ArrayListUnmanaged([]const u8);

pub fn deinitStringListItems(list: *StringList, allocator: std.mem.Allocator) void {
    for (list.items) |item| allocator.free(item);
}

pub fn deinitStringList(list: *StringList, allocator: std.mem.Allocator) void {
    deinitStringListItems(list, allocator);
    list.deinit(allocator);
}

pub fn eqlStringList(list1: *const StringList, list2: *const StringList) bool {
    if (list1.items.len != list2.items.len) {
        return false;
    }
    for (list1.items) |item1, i| {
        if (!std.mem.eql(u8, item1, list2.items[i])) {
            return false;
        }
    }
    return true;
}

test "eqlStringList" {
    testing.log_level = .debug;

    var list1_items = [_][]const u8{ "foo", "bar" };
    var list1 = StringList{ .items = list1_items[0..] };

    var list2_items = [_][]const u8{ "foo", "bar" };
    var list2 = StringList{ .items = list2_items[0..] };

    try testing.expect(eqlStringList(&list1, &list2));
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
    _ = allocator;
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

    var want_label_items = [_][]const u8{ "foo", "bar" };
    const want_labels = StringList{
        .items = want_label_items[0..],
    };

    var want_value_items = [_][]const u8{ "123", "GET / HTTP/1.1" };
    const want_values = StringList{
        .items = want_value_items[0..],
    };

    try std.testing.expectEqual(input.len, pos);
    try std.testing.expect(eqlStringList(&want_labels, &labels));
    try std.testing.expect(eqlStringList(&want_values, &values));
}

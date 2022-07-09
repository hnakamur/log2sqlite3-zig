const std = @import("std");
const testing = std.testing;

pub const String = struct {
    bytes: []const u8 = "",
    owns: bool = false,

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        if (self.owns) allocator.free(self.bytes);
    }

    pub fn eql(self: *const String, other: *const String) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }
};

pub const StringList = std.ArrayListUnmanaged(String);

fn deinitStringList(self: *StringList, allocator: std.mem.Allocator) void {
    for (self.items) |*item| item.deinit(allocator);
    self.deinit(allocator);
}

fn eqlStringList(list1: *const StringList, list2: *const StringList) bool {
    if (list1.items.len != list2.items.len) {
        return false;
    }
    for (list1.items) |item1, i| {
        if (!item1.eql(&list2.items[i])) {
            return false;
        }
    }
    return true;
}

test "eqlStringList" {
    testing.log_level = .debug;
    std.log.debug("eqlStringList start", .{});
    const allocator = std.testing.allocator;

    var list1 = StringList{};
    defer deinitStringList(&list1, allocator);
    try list1.append(allocator, .{ .bytes = "foo" });

    var list2 = StringList{};
    defer deinitStringList(&list2, allocator);
    {
        const foo_copy = try allocator.dupe(u8, "foo");
        errdefer allocator.free(foo_copy);
        try list2.append(allocator, .{ .bytes = foo_copy, .owns = true });
    }

    try testing.expect(eqlStringList(&list1, &list2));
}

inline fn startsWithPos(string: []const u8, start_index: usize, prefix: []const u8) bool {
    return std.mem.startsWith(u8, string[start_index..], prefix);
}

fn expectPrefixPos(input: []const u8, start_index: usize, prefix: []const u8) !usize {
    if (startsWithPos(input, start_index, prefix)) {
        return start_index + prefix.len;
    }
    return error.InvalidJson;
}

// fn unescapedLenOfStringTail(input: []const u8) ?usize {
//     const n: usize = 0;
//     const i: usize = 0;
//     while (i < input.len) : (i += 1) {
//         switch (input[i]) {
//             '"' => break,
//             '\\' => {
//                 i += 1;
//                 if (i == input.len) {
//                     return error.InvalidJson;
//                 }
//                 switch (input[i]) {
//                     '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {},
//                     'u' => {},
//                     else => return error.InvalidJson,
//                 }
//             },
//             else => n += 1,
//         }
//     }
//     return n;
// }

inline fn hexCharToDigit(c: u8) !u8 {
    return std.fmt.charToDigit(c, 16) catch error.InvalidJson;
}

fn parseString(
    allocator: std.mem.Allocator,
    input: []const u8,
    out_string: *String,
) !usize {
    _ = allocator;
    const start = try expectPrefixPos(input, 0, "\"");
    if (std.mem.indexOfAnyPos(u8, input, start, "\"\\")) |pos| {
        if (input[pos] == '"') {
            out_string.bytes = input[start..pos];
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
                            try bytes.append(allocator, '\x0c');
                        },
                        'r' => {
                            try bytes.append(allocator, '\r');
                        },
                        't' => {
                            try bytes.append(allocator, '\t');
                        },
                        'u' => {
                            if (i + 4 > input.len) {
                                return error.InvalidJson;
                            }
                            const c: u21 =
                                (@as(u21, try hexCharToDigit(input[i + 1])) << 12) |
                                (@as(u21, try hexCharToDigit(input[i + 2])) << 8) |
                                (@as(u21, try hexCharToDigit(input[i + 3])) << 4) |
                                @as(u21, try hexCharToDigit(input[i + 4]));
                            var buf: [6]u8 = undefined;
                            const c_len = try std.unicode.utf8Encode(c, &buf);
                            try bytes.appendSlice(allocator, buf[0..c_len]);
                            i += 4;
                            // TODO: handle surrogates
                        },
                        else => return error.InvalidJson,
                    }
                },
                else => try bytes.append(allocator, input[i]),
            }
        }
        out_string.* = .{ .bytes = bytes.toOwnedSlice(allocator), .owns = true };
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
        var got = String{};
        defer got.deinit(allocator);
        const got_pos = try parseString(allocator, input, &got);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqualStrings("foo", got.bytes);
        try testing.expectEqual(false, got.owns);
    }
    {
        const input =
            \\"foo\"\\\/\b\f\r\t\u3042"
        ;
        var got = String{};
        defer got.deinit(allocator);
        const got_pos = try parseString(allocator, input, &got);
        try testing.expectEqual(input.len, got_pos);
        try testing.expectEqualStrings("foo\"\\/\x08\x0c\r\t\xe3\x81\x82", got.bytes);
        try testing.expectEqual(true, got.owns);
    }
}

pub fn parseLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    labels: *StringList,
    values: *StringList,
) ![]const u8 {
    var rest = line;
    if (!startsWithPos(line, 0, "{")) {
        return error.InvalidJson;
    }
    // rest = rest[1..];

    _ = allocator;
    _ = labels;
    _ = values;
    return rest;
}

test "parseLine" {
    const allocator = std.testing.allocator;
    var labels = StringList{};
    var values = StringList{};
    const rest = try parseLine(allocator, "{}", &labels, &values);
    try std.testing.expectEqualStrings("{}", rest);
}

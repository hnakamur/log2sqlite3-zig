const std = @import("std");
const testing = std.testing;

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

// Caller owned returned memory but each string references to slice of csv.
// Caller needs to call allocator.free for returned value after use.
pub fn parseOptionalCsv(csv: ?[]const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    if (csv == null) {
        return ([_][]const u8{})[0..];
    }
    var list = std.ArrayListUnmanaged([]const u8){};
    errdefer list.deinit(allocator);
    var iter = std.mem.tokenize(u8, csv.?, ", ");
    while (iter.next()) |word| {
        try list.append(allocator, word);
    }
    return list.toOwnedSlice(allocator);
}

test "parseOptionalCsv" {
    const allocator = testing.allocator;
    try testing.expect(eqlStringList(([_][]const u8{})[0..], try parseOptionalCsv(null, allocator)));

    {
        const list = try parseOptionalCsv("a, b", allocator);
        defer allocator.free(list);
        try testing.expect(eqlStringList(([_][]const u8{ "a", "b" })[0..], list));
    }
}

pub fn hasCommonIgnoreCaseInStringList(list1: []const []const u8, list2: []const []const u8) bool {
    for (list1) |s1| {
        for (list2) |s2| {
            if (std.ascii.eqlIgnoreCase(s1, s2)) {
                return true;
            }
        }
    }
    return false;
}

test "hasCommonIgnoreCaseInStringList" {
    testing.log_level = .debug;
    try testing.expect(!hasCommonIgnoreCaseInStringList(([_][]const u8{})[0..], ([_][]const u8{})[0..]));
    try testing.expect(!hasCommonIgnoreCaseInStringList(([_][]const u8{})[0..], ([_][]const u8{"a"})[0..]));
    try testing.expect(!hasCommonIgnoreCaseInStringList(
        ([_][]const u8{ "a", "b", "c" })[0..],
        ([_][]const u8{ "d", "e" })[0..],
    ));

    try testing.expect(hasCommonIgnoreCaseInStringList(
        ([_][]const u8{ "a", "b", "c" })[0..],
        ([_][]const u8{ "d", "a" })[0..],
    ));
    try testing.expect(hasCommonIgnoreCaseInStringList(
        ([_][]const u8{ "a", "b", "c" })[0..],
        ([_][]const u8{ "d", "B" })[0..],
    ));
}

pub fn stringListContainsIgnoreCase(list: []const []const u8, elem: []const u8) bool {
    for (list) |s| {
        if (std.ascii.eqlIgnoreCase(s, elem)) {
            return true;
        }
    }
    return false;
}

test "stringListContainsIgnoreCase" {
    testing.log_level = .info;
    try testing.expect(!stringListContainsIgnoreCase(([_][]const u8{})[0..], "foo"));
    try testing.expect(stringListContainsIgnoreCase(([_][]const u8{ "foo", "bar" })[0..], "foo"));
    try testing.expect(!stringListContainsIgnoreCase(([_][]const u8{ "foo", "bar" })[0..], "baz"));
}

pub fn stringListContainsAllIgnoreCase(list: []const []const u8, subsets: []const []const u8) bool {
    for (subsets) |s1| {
        if (!stringListContainsIgnoreCase(list, s1)) {
            return false;
        }
    }
    return true;
}

test "stringListContainsAllIgnoreCase" {
    testing.log_level = .info;
    try testing.expect(stringListContainsAllIgnoreCase(
        ([_][]const u8{ "foo", "bar" })[0..],
        ([_][]const u8{})[0..],
    ));
    try testing.expect(stringListContainsAllIgnoreCase(
        ([_][]const u8{ "foo", "bar", "baz" })[0..],
        ([_][]const u8{ "baz", "foo" })[0..],
    ));
    try testing.expect(!stringListContainsAllIgnoreCase(
        ([_][]const u8{ "foo", "bar" })[0..],
        ([_][]const u8{"baz"})[0..],
    ));
}

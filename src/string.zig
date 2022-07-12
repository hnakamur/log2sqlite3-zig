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

pub fn hasCommonIgnoreCaseInOptCsv(csv1: ?[]const u8, csv2: ?[]const u8) bool {
    if (csv1 == null or csv2 == null) {
        return false;
    }

    var iter1 = std.mem.tokenize(u8, csv1.?, ", ");
    while (iter1.next()) |word1| {
        var iter2 = std.mem.tokenize(u8, csv2.?, ", ");
        while (iter2.next()) |word2| {
            if (std.ascii.eqlIgnoreCase(word1, word2)) {
                return true;
            }
        }
    }
    return false;
}

test "hasCommonIgnoreCaseInOptCsv" {
    testing.log_level = .debug;
    try testing.expect(!hasCommonIgnoreCaseInOptCsv(null, null));
    try testing.expect(!hasCommonIgnoreCaseInOptCsv(null, ""));
    try testing.expect(!hasCommonIgnoreCaseInOptCsv("a, b, c", "d,e"));

    try testing.expect(hasCommonIgnoreCaseInOptCsv("a, b, c", "d,a"));
    try testing.expect(hasCommonIgnoreCaseInOptCsv("a, b, c", "d,B"));
}

pub fn allValuesOptCsvInStringListIgnoreCase(csv: ?[]const u8, list: []const []const u8) bool {
    if (csv == null) {
        return true;
    }
    var iter = std.mem.tokenize(u8, csv.?, ", ");
    outer: while (iter.next()) |word| {
        for (list) |elem| {
            std.log.debug("word={s}, elem={s}.", .{ word, elem });
            if (std.ascii.eqlIgnoreCase(word, elem)) {
                std.log.debug("word={s}, elem={s}. continue", .{ word, elem });
                continue :outer;
            }
        }
        return false;
    }
    return true;
}

test "allValuesOptCsvInStringListIgnoreCase" {
    testing.log_level = .info;
    try testing.expect(allValuesOptCsvInStringListIgnoreCase(null, ([_][]const u8{ "foo", "bar" })[0..]));
    try testing.expect(allValuesOptCsvInStringListIgnoreCase("foo, bar", ([_][]const u8{ "foo", "bar", "baz" })[0..]));
    try testing.expect(!allValuesOptCsvInStringListIgnoreCase("foo, huga", ([_][]const u8{ "foo", "bar", "baz" })[0..]));
}

pub fn optCsvContainsStringIgnoreCase(csv: ?[]const u8, s: []const u8) bool {
    if (csv == null) {
        return false;
    }
    var iter = std.mem.tokenize(u8, csv.?, ", ");
    while (iter.next()) |word| {
        if (std.ascii.eqlIgnoreCase(word, s)) {
            return true;
        }
    }
    return false;
}

test "optCsvContainsStringIgnoreCase" {
    testing.log_level = .info;
    try testing.expect(!optCsvContainsStringIgnoreCase(null, "foo"));
    try testing.expect(optCsvContainsStringIgnoreCase("foo, bar", "foo"));
    try testing.expect(!optCsvContainsStringIgnoreCase("foo, bar", "baz"));
}

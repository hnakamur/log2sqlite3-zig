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

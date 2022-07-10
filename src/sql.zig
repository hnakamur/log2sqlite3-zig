const std = @import("std");
const sqlite = @import("sqlite");

pub fn createTable(allocator: std.mem.Allocator, db: sqlite.Db, table_name: []const u8, columns: [][]const u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("CREATE TABLE IF NOT EXISTS ");
    try buf.appendSlice(table_name);
    try buf.appendSlice(" (");
    for (columns) |column, i| {
        if (i > 0) {
            try buf.appendSlice(", ");
        }
        try buf.appendSlice(column);
        try buf.appendSlice(" TEXT");
    }
    try buf.appendSlice(")");

    try db.exec(buf.toOwnedSlice(), .{}, .{});
}

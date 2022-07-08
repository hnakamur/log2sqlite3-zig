const std = @import("std");
const sqlite = @import("sqlite");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    const query =
        \\CREATE TABLE IF NOT EXISTS table1 (col1 TEXT)
    ;

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{});
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}

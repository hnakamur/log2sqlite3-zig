const std = @import("std");
const sqlite = @import("sqlite");

pub fn createTable(
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    table_name: []const u8,
    columns: [][]const u8,
    int_columns: ?[]const u8,
    real_columns: ?[]const u8,
) !void {
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
        if (std.mem.eql(u8, column, "msec")) {
            try buf.appendSlice(" REAL");
        } else {
            try buf.appendSlice(" TEXT");
        }
    }
    try buf.appendSlice(")");

    try db.execDynamic(buf.toOwnedSlice(), .{}, .{});
}

pub fn prepareInsertLog(
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    table_name: []const u8,
    columns: [][]const u8,
) !sqlite.DynamicStatement {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("INSERT INTO ");
    try buf.appendSlice(table_name);
    try buf.appendSlice(" (");
    for (columns) |column, i| {
        if (i > 0) {
            try buf.appendSlice(", ");
        }
        try buf.appendSlice(column);
    }
    try buf.appendSlice(") VALUES (");
    for (columns) |_, i| {
        if (i > 0) {
            try buf.appendSlice(", ");
        }
        try buf.appendSlice("?");
    }
    try buf.appendSlice(")");

    return db.prepareDynamic(buf.toOwnedSlice());
}

pub fn execInsertLog(
    stmt: *sqlite.DynamicStatement,
    values: [][]const u8,
) !void {
    try stmt.exec(.{}, values);
    stmt.reset();
}

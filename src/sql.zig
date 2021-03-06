const std = @import("std");
const sqlite = @import("sqlite");

pub fn enableStrictMode(
    db: *sqlite.Db,
) !void {
    try db.exec("PRAGMA strict=ON;", .{}, .{});
}

pub fn createTable(
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    strict: bool,
    table_name: []const u8,
    columns: []const []const u8,
    types: []const []const u8,
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
        try buf.append(' ');
        try buf.appendSlice(types[i]);
    }
    try buf.append(')');
    if (strict) {
        try buf.appendSlice(" STRICT");
    }

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
        try buf.append('?');
    }
    try buf.append(')');

    return db.prepareDynamic(buf.toOwnedSlice());
}

pub fn execInsertLog(
    stmt: *sqlite.DynamicStatement,
    values: [][]const u8,
) !void {
    try stmt.exec(.{}, values);
    stmt.reset();
}

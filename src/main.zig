const std = @import("std");
const clap = @import("clap");
const sqlite = @import("sqlite");
const LineReader = @import("io.zig").LineReader;
const ndjson = @import("ndjson.zig");
const eqlStringList = @import("string.zig").eqlStringList;
const parseOptionalCsv = @import("string.zig").parseOptionalCsv;
const hasCommonIgnoreCaseInStringList = @import("string.zig").hasCommonIgnoreCaseInStringList;
const stringListContainsAllIgnoreCase = @import("string.zig").stringListContainsAllIgnoreCase;
const stringListContainsIgnoreCase = @import("string.zig").stringListContainsIgnoreCase;
const sql = @import("sql.zig");

const debug = std.debug;
const io = std.io;

const version = "0.1.0";

fn showUsage(comptime Id: type, params: []const clap.Param(Id)) !void {
    const stderr = std.io.getStdErr().writer();
    try std.fmt.format(
        stderr,
        "Usage: {s} [options] [arguments...]\n\n",
        .{std.fs.path.basename(std.mem.span(std.os.argv[0]))},
    );
    return clap.help(stderr, Id, params, .{});
}

pub fn main() anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\--db <str>             Database source name or simply database filename.
        \\--table <str>          Table name to create or to append records to.
        \\--format <str>         Choose a log format from "ndjson" (default) or "ltsv".
        \\--batch <usize>        Batch size of insert operations in a transaction (default: 1000).
        \\--int-columns <str>    Comma separated list of INTEGER column names.
        \\--real-columns <str>   Comma separated list of REAL column names.
        \\--strict-table         Enable SQLite Strict mode.
        \\-h, --help             Display this help and exit.
        \\--version              Show version and exit.
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch {
        return showUsage(clap.Help, &params);
    };
    defer res.deinit();

    if (res.args.help)
        return showUsage(clap.Help, &params);
    if (res.args.version) {
        debug.print("{s}\n", .{version});
        return;
    }

    var table_name: []const u8 = "";
    if (res.args.table) |t| {
        table_name = t;
    } else {
        try std.fmt.format(std.io.getStdErr().writer(), "Option \"--table\" is required.\n\n", .{});
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    var batch_size: usize = 1000;
    if (res.args.batch) |b| {
        batch_size = b;
    }

    const allocator = std.heap.page_allocator;

    const int_columns = try parseOptionalCsv(res.args.@"int-columns", allocator);
    defer allocator.free(int_columns);

    const real_columns = try parseOptionalCsv(res.args.@"real-columns", allocator);
    defer allocator.free(real_columns);

    if (hasCommonIgnoreCaseInStringList(int_columns, real_columns)) {
        try std.fmt.format(std.io.getStdErr().writer(), "Same column is both in \"--int-columns\" and \"--real-columns\"\n\n", .{});
        return;
    }

    // const log_fmt = if (res.args.format) |fmt| blk: {
    //     if (std.ascii.eqlIgnoreCase(fmt, "ndjson")) {
    //         break :blk "ndjson";
    //     } else if (std.ascii.eqlIgnoreCase(fmt, "ltsv")) {
    //         break :blk "ltsv";
    //     } else {
    //         try std.fmt.format(std.io.getStdErr().writer(), "Option --format must take \"ndjson\" or \"ltsv\"\n\n", .{});
    //         return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    //     }
    // } else "ndjson";

    if (res.positionals.len == 0) {
        try std.fmt.format(std.io.getStdErr().writer(), "input filename must be specified as a positinnal argument.\n\n", .{});
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
    const input_filename = res.positionals[0];

    const dsn = if (res.args.db) |dsn| dsn else {
        try std.fmt.format(std.io.getStdErr().writer(), "Option \"--db\" is required.\n\n", .{});
        return showUsage(clap.Help, &params);
    };
    const db_filename = try allocator.dupeZ(u8, dsn);
    defer allocator.free(db_filename);

    const file = try std.fs.cwd().openFile(input_filename, .{});
    defer file.close();

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_filename },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    const strict_mode = res.args.@"strict-table";
    if (strict_mode) {
        try sql.enableStrictMode(&db);
    }

    var first_line_parser = ndjson.Parser{};
    defer first_line_parser.deinit(allocator);
    var line_parser = ndjson.Parser{};
    defer line_parser.deinit(allocator);

    var line_number: usize = 1;
    var line_reader = LineReader(4096){};
    const reader = file.reader();

    var stmt: ?sqlite.DynamicStatement = null;
    defer if (stmt) |*s| s.deinit();

    var savepoint: ?sqlite.Savepoint = null;
    defer if (savepoint) |*sp| sp.rollback();

    while (try line_reader.readLine(reader)) |line| {
        try line_parser.parseLine(allocator, line);

        if (line_number == 1) {
            if (!stringListContainsAllIgnoreCase(line_parser.labels.items, int_columns)) {
                try std.fmt.format(std.io.getStdErr().writer(), "columns in \"--int-columns\" not in the labels of input rows.\n\n", .{});
                return;
            }
            if (!stringListContainsAllIgnoreCase(line_parser.labels.items, real_columns)) {
                try std.fmt.format(std.io.getStdErr().writer(), "columns in \"--real-columns\" not in the labels of input rows.\n\n", .{});
                return;
            }

            const types = try buildColumnTypes(allocator, line_parser.labels.items, int_columns, real_columns);
            defer allocator.free(types);
            try sql.createTable(allocator, &db, strict_mode, table_name, line_parser.labels.items, types);
            stmt = try sql.prepareInsertLog(allocator, &db, table_name, line_parser.labels.items);
        } else {
            if (!eqlStringList(line_parser.labels.items[0..], first_line_parser.labels.items[0..])) {
                std.log.err("labels at line_number={} are different from labels at the first line", .{line_number});
            }
        }

        if (savepoint == null) {
            savepoint = try db.savepoint("insert_logs");
        }
        try sql.execInsertLog(&stmt.?, line_parser.values.items);
        if (line_number % batch_size == 0) {
            savepoint.?.commit();
            savepoint = null;
        }

        if (line_number == 1) {
            first_line_parser = line_parser;
            line_parser = ndjson.Parser{};
        }
        line_number += 1;
    }
    if (savepoint) |*sp| sp.commit();
}

// Caller must call allocator.free to return value after use.
fn buildColumnTypes(
    allocator: std.mem.Allocator,
    columns: []const []const u8,
    int_columns: []const []const u8,
    real_columns: []const []const u8,
) ![]const []const u8 {
    var types = try allocator.alloc([]const u8, columns.len);
    for (columns) |column, i| {
        const @"type" = if (stringListContainsIgnoreCase(int_columns, column))
            "INTEGER"
        else if (stringListContainsIgnoreCase(real_columns, column))
            "REAL"
        else
            "TEXT";
        types[i] = @"type";
    }
    return types;
}

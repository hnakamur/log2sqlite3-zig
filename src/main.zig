const std = @import("std");
const clap = @import("clap");
const sqlite = @import("sqlite");
const LineReader = @import("io.zig").LineReader;
const json = @import("json.zig");
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

    const allocator = std.heap.page_allocator;

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

    var first_line_labels = json.StringList{};
    defer json.deinitStringList(&first_line_labels, allocator);

    var labels = json.StringList{};
    defer json.deinitStringList(&labels, allocator);
    var values = json.StringList{};
    defer json.deinitStringList(&values, allocator);

    var line_number: usize = 1;
    var line_reader = LineReader(4096){};
    const reader = file.reader();
    var stmt: ?sqlite.DynamicStatement = null;
    defer if (stmt) |*s| s.deinit();
    while (try line_reader.readLine(reader)) |line| {
        _ = try json.parseLine(allocator, line, &labels, &values);

        if (line_number == 1) {
            try sql.createTable(allocator, &db, table_name, labels.items);
            stmt = try sql.prepareInsertLog(allocator, &db, table_name, labels.items);
        } else {
            if (!json.eqlStringList(labels.items[0..], first_line_labels.items[0..])) {
                std.log.err("labels at line_number={} are different from labels at the first line", .{line_number});
            }
        }

        try sql.execInsertLog(&stmt.?, values.items);

        if (line_number == 1) {
            first_line_labels = labels;
            labels = json.StringList{};
        } else {
            json.deinitStringListItems(&labels, allocator);
            labels.items.len = 0;
        }
        json.deinitStringListItems(&values, allocator);
        values.items.len = 0;
        line_number += 1;
    }
}

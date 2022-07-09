const std = @import("std");
const clap = @import("clap");
const sqlite = @import("sqlite");
const json = @import("json.zig");

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

    // const dsn = if (res.args.db) |dsn| dsn else {
    //     try std.fmt.format(std.io.getStdErr().writer(), "Option --db is required.\n\n", .{});
    //     return showUsage(clap.Help, &params);
    // };
    // var filename_buf = [_]u8{0} ** (std.fs.MAX_PATH_BYTES + 1);
    // const filename = try std.fmt.bufPrintZ(&filename_buf, "{s}", .{dsn});

    const file = try std.fs.cwd().openFile(input_filename, .{});
    defer file.close();

    const allocator = std.heap.page_allocator;
    var labels = json.StringList{};
    defer json.deinitStringList(&labels, allocator);
    var values = json.StringList{};
    defer json.deinitStringList(&values, allocator);

    var buffer: [4096]u8 = undefined;
    const reader = file.reader();
    var leftover: usize = 0;
    while (true) {
        var n = try reader.read(buffer[leftover..]);
        if (n == 0) {
            break;
        }
        n += leftover;
        leftover = 0;

        var pos: usize = 0;
        while (pos < n) {
            if (std.mem.indexOfScalarPos(u8, buffer[0..n], pos, '\n')) |lf_pos| {
                debug.print("line=[{s}]\n", .{buffer[pos..lf_pos]});
                _ = try json.parseLine(allocator, buffer[pos..lf_pos], &labels, &values);
                debug.print("labels=", .{});
                for (labels.items) |*label, i| {
                    if (i > 0) {
                        debug.print(", ", .{});
                    }
                    debug.print("{s}", .{label.bytes});
                }
                debug.print("\n", .{});

                debug.print("values=", .{});
                for (values.items) |*value, i| {
                    if (i > 0) {
                        debug.print(", ", .{});
                    }
                    debug.print("{s}", .{value.bytes});
                }
                debug.print("\n", .{});

                json.deinitStringListItems(&labels, allocator);
                try labels.resize(allocator, 0);
                json.deinitStringListItems(&values, allocator);
                try values.resize(allocator, 0);
                pos = lf_pos + 1;
            } else {
                if (pos == 0 and n == buffer.len) {
                    return error.TooLongJsonLine;
                }
                std.mem.copy(u8, buffer[0..], buffer[pos .. n]);
                leftover = n - pos;
                break;
            }
        }
    }
    if (leftover > 0) {
        debug.print("last_line_without_newline=[{s}]\n", .{buffer[0..leftover]});
    }

    // var db = try sqlite.Db.init(.{
    //     .mode = sqlite.Db.Mode{ .File = filename },
    //     .open_flags = .{
    //         .write = true,
    //         .create = true,
    //     },
    //     .threading_mode = .MultiThread,
    // });
    // defer db.deinit();

    // const query =
    //     \\CREATE TABLE IF NOT EXISTS table1 (col1 TEXT)
    // ;

    // var stmt = try db.prepare(query);
    // defer stmt.deinit();

    // try stmt.exec(.{}, .{});
}

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
        "Usage: {s} [options] [argsuments...]\n\n",
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

    // const allocator = std.heap.page_allocator;

    var buffer: [4096]u8 = undefined;
    const reader = file.reader();
    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) {
            break;
        }

        debug.print("{s}", .{buffer[0..n]});
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

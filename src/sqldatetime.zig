const std = @import("std");
const datetime = @import("datetime");
const Datetime = datetime.datetime.Datetime;
const Date = datetime.datetime.Date;
const Time = datetime.datetime.Time;
const Timezone = datetime.datetime.Timezone;

fn parseDatetime(buf: []const u8, now_timestamp_ms: i64, out_timezone: *Timezone, rest: *[]const u8) !Datetime {
    var p = buf;
    var has_date = false;
    var has_time = false;
    var date: Date = undefined;
    var time = Time{};
    if (p.len >= "YYYY-MM-DD".len and p[4] == '-') {
        date = try parseDate(p, &p);
        has_date = true;
        if (p.len >= 1) {
            if (p[0] == ' ' or p[0] == 'T') {
                p = p[1..];
            } else {
                return error.InvalidFormat;
            }
        }
    }

    if (p.len >= "HH:MM".len and p[2] == ':') {
        time = try parseTime(p, &p);
        has_time = true;
    }

    out_timezone.* = if (p.len > 0) try parseTimezone(p, &p) else Timezone{ .offset = 0, .name = "" };
    if (!has_date) {
        date = Datetime.fromTimestamp(now_timestamp_ms).shiftTimezone(out_timezone).date;
    }

    if (!has_date and !has_time) {
        return error.InvalidFormat;
    }

    rest.* = p;
    return Datetime{ .date = date, .time = time, .zone = out_timezone };
}

fn parseDate(buf: []const u8, rest: *[]const u8) !Date {
    if (buf.len < "YYYY-MM-DD".len or buf[4] != '-' or buf[7] != '-') {
        return error.InvalidFormat;
    }
    const year = try parseUint(buf[0..4]);
    const month = try parseUint(buf[5..7]);
    const day = try parseUint(buf[8..10]);
    rest.* = buf[10..];
    return Date.create(year, month, day);
}

fn parseTime(buf: []const u8, rest: *[]const u8) !Time {
    if (buf.len < "HH:MM".len or buf[2] != ':') {
        return error.InvalidFormat;
    }
    const hour = try parseUint(buf[0..2]);
    const minute = try parseUint(buf[3..5]);
    var second: u32 = 0;
    var nanosecond: u32 = 0;
    var pos: usize = 5;
    if (buf.len >= "HH:MM:SS".len and buf[5] == ':') {
        second = try parseUint(buf[6..8]);
        if (buf.len >= "HH:MM:SS.S".len and buf[8] == '.') {
            const frac_start = 9;
            pos = frac_start;
            // https://www.sqlite.org/lang_datefunc.html
            // only the first three digits are significant to the result, but the input string can have
            // fewer or more than three digits and the date/time functions will still operate correctly
            while (pos < std.math.min(frac_start + 3, buf.len)) : (pos += 1) {
                nanosecond *= 10;
                nanosecond += try std.fmt.charToDigit(buf[pos], 10);
            }
            var i = pos;
            while (i < frac_start + 9) : (i += 1) {
                nanosecond *= 10;
            }

            // read and throw away the following digits.
            while (pos < buf.len) : (pos += 1) {
                switch (buf[pos]) {
                    '0'...'9' => {},
                    else => break,
                }
            }
        } else {
            pos = 8;
        }
    }
    rest.* = buf[pos..];
    return Time.create(hour, minute, second, nanosecond);
}

fn parseTimezone(buf: []const u8, rest: *[]const u8) !Timezone {
    if (buf.len >= "Z".len and buf[0] == 'Z') {
        rest.* = buf[1..];
        return Timezone.create("", 0);
    }

    var neg = false;
    var pos: usize = 0;
    if (pos < buf.len) {
        switch (buf[pos]) {
            '+' => pos += 1,
            '-' => {
                neg = true;
                pos += 1;
            },
            else => {},
        }
    }
    if (pos + "HH:MM".len > buf.len or buf[pos + 2] != ':') {
        return error.InvalidFormat;
    }
    const hour = try parseUint(buf[pos .. pos + 2]);
    const minute = try parseUint(buf[pos + 3 .. pos + 5]);
    rest.* = buf[pos + 5 ..];
    const offset: i16 = @intCast(i16, hour) * 60 + @intCast(i16, minute);
    return Timezone.create("", if (neg) -offset else offset);
}

fn parseUint(buf: []const u8) error{InvalidCharacter}!u32 {
    var ret: u32 = 0;
    for (buf) |c| {
        ret *= 10;
        ret += try std.fmt.charToDigit(c, 10);
    }
    return ret;
}

const testing = std.testing;

test "parseDatetime" {
    testing.log_level = .debug;

    const ok = struct {
        fn f(input: []const u8, now_timestamp_ms: i64, want: Datetime, want_rest: []const u8) !void {
            var rest: []const u8 = undefined;
            var got_timezone: Timezone = undefined;
            var got = try parseDatetime(input, now_timestamp_ms, &got_timezone, &rest);
            try testing.expect(got.eql(want));
            try testing.expectEqualStrings(want_rest, rest);
        }
    }.f;

    const ng = struct {
        fn f(input: []const u8, now_timestamp_ms: i64, want: anyerror) !void {
            var rest: []const u8 = undefined;
            var got_timezone: Timezone = undefined;
            try testing.expectError(want, parseDatetime(input, now_timestamp_ms, &got_timezone, &rest));
        }
    }.f;

    const utc = Timezone{ .offset = 0, .name = "" };
    const now_timestamp_ms_utc = @intCast(i64, (Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 14 },
        .time = .{ .hour = 23, .minute = 59, .second = 7 },
        .zone = &utc,
    }).toTimestamp());

    const jst = Timezone{ .offset = 540, .name = "" };
    const now_timestamp_ms_jst = @intCast(i64, (Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 14 },
        .time = .{ .hour = 8, .minute = 59, .second = 7 },
        .zone = &jst,
    }).toTimestamp());

    try ok("2022-07-13", now_timestamp_ms_utc, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 13 },
        .time = .{},
        .zone = &utc,
    }, "");

    try ok("2022-07-13 23:59:07", now_timestamp_ms_utc, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 13 },
        .time = .{ .hour = 23, .minute = 59, .second = 7 },
        .zone = &utc,
    }, "");

    try ok("2022-07-13T23:59:07", now_timestamp_ms_utc, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 13 },
        .time = .{ .hour = 23, .minute = 59, .second = 7 },
        .zone = &utc,
    }, "");

    try ok("23:59:07", now_timestamp_ms_utc, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 14 },
        .time = .{ .hour = 23, .minute = 59, .second = 7 },
        .zone = &utc,
    }, "");

    try ok("2022-07-13 23:59:07.1234+09:00", now_timestamp_ms_jst, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 13 },
        .time = .{ .hour = 23, .minute = 59, .second = 7, .nanosecond = 123_000_000 },
        .zone = &jst,
    }, "");

    try ok("23:59:07+09:00", now_timestamp_ms_jst, Datetime{
        .date = .{ .year = 2022, .month = 7, .day = 14 },
        .time = .{ .hour = 23, .minute = 59, .second = 7 },
        .zone = &jst,
    }, "");

    try ng("", 0, error.InvalidFormat);
}

test "parseDate" {
    var rest: []const u8 = undefined;
    var date = try parseDate("2022-07-14", &rest);
    try testing.expect(date.eql(Date{ .year = 2022, .month = 7, .day = 14 }));
    try testing.expectEqualStrings("", rest);
}

test "parseTime" {
    testing.log_level = .debug;

    const ok = struct {
        fn f(input: []const u8, want: Time, want_rest: []const u8) !void {
            var rest: []const u8 = undefined;
            var got = try parseTime(input, &rest);
            try testing.expect(got.eql(want));
            try testing.expectEqualStrings(want_rest, rest);
        }
    }.f;

    const ng = struct {
        fn f(input: []const u8, want: anyerror) !void {
            var rest: []const u8 = undefined;
            try testing.expectError(want, parseTime(input, &rest));
        }
    }.f;

    try ok("23:59:07", Time{ .hour = 23, .minute = 59, .second = 7 }, "");
    try ok("23:59:07.12", Time{ .hour = 23, .minute = 59, .second = 7, .nanosecond = 120_000_000 }, "");
    try ok("23:59:07.123", Time{ .hour = 23, .minute = 59, .second = 7, .nanosecond = 123_000_000 }, "");
    try ok("23:59:07.1234567890", Time{ .hour = 23, .minute = 59, .second = 7, .nanosecond = 123_000_000 }, "");

    try ok("23:59:07.", Time{ .hour = 23, .minute = 59, .second = 7, .nanosecond = 0 }, ".");

    try ng("", error.InvalidFormat);
    try ng("23:XX", error.InvalidCharacter);
    try ng("23!59", error.InvalidFormat);
}

test "parseTimezone" {
    testing.log_level = .debug;

    const ok = struct {
        fn f(input: []const u8, want_offset: i16, want_rest: []const u8) !void {
            var rest: []const u8 = undefined;
            var got = try parseTimezone(input, &rest);
            try testing.expectEqual(want_offset, got.offset);
            try testing.expectEqualStrings(want_rest, rest);
        }
    }.f;

    const ng = struct {
        fn f(input: []const u8, want: anyerror) !void {
            var rest: []const u8 = undefined;
            try testing.expectError(want, parseTimezone(input, &rest));
        }
    }.f;

    try ok("Z", 0, "");
    try ok("09:00", 540, "");
    try ok("+09:00", 540, "");
    try ok("-03:30", -210, "");

    try ng("", error.InvalidFormat);
    try ng("23:XX", error.InvalidCharacter);
    try ng("23!59", error.InvalidFormat);
}

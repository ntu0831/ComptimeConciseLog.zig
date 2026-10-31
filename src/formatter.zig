const std = @import("std");

const c = @import("config.zig");
const t = @import("time.zig");

const DateTime = t.DateTime;
const TimeZone = t.TimeZone;
const Options = c.Options;
const UserFormatter = c.UserFormatter;
const TimeZoneOffset = c.TimeZoneOffset;

pub fn Formatter(options: Options) type {
    return struct {
        timezone: TimeZoneOffset = .utc,

        pub fn exec(
            self: @This(),
            level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
            w: *std.Io.Writer,
            allocator: std.mem.Allocator,
            io: std.Io,
            ts: std.Io.Timestamp,
        ) std.Io.Writer.Error!void {
            const tokens = options.pattern.tokens;

            const pattern_has_datetime: bool = comptime blk: {
                break :blk for (tokens) |token| {
                    if (token.needDateTime()) break true;
                } else false;
            };
            const pattern_has_timezone: bool = comptime blk: {
                break :blk for (tokens) |token| {
                    if (token.needTimeZone()) break true;
                } else false;
            };

            const Date = if (pattern_has_datetime) DateTime.RFC3339 else void;
            const date: Date = if (pattern_has_datetime) switch (self.timezone) {
                .utc => .fromTimestamp(ts.toNanoseconds()),
                .local => |offset| .fromTimestamp(ts.toNanoseconds() + (offset * std.time.ns_per_s)),
            } else {};

            const TZ = if (pattern_has_timezone) TimeZone else void;
            const tz: TZ = if (pattern_has_timezone) switch (self.timezone) {
                .utc => .fromSeconds(0),
                .local => |offset| .fromSeconds(offset),
            } else {};

            inline for (tokens) |token| switch (token) {
                .literal => |str| try w.writeAll(str),
                .custom => |id| if (options.pattern.formatter) |f| try f(.{
                    .ts = ts,
                    .id = id,
                    .io = io,
                    .gpa = allocator,
                    .writer = w,
                    .level = level,
                }, format, args) else @compileError("userFormatter is null"),

                .msg => try w.print(format, args),
                .scope => try w.writeAll(@tagName(scope)),
                .level_full => try w.writeAll(fullLabel(level)),
                .level_short => try w.writeByte(shortLabel(level)),

                .year_4 => try w.print("{d:0>4}", .{date.year}),
                .year_2 => try w.print("{d:0>2}", .{date.year % 100}),
                .month => try w.print("{d:0>2}", .{date.month}),
                .day => try w.print("{d:0>2}", .{date.day}),
                .hour_24 => try w.print("{d:0>2}", .{date.hour}),
                .minute => try w.print("{d:0>2}", .{date.minute}),
                .second => try w.print("{d:0>2}", .{date.second}),
                .time => try w.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ date.hour, date.minute, date.second }),
                .date => try w.print("{d:0>2}/{d:0>2}/{d:0>2}", .{ date.month, date.day, date.year % 100 }),
                .zone => try tz.formatStrftimeZ(w),
                .zone_gnu => try tz.formatRFC3339(w),

                .millisecond => try w.print("{d:0>3}", .{date.millisecond}),
                .microsecond => try w.print("{d:0>3}", .{date.microsecond}),
                .nanosecond => try w.print("{d:0>3}", .{date.nanosecond}),

                .rfc3339 => try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{d:0>3}{d:0>3}{f}", .{
                    date.year,        date.month,       date.day,
                    date.hour,        date.minute,      date.second,
                    date.millisecond, date.microsecond, date.nanosecond,
                    tz,
                }),
                .rfc3339zulu => try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{d:0>3}{d:0>3}Z", .{
                    date.year,        date.month,       date.day,
                    date.hour,        date.minute,      date.second,
                    date.millisecond, date.microsecond, date.nanosecond,
                }),
            };

            try w.writeByte('\n');
        }
    };
}

fn fullLabel(level: std.log.Level) []const u8 {
    return switch (level) {
        .err => "error",
        .warn => "warning",
        .info => "info",
        .debug => "debug",
    };
}

fn shortLabel(level: std.log.Level) u8 {
    return switch (level) {
        .err => 'E',
        .warn => 'W',
        .info => 'I',
        .debug => 'D',
    };
}

test {
    _ = @import("./tests/formatter.zig");
}

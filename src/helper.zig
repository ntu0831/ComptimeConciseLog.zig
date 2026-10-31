const std = @import("std");

const logger = @import("logger.zig");

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    logger.log(level, scope, format, args);
}

pub const getBaseUtcOffset = @import("localtime.zig").getBaseUtcOffset;

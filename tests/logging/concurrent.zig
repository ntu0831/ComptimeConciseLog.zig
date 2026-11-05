const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.logging);

pub const cclog_options: cclog.Options = .{
    .pattern = .parse("{@msg}"),
    .mode = .{ .concurrent = .{} },
};

fn test_by_self_call(init: std.process.Init, comptime config: Config) !void {
    const expected: usize = (config.content.len + 1) * config.repeat * config.concurrency;
    var w: std.Io.Writer.Discarding = .init(&.{});
    try cclog.init(init.io, init.gpa, .{ .output = .{ .writer = &w.writer } });
    for (0..config.repeat) |_| Log.info("{s}", .{config.content});
    cclog.deinit(init.io);
    try expectEqual(expected, w.fullCount());
}

fn test_by_async_call(init: std.process.Init, comptime config: Config) !void {
    const expected: usize = (config.content.len + 1) * config.repeat * config.concurrency;
    var w: std.Io.Writer.Discarding = .init(&.{});
    try cclog.init(init.io, init.gpa, .{ .output = .{ .writer = &w.writer } });
    var group: std.Io.Group = .init;
    for (0..config.concurrency) |_| group.async(init.io, log, .{ config.content, config.repeat });
    try group.await(init.io);
    cclog.deinit(init.io);
    try expectEqual(expected, w.fullCount());
}

fn test_by_concurrent_call(init: std.process.Init, comptime config: Config) !void {
    const expected: usize = (config.content.len + 1) * config.repeat * config.concurrency;
    var w: std.Io.Writer.Discarding = .init(&.{});
    try cclog.init(init.io, init.gpa, .{ .output = .{ .writer = &w.writer } });
    var group: std.Io.Group = .init;
    for (0..config.concurrency) |_| try group.concurrent(init.io, log, .{ config.content, config.repeat });
    try group.await(init.io);
    cclog.deinit(init.io);
    try expectEqual(expected, w.fullCount());
}

fn test_with_concurrcy(init: std.process.Init, comptime config: Config) !void {
    try test_by_async_call(init, config);
    try test_by_concurrent_call(init, config);
}

fn test_with_non_concurrcy(init: std.process.Init, comptime config: Config) !void {
    try test_by_self_call(init, config);
    try test_by_async_call(init, config);
    try test_by_concurrent_call(init, config);
}

fn test_log_one(init: std.process.Init, comptime content: []const u8) !void {
    const repeat = 1;
    try test_with_non_concurrcy(init, .{
        .concurrency = 1,
        .repeat = repeat,
        .content = content,
    });
    try test_with_concurrcy(init, .{
        .concurrency = 3,
        .repeat = repeat,
        .content = content,
    });
}

fn test_log_multi(init: std.process.Init, comptime content: []const u8) !void {
    const repeat = 100;
    try test_with_non_concurrcy(init, .{
        .concurrency = 1,
        .repeat = repeat,
        .content = content,
    });
    try test_with_concurrcy(init, .{
        .concurrency = 3,
        .repeat = repeat,
        .content = content,
    });
}

fn test_log_short(init: std.process.Init) !void {
    const content = "0123456789";
    try test_log_one(init, content);
    try test_log_multi(init, content);
}

fn test_log_long(init: std.process.Init) !void {
    const content = comptime repeatStr("0123456789", 800);
    try test_log_one(init, content);
    try test_log_multi(init, content);
}

pub fn main(init: std.process.Init) !void {
    try test_log_short(init);
    try test_log_long(init);
}

const Config = struct {
    repeat: usize,
    content: []const u8,
    concurrency: usize,
};

fn log(str: []const u8, repeat: usize) void {
    for (0..repeat) |_| Log.info("{s}", .{str});
}

fn repeatStr(comptime str: []const u8, comptime repeat: usize) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (0..repeat) |_| s = s ++ str;
        const result = s;
        return result;
    }
}

const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.single_produer);

fn logLoop() !void {
    for (0..100) |i| Log.info("{s} {d}", .{ "test single producer", i });
}

test "looplog_with_self" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try cclog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var f = std.Io.async(io, logLoop, .{});
    try f.await(io);

    cclog.deinit(io);

    try expectEqual(7790, w.fullCount());
}

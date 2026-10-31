const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.multi_producer);

fn log() !void {
    Log.info("{s}", .{"test multi producer"});
}

test "onelog_with_async" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try cclog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var group: std.Io.Group = .init;
    for (0..3) |_| try group.concurrent(io, log, .{});
    try group.await(io);

    cclog.deinit(io);

    try expectEqual(222, w.fullCount());
}

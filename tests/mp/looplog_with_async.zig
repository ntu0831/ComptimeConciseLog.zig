const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.multi_producer);

fn logLoop() !void {
    for (0..100) |i| Log.info("{s} {d}", .{ "test multi producer", i });
}

test "onelog_with_async" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try cclog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var group: std.Io.Group = .init;
    for (0..3) |_| group.async(io, logLoop, .{});
    try group.await(io);

    cclog.deinit(io);

    try expectEqual(23070, w.fullCount());
}

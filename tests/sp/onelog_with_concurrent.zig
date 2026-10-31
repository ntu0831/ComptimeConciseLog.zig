const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.single_produer);

fn log() !void {
    Log.info("{s}", .{"test single producer"});
}

test "onelog with concurrent" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try cclog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var f = try std.Io.concurrent(io, log, .{});
    try f.await(io);

    cclog.deinit(io);

    try expectEqual(75, w.fullCount());
}

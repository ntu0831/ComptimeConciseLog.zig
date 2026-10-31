const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = cclog.Log(.api);

test "log before init" {
    Log.err("{s}", .{"test api"});
    Log.warn("{s}", .{"test api"});
    Log.info("{s}", .{"test api"});
    Log.debug("{s}", .{"test api"});
    var w: std.Io.Writer.Discarding = .init(&.{});
    try cclog.init(io, gpa, .{ .output = .{ .writer = &w.writer } });
    cclog.deinit(io);
}

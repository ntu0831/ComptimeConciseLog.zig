const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.pool_buf_exhaustion);

pub const cclog_options: cclog.Options = .{
    .pattern = .parse("{@msg}"),
    .mode = .{
        .async = .{
            .on_pool_exhausted = .drop,
            .buffer = .{ .count = 2, .size = 4 },
        },
    },
};

fn test_drop(init: std.process.Init) !void {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try cclog.init(init.io, init.gpa, .{
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"1234567890"});
    cclog.deinit(init.io);

    try expectEqual(0, w.fullCount());
}

pub fn main(init: std.process.Init) !void {
    try test_drop(init);
}

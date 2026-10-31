const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const expectEqual = std.testing.expectEqual;

const Log = cclog.Log(.pool_buf_exhaustion);

pub const cclog_options: cclog.Options = .{
    .max_buffers_per_record = 2,
    .pattern = .parse("{@msg}"),
    .mode = .{
        .async = .{
            .on_record_exhausted = .drop,
            .buffer = .{ .count = 16, .size = 4 },
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

const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const expectEqualStrings = std.testing.expectEqualStrings;

const Log = cclog.Log(.pool_buf_exhaustion);

pub const cclog_options: cclog.Options = .{
    .pattern = .parse("{@msg}"),
    .mode = .{
        .async = .{
            .on_pool_exhausted = .truncate,
            .buffer = .{ .count = 2, .size = 4 },
        },
    },
};

fn test_truncate(init: std.process.Init) !void {
    var w: std.Io.Writer.Allocating = .init(init.gpa);
    defer w.deinit();

    try cclog.init(init.io, init.gpa, .{
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"1234567890"});
    cclog.deinit(init.io);

    try expectEqualStrings("12345678\n", w.written());
}

pub fn main(init: std.process.Init) !void {
    try test_truncate(init);
}

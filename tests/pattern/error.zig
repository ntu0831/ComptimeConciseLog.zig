const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const expectEqualStrings = std.testing.expectEqualStrings;

const Log = cclog.Log(.pattern);

pub const cclog_options: cclog.Options = .{
    .pattern = .parse("{#id}"),
};

fn test_error(init: std.process.Init) !void {
    var w: std.Io.Writer.Allocating = .init(init.gpa);
    defer w.deinit();

    try cclog.init(init.io, init.gpa, .{
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    cclog.deinit(init.io);
}

pub fn main(init: std.process.Init) !void {
    try test_error(init);
}

const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const expectEqualStrings = std.testing.expectEqualStrings;

const Log = cclog.Log(.pattern);

pub const cclog_options: cclog.Options = .{
    .pattern = .parseWithFormatter("{#test}", formatter),
};

pub fn formatter(ctx: cclog.config.UserFormatterContext, comptime format: []const u8, args: anytype) std.Io.Writer.Error!void {
    if (std.mem.eql(u8, ctx.id, "test")) {
        try ctx.writer.print("{s}", .{"hello"});
    }
    _ = format;
    _ = args;
}

fn test_formatter(init: std.process.Init) !void {
    var w: std.Io.Writer.Allocating = .init(init.gpa);
    defer w.deinit();

    try cclog.init(init.io, init.gpa, .{
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    cclog.deinit(init.io);

    try expectEqualStrings("hello\n", w.written());
}

pub fn main(init: std.process.Init) !void {
    try test_formatter(init);
}

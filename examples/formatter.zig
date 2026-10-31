const std = @import("std");
const cclog = @import("ComptimeConciseLog");

pub const cclog_options: cclog.Options = .{
    .pattern = .parseWithFormatter("{#ts} {#level} {#msg}", formatter),
};

fn formatter(ctx: cclog.config.UserFormatterContext, comptime format: []const u8, args: anytype) std.Io.Writer.Error!void {
    if (std.mem.eql(u8, ctx.id, "ts")) try ctx.writer.print("{d}", .{ctx.ts});
    if (std.mem.eql(u8, ctx.id, "level")) try ctx.writer.print("{d}", .{@backingInt(ctx.level)});
    if (std.mem.eql(u8, ctx.id, "msg")) try ctx.writer.print(format, args);
}

const Log = cclog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try cclog.init(init.io, init.gpa, .{});
    defer cclog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}

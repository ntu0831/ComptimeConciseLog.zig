const std = @import("std");
const cclog = @import("ComptimeConciseLog");

pub const cclog_options: cclog.Options = .{
    // python logging style
    // %(asctime)s - %(name)s - %(levelname)s - %(message)s
    // 2005-03-19 15:10:26,618 - simple_example - DEBUG - debug message
    .pattern = .parse("{%Y}-{%m}-{%d} {%T},{@ms} - {@scope} - {@level} - {@msg}"),
};

const Log = cclog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try cclog.init(init.io, init.gpa, .default);
    defer cclog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}

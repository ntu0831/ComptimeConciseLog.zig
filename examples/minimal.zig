const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const Log = cclog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try cclog.init(init.io, init.gpa, .default);
    defer cclog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}

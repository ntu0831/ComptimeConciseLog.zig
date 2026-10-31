const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = cclog.Log(.api);

test "deinit before init" {
    cclog.deinit(io); // focus
    try cclog.init(io, gpa, .default);
    cclog.deinit(io);
}

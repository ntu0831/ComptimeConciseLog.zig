const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = cclog.Log(.api);

test "init after deinit" {
    try cclog.init(io, gpa, .default);
    cclog.deinit(io);
    try cclog.init(io, gpa, .default); // focus
    cclog.deinit(io);
}

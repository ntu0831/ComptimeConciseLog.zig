const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectError = std.testing.expectError;

const Log = cclog.Log(.aapi);

test "double init after deinit" {
    try cclog.init(io, gpa, .default);
    cclog.deinit(io);
    try cclog.init(io, gpa, .default);
    defer cclog.deinit(io);
    try expectError(error.Initialized, cclog.init(io, gpa, .default));
}

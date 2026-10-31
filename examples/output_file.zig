const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const msgs_per_worker = 100;

pub fn main(init: std.process.Init) !void {
    try cclog.init(init.io, init.gpa, .{
        .output = .{ .file = .{ .path = "log.txt" } },
    });
    defer cclog.deinit(init.io);

    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    try group.concurrent(init.io, workerTaskA, .{init.io});
    try group.concurrent(init.io, workerTaskB, .{init.io});
    try group.await(init.io);
}

fn workerTaskA(io: std.Io) std.Io.Cancelable!void {
    const Log = cclog.Log(.TaskA);
    for (0..msgs_per_worker) |i| {
        Log.info("processing item {d}", .{i});
        if (i % 25 == 0) try io.sleep(.fromMilliseconds(2), .awake);
    }
}

fn workerTaskB(io: std.Io) std.Io.Cancelable!void {
    const Log = cclog.Log(.TaskB);
    for (0..msgs_per_worker) |i| {
        switch (i % 4) {
            0 => Log.err("processing item {d}", .{i}),
            1 => Log.warn("processing item {d}", .{i}),
            2 => Log.info("processing item {d}", .{i}),
            else => Log.debug("processing item {d}", .{i}),
        }
        if (i % 25 == 0) try io.sleep(.fromMilliseconds(2), .awake);
    }
}

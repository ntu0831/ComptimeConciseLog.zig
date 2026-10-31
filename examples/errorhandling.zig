const std = @import("std");
const cclog = @import("ComptimeConciseLog");

const Log = cclog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try FailingWriter.main(init);
    try FileWriter.main(init);
}

const FailingWriter = struct {
    pub fn errorHandler(_: std.Io, _: *std.Io.Writer) void {
        std.debug.print("{s}", .{"FaillingWriter Error\n"});
    }

    fn main(init: std.process.Init) !void {
        var writer = std.Io.Writer.failing;

        try cclog.init(init.io, init.gpa, .{
            .errhandler = .{ .func = errorHandler },
            .output = .{ .writer = &writer },
        });
        defer cclog.deinit(init.io);

        Log.info("{s}", .{"done"});
    }
};

const FileWriter = struct {
    fn errorHandler(_: std.Io, w: *std.Io.Writer) void {
        const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", w));
        if (fw.err) |e| std.debug.print("FileWriter Error: {}\n", .{e});
        cclog.disable();
    }

    fn main(init: std.process.Init) !void {
        const tmpfile = try std.Io.Dir.cwd().createFile(init.io, "log.txt", .{});
        defer tmpfile.close(init.io);

        const logfile = try std.Io.Dir.cwd().openFile(init.io, "log.txt", .{ .mode = .read_only });
        defer logfile.close(init.io);

        var writer = logfile.writer(init.io, &.{});

        try cclog.init(init.io, init.gpa, .{
            .errhandler = .{ .func = errorHandler },
            .output = .{ .writer = &writer.interface },
        });
        defer cclog.deinit(init.io);

        Log.info("{s}", .{"done"});
    }
};

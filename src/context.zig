const std = @import("std");

const c = @import("config.zig");

const options = c.options;
const Config = c.Config;
const PoolExhaustionPolicy = c.PoolExhaustionPolicy;
const RecordExhaustionPolicy = c.RecordExhaustionPolicy;
const ErrorHandler = c.ErrorHandler;
const RawOutputWriter = @import("writer.zig").RawOutputWriter;
const Formatter = @import("formatter.zig").Formatter;
const Metrics = @import("metrics.zig").Metrics;

pub const LogEvent = []u8;

const Pool = struct {
    free: std.Io.Queue(LogEvent) = undefined,
    pending: std.Io.Queue(LogEvent) = undefined,
    size: usize = 0,
};

const RunMode = union(enum) {
    blocking: Blocking,
    non_blocking: NonBlocking,

    pub const Blocking = struct {
        writer_mutex: std.Io.Mutex = .init,
    };

    pub const NonBlocking = struct {
        pool: Pool,
        pool_policy: PoolExhaustionPolicy,
        record_policy: RecordExhaustionPolicy,
        tasks: std.Io.Group = .init,
        running: bool = false, // run tasks
        kind: enum { async, concurrent } = .concurrent,
    };
};

pub const OutputWriter = struct {
    interface: *std.Io.Writer,
    kind: Kind,
    errorhandler: ErrorHandler = undefined,

    const Kind = enum {
        custom,
        stdout,
        stderr,
        file,
    };
};

const Data = switch (options.mode) {
    .sync => BlockingData,
    .async, .concurrent => NonBlockingData,
};

const BlockingData = struct {
    writer_mutex: std.Io.Mutex = .init,
};

const NonBlockingData = struct {
    pool: Pool,
    tasks: std.Io.Group = .init,
    running: bool = false, // run tasks
    kind: enum { async, concurrent } = .concurrent,
};

pub const Context = struct {
    inited: bool = init_inited, // init resource

    level: std.atomic.Value(i8) = init_level,

    io: std.Io,
    arena: std.heap.ArenaAllocator,

    metrics: Metrics = .{},

    ow: OutputWriter,
    formatter: Formatter(options) = .{},
    data: Data,

    const init_inited: bool = false;
    const init_level: std.atomic.Value(i8) = .init(-1);

    pub fn deinit(self: *@This()) void {
        if (self.inited == false) return;

        const io = self.io;

        if (options.mode != .sync) {
            self.data.pool.free.close(io);
            self.data.pool.pending.close(io);
            self.data.tasks.cancel(io);
            self.ow.interface.flush() catch {}; // TODO need call errorhandler?
        }

        switch (self.ow.kind) {
            .stderr, .stdout => {
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", self.ow.interface));
                const row: *RawOutputWriter.Stdio = @alignCast(@fieldParentPtr("fw", fw));
                row.deinit(self.arena.allocator());
            },
            .file => {
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", self.ow.interface));
                const row: *RawOutputWriter.File = @alignCast(@fieldParentPtr("fw", fw));
                row.deinit(self.arena.allocator(), self.io);
            },
            .custom => {},
        }

        var arena = self.arena;
        arena.deinit();

        self.inited = init_inited;
        self.level = init_level;
    }

    pub fn init(io: std.Io, alloc: std.mem.Allocator, config: Config) !@This() {
        var ctx_arena: std.heap.ArenaAllocator = .init(alloc);
        errdefer ctx_arena.deinit();
        const arena = ctx_arena.allocator();

        var ow: OutputWriter = switch (config.output) {
            .stdout => |cfg| stdout: {
                const ow = try arena.create(RawOutputWriter.Stdio);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, .stdout, cfg.bufsize);
                errdefer ow.deinit(arena);
                break :stdout .{ .interface = ow.writer(), .kind = .stdout };
            },
            .stderr => |cfg| stderr: {
                const ow = try arena.create(RawOutputWriter.Stdio);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, .stderr, cfg.bufsize);
                errdefer ow.deinit(arena);
                break :stderr .{ .interface = ow.writer(), .kind = .stderr };
            },
            .file => |cfg| file: {
                const ow = try arena.create(RawOutputWriter.File);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, cfg.path, cfg.bufsize);
                errdefer ow.deinit(arena, io);
                break :file .{ .interface = ow.writer(), .kind = .file };
            },
            .writer => |interface| .{
                .interface = interface,
                .kind = .custom,
            },
        };
        ow.errorhandler = config.errhandler;

        const data: Data = switch (options.mode) {
            inline .sync => .{},
            inline .async, .concurrent => |cfg| .{
                .kind = switch (options.mode) {
                    inline .async => .async,
                    inline .concurrent => .concurrent,
                    inline else => unreachable,
                },
                .pool = blk: {
                    std.debug.assert(cfg.buffer.count != 0);
                    std.debug.assert(cfg.buffer.size != 0);
                    if (cfg.on_pool_exhausted == .block) std.debug.assert(options.max_buffers_per_record <= cfg.buffer.count);

                    const size = cfg.buffer.size;
                    const count = cfg.buffer.count;
                    const pool_buffer_storage = try arena.alloc(u8, size * count);
                    errdefer arena.free(pool_buffer_storage);
                    const pool_free_storage = try arena.alloc(LogEvent, count);
                    errdefer arena.free(pool_free_storage);
                    const pool_pending_storage = try arena.alloc(LogEvent, count);
                    errdefer arena.free(pool_pending_storage);

                    var free_pool_buf = try arena.alloc([]u8, count);
                    defer arena.free(free_pool_buf);
                    for (0..count) |idx| {
                        const baseline = idx * size;
                        free_pool_buf[idx] = pool_buffer_storage[baseline .. baseline + size];
                    }
                    var free: std.Io.Queue(LogEvent) = .init(pool_free_storage);
                    _ = free.putUncancelable(io, free_pool_buf, free_pool_buf.len) catch unreachable;

                    break :blk .{
                        .size = size,
                        .pending = .init(pool_pending_storage),
                        .free = free,
                    };
                },
            },
        };

        return .{
            .io = io,
            .arena = ctx_arena,
            .ow = ow,
            .inited = true,
            .data = data,
            .level = .init(@backingInt(config.level)),
            .formatter = .{ .timezone = config.timezone },
        };
    }

    pub fn start(self: *@This()) !void {
        if (options.mode == .sync) return;
        if (self.inited == false) return;

        const io = self.io;
        switch (options.mode) {
            inline .async => self.data.tasks.async(io, loop, .{self}),
            inline .concurrent => try self.data.tasks.concurrent(io, loop, .{self}),
            inline else => unreachable,
        }
        self.data.running = true;
    }

    pub fn setLevel(self: *@This(), level: std.log.Level) void {
        self.level.store(@backingInt(level), .monotonic);
    }

    pub fn disable(self: *@This()) void {
        self.level.store(-1, .monotonic);
    }
};

/// writer loop
fn loop(ctx: *Context) void {
    const io = ctx.io;
    const ow = ctx.ow;
    const writer = ow.interface;

    const pending = &ctx.data.pool.pending;
    const free = &ctx.data.pool.free;

    // Protect the write call from cancellation
    const old_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_protection);

    var storage: [options.max_buffers_per_batch][]u8 = undefined;

    while (true) {
        const count = pending.getUncancelable(io, &storage, 1) catch |e| switch (e) {
            error.Closed => return,
        };
        const valid = storage[0..count];
        defer _ = free.putUncancelable(io, valid, count) catch |e| switch (e) {
            error.Closed => {},
        };

        writer.writeVecAll(@ptrCast(valid)) catch ow.errorhandler.func(io, writer);
    }
}

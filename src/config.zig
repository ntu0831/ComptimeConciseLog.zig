const std = @import("std");

const root = @import("root");
const p = @import("pattern.zig");
const h = @import("helper.zig");
const PatternToken = p.PatternToken;

/// Compile-time settings, overridable by the root source file.
pub const options: Options = if (@hasDecl(root, "ComptimeConciseLog_options"))
    root.ComptimeConciseLog_options
else if (@hasDecl(root, "comptimeconciselog_options"))
    root.comptimeconciselog_options
else if (@hasDecl(root, "cclog_options"))
    root.cclog_options
else
    .{};

pub const Options = struct {
    /// The maximum number of blocks one log record may occupy.
    ///
    /// A record that needs one more block is handled according to
    /// `AsyncConfig.on_record_exhausted`. The blocks a record holds are
    /// returned to the pool once the record has been written.
    max_buffers_per_record: usize = 16,

    /// The maximum number of blocks the writer task takes from the pending
    /// queue in one batch, i.e. the upper bound of a single write burst.
    max_buffers_per_batch: usize = 16,

    pattern: Pattern = .default,

    mode: RunningMode = .default,
};

/// Settings accepted by `ComptimeConciseLog.init`.
///
/// Every field is read once during initialization; mutating a `Config` after
/// the logger has been initialized has no effect. The log level is the only
/// setting that can be changed while the logger is running, see
/// `ComptimeConciseLog.setLevel` and `ComptimeConciseLog.disable`.
///
/// Example:
/// ```
/// try ComptimeConciseLog.init(io, gpa, .{
///     .level = .debug,
///     .output = .{ .file = .{ .path = "app.log" } },
/// });
/// ```
pub const Config = struct {
    level: Level = std.log.default_level,

    output: Output = .default,

    errhandler: ErrorHandler = .default,

    timezone: TimeZoneOffset = .default,

    pub const default: Config = .{};
};

pub const Level = std.log.Level;

/// How a log call delivers its record to the output.
///
/// In the `sync` mode the record has reached the destination by the time the
/// call returns. The other two modes only queue the record, so the call
/// returns before the write happens and a full queue is handled according to
/// the policies in `AsyncConfig`.
pub const RunningMode = union(enum) {
    /// Format and write the record on the calling thread.
    ///
    /// Concurrent calls are serialized, so their records never interleave. Use
    /// this when the output is cheap, or when records must not be lost when
    /// the process exits abruptly.
    sync,

    async: AsyncConfig,

    concurrent: AsyncConfig,

    pub const default: @This() = .{ .concurrent = .default };
};

/// Settings for the `async` and `concurrent` running modes.
///
/// A record is formatted into blocks borrowed from `buffer` and submitted to
/// the writer task. `on_pool_exhausted` decides what happens when the pool is
/// empty, and `on_record_exhausted` what happens when a single record has used
/// up its quota.
pub const AsyncConfig = struct {
    /// The pool of blocks that formatted records are built from.
    buffer: BufferPool = .default,

    /// What to do when the pool has no free block left.
    ///
    /// The writer task returns blocks to the pool, so in `block` mode a record
    /// can always make progress eventually.
    on_pool_exhausted: PoolExhaustionPolicy = .block,

    /// What to do when a record already holds `max_buffers_per_record` blocks
    /// and needs one more.
    on_record_exhausted: RecordExhaustionPolicy = .truncate,

    const default: @This() = .{};

    /// The fixed-size buffers that formatted records are built in.
    ///
    /// The pool holds `count` blocks of `size` bytes each. A block is owned by one
    /// record at a time, which lets the writer task read a finished block without
    /// copying it out.
    pub const BufferPool = struct {
        /// Size of one block in bytes.
        size: usize = 4096,

        /// Number of blocks in the pool.
        count: usize = 32,

        /// A pool with the default block size and block count.
        pub const default: BufferPool = .{};
    };
};

/// What a log call does when `BufferPool` has no free block.
pub const PoolExhaustionPolicy = enum {
    /// Wait until the writer task returns a block, then continue.
    ///
    /// The record is written in full, at the cost of blocking the caller.
    block,

    /// Give up and discard the whole record.
    ///
    /// Blocks already taken by the call are returned to the pool, so nothing
    /// of this record is printed.
    drop,

    /// Stop formatting and hand over what has been formatted so far.
    ///
    /// Blocks already taken stay with the partial record and are returned
    /// after it is written; the rest of the record is not printed.
    truncate,
};

/// What a log call does when the record has used `max_buffers_per_record`
/// blocks and needs another one.
///
/// Waiting cannot help here, because the quota does not grow while the record
/// is being formatted, so the call either drops the record or prints what fits.
pub const RecordExhaustionPolicy = enum {
    /// Discard the record; nothing is printed.
    drop,

    /// Print the part of the record that fits in the quota.
    truncate,
};

pub const UserFormatterContext = struct {
    level: std.log.Level,
    ts: std.Io.Timestamp,
    writer: *std.Io.Writer,
    id: []const u8,
    io: std.Io,
    gpa: std.mem.Allocator,
};

pub const UserFormatter = fn (ctx: UserFormatterContext, comptime format: []const u8, args: anytype) std.Io.Writer.Error!void;

/// The layout of a formatted record, parsed from a pattern string at compile
/// time.
///
/// A pattern is literal text with fields following this format:
/// ```
/// {@name}   built-in field
/// {%field}  strftime field
/// {#id}     custom field
/// ```
///
/// The examples below assume a `.utc` time zone, scope `main`, level `.info`,
/// and the timestamp `2014-10-02T15:01:23.045123456Z`.
///
/// Built-in fields:
/// - `{@msg}`: the message, rendered from the log call's `format` and `args`,
///   e.g. `starting up`
/// - `{@scope}`: the scope of the logging namespace, e.g. `main`
/// - `{@level}`: the level in full and lowercase, e.g. `info`
/// - `{@LEVEL}`: the level as one uppercase letter, e.g. `I`
/// - `{@RFC3339}`: date and time with the numeric offset of `timezone`, e.g.
///   `2014-10-02T15:01:23.045123456+00:00`
/// - `{@RFC3339Z}`: date and time with a `Z` suffix, e.g.
///   `2014-10-02T15:01:23.045123456Z`
/// - `{@ms}`, `{@us}`, `{@ns}`: the sub-second part of the timestamp, three
///   digits each, e.g. `045`, `123`, `456`
///
/// `strftime` fields:
/// - `{%Y}`: four-digit year, e.g. `2014`
/// - `{%y}`: two-digit year, e.g. `14`
/// - `{%m}`: month, e.g. `10`
/// - `{%d}`: day of the month, e.g. `02`
/// - `{%H}`: hour, e.g. `15`
/// - `{%M}`: minute, e.g. `01`
/// - `{%S}`: second, e.g. `23`
/// - `{%T}`: `{%H}:{%M}:{%S}`, e.g. `15:01:23`
/// - `{%D}`: `{%m}/{%d}/{%y}`, e.g. `10/02/14`
/// - `{%z}`: numeric offset, e.g. `+0000`
/// - `{%:z}`: numeric offset with a colon, e.g. `+00:00`
///
/// Custom fields:
/// - `{#id}`: passed to `formatter`, with `id` holding the text after the `#`
///
/// Date and time fields are rendered in `timezone`. Note that
/// `{@RFC3339Z}` always writes a literal `Z`, even when `timezone` is not
/// `.utc`; keep `timezone` at `.utc` when using that field.
///
/// A literal `{` or `}` is written by doubling it: `{{` and `}}`. Unknown
/// field names and unbalanced braces are rejected when the pattern is parsed.
///
/// See `PatternToken` for the token each field parses to.
pub const Pattern = struct {
    /// The tokens the pattern was compiled to, including the literal text
    /// between the fields.
    tokens: []const PatternToken,

    /// Renders the custom `{#id}` fields of `tokens`.
    ///
    /// Must be non-null if `tokens` contains a `custom` token.
    formatter: ?UserFormatter = null,

    /// The default pattern, `[{@RFC3339Z}] [{@scope}]({@LEVEL}): {@msg}`,
    /// which renders records like this:
    /// ```
    /// [2014-10-02T15:01:23.045123456Z] [main](I): starting up
    /// ```
    pub const default: @This() = .{ .tokens = &.{
        .{ .literal = "[" },
        .rfc3339zulu,
        .{ .literal = "] [" },
        .scope,
        .{ .literal = "](" },
        .level_short,
        .{ .literal = "): " },
        .msg,
    } };

    /// Parses `pattern` at compile time and returns it as a token slice.
    pub fn parse(comptime pattern: []const u8) Pattern {
        return .{ .tokens = comptime p.parsePatternComptime(pattern) catch unreachable };
    }

    /// Same as `parse`, but renders `{#id}` fields with `f`.
    pub fn parseWithFormatter(comptime pattern: []const u8, f: UserFormatter) Pattern {
        return .{ .tokens = comptime p.parsePatternComptime(pattern) catch unreachable, .formatter = f };
    }
};

pub const TimeZoneOffset = union(enum) {
    utc,
    local: isize, // base UTC offset

    pub const default: @This() = .utc;

    /// Returns a `local` offset read from the operating system.
    ///
    /// The returned offset is the current base offset of the local time zone.
    /// Returns an error if the offset cannot be determined.
    pub fn initLocalTimeByHelper() error{unknow}!TimeZoneOffset {
        return .{ .local = h.getBaseUtcOffset() catch return error.unknow };
    }
};

pub const Output = union(enum) {
    /// A caller-supplied writer.
    ///
    /// The logger serializes its own writes, so at most one task calls into
    /// `writer` at a time; the caller must not write to it concurrently.
    writer: *std.Io.Writer,

    stderr: Stream,

    stdout: Stream,

    file: File,

    pub const Stream = struct {
        bufsize: usize = 4096,
    };

    pub const File = struct {
        bufsize: usize = 4096,

        /// Path of the file. A relative path is resolved against the current
        /// working directory.
        path: []const u8,
    };

    pub const default: @This() = .{ .stdout = .{} };
};

pub const ErrorHandler = struct {
    func: *const fn (std.Io, *std.Io.Writer) void,

    pub const default: ErrorHandler = .{ .func = &debugPrint };

    pub const discarding: ErrorHandler = .{ .func = noop };

    fn noop(_: std.Io, _: *std.Io.Writer) void {}

    fn debugPrint(_: std.Io, _: *std.Io.Writer) void {
        std.debug.print("{s}\n", .{"ComptimeConciseLog Writer Error"});
    }
};

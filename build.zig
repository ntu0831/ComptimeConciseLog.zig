const std = @import("std");

const name = "ComptimeConciseLog";

// zig build docs
// zig build examples
// zig build test
// zig build test-unit
// zig build test-examples
// zig build test-integration

pub fn build(b: *std.Build) !void {
    var ctx: Context = .{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
    };

    try addModule(b, &ctx);
    try addExamples(b, &ctx);
    try addIntegrationTest(b, &ctx);

    if (ctx.test_unit != null and ctx.test_examples != null and ctx.test_integration != null) {
        const test_all = b.step("test", "Run all tests");
        if (ctx.test_unit) |step| test_all.dependOn(step);
        if (ctx.test_examples) |step| test_all.dependOn(step);
        if (ctx.test_integration) |step| test_all.dependOn(step);
        sortCommand(b);
    }
}

fn addModule(b: *std.Build, ctx: *Context) !void {
    ctx.mod = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });

    const exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
        }),
    });

    const step_docs = b.step("docs", "Build the docs");
    step_docs.dependOn(&b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    const step_test = b.step("test-unit", "Run unit tests");
    step_test.dependOn(&b.addRunArtifact(exe).step);
    ctx.test_unit = step_test;
}

fn addExamples(b: *std.Build, ctx: *Context) !void {
    if (helper.notExistDir(b, "examples")) return;

    const step_build = b.step("examples", "Build examples");
    const step_test = b.step("test-examples", "Run example tests");
    ctx.test_examples = step_test;

    inline for (static.tests_with_examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = ctx.target,
                .optimize = ctx.optimize,
                .imports = &.{.{ .name = name, .module = ctx.mod.? }},
            }),
        });

        const run = b.addRunArtifact(exe);
        run.cwd = exe.getEmittedBinDirectory();
        if (example.expectStdErrMatch) |e| run.expectStdErrMatch(e);
        if (example.expectStdOutMatch) |e| run.expectStdOutMatch(e);

        step_build.dependOn(&b.addInstallArtifact(exe, .{}).step);
        step_test.dependOn(&run.step);
    }
}

fn addIntegrationTest(b: *std.Build, ctx: *Context) !void {
    if (helper.notExistDir(b, "tests")) return;

    const step_test = b.step("test-integration", "Run integraion tests");
    ctx.test_integration = step_test;

    inline for (static.tests) |t| {
        const exe = b.addTest(.{
            .name = t.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(t.path),
                .target = ctx.target,
                .optimize = ctx.optimize,
                .imports = &.{.{ .name = name, .module = ctx.mod.? }},
            }),
        });
        step_test.dependOn(&b.addRunArtifact(exe).step);
    }
    inline for (static.tests_with_run) |t| {
        const exe = b.addExecutable(.{
            .name = t.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(t.path),
                .target = ctx.target,
                .optimize = ctx.optimize,
                .imports = &.{.{ .name = name, .module = ctx.mod.? }},
            }),
        });
        step_test.dependOn(&b.addRunArtifact(exe).step);
    }
    inline for (static.tests_with_error) |t| {
        const exe = b.addExecutable(.{
            .name = t.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(t.path),
                .target = ctx.target,
                .optimize = ctx.optimize,
                .imports = &.{.{ .name = name, .module = ctx.mod.? }},
            }),
        });
        exe.expect_errors = .{ .contains = t.err };
        step_test.dependOn(&exe.step);
    }
}

fn sortCommand(b: *std.Build) void {
    const SortContext = struct {
        ahm: *@TypeOf(b.top_level_steps),

        const priority: std.StaticStringMap(u8) = .initComptime(.{
            .{ "docs", 1 },
            .{ "examples", 2 },
            .{ "test", 3 },
            .{ "test-unit", 4 },
            .{ "test-examples", 5 },
            .{ "test-integration", 6 },
        });

        pub fn lessThan(self: @This(), a_idx: usize, b_idx: usize) bool {
            const keys = self.ahm.keys();
            const a_name = keys[a_idx];
            const b_name = keys[b_idx];
            const a_prio = priority.get(a_name) orelse 0;
            const b_prio = priority.get(b_name) orelse 0;
            if (a_prio != b_prio) return a_prio < b_prio;
            return std.mem.lessThan(u8, a_name, b_name);
        }
    };

    const ctx: SortContext = .{ .ahm = &b.top_level_steps };
    b.top_level_steps.sort(ctx);
}

const Context = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    mod: ?*std.Build.Module = null,

    test_unit: ?*std.Build.Step = null,
    test_examples: ?*std.Build.Step = null,
    test_integration: ?*std.Build.Step = null,
};

const static = struct {
    const tests = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "init_after_deinit", .path = "tests/api/init_after_deinit.zig" },
        .{ .name = "deinit_before_init", .path = "tests/api/deinit_before_init.zig" },
        .{ .name = "double_deinit", .path = "tests/api/double_deinit.zig" },
        .{ .name = "double_init_after_deinit", .path = "tests/api/double_init_after_deinit.zig" },
        .{ .name = "double_init_before_deinit", .path = "tests/api/double_init_before_deinit.zig" },
        .{ .name = "log_after_deinit", .path = "tests/api/log_after_deinit.zig" },
        .{ .name = "log_before_init", .path = "tests/api/log_before_init.zig" },

        // single producer
        .{ .name = "onelog_with_self", .path = "tests/sp/onelog_with_self.zig" },
        .{ .name = "onelog_with_async", .path = "tests/sp/onelog_with_async.zig" },
        .{ .name = "onelog_with_concurrent", .path = "tests/sp/onelog_with_concurrent.zig" },
        .{ .name = "looplog_with_self", .path = "tests/sp/looplog_with_self.zig" },
        .{ .name = "looplog_with_async", .path = "tests/sp/looplog_with_async.zig" },
        .{ .name = "looplog_with_concurrent", .path = "tests/sp/looplog_with_concurrent.zig" },

        // multi producer
        .{ .name = "onelog_with_async", .path = "tests/mp/onelog_with_async.zig" },
        .{ .name = "onelog_with_concurrent", .path = "tests/mp/onelog_with_concurrent.zig" },
        .{ .name = "looplog_with_async", .path = "tests/mp/looplog_with_async.zig" },
        .{ .name = "looplog_with_concurrent", .path = "tests/mp/looplog_with_concurrent.zig" },
    };
    const tests_with_run = &.{
        .{ .name = "pattern_pattern", .path = "tests/pattern/pattern.zig" },
        .{ .name = "pattern_formatter", .path = "tests/pattern/formatter.zig" },
        .{ .name = "pool_buf_exhaustion_drop", .path = "tests/pool_buf_exhaustion/drop.zig" },
        .{ .name = "pool_buf_exhaustion_block", .path = "tests/pool_buf_exhaustion/block.zig" },
        .{ .name = "pool_buf_exhaustion_truncate", .path = "tests/pool_buf_exhaustion/truncate.zig" },
        .{ .name = "record_buf_exhaustion_drop", .path = "tests/record_buf_exhaustion/drop.zig" },
        .{ .name = "record_buf_exhaustion_truncate", .path = "tests/record_buf_exhaustion/truncate.zig" },
    };
    const tests_with_error = &.{
        .{ .name = "pattern_pattern", .path = "tests/pattern/error.zig", .err = "userFormatter is null" },
    };

    const tests_with_examples = [_]struct { name: []const u8, path: []const u8, expectStdOutMatch: ?[]const u8 = null, expectStdErrMatch: ?[]const u8 = null }{
        .{ .name = "minimal", .path = "examples/minimal.zig", .expectStdOutMatch = "" },
        .{ .name = "stdlog", .path = "examples/stdlog.zig", .expectStdOutMatch = "" },
        .{ .name = "pattern", .path = "examples/pattern.zig", .expectStdOutMatch = "" },
        .{ .name = "formatter", .path = "examples/formatter.zig", .expectStdOutMatch = "" },
        .{ .name = "output_file", .path = "examples/output_file.zig" },
        .{ .name = "output_writer", .path = "examples/output_writer.zig", .expectStdErrMatch = "" },
        .{ .name = "errorhandling", .path = "examples/errorhandling.zig", .expectStdErrMatch = "" },
    };
};

const helper = struct {
    fn notExistDir(b: *std.Build, path: []const u8) bool {
        const dir = b.root.openDir(b.graph.io, path, .{}) catch return true;
        defer dir.close(b.graph.io);
        return false;
    }
};

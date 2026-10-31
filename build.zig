const std = @import("std");

const name = "ComptimeConciseLog";

pub fn build(b: *std.Build) !void {
    var ctx: Context = .{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
    };

    // zig build docs
    // zig build examples
    // zig build test
    // zig build test-unit
    // zig build test-examples
    // zig build test-integration

    try addModule(b, &ctx);
    try addExamples(b, &ctx);
    try addIntegrationTest(b, &ctx);
    try addCommand(b, &ctx);
}

fn addCommand(b: *std.Build, ctx: *Context) !void {
    const build_docs = b.step("docs", "Build the docs");
    build_docs.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.addObject(.{
            .name = name,
            .root_module = ctx.mod.?,
        }).getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    const build_examples = b.step("examples", "Build examples");
    for (ctx.examples_exe.items) |r| build_examples.dependOn(&r.step);

    const test_all = b.step("test", "Run all tests");

    const test_u = b.step("test-unit", "Run unit tests");
    test_u.dependOn(&ctx.mod_test.?.step);

    const test_e = b.step("test-examples", "Run example tests");
    for (ctx.examples_test.items) |r| test_e.dependOn(&r.step);

    const test_i = b.step("test-integration", "Run integration tests");
    for (ctx.integration_test.items) |r| test_i.dependOn(&r.step);
    for (ctx.integration_test_run.items) |r| test_i.dependOn(&r.step);
    for (ctx.integration_test_error.items) |c| test_i.dependOn(&c.step);

    test_all.dependOn(test_u);
    test_all.dependOn(test_e);
    test_all.dependOn(test_i);
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
    ctx.mod_test = b.addRunArtifact(exe);
}

fn addExamples(b: *std.Build, ctx: *Context) !void {
    if (helper.notExistDir(b, "examples")) return;

    const gpa = b.allocator;
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
        try ctx.examples_test.append(gpa, run);
        try ctx.examples_exe.append(gpa, b.addInstallArtifact(exe, .{}));
    }
}

fn addIntegrationTest(b: *std.Build, ctx: *Context) !void {
    if (helper.notExistDir(b, "tests")) return;

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
        try ctx.integration_test.append(b.allocator, b.addRunArtifact(exe));
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
        try ctx.integration_test_run.append(b.allocator, b.addRunArtifact(exe));
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
        try ctx.integration_test_error.append(b.allocator, exe);
    }
}

const Context = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    mod: ?*std.Build.Module = null,

    examples_exe: std.ArrayList(*std.Build.Step.InstallArtifact) = .empty,

    mod_test: ?*std.Build.Step.Run = null,
    examples_test: std.ArrayList(*std.Build.Step.Run) = .empty,
    integration_test: std.ArrayList(*std.Build.Step.Run) = .empty,
    integration_test_run: std.ArrayList(*std.Build.Step.Run) = .empty,
    integration_test_error: std.ArrayList(*std.Build.Step.Compile) = .empty,
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

const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const zig_graph_module_name = "zig-graph";
    const zig_graph_module = b.addModule(zig_graph_module_name, .{ .source_file = .{ .path = "external_libs/zig-graph/src/graph.zig" } });
    const zap_module_name = "zap";
    const zap_module = b.addModule(zap_module_name, .{ .source_file = .{ .path = "external_libs/zap/src/thread_pool.zig" } });

    const dependencies = [_]std.Build.ModuleDependency{ .{ .name = zig_graph_module_name, .module = zig_graph_module }, .{ .name = zap_module_name, .module = zap_module } };
    const taskflow_module_name = "taskflow";
    const taskflow_module = b.addModule(taskflow_module_name, .{ .source_file = .{ .path = "src/taskflow/flow.zig" }, .dependencies = &dependencies });

    // Creates a step for building a shared library
    const build_lib_step = b.addSharedLibrary(.{
        .name = "taskflow",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    build_lib_step.addModule(taskflow_module_name, taskflow_module);

    // This declares intent for the shared library to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    _ = b.installArtifact(build_lib_step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const build_unit_test_step = b.addTest(.{
        .root_source_file = .{ .path = "tests/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    build_unit_test_step.addModule(taskflow_module_name, taskflow_module);

    const run_unit_tests = b.addRunArtifact(build_unit_test_step);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run the comprehensive unit test");
    test_step.dependOn(&run_unit_tests.step);
}

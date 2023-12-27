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
    const zig_async_module_name = "zig-async";
    const zig_async_module = b.addModule(zig_async_module_name, .{ .source_file = .{ .path = "external_libs/zig-async/src/task.zig" } });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var build_steps: std.ArrayList(*std.Build.Step.Compile) = std.ArrayList(*std.Build.Step.Compile).init(allocator);

    const build_lib_step = b.addSharedLibrary(.{
        .name = "taskflow",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/taskflow/flow.zig" },
        .target = target,
        .optimize = optimize,
    });
    build_steps.append(build_lib_step) catch unreachable;

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const build_unit_test_step = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    build_steps.append(build_unit_test_step) catch unreachable;

    for (build_steps.items) |step| {
        step.addModule(zig_graph_module_name, zig_graph_module);
        step.addModule(zig_async_module_name, zig_async_module);
    }

    // This declares intent for the shared library to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    _ = b.installArtifact(build_lib_step);
    const run_unit_tests = b.addRunArtifact(build_unit_test_step);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run the comprehensive unit test");
    test_step.dependOn(&run_unit_tests.step);
}

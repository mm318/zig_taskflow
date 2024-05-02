const std = @import("std");
const Flow = @import("taskflow").Flow;
const Task = @import("taskflow").Task;
const IntegrationTest = @import("small_integration.zig");

//
// Create a TaskFlow graph like the following:
//
//                 A     B
//                / \    |
//               C   D   E
//               |\ / \ /
//               | F   G
//               |/   / \
//               H   I   J
//                \  |  /
//                 \ | /
//                  \|/
//                   K
//

var scratch_allocator: ?*const std.mem.Allocator = null;

const Data = struct {
    x: []const u8,
    y: std.atomic.Value(usize),
};

const TaskA = Task.createTaskType(&.{}, &.{i64});

fn func_a() struct { i64 } {
    return .{@as(i64, 492)};
}

const TaskB = Task.createTaskType(&.{}, &.{[]const u8});

fn func_b() struct { []const u8 } {
    return .{"From Task B"};
}

const TaskC = Task.createTaskType(&.{i64}, &.{ bool, ?*const u8 });

fn func_c(x: *const i64) struct { bool, ?*const u8 } {
    const result2 = scratch_allocator.?.create(u8) catch unreachable;
    result2.* = @truncate(@as(u64, @bitCast(x.*)));
    return .{ @mod(x.*, 2) == 1, result2 };
}

const TaskD = Task.createTaskType(&.{i64}, &.{ ?*const bool, Data });

fn func_d(x: *const i64) struct { ?*const bool, Data } {
    const result1 = scratch_allocator.?.create(bool) catch unreachable;
    result1.* = @mod(x.*, 2) == 0;
    return .{ result1, Data{ .x = "From Task D", .y = std.atomic.Value(usize).init(@as(usize, @bitCast(x.*))) } };
}

const TaskE = Task.createTaskType(&.{[]const u8}, &.{std.ArrayList(u8)});

fn func_e(x: *const []const u8) struct { std.ArrayList(u8) } {
    var result = std.ArrayList(u8).init(scratch_allocator.?.*);
    result.writer().print("{s}\nFrom Task E", .{x.*}) catch unreachable;
    return .{result};
}

const TaskF = Task.createTaskType(&.{ ?*const u8, ?*const bool }, &.{u32});

fn func_f(x: *const ?*const u8, y: *const ?*const bool) struct { u32 } {
    const result = if (y.*.?.*)
        x.*.?.* ^ 0b00000000
    else
        x.*.?.* ^ 0b11111111;
    return .{result};
}

const TaskG = Task.createTaskType(&.{ Data, std.ArrayList(u8) }, &.{ u32, bool });

fn func_g(x: *const Data, y: *const std.ArrayList(u8)) struct { u32, bool } {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHashStrat(&hasher, x.x, std.hash.Strategy.Deep);
    std.hash.autoHashStrat(&hasher, y.items, std.hash.Strategy.Deep);
    return .{ @truncate(hasher.final()), std.ascii.eqlIgnoreCase(y.items, x.x) or @mod(x.y.load(.monotonic), 2) == 0 };
}

const TaskH = Task.createTaskType(&.{ bool, u32 }, &.{ Data, std.ArrayList(bool) });

fn func_h(x: *const bool, y: *const u32) struct { Data, std.ArrayList(bool) } {
    var result2 = std.ArrayList(bool).initCapacity(scratch_allocator.?.*, 15) catch unreachable;
    for (0..result2.capacity) |_| {
        result2.append(x.*) catch unreachable;
    }
    return .{ Data{ .x = "From Task H", .y = std.atomic.Value(usize).init(@as(usize, y.*)) }, result2 };
}

const TaskI = Task.createTaskType(&.{ bool, u32 }, &.{[5]u16});

fn func_i(x: *const bool, y: *const u32) struct { [5]u16 } {
    const bytes = std.mem.asBytes(y);
    var result = [_]u16{0} ** 5;
    for (0.., bytes) |i, b| {
        result[i] = b;
    }
    result[result.len - 1] = if (x.*) 1 else 0;
    return .{result};
}

const TaskJ = Task.createTaskType(&.{ bool, u32 }, &.{[10]i8});

fn func_j(x: *const bool, y: *const u32) struct { [10]i8 } {
    const bytes = std.mem.asBytes(y);
    var result = if (x.*) [_]i8{0} ** 10 else [_]i8{2} ** 10;
    for (0.., bytes) |i, b| {
        result[i] += @bitCast(b);
    }
    for (0.., bytes) |i, b| {
        result[10 - i - 1] -= @bitCast(b);
    }
    return .{result};
}

const TaskK = Task.createTaskType(&.{ [10]i8, [5]u16, std.ArrayList(bool), Data }, &.{std.ArrayList(u8)});

fn func_k(w: *const [10]i8, x: *const [5]u16, y: *const std.ArrayList(bool), z: *const Data) struct { std.ArrayList(u8) } {
    var result = std.ArrayList(u8).init(scratch_allocator.?.*);
    result.writer().print("Task K result: {any} {any} {any} {any} {}", .{ w.*, x.*, y.items, z.x, z.y }) catch unreachable;
    return .{result};
}

test "integration test" {
    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Beginning "integration" test
        \\#####################################################################
        \\
    , .{});

    const allocator = std.testing.allocator;

    var flowgraph = try Flow.init(allocator);
    defer flowgraph.deinit();

    const task_a = try flowgraph.newTask(TaskA, undefined, func_a);
    const task_b = try flowgraph.newTask(TaskB, undefined, func_b);
    const task_c = try flowgraph.newTask(TaskC, undefined, func_c);
    const task_d = try flowgraph.newTask(TaskD, undefined, func_d);
    const task_e = try flowgraph.newTask(TaskE, undefined, func_e);
    const task_f = try flowgraph.newTask(TaskF, undefined, func_f);
    const task_g = try flowgraph.newTask(TaskG, undefined, func_g);
    const task_h = try flowgraph.newTask(TaskH, undefined, func_h);
    const task_i = try flowgraph.newTask(TaskI, undefined, func_i);
    const task_j = try flowgraph.newTask(TaskJ, undefined, func_j);
    var task_k = try flowgraph.newTask(TaskK, undefined, func_k);

    try flowgraph.connect(task_a, 0, task_c, 0);
    try flowgraph.connect(task_a, 0, task_d, 0);
    try flowgraph.connect(task_b, 0, task_e, 0);
    try flowgraph.connect(task_c, 0, task_h, 0);
    try flowgraph.connect(task_c, 1, task_f, 0);
    try flowgraph.connect(task_d, 0, task_f, 1);
    try flowgraph.connect(task_d, 1, task_g, 0);
    try flowgraph.connect(task_e, 0, task_g, 1);
    try flowgraph.connect(task_f, 0, task_h, 1);
    try flowgraph.connect(task_g, 0, task_i, 1);
    try flowgraph.connect(task_g, 1, task_i, 0);
    try flowgraph.connect(task_g, 0, task_j, 1);
    try flowgraph.connect(task_g, 1, task_j, 0);
    try flowgraph.connect(task_h, 0, task_k, 3);
    try flowgraph.connect(task_h, 1, task_k, 2);
    try flowgraph.connect(task_i, 0, task_k, 1);
    try flowgraph.connect(task_j, 0, task_k, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    scratch_allocator = &arena_allocator;

    try flowgraph.execute();

    IntegrationTest.printTaskInfo(task_a, "task_a", "post-execute()");
    IntegrationTest.printTaskInfo(task_b, "task_b", "post-execute()");
    IntegrationTest.printTaskInfo(task_c, "task_c", "post-execute()");
    IntegrationTest.printTaskInfo(task_d, "task_d", "post-execute()");
    IntegrationTest.printTaskInfo(task_e, "task_e", "post-execute()");
    IntegrationTest.printTaskInfo(task_f, "task_f", "post-execute()");
    IntegrationTest.printTaskInfo(task_g, "task_g", "post-execute()");
    IntegrationTest.printTaskInfo(task_h, "task_h", "post-execute()");
    IntegrationTest.printTaskInfo(task_i, "task_i", "post-execute()");
    IntegrationTest.printTaskInfo(task_j, "task_j", "post-execute()");
    IntegrationTest.printTaskInfo(task_k, "task_k", "post-execute()");

    std.debug.print("\n\nFinal output:\n{s}\n", .{task_k.getOutputPtr(0).items});

    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Finished "integration" test
        \\#####################################################################
        \\
    , .{});
}

const std = @import("std");
const Flow = @import("taskflow").Flow;
const Task = @import("taskflow").Task;

pub const DummyError = error{
    Error1,
    Error2,
    Error3,
};

pub const DummyStruct = struct {
    name: []const u8,
    depends_on: []const *DummyStruct,
    value: f32,
};

fn dummyTaskFunc(input1: *const DummyStruct, input2: *const DummyError) struct { DummyStruct, DummyError } {
    return .{ input1.*, input2.* };
}

test "cycle detection" {
    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Beginning "cycle detection" test
        \\#####################################################################
        \\
    , .{});

    var allocator = std.testing.allocator;

    const TestTaskType = Task.createTaskType(
        &.{ DummyStruct, DummyError },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = try Flow.init(allocator);
    defer flowgraph.deinit();

    var task1 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "1", .depends_on = undefined, .value = undefined }, DummyError.Error1 }, &dummyTaskFunc);
    var task2 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "2", .depends_on = undefined, .value = undefined }, DummyError.Error2 }, &dummyTaskFunc);
    var task3 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "3", .depends_on = undefined, .value = undefined }, DummyError.Error3 }, &dummyTaskFunc);

    try flowgraph.connect(task1, 0, task2, 0);
    try flowgraph.connect(task1, 1, task2, 1);
    try flowgraph.connect(task2, 0, task3, 0);
    try flowgraph.connect(task2, 1, task3, 1);
    try flowgraph.connect(task3, 0, task1, 0); // this creates a cycle
    try flowgraph.connect(task3, 1, task1, 1); // this creates a cycle

    try std.testing.expectError(Flow.Error.CyclicDependencyGraph, flowgraph.execute());

    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Finished "cycle detection" test
        \\#####################################################################
        \\
    , .{});
}

test "incomplete inputs detection" {
    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Beginning "incomplete inputs detection" test
        \\#####################################################################
        \\
    , .{});

    var allocator = std.testing.allocator;

    const TestTaskType = Task.createTaskType(
        &.{ DummyStruct, DummyError },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = try Flow.init(allocator);
    defer flowgraph.deinit();

    var task1 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "1", .depends_on = undefined, .value = undefined }, DummyError.Error1 }, &dummyTaskFunc);
    var task2 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "2", .depends_on = undefined, .value = undefined }, DummyError.Error2 }, &dummyTaskFunc);
    var task3 = try flowgraph.newTask(TestTaskType, .{ DummyStruct{ .name = "3", .depends_on = undefined, .value = undefined }, DummyError.Error3 }, &dummyTaskFunc);

    try flowgraph.connect(task1, 0, task2, 0);
    // try flowgraph.connect(task1, 1, task2, 1);  // task 2 does not have all of its inputs set
    try flowgraph.connect(task2, 0, task3, 0);
    // try flowgraph.connect(task2, 1, task3, 1);  // task 3 does not have all of its inputs set

    try std.testing.expectError(Flow.Error.DisconnectedInput, flowgraph.execute());

    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Finished "incomplete inputs detection" test
        \\#####################################################################
        \\
    , .{});
}

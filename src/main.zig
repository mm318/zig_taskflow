const std = @import("std");
const Flow = @import("taskflow/flow.zig");
const Task = @import("taskflow/task.zig");

const DummyError = error{
    Error1,
    Error2,
    Error3,
};

const DummyStruct = struct {
    name: []const u8,
    depends_on: []const *DummyStruct,
    value: f32,
};

fn dummyTaskFunc(input1: *const DummyStruct, input2: *const DummyError) struct { DummyStruct, DummyError } {
    return .{ input1.*, input2.* };
}

fn dummyTaskFunc1(_: *const i32, _: *const u32, _: *const usize) struct { u8, f16, f32 } {
    return .{ 7, -1.234, -5.678 };
}

fn dummyTaskFunc2(input1: *const u8, input2: *const f32, input3: *const f16) struct { DummyStruct, DummyError } {
    const sum: f32 = @as(f32, @floatFromInt(input1.*)) + input2.* + input3.*;
    return .{ DummyStruct{ .name = "dummy1", .depends_on = &.{}, .value = sum }, DummyError.Error1 };
}

fn printTaskInfo(task: anytype, task_name: []const u8, header: []const u8) void {
    std.debug.print("\nDebug {s} {s}:\n", .{ task_name, header });
    inline for (0.., @typeInfo(@TypeOf(task.internals)).Struct.fields) |i, task_field| {
        _ = i;
        if (@typeInfo(task_field.type) == .Struct) {
            std.debug.print("{s} {s}\n", .{ task_name, task_field.name });
            inline for (0.., @typeInfo(task_field.type).Struct.fields) |j, io_struct_field| {
                const value_ptr = &@field(@field(task.internals, task_field.name), io_struct_field.name);
                const value = value_ptr.*;
                if (std.mem.eql(u8, task_field.name, "inputs")) {
                    std.debug.print("\t{s}[{}] ({}) = {?}\n", .{ task_field.name, j, io_struct_field.type, value });
                } else {
                    std.debug.print("\t{s}[{}] ({}) = {?} ({*})\n", .{ task_field.name, j, io_struct_field.type, value, value_ptr });
                }
            }
        } else {
            std.debug.print("{s} {s}\n", .{ task_name, task_field.name });
            std.debug.print("\t{}\n", .{task_field.type});
        }
    }
}

test "cycle detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        std.debug.assert(deinit_status != .leak);
    }

    const TestTaskType = Task.createTaskType(
        &.{ DummyStruct, DummyError },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = try Flow.init(&allocator);
    defer flowgraph.free();

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
}

test "integration test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        std.testing.expect(deinit_status != .leak) catch unreachable;
    }

    const TestTaskType1 = Task.createTaskType(
        &.{ i32, u32, usize },
        &.{ u8, f16, f32 },
    );
    const TestTaskType2 = Task.createTaskType(
        &.{ u8, f32, f16 },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = try Flow.init(&allocator);
    defer flowgraph.free();

    var task1 = try flowgraph.newTask(TestTaskType1, .{ 0, 0, 0 }, &dummyTaskFunc1);
    var task2 = try flowgraph.newTask(TestTaskType2, .{ DummyStruct{ .name = "none", .depends_on = undefined, .value = undefined }, DummyError.Error3 }, &dummyTaskFunc2);
    printTaskInfo(task1, "task1", "post-createTaskType()");
    printTaskInfo(task2, "task2", "post-createTaskType()");

    try flowgraph.connect(task1, 0, task2, 0);
    try flowgraph.connect(task1, 1, task2, 2);
    try flowgraph.connect(task1, 2, task2, 1);

    try flowgraph.execute();
    printTaskInfo(task1, "task1", "post-execute()");
    printTaskInfo(task2, "task2", "post-execute()");

    try std.testing.expectEqual(@as(u8, 7), task1.getOutputPtr(0).*);
    try std.testing.expectApproxEqRel(@as(f16, -1.234375), task1.getOutputPtr(1).*, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, -5.67799997), task1.getOutputPtr(2).*, 0.0001);
    try std.testing.expectEqualStrings("dummy1", task2.getOutputPtr(0).*.name);
    try std.testing.expectApproxEqRel(@as(f32, 8.76250267e-02), task2.getOutputPtr(0).value, 0.0001);
}

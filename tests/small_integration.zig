const std = @import("std");
const Flow = @import("taskflow").Flow;
const Task = @import("taskflow").Task;

const DummyError = @import("unit.zig").DummyError;
const DummyStruct = @import("unit.zig").DummyStruct;

fn dummyTaskFunc1() struct { u8, f16, f32 } {
    return .{ 7, -1.234, -5.678 };
}

fn dummyTaskFunc2(input1: *const u8, input2: *const f32, input3: *const f16) struct { DummyStruct, DummyError } {
    const sum: f32 = @as(f32, @floatFromInt(input1.*)) + input2.* + input3.*;
    return .{ DummyStruct{ .name = "dummy1", .depends_on = &.{}, .value = sum }, DummyError.Error1 };
}

pub fn printTaskInfo(task: anytype, task_name: []const u8, header: []const u8) void {
    std.debug.print("Debug {s} {s}:\n", .{ task_name, header });
    inline for (@typeInfo(@TypeOf(task.internals)).Struct.fields) |task_field| {
        if (@typeInfo(task_field.type) == .Struct) {
            std.debug.print("{s} {s}\n", .{ task_name, task_field.name });
            inline for (0.., @typeInfo(task_field.type).Struct.fields) |j, io_struct_field| {
                const value_ptr = &@field(@field(task.internals, task_field.name), io_struct_field.name);
                const value = value_ptr.*;
                if (std.mem.eql(u8, task_field.name, "inputs")) {
                    std.debug.print("\t{s}[{}] ({}) = {any}\n", .{ task_field.name, j, io_struct_field.type, value });
                } else {
                    std.debug.print("\t{s}[{}] ({}) = {any} ({*})\n", .{ task_field.name, j, io_struct_field.type, value, value_ptr });
                }
            }
        } else {
            std.debug.print("{s} {s}\n", .{ task_name, task_field.name });
            std.debug.print("\t{}\n", .{task_field.type});
        }
    }
}

test "small integration test" {
    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Beginning "small integration" test
        \\#####################################################################
        \\
    , .{});

    var allocator = std.testing.allocator;

    const TestTaskType1 = Task.createTaskType(
        &.{},
        &.{ u8, f16, f32 },
    );
    const TestTaskType2 = Task.createTaskType(
        &.{ u8, f32, f16 },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = try Flow.init(allocator);
    defer flowgraph.deinit();

    var task1 = try flowgraph.newTask(TestTaskType1, .{ 0, 0, 0 }, &dummyTaskFunc1);
    var task2 = try flowgraph.newTask(TestTaskType2, .{ DummyStruct{ .name = "none", .depends_on = undefined, .value = undefined }, DummyError.Error3 }, &dummyTaskFunc2);
    std.debug.print("\n", .{});
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

    std.debug.print(
        \\
        \\#####################################################################
        \\#####  Finished "small integration" test
        \\#####################################################################
        \\
    , .{});
}

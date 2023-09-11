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
};

fn dummyTaskFunc1(_: *const i32, _: *const u32, _: *const usize) struct { u8, f16, f32 } {
    return .{ 0, 0, 0 };
}

fn dummyTaskFunc2(_: *const u8, _: *const f32, _: *const f16) struct { DummyStruct, DummyError } {
    return .{ DummyStruct{ .name = "dummy1", .depends_on = undefined }, DummyError.Error1 };
}

fn printTaskInfo(task: anytype, header: []const u8) void {
    std.debug.print("\nDebug {s}:\n", .{header});
    inline for (0.., @typeInfo(@TypeOf(task.internals)).Struct.fields) |i, f| {
        std.debug.print("TestFlowTask field{} is \"{s}\" (type: {})\n", .{ i, f.name, f.type });
        if (@typeInfo(f.type) == .Struct) {
            inline for (0.., @typeInfo(f.type).Struct.fields) |j, g| {
                const value = @field(@field(task.internals, f.name), g.name);
                std.debug.print("\t{s} field{} is \"{s}\" (type: {}) = {?}\n", .{ f.name, j, g.name, g.type, value });
            }
        }
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        std.debug.assert(deinit_status != .leak);
    }

    const TestTaskType1 = Task.createTaskType(
        &.{ i32, u32, usize },
        &.{ u8, f16, f32 },
    );
    const TestTaskType2 = Task.createTaskType(
        &.{ u8, f32, f16 },
        &.{ DummyStruct, DummyError },
    );

    var flowgraph = Flow.init(&allocator);
    defer flowgraph.free();

    var task1 = try flowgraph.newTask(TestTaskType1, undefined, .{ 0, 0, 0 }, &dummyTaskFunc1);
    var task2 = try flowgraph.newTask(TestTaskType2, undefined, .{ DummyStruct{ .name = "none", .depends_on = undefined }, DummyError.Error3 }, &dummyTaskFunc2);
    printTaskInfo(task1, "post-createTaskType()");
    printTaskInfo(task2, "post-createTaskType()");

    task1.execute();
    task2.execute();
    printTaskInfo(task1, "post-execute()");
    printTaskInfo(task2, "post-execute()");
}

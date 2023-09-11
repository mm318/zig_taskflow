const std = @import("std");
const Task = @import("task.zig");

const Flow = @This();
tasks: std.ArrayList(*Task),
allocator: *std.mem.Allocator,

pub fn init(a: *std.mem.Allocator) Flow {
    return Flow{ .tasks = std.ArrayList(*Task).init(a.*), .allocator = a };
}

pub fn newTask(self: *Flow, comptime TaskType: type, init_inputs: anytype, init_outputs: anytype, func_ptr: anytype) !*TaskType {
    const result = try TaskType.new(self.allocator, init_inputs, init_outputs, func_ptr);
    try self.tasks.append(&result.interface);
    return result;
}

pub fn free(self: *Flow) void {
    for (self.tasks.items) |task| {
        task.free(self.allocator);
    }
    self.tasks.deinit();
}

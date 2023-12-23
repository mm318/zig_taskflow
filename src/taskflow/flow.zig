const std = @import("std");
const Task = @import("task.zig");
const Graph = @import("zig-graph").DirectedGraph(*Task, std.hash_map.AutoContext(*Task));

const Flow = @This();
tasks: std.ArrayList(*Task),
graph: Graph,
allocator: *std.mem.Allocator,

pub fn init(a: *std.mem.Allocator) Flow {
    return Flow{ .tasks = std.ArrayList(*Task).init(a.*), .graph = Graph.init(a.*), .allocator = a };
}

pub fn newTask(self: *Flow, comptime TaskType: type, init_outputs: anytype, func_ptr: anytype) !*TaskType {
    const result = try TaskType.new(self.allocator, undefined, init_outputs, func_ptr);
    try self.tasks.append(&result.interface);
    return result;
}

pub fn connect(_: *Flow, src_task: anytype, comptime output_idx: usize, dst_task: anytype, comptime input_idx: usize) void {
    dst_task.setInput(input_idx, src_task, output_idx);
}

pub fn execute(self: Flow) void {
    for (self.tasks.items) |task| {
        task.execute();
    }
}

pub fn free(self: *Flow) void {
    for (self.tasks.items) |task| {
        task.free(self.allocator);
    }
    self.tasks.deinit();
}

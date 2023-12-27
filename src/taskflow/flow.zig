const std = @import("std");
const Task = @import("task.zig");
const Graph = @import("zig-graph").DirectedGraph(*Task, std.hash_map.AutoContext(*Task));
const Async = @import("zig-async");

const Flow = @This();

pub const Error = error{
    CyclicDependencyGraph,
};

allocator: std.mem.Allocator,
tasks: std.ArrayList(*Task),
graph: Graph,

pub fn init(a: std.mem.Allocator) Flow {
    return .{ .allocator = a, .tasks = std.ArrayList(*Task).init(a), .graph = Graph.init(a) };
}

pub fn newTask(self: *Flow, comptime TaskType: type, init_outputs: anytype, func_ptr: anytype) !*TaskType {
    const result = try TaskType.new(self.allocator, undefined, init_outputs, func_ptr);
    try self.tasks.append(&result.interface);
    try self.graph.add(&result.interface);
    return result;
}

pub fn connect(self: *Flow, src_task: anytype, comptime output_idx: usize, dst_task: anytype, comptime input_idx: usize) !void {
    const DUMMY_EDGE_WEIGHT = 1;
    try self.graph.addEdge(&src_task.interface, &dst_task.interface, DUMMY_EDGE_WEIGHT);
    dst_task.setInput(input_idx, src_task, output_idx);
}

pub fn execute(self: Flow) !void {
    var cycles = self.graph.cycles();
    if (cycles != null) {
        // std.log.err("there are {d} cycles", .{cycles.?.count()});
        cycles.?.deinit();
        return Error.CyclicDependencyGraph;
    }

    const ExecTask = Async.Task(Task.execute);
    var bfsIter = try self.graph.bfsIterator();
    while (true) {
        if (bfsIter.next()) |task_iter| {
            if (task_iter) |task_ptr| {
                var future = try ExecTask.launch(self.allocator, .{task_ptr});
                defer future.deinit();
                future.wait();
            } else {
                break;
            }
        } else |err| {
            std.log.err("error occurred while executing: {}", .{err});
            break;
        }
    }
    bfsIter.deinit();
}

pub fn free(self: *Flow) void {
    for (self.tasks.items) |task| {
        task.free(self.allocator);
    }
    self.tasks.deinit();
    self.graph.deinit();
}

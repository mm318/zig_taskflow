const std = @import("std");
const Task = @import("task.zig");
const Graph = @import("zig-graph").DirectedGraph(*Task, std.hash_map.AutoContext(*Task));
const ThreadPool = @import("zap").ThreadPool;

const Flow = @This();

pub const Error = error{
    CyclicDependencyGraph,
};

allocator: *std.mem.Allocator,
tasks: std.ArrayList(*Task),
graph: Graph,
executor: ThreadPool,

pub fn init(a: *std.mem.Allocator) !Flow {
    const num_cpus: u32 = @truncate(std.Thread.getCpuCount() catch 8);
    return .{ .allocator = a, .tasks = std.ArrayList(*Task).init(a.*), .graph = Graph.init(a.*), .executor = ThreadPool.init(.{ .max_threads = num_cpus }) };
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

pub fn execute(self: *Flow) !void {
    var cycles = self.graph.cycles();
    if (cycles != null) {
        // std.log.err("there are {d} cycles", .{cycles.?.count()});
        cycles.?.deinit();
        return Error.CyclicDependencyGraph;
    }

    var tp_batch = ThreadPool.Batch{};
    var tp_tasks = std.ArrayList(ThreadPool.Task).init(self.allocator.*);
    defer tp_tasks.deinit();

    var bfsIter = try self.graph.bfsIterator();
    while (true) {
        if (bfsIter.next()) |task_iter| {
            if (task_iter) |task| {
                try tp_tasks.append(ThreadPool.Task{ .callback = task.executeInThreadPoolFn, .cookie = @ptrCast(task) });
            } else {
                break;
            }
        } else |err| {
            std.log.err("error occurred while executing: {}", .{err});
            break;
        }
    }
    bfsIter.deinit();

    for (tp_tasks.items) |*tp_task| {
        tp_batch.push(ThreadPool.Batch.from(tp_task));
    }
    self.executor.schedule(tp_batch);
}

pub fn free(self: *Flow) void {
    for (self.tasks.items) |task| {
        task.free(self.allocator);
    }
    self.tasks.deinit();
    self.graph.deinit();
    self.executor.shutdown();
    self.executor.deinit();
}

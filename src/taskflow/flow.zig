const std = @import("std");
const assert = @import("std").debug.assert;
const Task = @import("task.zig");
const Graph = @import("zig-graph").DirectedGraph(*Task, std.hash_map.AutoContext(*Task));
const ThreadPool = @import("zap").ThreadPool;

const Flow = @This();

pub const Error = error{
    CyclicDependencyGraph,
    DisconnectedInput,
};

allocator: std.mem.Allocator,
tasks: std.ArrayList(*Task),
graph: Graph,
executor: ThreadPool,

pub fn init(a: std.mem.Allocator) !Flow {
    const num_cpus: u32 = @truncate(std.Thread.getCpuCount() catch 8);
    return .{ .allocator = a, .tasks = std.ArrayList(*Task).init(a), .graph = Graph.init(a), .executor = ThreadPool.init(.{ .max_threads = num_cpus }) };
}

pub fn newTask(self: *Flow, comptime TaskType: type, init_outputs: anytype, func_ptr: anytype) !*TaskType {
    const result = try TaskType.new(self.allocator, self.tasks.items.len, init_outputs, func_ptr);
    try self.tasks.append(&result.interface);
    try self.graph.add(&result.interface);
    return result;
}

pub fn connect(self: *Flow, src_task: anytype, comptime output_idx: usize, dst_task: anytype, comptime input_idx: usize) !void {
    const DUMMY_EDGE_WEIGHT = 1;
    try self.graph.addEdge(&src_task.interface, &dst_task.interface, DUMMY_EDGE_WEIGHT);
    dst_task.setInput(input_idx, src_task, output_idx);
}

const TaskExecutionContext = struct {
    tp_task: ThreadPool.Task,
    flow_task: *Task,
    is_completed: bool = false,
    is_sink: bool = false,
    parent_context: *FlowExecutionContext,

    fn executeTaskInThreadPool(vptr: ?*void) void {
        const self: *TaskExecutionContext = @ptrCast(@alignCast(vptr));
        self.executeTask();
    }

    fn executeTask(self: *TaskExecutionContext) void {
        self.flow_task.execute();
        {
            // have self.completed assignment take effect
            self.parent_context.lock.lock();
            defer self.parent_context.lock.unlock();
            self.is_completed = true;
        }

        if (!self.is_sink) {
            // check this task's fan-outs to see if the rest of their dependencies have also been completed
            const fan_outs = self.parent_context.parent_context.graph.getFanOuts(self.flow_task, self.parent_context.allocator);
            defer fan_outs.deinit();
            for (fan_outs.items) |next_task| {
                const next_tp_batch = ThreadPool.Batch.from(&self.parent_context.task_contexts.items[next_task.*.id].tp_task);
                self.parent_context.parent_context.executor.schedule(next_tp_batch);
            }
        } else {
            self.parent_context.signal.signal();
        }
    }
};

const FlowExecutionContext = struct {
    allocator: std.mem.Allocator,
    task_contexts: std.ArrayList(TaskExecutionContext),
    sinks: std.ArrayList(usize),
    parent_context: *Flow,
    lock: std.Thread.Mutex = std.Thread.Mutex{},
    signal: std.Thread.Condition = std.Thread.Condition{},

    fn init(allocator: std.mem.Allocator, parent: *Flow, num_tasks: usize) !FlowExecutionContext {
        return FlowExecutionContext{ .allocator = allocator, .task_contexts = try std.ArrayList(TaskExecutionContext).initCapacity(allocator, num_tasks), .sinks = std.ArrayList(usize).init(allocator), .parent_context = parent };
    }

    fn deinit(self: *FlowExecutionContext) void {
        self.task_contexts.deinit();
        self.sinks.deinit();
    }

    // self.lock has already been acquired when coming here from the Task::execute() while loop
    fn hasCompleted(self: *const FlowExecutionContext) bool {
        for (self.sinks.items) |sink_task_id| {
            if (!self.task_contexts.items[sink_task_id].is_completed) {
                return false;
            }
        }
        return true;
    }
};

pub fn execute(self: *Flow) !void {
    var cycles = self.graph.cycles();
    if (cycles != null) {
        // std.log.err("there are {d} cycles", .{cycles.?.count()});
        cycles.?.deinit();
        return Error.CyclicDependencyGraph;
    }

    var flow_context = try FlowExecutionContext.init(self.allocator, self, self.tasks.items.len);
    defer flow_context.deinit();

    std.debug.print("\n", .{});
    var initial_tp_batch = ThreadPool.Batch{};
    for (self.tasks.items) |task| {
        assert(flow_context.task_contexts.items.len == task.id);
        const task_context = TaskExecutionContext{ .tp_task = ThreadPool.Task{ .callback = TaskExecutionContext.executeTaskInThreadPool, .cookie = null }, .flow_task = task, .parent_context = &flow_context };
        try flow_context.task_contexts.append(task_context);
        // flow_context.task_contexts has been preallocated so the append should not change address of flow_context.task_contexts[*]
        flow_context.task_contexts.items[task.id].tp_task.cookie = @ptrCast(&flow_context.task_contexts.items[task.id]);

        // check if this task is a root task that needs to be initially scheduled
        const edge_count = self.graph.countInOutEdges(task);
        if (edge_count.fan_ins <= 0) {
            std.debug.print("task {} is source\n", .{task.id});
            initial_tp_batch.push(ThreadPool.Batch.from(&flow_context.task_contexts.items[task.id].tp_task));
        } else {
            if (!task.checkAllInputsSet()) {
                std.debug.print("task {} does not have all inputs connected\n", .{task.id});
                return Error.DisconnectedInput;
            }
        }
        if (edge_count.fan_outs <= 0) {
            std.debug.print("task {} is sink\n", .{task.id});
            flow_context.task_contexts.items[task.id].is_sink = true;
            try flow_context.sinks.append(task.id);
        }
    }
    std.debug.print("\n", .{});

    // start execution
    flow_context.lock.lock();
    defer flow_context.lock.unlock();

    self.executor.schedule(initial_tp_batch);

    while (!flow_context.hasCompleted()) {
        flow_context.signal.wait(&flow_context.lock);
    }
}

pub fn deinit(self: *Flow) void {
    for (self.tasks.items) |task| {
        task.free(self.allocator);
    }
    self.tasks.deinit();
    self.graph.deinit();
    self.executor.shutdown();
    self.executor.deinit();
}

const std = @import("std");
const Graph = @import("zig-graph").DirectedGraph(*Task, std.hash_map.AutoContext(*Task));
const ThreadPool = @import("zap").ThreadPool;

pub const Flow = @This();
pub const Task = @import("task.zig");

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
    const State = enum(u8) {
        IDLE = 0,
        SCHEDULED,
        FINISHED,
    };

    tp_task: ThreadPool.Task,
    flow_task: *Task,
    state: std.atomic.Atomic(State) = std.atomic.Atomic(State).init(.IDLE),
    lock: std.Thread.Mutex = std.Thread.Mutex{},
    is_sink: bool = false,
    parent_context: *FlowExecutionContext,

    fn executeTaskInThreadPool(vptr: ?*void) void {
        const self: *TaskExecutionContext = @ptrCast(@alignCast(vptr));
        self.executeTask();
    }

    fn executeTask(self: *TaskExecutionContext) void {
        // std.debug.print("starting executing task {}\n", .{self.flow_task.id});
        self.flow_task.execute();
        // std.debug.print("finished executing task {}\n", .{self.flow_task.id});
        self.state.store(.FINISHED, .Monotonic);

        if (!self.is_sink) {
            // check this task's fan-outs to see if the rest of their dependencies have also been completed
            const fan_outs = self.parent_context.parent_context.graph.getFanOuts(self.flow_task, self.parent_context.allocator);
            defer fan_outs.deinit();
            for (fan_outs.items) |next_task| {
                const next_task_context = &self.parent_context.task_contexts.items[next_task.*.id];
                // std.debug.print("next task id: {} state: {}\n", .{next_task.*.id, next_task_context.state.load(.Monotonic)});
                if (next_task_context.state.load(.Monotonic) == .IDLE) {
                    const fan_ins = self.parent_context.parent_context.graph.getFanIns(next_task.*, self.parent_context.allocator);
                    defer fan_ins.deinit();

                    next_task_context.lock.lock();
                    defer next_task_context.lock.unlock();

                    var deps_met = true;
                    for (fan_ins.items) |prev_task| {
                        const prev_task_context = &self.parent_context.task_contexts.items[prev_task.*.id];
                        if (prev_task_context.state.load(.Monotonic) != .FINISHED) {
                            // std.debug.print("not starting task {} because task {} has not finished\n", .{next_task.*.id, prev_task.*.id});
                            deps_met = false;
                            break;
                        }
                    }

                    if (deps_met and next_task_context.state.load(.Monotonic) == .IDLE) {
                        const next_tp_batch = ThreadPool.Batch.from(&next_task_context.tp_task);
                        self.parent_context.parent_context.executor.schedule(next_tp_batch);
                        next_task_context.state.store(.SCHEDULED, .Monotonic);
                    }
                }
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
            if (self.task_contexts.items[sink_task_id].state.load(.Monotonic) != .FINISHED) {
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
        std.debug.assert(flow_context.task_contexts.items.len == task.id);
        const task_context = TaskExecutionContext{ .tp_task = ThreadPool.Task{ .callback = TaskExecutionContext.executeTaskInThreadPool, .cookie = null }, .flow_task = task, .parent_context = &flow_context };
        try flow_context.task_contexts.append(task_context);
        // flow_context.task_contexts has been preallocated so the append should not change address of flow_context.task_contexts[*]
        flow_context.task_contexts.items[task.id].tp_task.cookie = @ptrCast(&flow_context.task_contexts.items[task.id]);

        // check if this task is a root task that needs to be initially scheduled
        const edge_count = self.graph.countInOutEdges(task);
        if (edge_count.fan_ins <= 0) {
            std.debug.print("task {} is source\n", .{task.id});
            initial_tp_batch.push(ThreadPool.Batch.from(&flow_context.task_contexts.items[task.id].tp_task));
            flow_context.task_contexts.items[task.id].state.store(.SCHEDULED, .Monotonic);
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

const std = @import("std");
const taskflow = @import("taskflow/task.zig");

const Node = struct {
    name: []const u8,
    depends_on: []const *Node,

    pub fn print_dependencies(self: Node) void {
        std.debug.print("node \"{s}\" depends on:\n", .{self.name});
        for (self.depends_on) |dependency| {
            std.debug.print("  {s}", .{dependency.name});
        }
        std.debug.print("\n", .{});
    }
};

fn dummyTaskFunc(_: ?*const i32, _: ?*const u32, _: ?*const usize) struct { u8, f16, f32 } {
    return .{ 0, 0, 0 };
}

pub fn main() anyerror!void {
    var node1 = Node{
        .name = "node1",
        .depends_on = &[_]*Node{},
    };
    node1.depends_on = &[_]*Node{&node1};
    node1.print_dependencies();

    const var1: i32 = 1;
    const var2: u32 = 2;
    const var3: usize = 3;

    const TestFlowTask = taskflow.createTaskType(
        &.{ i32, u32, usize },
        &.{ u8, f16, f32 },
    );

    var task = TestFlowTask.init(.{ &var1, &var2, &var3 }, .{ 0, 0, 0 }, &dummyTaskFunc);
    std.debug.print("\nDebug post-createTaskType():\n", .{});
    inline for (0.., @typeInfo(@TypeOf(task.internals)).Struct.fields) |i, f| {
        std.debug.print("TestFlowTask field{} is {s} (type: {})\n", .{ i, f.name, f.type });
        if (@typeInfo(f.type) == .Struct) {
            inline for (0.., @typeInfo(f.type).Struct.fields) |j, g| {
                std.debug.print("\t{s} field{} is {s} (type: {})\n", .{ f.name, j, g.name, g.type });
            }
        }
    }

    task.execute();
}

test "whatever" {
    try std.testing.expectEqual(10, 3 + 7);
}

const std = @import("std");

const Node = struct {
    name: []const u8,
    depends_on: []const *Node,

    pub fn print_dependencies(self: Node) void {
        std.debug.print("node \"{s}\" depends on:\n", .{self.name});
        for (self.depends_on) |dependency| {
            std.debug.print("  {s}", .{dependency.name});
        }
    }
};

fn createTaskType(comptime input_types: []const type, comptime output_types: []const type) type {
    var input_pointer_types: [input_types.len]type = undefined;
    for (0.., input_types) |i, t| {
        input_pointer_types[i] = @Type(.{ .Pointer = .{
            .size = std.builtin.Type.Pointer.Size.One,
            .is_const = true,
            .is_volatile = false,
            .address_space = std.builtin.AddressSpace.generic,
            .child = t,
            .is_allowzero = false,
            .sentinel = null,
            .alignment = 0,
        }});
    }

    var input_fields: [input_types.len]std.builtin.Type.StructField = undefined;
    var optional_input_fields: [input_types.len]std.builtin.Type.StructField = undefined;
    var input_params: [input_types.len]std.builtin.Type.Fn.Param = undefined;
    for (0.., input_pointer_types) |i, t| {
        const field_name: []const u8 = std.fmt.comptimePrint("{}", .{i});
        input_fields[i] = .{
            .name = field_name,
            .type = t,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };

        const optional_field_type: type = @Type(.{ .Optional = .{ .child = t}});
        optional_input_fields[i] = .{
            .name = field_name,
            .type = optional_field_type,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };

        input_params[i] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = t,
        };
    }    

    var output_fields: [output_types.len]std.builtin.Type.StructField = undefined;
    for (0.., output_types) |i, t| {
        const field_name: []const u8 = std.fmt.comptimePrint("{}", .{i});
        output_fields[i] = .{
            .name = field_name,
            .type = t,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    const input_type = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = optional_input_fields[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = true,
    }});
    const input_field: std.builtin.Type.StructField = .{
        .name = "inputs",
        .type = input_type,
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    };

    const output_type = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = output_fields[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = true,
    }});
    const output_field: std.builtin.Type.StructField = .{
        .name = "outputs",
        .type = output_type,
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    };

    const fn_type = @Type(.{ .Fn = .{
        .calling_convention = .Unspecified,
        .is_generic = false,
        .is_var_args = false,
        .params = input_params[0..],
        .return_type = output_type,
        .alignment = 0,
    }});
    var fn_field: std.builtin.Type.StructField = .{
        .name = "task_func",
        .type = fn_type,
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    };

    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = &[_]std.builtin.Type.StructField{input_field, fn_field, output_field},
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        }
    });
}

pub fn main() anyerror!void {
    var node1 = Node {
        .name = "node1",
        .depends_on = &[_]*Node{},
    };
    node1.depends_on = &[_] *Node{&node1};
    node1.print_dependencies();

    const TestFlowTask = createTaskType(
        &.{i32, u32, usize},
        &.{u8, f16, f32},
    );

    std.debug.print("\n", .{});
    inline for (0.., @typeInfo(TestFlowTask).Struct.fields) |i, f| {
        std.debug.print("struct field {} is \"{s}: {}\"\n", .{ i, f.name, f.type });
        if (i != 1) {
            inline for (0.., @typeInfo(f.type).Struct.fields) |j, g| {
                std.debug.print("\tstruct field {} is \"{s}: {}\"\n", .{ j, g.name, g.type });
            }
        } else {
            const return_type = @typeInfo(f.type).Fn.return_type.?;
            inline for (0.., @typeInfo(return_type).Struct.fields) |j, g| {
                std.debug.print("\treturn field {} is \"{s}: {}\"\n", .{ j, g.name, g.type });
            }
        }
    }
}

test "whatever" {
    try std.testing.expectEqual(10, 3 + 7);
}

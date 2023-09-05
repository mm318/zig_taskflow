const std = @import("std");

fn createTaskInternalsType(comptime input_types: []const type, comptime output_types: []const type) type {
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
        } });
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

        const optional_field_type: type = @Type(.{ .Optional = .{ .child = t } });
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
    } });
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
    } });
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
    } });
    const fn_ptr_type = @Type(.{ .Pointer = .{
        .size = std.builtin.Type.Pointer.Size.One,
        .is_const = true,
        .is_volatile = false,
        .address_space = std.builtin.AddressSpace.generic,
        .child = fn_type,
        .is_allowzero = false,
        .sentinel = null,
        .alignment = 0,
    } });
    var fn_field: std.builtin.Type.StructField = .{
        .name = "func",
        .type = fn_ptr_type,
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    };

    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &[_]std.builtin.Type.StructField{ input_field, fn_field, output_field },
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });
}

const Task = struct {
    executeFn: *const fn (self: *Task) void,

    pub fn execute(self: *Task) void {
        self.executeFn(self);
    }
};

pub fn createTaskType(comptime input_types: []const type, comptime output_types: []const type) type {
    const Internals = createTaskInternalsType(input_types, output_types);

    const ConcreteTask = struct {
        const Self = @This();
        interface: Task,
        internals: Internals,

        pub fn init(initial_inputs: anytype, initial_outputs: anytype, func_ptr: anytype) Self {
            const impl = struct {
                pub fn execute(ptr: *Task) void {
                    const self = @fieldParentPtr(Self, "interface", ptr);
                    self.execute();
                }
            };

            return Self{ .interface = Task{ .executeFn = impl.execute }, .internals = Internals{ .inputs = initial_inputs, .func = func_ptr, .outputs = initial_outputs } };
        }

        pub fn execute(self: *Self) void {
            std.debug.print("\nDebug executeTask():\n", .{});
            inline for (0.., @typeInfo(@TypeOf(self.internals.inputs)).Struct.fields) |i, f| {
                std.debug.print("task field{} is {s}: (type: {})\n", .{ i, f.name, f.type });
            }

            const Args = std.meta.ArgsTuple(@typeInfo(@TypeOf(self.internals.func)).Pointer.child);
            var args: Args = undefined;
            inline for (0.., std.meta.fields(Args)) |i, _| {
                args[i] = self.internals.inputs[i].?;
            }

            self.internals.outputs = @call(std.builtin.CallModifier.auto, self.internals.func, args);
        }
    };

    return ConcreteTask;
}

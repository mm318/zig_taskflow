const std = @import("std");
pub const test_a = @import("unit.zig");
pub const test_b = @import("small_integration.zig");
pub const test_c = @import("integration.zig");

test {
    std.testing.refAllDecls(@This());
}

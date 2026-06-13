const std = @import("std");

/// Physics tuning constants. Values are starting points from the design spec
/// and will be adjusted through playtesting.
pub const Constants = struct {
    k_spring: f32 = 10.0,
    rest_length: f32 = 1.0,
    k_angle: f32 = 5.0,
    k_repel: f32 = 2.0,
    repulsion_threshold: f32 = 0.8,
    damping: f32 = 0.98,
    convergence_threshold: f32 = 0.001,
    dt: f32 = 0.016,
};

pub const default = Constants{};

test "default constants match the design spec" {
    const c = default;
    try std.testing.expectEqual(@as(f32, 10.0), c.k_spring);
    try std.testing.expectEqual(@as(f32, 1.0), c.rest_length);
    try std.testing.expectEqual(@as(f32, 5.0), c.k_angle);
    try std.testing.expectEqual(@as(f32, 2.0), c.k_repel);
    try std.testing.expectEqual(@as(f32, 0.8), c.repulsion_threshold);
    try std.testing.expectEqual(@as(f32, 0.98), c.damping);
    try std.testing.expectEqual(@as(f32, 0.001), c.convergence_threshold);
    try std.testing.expectEqual(@as(f32, 0.016), c.dt);
}

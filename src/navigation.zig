const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

const Quaternion = @import("quaternion.zig").Quaternion;

pub const Direction = enum { prev, next };

/// Next/previous index over `len` items, wrapping. Returns 0 if len == 0.
pub fn cycle(index: usize, len: usize, dir: Direction) usize {
    if (len == 0) return 0;
    return switch (dir) {
        .next => (index + 1) % len,
        .prev => (index + len - 1) % len,
    };
}

/// Orientation that rotates an open point's outward direction to face the
/// camera (+Z). Shortest-arc, so roll is minimized.
pub fn targetOrientation(dir: Vec3) Quaternion {
    return Quaternion.rotationBetween(dir, Vec3.init(0, 0, 1));
}

test "cycle wraps next and prev (incl. len 1)" {
    try std.testing.expectEqual(@as(usize, 1), cycle(0, 4, .next));
    try std.testing.expectEqual(@as(usize, 0), cycle(3, 4, .next));
    try std.testing.expectEqual(@as(usize, 3), cycle(0, 4, .prev));
    try std.testing.expectEqual(@as(usize, 2), cycle(3, 4, .prev));
    try std.testing.expectEqual(@as(usize, 0), cycle(0, 1, .next));
    try std.testing.expectEqual(@as(usize, 0), cycle(0, 1, .prev));
}

test "targetOrientation brings a direction to +Z" {
    const dir = Vec3.init(1, 0, 0);
    const q = targetOrientation(dir);
    try std.testing.expect(q.rotateVec(dir).approxEq(Vec3.init(0, 0, 1), 1e-5));
}

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

pub const PressDir = enum { left, right, up, down };

/// An atom to select plus the world-axis rotation that brings it to the front.
pub const AtomPick = struct { index: usize, axis: Vec3, angle: f32 };

fn wrap2pi(a: f32) f32 {
    var x = @mod(a, 2.0 * std.math.pi);
    if (x < 0) x += 2.0 * std.math.pi;
    return x;
}

/// Given atoms by their view-space directions (each rotated by the current
/// orientation; camera looks down -Z), pick the atom that first reaches the
/// front (+Z) as the molecule rotates in the pressed direction, and the
/// world-axis rotation amount to bring it there. Left/Right rotate about the
/// vertical (yaw); Up/Down about the horizontal (pitch). Atoms already at the
/// front (amount ~ 0) are skipped, so selection and rotation stay consistent
/// (press Left -> molecule turns one way -> the next atom in line is selected).
/// Returns null if nothing qualifies.
pub fn nextAtomByRotation(view_dirs: []const Vec3, press: PressDir) ?AtomPick {
    const eps: f32 = 1e-3;
    const axis = switch (press) {
        .left => Vec3.init(0, 1, 0),
        .right => Vec3.init(0, -1, 0),
        .up => Vec3.init(1, 0, 0),
        .down => Vec3.init(-1, 0, 0),
    };
    var best: ?usize = null;
    var best_amount: f32 = std.math.inf(f32);
    for (view_dirs, 0..) |rd, i| {
        const amount = switch (press) {
            .left => wrap2pi(-std.math.atan2(rd.x, rd.z)),
            .right => wrap2pi(std.math.atan2(rd.x, rd.z)),
            .up => wrap2pi(std.math.atan2(rd.y, rd.z)),
            .down => wrap2pi(-std.math.atan2(rd.y, rd.z)),
        };
        if (amount < eps) continue;
        if (amount < best_amount) {
            best_amount = amount;
            best = i;
        }
    }
    if (best) |b| return .{ .index = b, .axis = axis, .angle = best_amount };
    return null;
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

test "nextAtomByRotation picks the atom that reaches front first in the press direction" {
    const dirs = [_]Vec3{
        Vec3.init(0, 0, 1), // 0: at front (skipped)
        Vec3.init(-0.2, 0, 0.98), // 1: slightly left
        Vec3.init(0.5, 0, 0.86), // 2: right
        Vec3.init(-0.9, 0, -0.4), // 3: far left/back
    };
    // Left turns the molecule so left atoms come to front first -> the near-left one.
    try std.testing.expectEqual(@as(usize, 1), nextAtomByRotation(&dirs, .left).?.index);
    // Right brings the right atom first.
    try std.testing.expectEqual(@as(usize, 2), nextAtomByRotation(&dirs, .right).?.index);

    const vdirs = [_]Vec3{
        Vec3.init(0, 0, 1), // front
        Vec3.init(0, 0.2, 0.98), // up
        Vec3.init(0, -0.5, 0.86), // down
    };
    try std.testing.expectEqual(@as(usize, 1), nextAtomByRotation(&vdirs, .up).?.index);
    try std.testing.expectEqual(@as(usize, 2), nextAtomByRotation(&vdirs, .down).?.index);

    // Only a front-facing atom -> nothing to rotate to.
    const one = [_]Vec3{Vec3.init(0, 0, 1)};
    try std.testing.expect(nextAtomByRotation(&one, .left) == null);
}

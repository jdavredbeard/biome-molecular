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

/// Cursor-like directional selection. `view_positions` are the open points'
/// positions in the current view space (camera looks down -Z, so x = right,
/// y = up). Starting from the `selected` point, pick the nearest other point
/// lying in the pressed screen direction `(dx, dy)` (assumed unit). Off-axis
/// candidates are penalized (cost = along + 2*perpendicular) so a press favors
/// well-aligned neighbors. Returns null if nothing lies in that direction.
pub fn directionalSelect(view_positions: []const Vec3, selected: usize, dx: f32, dy: f32) ?usize {
    if (selected >= view_positions.len) return null;
    const sel = view_positions[selected];
    var best: ?usize = null;
    var best_cost: f32 = std.math.inf(f32);
    for (view_positions, 0..) |p, i| {
        if (i == selected) continue;
        const ex = p.x - sel.x;
        const ey = p.y - sel.y;
        const along = ex * dx + ey * dy;
        if (along <= 1e-4) continue; // not in the pressed direction
        const px = ex - dx * along;
        const py = ey - dy * along;
        const perp = @sqrt(px * px + py * py);
        const cost = along + 2.0 * perp;
        if (cost < best_cost) {
            best_cost = cost;
            best = i;
        }
    }
    return best;
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

test "directionalSelect picks the nearest in-direction point from the selected one" {
    const vps = [_]Vec3{
        Vec3.init(0, 0, 0), // 0: selected (center)
        Vec3.init(0, 2, 0), // 1: up, near
        Vec3.init(1, 0.1, 0), // 2: right
        Vec3.init(0, -2, 0), // 3: down
        Vec3.init(0, 5, 0), // 4: up, far
    };
    try std.testing.expectEqual(@as(?usize, 1), directionalSelect(&vps, 0, 0, 1)); // up -> nearer up node
    try std.testing.expectEqual(@as(?usize, 2), directionalSelect(&vps, 0, 1, 0)); // right
    try std.testing.expectEqual(@as(?usize, 3), directionalSelect(&vps, 0, 0, -1)); // down
    // From the near-up node, pressing down returns toward center (nearer than the down node).
    try std.testing.expectEqual(@as(?usize, 0), directionalSelect(&vps, 1, 0, -1));
    // Nothing to the left of center.
    try std.testing.expectEqual(@as(?usize, null), directionalSelect(&vps, 0, -1, 0));
}

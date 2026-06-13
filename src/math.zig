const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn lengthSq(a: Vec3) f32 {
        return a.dot(a);
    }

    pub fn length(a: Vec3) f32 {
        return @sqrt(a.lengthSq());
    }

    pub fn normalize(a: Vec3) Vec3 {
        const len = a.length();
        if (len < 1e-8) return Vec3.zero;
        return a.scale(1.0 / len);
    }

    pub fn distance(a: Vec3, b: Vec3) f32 {
        return a.sub(b).length();
    }

    pub fn approxEq(a: Vec3, b: Vec3, tol: f32) bool {
        return @abs(a.x - b.x) <= tol and @abs(a.y - b.y) <= tol and @abs(a.z - b.z) <= tol;
    }
};

/// Angle in radians between two vectors. Clamps to avoid NaN from rounding.
pub fn angleBetween(a: Vec3, b: Vec3) f32 {
    const denom = a.length() * b.length();
    if (denom < 1e-8) return 0;
    const c = std.math.clamp(a.dot(b) / denom, -1.0, 1.0);
    return std.math.acos(c);
}

/// Rotate `v` around unit `axis` by `angle` radians (Rodrigues' formula).
pub fn rodrigues(v: Vec3, axis: Vec3, angle: f32) Vec3 {
    const c = @cos(angle);
    const s = @sin(angle);
    const term1 = v.scale(c);
    const term2 = axis.cross(v).scale(s);
    const term3 = axis.scale(axis.dot(v) * (1.0 - c));
    return term1.add(term2).add(term3);
}

/// Return an arbitrary unit vector perpendicular to `v` (assumes |v| ~ 1).
pub fn anyPerpendicular(v: Vec3) Vec3 {
    // Cross with whichever basis axis is least aligned with v.
    const ref = if (@abs(v.x) < 0.9) Vec3.init(1, 0, 0) else Vec3.init(0, 1, 0);
    return v.cross(ref).normalize();
}

pub const AxisAngle = struct { axis: Vec3, angle: f32 };

/// Shortest-arc rotation taking unit vector `from` onto unit vector `to`.
pub fn rotationAxisAngle(from: Vec3, to: Vec3) AxisAngle {
    const d = std.math.clamp(from.dot(to), -1.0, 1.0);
    const axis = from.cross(to);
    if (axis.length() < 1e-6) {
        // Parallel (d ~ 1) -> no rotation; antiparallel (d ~ -1) -> 180 deg about any perpendicular.
        if (d > 0) return .{ .axis = Vec3.init(0, 0, 1), .angle = 0 };
        return .{ .axis = anyPerpendicular(from), .angle = std.math.pi };
    }
    return .{ .axis = axis.normalize(), .angle = std.math.acos(d) };
}

test "Vec3 add/sub/scale/neg" {
    const a = Vec3.init(1, 2, 3);
    const b = Vec3.init(4, 5, 6);
    try expectVec(Vec3.init(5, 7, 9), a.add(b));
    try expectVec(Vec3.init(-3, -3, -3), a.sub(b));
    try expectVec(Vec3.init(2, 4, 6), a.scale(2));
    try expectVec(Vec3.init(-1, -2, -3), a.neg());
}

test "Vec3 dot/cross" {
    const a = Vec3.init(1, 0, 0);
    const b = Vec3.init(0, 1, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.dot(b), 1e-6);
    try expectVec(Vec3.init(0, 0, 1), a.cross(b));
    try std.testing.expectApproxEqAbs(@as(f32, 32), Vec3.init(1, 2, 3).dot(Vec3.init(4, 5, 6)), 1e-5);
}

test "Vec3 length/normalize/distance" {
    const v = Vec3.init(3, 4, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 25), v.lengthSq(), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), v.length(), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v.normalize().length(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 5), Vec3.init(0, 0, 0).distance(Vec3.init(0, 3, 4)), 1e-5);
}

test "Vec3 normalize of zero is zero" {
    try expectVec(Vec3.zero, Vec3.zero.normalize());
}

fn expectVec(expected: Vec3, actual: Vec3) !void {
    try std.testing.expect(expected.approxEq(actual, 1e-5));
}

test "angleBetween orthogonal and parallel" {
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), angleBetween(Vec3.init(1, 0, 0), Vec3.init(0, 1, 0)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), angleBetween(Vec3.init(0, 0, 2), Vec3.init(0, 0, 5)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), angleBetween(Vec3.init(1, 0, 0), Vec3.init(-1, 0, 0)), 1e-5);
}

test "rodrigues rotates 90 degrees about Z" {
    const out = rodrigues(Vec3.init(1, 0, 0), Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(out.approxEq(Vec3.init(0, 1, 0), 1e-5));
}

test "anyPerpendicular is unit and orthogonal" {
    const inputs = [_]Vec3{ Vec3.init(0, 0, 1), Vec3.init(1, 0, 0), Vec3.init(1, 1, 1).normalize() };
    for (inputs) |v| {
        const p = anyPerpendicular(v);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.length(), 1e-5);
        try std.testing.expectApproxEqAbs(@as(f32, 0), p.dot(v), 1e-5);
    }
}

test "rotationAxisAngle maps from onto to" {
    const from = Vec3.init(1, 0, 0);
    const to = Vec3.init(0, 0, 1);
    const r = rotationAxisAngle(from, to);
    const moved = rodrigues(from, r.axis, r.angle);
    try std.testing.expect(moved.approxEq(to, 1e-5));
}

test "rotationAxisAngle handles antiparallel" {
    const from = Vec3.init(0, 0, 1);
    const to = Vec3.init(0, 0, -1);
    const r = rotationAxisAngle(from, to);
    const moved = rodrigues(from, r.axis, r.angle);
    try std.testing.expect(moved.approxEq(to, 1e-5));
}

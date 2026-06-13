const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

/// Unit quaternion rotation. v' = q v q*. mul(a, b) applies b then a.
pub const Quaternion = struct {
    w: f32,
    x: f32,
    y: f32,
    z: f32,

    pub const identity = Quaternion{ .w = 1, .x = 0, .y = 0, .z = 0 };

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quaternion {
        const a = axis.normalize();
        const h = angle * 0.5;
        const s = @sin(h);
        return .{ .w = @cos(h), .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn mul(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    pub fn dot(a: Quaternion, b: Quaternion) f32 {
        return a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn add(a: Quaternion, b: Quaternion) Quaternion {
        return .{ .w = a.w + b.w, .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Quaternion, b: Quaternion) Quaternion {
        return .{ .w = a.w - b.w, .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Quaternion, s: f32) Quaternion {
        return .{ .w = a.w * s, .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Quaternion) Quaternion {
        return .{ .w = -a.w, .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn length(a: Quaternion) f32 {
        return @sqrt(a.dot(a));
    }

    pub fn normalize(a: Quaternion) Quaternion {
        const len = a.length();
        if (len < 1e-8) return Quaternion.identity;
        return a.scale(1.0 / len);
    }

    /// Rotate a vector: v' = v + w*t + qv x t, where qv = (x,y,z), t = 2*(qv x v).
    pub fn rotateVec(q: Quaternion, v: Vec3) Vec3 {
        const qv = Vec3.init(q.x, q.y, q.z);
        const t = qv.cross(v).scale(2.0);
        return v.add(t.scale(q.w)).add(qv.cross(t));
    }
};

test "fromAxisAngle + rotateVec rotates +X 90deg about +Z to +Y" {
    const q = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    const v = q.rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(v.approxEq(Vec3.init(0, 1, 0), 1e-5));
}

test "mul composes rotations (two 90deg about Z = 180deg)" {
    const q90 = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    const q180 = q90.mul(q90);
    const v = q180.rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(v.approxEq(Vec3.init(-1, 0, 0), 1e-5));
}

test "identity rotates nothing and normalize keeps unit length" {
    const v = Quaternion.identity.rotateVec(Vec3.init(3, -2, 1));
    try std.testing.expect(v.approxEq(Vec3.init(3, -2, 1), 1e-6));
    const q = Quaternion{ .w = 2, .x = 0, .y = 0, .z = 0 }; // length 2
    const n = q.normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.length(), 1e-6);
}

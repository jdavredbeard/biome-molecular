const std = @import("std");
const Vec3 = @import("math.zig").Vec3;
const Mat4 = @import("mat4.zig").Mat4;

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

    /// Spherical linear interpolation along the shortest arc.
    pub fn slerp(a: Quaternion, b: Quaternion, t: f32) Quaternion {
        var bb = b;
        var d = a.dot(b);
        if (d < 0) {
            bb = b.neg();
            d = -d;
        }
        if (d > 0.9995) {
            // Nearly parallel: linear interpolation + renormalize.
            return a.add(bb.sub(a).scale(t)).normalize();
        }
        const theta0 = std.math.acos(d);
        const theta = theta0 * t;
        const sin0 = @sin(theta0);
        const s0 = @sin(theta0 - theta) / sin0;
        const s1 = @sin(theta) / sin0;
        return a.scale(s0).add(bb.scale(s1));
    }

    /// Shortest-arc rotation mapping unit vector `from` onto unit vector `to`.
    pub fn rotationBetween(from: Vec3, to: Vec3) Quaternion {
        const f = from.normalize();
        const t = to.normalize();
        const d = std.math.clamp(f.dot(t), -1.0, 1.0);
        if (d > 0.999999) return Quaternion.identity;
        if (d < -0.999999) {
            const axis = @import("math.zig").anyPerpendicular(f);
            return Quaternion.fromAxisAngle(axis, std.math.pi);
        }
        const c = f.cross(t);
        return (Quaternion{ .w = 1.0 + d, .x = c.x, .y = c.y, .z = c.z }).normalize();
    }

    /// Column-major rotation matrix (matches Mat4: m[col*4+row], v' = M*v).
    pub fn toMat4(q: Quaternion) Mat4 {
        const x = q.x;
        const y = q.y;
        const z = q.z;
        const w = q.w;
        var m = Mat4.identity;
        m.m[0] = 1 - 2 * (y * y + z * z);
        m.m[1] = 2 * (x * y + w * z);
        m.m[2] = 2 * (x * z - w * y);
        m.m[4] = 2 * (x * y - w * z);
        m.m[5] = 1 - 2 * (x * x + z * z);
        m.m[6] = 2 * (y * z + w * x);
        m.m[8] = 2 * (x * z + w * y);
        m.m[9] = 2 * (y * z - w * x);
        m.m[10] = 1 - 2 * (x * x + y * y);
        return m;
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

test "slerp endpoints and midpoint" {
    const a = Quaternion.identity;
    const b = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(a.slerp(b, 0).rotateVec(Vec3.init(1, 0, 0)).approxEq(Vec3.init(1, 0, 0), 1e-5));
    try std.testing.expect(a.slerp(b, 1).rotateVec(Vec3.init(1, 0, 0)).approxEq(Vec3.init(0, 1, 0), 1e-5));
    // Halfway = 45 deg about Z: (1,0,0) -> (cos45, sin45, 0).
    const h = a.slerp(b, 0.5).rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(h.approxEq(Vec3.init(0.70710677, 0.70710677, 0), 1e-4));
}

test "slerp takes the shortest path (negative dot)" {
    const a = Quaternion.identity;
    const b = Quaternion.identity.neg(); // same rotation, opposite sign
    const m = a.slerp(b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.length(), 1e-5);
    try std.testing.expect(m.rotateVec(Vec3.init(1, 2, 3)).approxEq(Vec3.init(1, 2, 3), 1e-4));
}

test "rotationBetween maps from onto to (incl. parallel and antiparallel)" {
    const from = Vec3.init(1, 0, 0);
    const to = Vec3.init(0, 0, 1);
    const q = Quaternion.rotationBetween(from, to);
    try std.testing.expect(q.rotateVec(from).approxEq(to, 1e-5));
    try std.testing.expect(Quaternion.rotationBetween(from, from).rotateVec(from).approxEq(from, 1e-5));
    const anti = Quaternion.rotationBetween(from, from.neg());
    try std.testing.expect(anti.rotateVec(from).approxEq(from.neg(), 1e-4));
}

test "toMat4 agrees with rotateVec" {
    const q = Quaternion.fromAxisAngle(Vec3.init(1, 1, 0).normalize(), 0.9);
    const v = Vec3.init(1, 2, 3);
    const by_mat = q.toMat4().mulPoint(v);
    const by_quat = q.rotateVec(v);
    try std.testing.expect(by_mat.approxEq(by_quat, 1e-4));
}

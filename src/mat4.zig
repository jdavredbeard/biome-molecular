const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

/// Column-major 4x4 matrix. m[col*4 + row]. Points are column vectors: p' = M*p.
pub const Mat4 = struct {
    m: [16]f32,

    pub const identity = Mat4{ .m = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    } };

    /// Standard matrix product a*b.
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: [16]f32 = undefined;
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) sum += a.m[k * 4 + row] * b.m[col * 4 + k];
                out[col * 4 + row] = sum;
            }
        }
        return .{ .m = out };
    }

    /// Transform a point (w = 1), with perspective divide if w != 1.
    pub fn mulPoint(self: Mat4, p: Vec3) Vec3 {
        const x = self.m[0] * p.x + self.m[4] * p.y + self.m[8] * p.z + self.m[12];
        const y = self.m[1] * p.x + self.m[5] * p.y + self.m[9] * p.z + self.m[13];
        const z = self.m[2] * p.x + self.m[6] * p.y + self.m[10] * p.z + self.m[14];
        const w = self.m[3] * p.x + self.m[7] * p.y + self.m[11] * p.z + self.m[15];
        if (@abs(w) > 1e-8 and @abs(w - 1.0) > 1e-8) {
            return Vec3.init(x / w, y / w, z / w);
        }
        return Vec3.init(x, y, z);
    }

    pub fn translation(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[12] = v.x;
        r.m[13] = v.y;
        r.m[14] = v.z;
        return r;
    }

    pub fn scale(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[0] = v.x;
        r.m[5] = v.y;
        r.m[10] = v.z;
        return r;
    }

    /// Rotation about a unit axis by angle radians (column-major Rodrigues).
    pub fn fromAxisAngle(axis: Vec3, angle: f32) Mat4 {
        const a = axis.normalize();
        const c = @cos(angle);
        const s = @sin(angle);
        const t = 1.0 - c;
        const x = a.x;
        const y = a.y;
        const z = a.z;
        var r = Mat4.identity;
        // Column 0
        r.m[0] = t * x * x + c;
        r.m[1] = t * x * y + s * z;
        r.m[2] = t * x * z - s * y;
        // Column 1
        r.m[4] = t * x * y - s * z;
        r.m[5] = t * y * y + c;
        r.m[6] = t * y * z + s * x;
        // Column 2
        r.m[8] = t * x * z + s * y;
        r.m[9] = t * y * z - s * x;
        r.m[10] = t * z * z + c;
        return r;
    }

    /// Right-handed view matrix looking from `eye` toward `center`.
    pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
        const f = center.sub(eye).normalize(); // forward
        const s = f.cross(up).normalize(); // right
        const u = s.cross(f); // true up
        var r = Mat4.identity;
        r.m[0] = s.x;
        r.m[4] = s.y;
        r.m[8] = s.z;
        r.m[1] = u.x;
        r.m[5] = u.y;
        r.m[9] = u.z;
        r.m[2] = -f.x;
        r.m[6] = -f.y;
        r.m[10] = -f.z;
        r.m[12] = -s.dot(eye);
        r.m[13] = -u.dot(eye);
        r.m[14] = f.dot(eye);
        return r;
    }

    /// Perspective projection with WebGPU/Metal clip space (z in [0, 1]).
    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const fl = 1.0 / @tan(fovy / 2.0);
        var r = Mat4{ .m = .{0} ** 16 };
        r.m[0] = fl / aspect;
        r.m[5] = fl;
        r.m[10] = far / (near - far);
        r.m[11] = -1.0;
        r.m[14] = (far * near) / (near - far);
        return r;
    }
};

fn expectMat(expected: [16]f32, actual: Mat4) !void {
    for (expected, actual.m) |e, a| try std.testing.expectApproxEqAbs(e, a, 1e-5);
}

test "identity is the multiplicative identity" {
    const i = Mat4.identity;
    try expectMat(.{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, i);
    const a = Mat4.translation(Vec3.init(3, 4, 5));
    try expectMat(a.m, a.mul(i));
    try expectMat(a.m, i.mul(a));
}

test "mulPoint applies translation then is identity-safe" {
    const t = Mat4.translation(Vec3.init(1, 2, 3));
    const p = t.mulPoint(Vec3.init(10, 20, 30));
    try std.testing.expect(p.approxEq(Vec3.init(11, 22, 33), 1e-5));
}

test "scale then translate composes as translate*scale" {
    // model = T * S : scale first, then translate.
    const m = Mat4.translation(Vec3.init(5, 0, 0)).mul(Mat4.scale(Vec3.init(2, 2, 2)));
    const p = m.mulPoint(Vec3.init(1, 0, 0)); // scaled to (2,0,0) then +5 -> (7,0,0)
    try std.testing.expect(p.approxEq(Vec3.init(7, 0, 0), 1e-5));
}

test "fromAxisAngle rotates +Y 90deg about +Z to -X... and +Z onto +X" {
    // Rotate the unit +Y vector by 90 deg about +Z -> -X.
    const r = Mat4.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(r.mulPoint(Vec3.init(0, 1, 0)).approxEq(Vec3.init(-1, 0, 0), 1e-5));
}

test "lookAt places the camera so the target maps in front (negative z)" {
    const view = Mat4.lookAt(Vec3.init(0, 0, 5), Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    // The origin (target) should be 5 units in front of the camera => view-space z = -5.
    const p = view.mulPoint(Vec3.init(0, 0, 0));
    try std.testing.expect(p.approxEq(Vec3.init(0, 0, -5), 1e-4));
}

test "perspective maps the near plane to z=0 and far plane to z=1 (WebGPU clip space)" {
    const proj = Mat4.perspective(std.math.pi / 2.0, 1.0, 1.0, 100.0);
    // A point on the near plane (view-space z = -near) -> clip z 0 after divide.
    const near_pt = proj.mulPoint(Vec3.init(0, 0, -1));
    try std.testing.expectApproxEqAbs(@as(f32, 0), near_pt.z, 1e-3);
    // A point on the far plane (view-space z = -far) -> clip z 1 after divide.
    const far_pt = proj.mulPoint(Vec3.init(0, 0, -100));
    try std.testing.expectApproxEqAbs(@as(f32, 1), far_pt.z, 1e-3);
}

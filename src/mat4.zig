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

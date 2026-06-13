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

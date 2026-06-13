const std = @import("std");

const Vec3 = @import("math.zig").Vec3;
const BondId = @import("bond.zig").BondId;

pub const AtomId = usize;

pub const AtomType = enum {
    mono, // 1 bond, no angle preference
    linear, // 2 bonds, 180 degrees
    trigonal, // 3 bonds, 120 degrees
    tetra, // 4 bonds, 109.5 degrees
};

pub const Atom = struct {
    position: Vec3,
    velocity: Vec3 = Vec3.zero,
    atom_type: AtomType,
    bonds: std.BoundedArray(BondId, 4) = .{},
    id: AtomId,
};

pub fn maxBonds(t: AtomType) usize {
    return switch (t) {
        .mono => 1,
        .linear => 2,
        .trigonal => 3,
        .tetra => 4,
    };
}

/// Preferred angle between any two bonds at this atom, in radians.
pub fn preferredAngle(t: AtomType) f32 {
    return switch (t) {
        .mono => 0, // single bond: no angle constraint
        .linear => std.math.pi,
        .trigonal => 2.0 * std.math.pi / 3.0,
        .tetra => @floatCast(std.math.acos(@as(f64, -1.0) / 3.0)),
    };
}

test "maxBonds per atom type" {
    try std.testing.expectEqual(@as(usize, 1), maxBonds(.mono));
    try std.testing.expectEqual(@as(usize, 2), maxBonds(.linear));
    try std.testing.expectEqual(@as(usize, 3), maxBonds(.trigonal));
    try std.testing.expectEqual(@as(usize, 4), maxBonds(.tetra));
}

test "preferredAngle per atom type (radians)" {
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), preferredAngle(.linear), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0 * std.math.pi / 3.0), preferredAngle(.trigonal), 1e-5);
    // 109.47 degrees = acos(-1/3).
    try std.testing.expectApproxEqAbs(@as(f32, 1.9106332), preferredAngle(.tetra), 1e-4);
}

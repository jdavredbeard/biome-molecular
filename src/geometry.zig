const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom = @import("atom.zig");
const AtomType = atom.AtomType;

const sqrt3_over_2: f32 = 0.8660254; // sqrt(3)/2
const inv_sqrt3: f32 = 0.5773503; // 1/sqrt(3)

/// Canonical (zero-existing-bond) open directions for an atom type.
/// Pairwise angles equal the type's preferred angle; all unit length.
pub fn canonical(t: AtomType) []const Vec3 {
    return switch (t) {
        .mono => &mono_dirs,
        .linear => &linear_dirs,
        .trigonal => &trigonal_dirs,
        .tetra => &tetra_dirs,
    };
}

const mono_dirs = [_]Vec3{Vec3.init(0, 0, 1)};

const linear_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(0, 0, -1),
};

// Three directions in the XZ plane, 120 degrees apart.
const trigonal_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(sqrt3_over_2, 0, -0.5),
    Vec3.init(-sqrt3_over_2, 0, -0.5),
};

// Four vertices of a regular tetrahedron, normalized. Pairwise dot = -1/3.
const tetra_dirs = [_]Vec3{
    Vec3.init(inv_sqrt3, inv_sqrt3, inv_sqrt3),
    Vec3.init(inv_sqrt3, -inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, -inv_sqrt3, inv_sqrt3),
};

test "canonical direction counts match bond counts" {
    try std.testing.expectEqual(@as(usize, 1), canonical(.mono).len);
    try std.testing.expectEqual(@as(usize, 2), canonical(.linear).len);
    try std.testing.expectEqual(@as(usize, 3), canonical(.trigonal).len);
    try std.testing.expectEqual(@as(usize, 4), canonical(.tetra).len);
}

test "canonical directions are unit vectors" {
    inline for (.{ .mono, .linear, .trigonal, .tetra }) |t| {
        for (canonical(t)) |d| {
            try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-5);
        }
    }
}

test "canonical pairwise angles equal the preferred angle" {
    inline for (.{ .linear, .trigonal, .tetra }) |t| {
        const dirs = canonical(t);
        const want = atom.preferredAngle(t);
        for (dirs, 0..) |di, i| {
            for (dirs[i + 1 ..]) |dj| {
                try std.testing.expectApproxEqAbs(want, math.angleBetween(di, dj), 1e-3);
            }
        }
    }
}

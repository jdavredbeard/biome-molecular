const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;
const Mat4 = @import("../mat4.zig").Mat4;
const Molecule = @import("../molecule.zig").Molecule;

const atom_style = @import("atom_style.zig");

pub const Sphere = struct { center: Vec3, radius: f32 };

/// Smallest-ish sphere enclosing all atoms (centroid center; radius reaches the
/// farthest atom's painted surface). Empty molecule -> unit sphere at origin.
pub fn boundingSphere(mol: *const Molecule) Sphere {
    const atoms = mol.atoms.items;
    if (atoms.len == 0) return .{ .center = Vec3.zero, .radius = 1.0 };
    var center = Vec3.zero;
    for (atoms) |atom| center = center.add(atom.position);
    center = center.scale(1.0 / @as(f32, @floatFromInt(atoms.len)));
    var radius: f32 = 0;
    for (atoms) |atom| {
        const reach = center.distance(atom.position) + atom_style.styleFor(atom.atom_type).radius;
        if (reach > radius) radius = reach;
    }
    return .{ .center = center, .radius = radius };
}

/// Camera pull-back distance: 2.5x the bounding radius, never closer than 5.0.
pub fn cameraDistance(radius: f32) f32 {
    return @max(radius * 2.5, 5.0);
}

/// View matrix: camera on +Z looking at the sphere center.
pub fn viewMatrix(s: Sphere) Mat4 {
    const eye = Vec3.init(s.center.x, s.center.y, s.center.z + cameraDistance(s.radius));
    return Mat4.lookAt(eye, s.center, Vec3.init(0, 1, 0));
}

/// Projection matrix for the given aspect ratio (45 deg vertical FOV).
pub fn projectionMatrix(aspect: f32) Mat4 {
    return Mat4.perspective(std.math.pi / 4.0, aspect, 0.1, 1000.0);
}

test "boundingSphere centers on the centroid and covers all atoms incl. radius" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // mono at (0,0,1)

    const s = boundingSphere(&mol);
    try std.testing.expect(s.center.approxEq(Vec3.init(0, 0, 0.5), 1e-4));
    // Radius reaches the far atom's surface: dist(center, atom) + atom radius.
    try std.testing.expect(s.radius > 0.5);
}

test "cameraDistance applies the 2.5x factor with a floor of 5.0" {
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), cameraDistance(0.1), 1e-5); // floored
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), cameraDistance(10.0), 1e-5); // 10*2.5
}

test "view looks at the bounding-sphere center from +z; center maps to -distance" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    const s = boundingSphere(&mol);
    const v = viewMatrix(s);
    const center_view = v.mulPoint(s.center);
    try std.testing.expectApproxEqAbs(@as(f32, -cameraDistance(s.radius)), center_view.z, 1e-3);
}

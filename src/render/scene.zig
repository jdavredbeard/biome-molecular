const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;
const Mat4 = @import("../mat4.zig").Mat4;
const Molecule = @import("../molecule.zig").Molecule;
const atom_style = @import("atom_style.zig");

/// Per-instance GPU data: a model matrix and an RGBA color (w unused).
/// `extern` for a stable layout matching the WGSL instance attributes.
pub const Instance = extern struct {
    model: [16]f32,
    color: [4]f32,
};

fn make(model: Mat4, color: [3]f32) Instance {
    return .{ .model = model.m, .color = .{ color[0], color[1], color[2], 1.0 } };
}

/// One sphere instance per atom: translate to the atom, scale by its radius.
pub fn atomInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const atoms = mol.atoms.items;
    const out = try allocator.alloc(Instance, atoms.len);
    for (atoms, 0..) |atom, i| {
        const style = atom_style.styleFor(atom.atom_type);
        const model = Mat4.translation(atom.position).mul(Mat4.scale(Vec3.init(style.radius, style.radius, style.radius)));
        out[i] = make(model, style.color);
    }
    return out;
}

/// One cylinder instance per bond: orient + scale the unit (+Y) cylinder from
/// atom A to atom B with the fixed bond radius.
pub fn bondInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const bonds = mol.bonds.items;
    const out = try allocator.alloc(Instance, bonds.len);
    const y_axis = Vec3.init(0, 1, 0);
    for (bonds, 0..) |bond, i| {
        const pa = mol.atoms.items[bond.atom_a].position;
        const pb = mol.atoms.items[bond.atom_b].position;
        const dir = pb.sub(pa);
        const len = dir.length();
        const rot = rotationToward(y_axis, dir);
        const model = Mat4.translation(pa)
            .mul(rot)
            .mul(Mat4.scale(Vec3.init(atom_style.bond_radius, len, atom_style.bond_radius)));
        out[i] = make(model, atom_style.bond_color);
    }
    return out;
}

/// Rotation mapping unit vector `from` onto the direction of `to`.
fn rotationToward(from: Vec3, to: Vec3) Mat4 {
    const d = to.normalize();
    const dot = std.math.clamp(from.dot(d), -1.0, 1.0);
    if (dot > 0.9999) return Mat4.identity;
    if (dot < -0.9999) {
        // 180 deg about any axis perpendicular to `from`.
        return Mat4.fromAxisAngle(@import("../math.zig").anyPerpendicular(from), std.math.pi);
    }
    const axis = from.cross(d).normalize();
    return Mat4.fromAxisAngle(axis, std.math.acos(dot));
}

fn modelOf(inst: Instance) Mat4 {
    return .{ .m = inst.model };
}

test "atomInstances: one per atom; model places a unit sphere at the atom, scaled by radius" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);

    const insts = try atomInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 2), insts.len);

    // Atom 0 is a tetra at origin: sphere center maps to origin; the +X surface
    // point (1,0,0) maps to (tetra_radius, 0, 0).
    const m0 = modelOf(insts[0]);
    try std.testing.expect(m0.mulPoint(Vec3.zero).approxEq(Vec3.zero, 1e-5));
    const r = atom_style.styleFor(.tetra).radius;
    try std.testing.expect(m0.mulPoint(Vec3.init(1, 0, 0)).approxEq(Vec3.init(r, 0, 0), 1e-5));
}

test "bondInstances: one per bond; cylinder endpoints map to the bonded atoms" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const b = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // bond from origin to (0,0,1)

    const insts = try bondInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 1), insts.len);

    const m = modelOf(insts[0]);
    const pa = mol.atoms.items[a].position;
    const pb = mol.atoms.items[b].position;
    // Unit cylinder runs y in [0,1]; its endpoints must map to the two atoms.
    try std.testing.expect(m.mulPoint(Vec3.init(0, 0, 0)).approxEq(pa, 1e-4));
    try std.testing.expect(m.mulPoint(Vec3.init(0, 1, 0)).approxEq(pb, 1e-4));
}

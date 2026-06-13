const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom_mod = @import("atom.zig");
const constants = @import("constants.zig");
const Constants = constants.Constants;
const molecule = @import("molecule.zig");
const Molecule = molecule.Molecule;

/// Accumulate Hooke's-law spring forces for every bond into `forces`
/// (indexed by atom id). `forces.len` must equal the atom count.
/// F = k_spring * (dist - rest_length), directed along the bond.
pub fn addSpringForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (mol.bonds.items) |b| {
        const pa = mol.atoms.items[b.atom_a].position;
        const pb = mol.atoms.items[b.atom_b].position;
        const delta = pb.sub(pa);
        const dist = delta.length();
        if (dist < 1e-8) continue;
        const dir = delta.scale(1.0 / dist);
        const f = c.k_spring * (dist - c.rest_length);
        // Positive f (stretched) pulls a toward b and b toward a.
        forces[b.atom_a] = forces[b.atom_a].add(dir.scale(f));
        forces[b.atom_b] = forces[b.atom_b].add(dir.scale(-f));
    }
}

test "spring: stretched bond pulls atoms together" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    // Place neighbor at distance 2.0 (stretched: rest_length = 1.0).
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2);

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addSpringForces(&mol, constants.default, &forces);

    // F = k*(dist - rest) = 10*(2-1) = 10. Atom a pulled toward +Z, atom b toward -Z.
    try std.testing.expectApproxEqAbs(@as(f32, 10), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -10), forces[1].z, 1e-3);
    // Equal and opposite.
    try std.testing.expect(forces[0].add(forces[1]).approxEq(Vec3.zero, 1e-4));
}

test "spring: compressed bond pushes atoms apart" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 0.5); // compressed

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addSpringForces(&mol, constants.default, &forces);

    // F = 10*(0.5-1) = -5. Atom a pushed toward -Z, atom b toward +Z.
    try std.testing.expectApproxEqAbs(@as(f32, -5), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 5), forces[1].z, 1e-3);
}

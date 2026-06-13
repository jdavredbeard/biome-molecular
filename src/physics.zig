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

/// Accumulate harmonic angle forces. For each atom with >= 2 bonds, every pair
/// of bonds (i, j) is pushed toward the atom's preferred angle. Forces are
/// applied to the neighbor atoms perpendicular to each bond (per the design
/// spec), with the reaction applied to the central atom so total momentum is
/// conserved.
pub fn addAngleForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (mol.atoms.items) |center| {
        const n = center.bonds.len;
        if (n < 2) continue;
        const preferred = atom_mod.preferredAngle(center.atom_type);
        const cpos = center.position;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const ni = mol.bonds.items[center.bonds.get(i)].other(center.id);
            const bond_i = mol.atoms.items[ni].position.sub(cpos);
            const li2 = bond_i.lengthSq();
            if (li2 < 1e-12) continue;

            var j: usize = i + 1;
            while (j < n) : (j += 1) {
                const nj = mol.bonds.items[center.bonds.get(j)].other(center.id);
                const bond_j = mol.atoms.items[nj].position.sub(cpos);
                const lj2 = bond_j.lengthSq();
                if (lj2 < 1e-12) continue;

                const li = @sqrt(li2);
                const lj = @sqrt(lj2);
                const cos_a = std.math.clamp(bond_i.dot(bond_j) / (li * lj), -1.0, 1.0);
                const angle = std.math.acos(cos_a);
                const delta = angle - preferred;
                // Positive magnitude => bonds should open (angle < preferred).
                const magnitude = -c.k_angle * delta;

                // In-plane unit vectors perpendicular to each bond, pointing
                // toward the other bond (the angle-closing direction). Using a
                // raw radial component (bond_i itself) is wrong: an angle force
                // must be perpendicular to its own bond so it changes the angle
                // rather than the bond length.
                const cross_ij = bond_i.cross(bond_j);
                if (cross_ij.lengthSq() < 1e-12) continue; // collinear: no torque axis
                var perp_i = cross_ij.cross(bond_i).normalize();
                var perp_j = bond_j.cross(cross_ij).normalize();

                // To OPEN the angle (magnitude > 0) push neighbors away from the
                // other bond, i.e. opposite the closing direction.
                perp_i = perp_i.neg();
                perp_j = perp_j.neg();

                const fi = perp_i.scale(magnitude / li);
                const fj = perp_j.scale(magnitude / lj);

                forces[ni] = forces[ni].add(fi);
                forces[nj] = forces[nj].add(fj);
                forces[center.id] = forces[center.id].add(fi.add(fj).neg()); // reaction
            }
        }
    }
}

/// Accumulate steric repulsion between non-bonded atom pairs closer than
/// `repulsion_threshold`. F = k_repel / dist^2, directed apart.
pub fn addRepulsionForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    const atoms = mol.atoms.items;
    var i: usize = 0;
    while (i < atoms.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < atoms.len) : (j += 1) {
            if (areBonded(mol, atoms[i].id, atoms[j].id)) continue;
            const delta = atoms[j].position.sub(atoms[i].position);
            const dist = delta.length();
            if (dist >= c.repulsion_threshold or dist < 1e-6) continue;
            const dir = delta.scale(1.0 / dist);
            const f = c.k_repel / (dist * dist);
            forces[atoms[i].id] = forces[atoms[i].id].add(dir.scale(-f));
            forces[atoms[j].id] = forces[atoms[j].id].add(dir.scale(f));
        }
    }
}

fn areBonded(mol: *const Molecule, a: atom_mod.AtomId, b: atom_mod.AtomId) bool {
    for (mol.atoms.items[a].bonds.slice()) |bond_id| {
        if (mol.bonds.items[bond_id].other(a) == b) return true;
    }
    return false;
}

/// Number of integration substeps run per `simulate` call for stability.
pub const substeps: usize = 4;

/// Zero `forces`, then accumulate spring + angle + repulsion contributions.
pub fn computeForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (forces) |*f| f.* = Vec3.zero;
    addSpringForces(mol, c, forces);
    addAngleForces(mol, c, forces);
    addRepulsionForces(mol, c, forces);
}

/// Total kinetic energy assuming unit mass: sum of 0.5 * |v|^2.
pub fn kineticEnergy(mol: *const Molecule) f32 {
    var ke: f32 = 0;
    for (mol.atoms.items) |a| ke += 0.5 * a.velocity.lengthSq();
    return ke;
}

/// One integration substep: semi-implicit (symplectic) Euler with velocity
/// damping. Unit mass, so acceleration == force.
fn step(mol: *Molecule, c: Constants, dt: f32, forces: []Vec3) void {
    computeForces(mol, c, forces);
    for (mol.atoms.items, 0..) |*a, i| {
        a.velocity = a.velocity.add(forces[i].scale(dt));
        a.velocity = a.velocity.scale(c.damping);
        a.position = a.position.add(a.velocity.scale(dt));
    }
}

/// Advance the simulation by one frame (`substeps` substeps of `c.dt /
/// substeps` each). Returns true once the molecule reaches equilibrium:
/// both kinetic energy AND net force are below the convergence threshold.
/// (Kinetic energy alone is insufficient — it dips to ~0 at every oscillation
/// turning point, where the restoring force is still large, which would report
/// "settled" mid-swing far from rest.)
pub fn simulate(mol: *Molecule, c: Constants, allocator: std.mem.Allocator) !bool {
    const forces = try allocator.alloc(Vec3, mol.atoms.items.len);
    defer allocator.free(forces);
    const sub_dt = c.dt / @as(f32, @floatFromInt(substeps));
    var s: usize = 0;
    while (s < substeps) : (s += 1) step(mol, c, sub_dt, forces);
    // Re-evaluate forces at the final positions to test for true rest.
    computeForces(mol, c, forces);
    return kineticEnergy(mol) < c.convergence_threshold and netForceSq(forces) < c.convergence_threshold;
}

/// Sum of squared force magnitudes across all atoms (a scalar "how far from
/// force equilibrium" measure).
fn netForceSq(forces: []const Vec3) f32 {
    var sum: f32 = 0;
    for (forces) |f| sum += f.lengthSq();
    return sum;
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

test "angle: forces on the three atoms sum to zero (momentum conserved)" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(center, Vec3.init(1, 0, 0), .mono); // neighbor 1 at +X
    _ = try mol.addAtom(center, Vec3.init(0, 1, 0), .mono); // neighbor 2 at +Y (90 deg, want 180)

    var forces = [_]Vec3{Vec3.zero} ** 3;
    addAngleForces(&mol, constants.default, &forces);

    const total = forces[0].add(forces[1]).add(forces[2]);
    try std.testing.expect(total.approxEq(Vec3.zero, 1e-4));
}

test "angle: a bent linear atom is pushed toward straight (angle increases)" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.linear);
    const n1 = try mol.addAtom(center, Vec3.init(1, 0, 0), .mono);
    const n2 = try mol.addAtom(center, Vec3.init(0, 1, 0), .mono);

    const before = math.angleBetween(
        mol.atoms.items[n1].position.sub(mol.atoms.items[center].position),
        mol.atoms.items[n2].position.sub(mol.atoms.items[center].position),
    );

    // Take one tiny explicit step using only angle forces.
    var forces = [_]Vec3{Vec3.zero} ** 3;
    addAngleForces(&mol, constants.default, &forces);
    const h: f32 = 0.01;
    for (mol.atoms.items, 0..) |*atom, i| atom.position = atom.position.add(forces[i].scale(h));

    const after = math.angleBetween(
        mol.atoms.items[n1].position.sub(mol.atoms.items[center].position),
        mol.atoms.items[n2].position.sub(mol.atoms.items[center].position),
    );
    try std.testing.expect(after > before); // moving toward 180 degrees
}

test "angle: a single-bond atom contributes no angle force" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(1, 0, 0), .mono);

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addAngleForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}

test "repulsion: close non-bonded atoms push apart" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    // Two unbonded atoms 0.5 apart along Z (< repulsion_threshold 0.8).
    _ = try mol.addFirstAtom(.mono);
    try mol.atoms.append(.{ .position = Vec3.init(0, 0, 0.5), .atom_type = .mono, .id = 1 });

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);

    // F = k_repel / dist^2 = 2 / 0.25 = 8. Atom 0 toward -Z, atom 1 toward +Z.
    try std.testing.expectApproxEqAbs(@as(f32, -8), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 8), forces[1].z, 1e-3);
}

test "repulsion: atoms beyond the threshold feel nothing" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    try mol.atoms.append(.{ .position = Vec3.init(0, 0, 1.5), .atom_type = .mono, .id = 1 });

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}

test "repulsion: directly bonded atoms are excluded" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // bonded, dist 1.0 anyway
    mol.atoms.items[1].position = Vec3.init(0, 0, 0.5); // pull within threshold

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}

test "computeForces aggregates spring + angle + repulsion" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2); // stretched bond

    var forces = [_]Vec3{Vec3.zero} ** 2;
    computeForces(&mol, constants.default, &forces);
    // At minimum the spring contribution must be present.
    try std.testing.expect(@abs(forces[0].z) > 1e-3);
}

test "kineticEnergy sums 0.5*v^2 over atoms" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    mol.atoms.items[0].velocity = Vec3.init(0, 0, 2); // KE = 0.5 * 4 = 2
    try std.testing.expectApproxEqAbs(@as(f32, 2), kineticEnergy(&mol), 1e-5);
}

test "simulate settles a stretched two-atom bond toward rest length" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2); // stretched

    var settled = false;
    var iterations: usize = 0;
    while (!settled and iterations < 5000) : (iterations += 1) {
        settled = try simulate(&mol, constants.default, std.testing.allocator);
    }
    try std.testing.expect(settled);
    const dist = mol.atoms.items[0].position.distance(mol.atoms.items[1].position);
    try std.testing.expectApproxEqAbs(constants.default.rest_length, dist, 0.05);
}

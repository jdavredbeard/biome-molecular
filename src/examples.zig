const std = @import("std");
const Vec3 = @import("math.zig").Vec3;
const Molecule = @import("molecule.zig").Molecule;
const OpenBondPoint = @import("molecule.zig").OpenBondPoint;

const AtomType = @import("atom.zig").AtomType;

/// Place `atom_type` on the first currently-open bond point of `parent`.
/// Returns the new atom id. Asserts the parent has an open point.
fn addOnOpenPoint(mol: *Molecule, scratch: *std.ArrayList(OpenBondPoint), parent: usize, atom_type: AtomType) !usize {
    try mol.openBondPoints(scratch);
    for (scratch.items) |p| {
        if (p.parent_atom == parent) return try mol.addAtom(parent, p.direction, atom_type);
    }
    unreachable; // caller guarantees an open point exists on `parent`
}

pub fn buildMethane(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var i: usize = 0;
    while (i < 4) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c, .mono);
    return mol;
}

pub fn buildChain(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    var prev = try mol.addFirstAtom(.linear);
    var i: usize = 1;
    while (i < 6) : (i += 1) {
        // A linear atom with one bond opens straight ahead; reuse +Z for simplicity.
        prev = try mol.addAtom(prev, Vec3.init(0, 0, 1), .linear);
    }
    return mol;
}

pub fn buildTrigonalStar(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c = try mol.addFirstAtom(.trigonal);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var i: usize = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c, .mono);
    return mol;
}

test "methane: 1 tetra + 4 mono caps, 4 bonds" {
    var mol = try buildMethane(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 5), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 4), mol.bonds.items.len);
}

test "linear chain: 6 atoms, 5 bonds" {
    var mol = try buildChain(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 6), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 5), mol.bonds.items.len);
}

test "trigonal star: 1 trigonal + 3 mono, 3 bonds" {
    var mol = try buildTrigonalStar(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 4), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 3), mol.bonds.items.len);
}

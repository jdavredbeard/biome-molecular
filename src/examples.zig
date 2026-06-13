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

pub fn buildEthane(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c0 = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    const c1 = try addOnOpenPoint(&mol, &scratch, c0, .tetra); // tetra-tetra bond
    // Cap the 3 remaining open points on each tetra with mono.
    var i: usize = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c0, .mono);
    i = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c1, .mono);
    return mol;
}

pub fn buildBranchedBlob(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const center = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var arms: [4]usize = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) arms[i] = try addOnOpenPoint(&mol, &scratch, center, .tetra);
    // Cap each arm's 3 remaining points with mono.
    for (arms) |arm| {
        var j: usize = 0;
        while (j < 3) : (j += 1) _ = try addOnOpenPoint(&mol, &scratch, arm, .mono);
    }
    return mol;
}

pub fn buildTrigonalSheet(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const center = try mol.addFirstAtom(.trigonal);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var arms: [3]usize = undefined;
    var i: usize = 0;
    while (i < 3) : (i += 1) arms[i] = try addOnOpenPoint(&mol, &scratch, center, .trigonal);
    // Each outer trigonal has 2 remaining open points -> cap with mono.
    for (arms) |arm| {
        var j: usize = 0;
        while (j < 2) : (j += 1) _ = try addOnOpenPoint(&mol, &scratch, arm, .mono);
    }
    return mol;
}

pub const Example = struct {
    name: []const u8,
    build: *const fn (std.mem.Allocator) anyerror!Molecule,
};

pub const all = [_]Example{
    .{ .name = "Methane", .build = buildMethane },
    .{ .name = "Linear chain", .build = buildChain },
    .{ .name = "Trigonal star", .build = buildTrigonalStar },
    .{ .name = "Ethane-like", .build = buildEthane },
    .{ .name = "Branched blob", .build = buildBranchedBlob },
    .{ .name = "Trigonal sheet", .build = buildTrigonalSheet },
};

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

test "ethane-like: two tetra + 6 mono caps = 8 atoms, 7 bonds" {
    var mol = try buildEthane(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 8), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 7), mol.bonds.items.len);
}

test "branched blob: tetra + 4 tetra + 12 mono caps = 17 atoms, 16 bonds" {
    var mol = try buildBranchedBlob(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 17), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 16), mol.bonds.items.len);
}

test "trigonal sheet: trigonal + 3 trigonal + 6 mono caps = 10 atoms, 9 bonds" {
    var mol = try buildTrigonalSheet(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 10), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 9), mol.bonds.items.len);
}

test "registry lists every example and each builds + settles" {
    const physics = @import("physics.zig");
    const constants = @import("constants.zig");
    try std.testing.expect(all.len == 6);
    for (all) |ex| {
        var mol = try ex.build(std.testing.allocator);
        defer mol.deinit();
        try std.testing.expect(mol.atoms.items.len >= 1);
        var settled = false;
        var iters: usize = 0;
        while (!settled and iters < 20000) : (iters += 1) {
            settled = try physics.simulate(&mol, constants.default, std.testing.allocator);
        }
        try std.testing.expect(settled);
    }
}

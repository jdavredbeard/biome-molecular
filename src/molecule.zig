const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const AtomId = atom_mod.AtomId;
const AtomType = atom_mod.AtomType;
const bond_mod = @import("bond.zig");
const Bond = bond_mod.Bond;
const geometry = @import("geometry.zig");
const constants = @import("constants.zig");

pub const BondPointId = usize;

pub const OpenBondPoint = struct {
    parent_atom: AtomId,
    direction: Vec3, // unit vector from the parent atom, at the preferred angle
    id: BondPointId,
};

pub const Molecule = struct {
    atoms: std.ArrayList(Atom),
    bonds: std.ArrayList(Bond),
    rest_length: f32,

    pub fn init(allocator: std.mem.Allocator) Molecule {
        return .{
            .atoms = std.ArrayList(Atom).init(allocator),
            .bonds = std.ArrayList(Bond).init(allocator),
            .rest_length = constants.default.rest_length,
        };
    }

    pub fn deinit(self: *Molecule) void {
        self.atoms.deinit();
        self.bonds.deinit();
    }

    /// Place the first atom at the origin. Errors if atoms already exist.
    pub fn addFirstAtom(self: *Molecule, atom_type: AtomType) !AtomId {
        std.debug.assert(self.atoms.items.len == 0);
        const id: AtomId = self.atoms.items.len;
        try self.atoms.append(.{ .position = Vec3.zero, .atom_type = atom_type, .id = id });
        return id;
    }

    /// Place a new atom at `parent.position + direction * rest_length` and bond
    /// it to `parent`. `direction` should be a unit vector (typically an open
    /// bond point's direction).
    pub fn addAtom(self: *Molecule, parent: AtomId, direction: Vec3, atom_type: AtomType) !AtomId {
        const parent_pos = self.atoms.items[parent].position;
        const new_pos = parent_pos.add(direction.scale(self.rest_length));
        const new_id: AtomId = self.atoms.items.len;
        try self.atoms.append(.{ .position = new_pos, .atom_type = atom_type, .id = new_id });

        const bond_id = self.bonds.items.len;
        try self.bonds.append(.{ .atom_a = parent, .atom_b = new_id, .id = bond_id });
        self.atoms.items[parent].bonds.appendAssumeCapacity(bond_id);
        self.atoms.items[new_id].bonds.appendAssumeCapacity(bond_id);
        return new_id;
    }

    pub fn centerOfMass(self: *const Molecule) Vec3 {
        if (self.atoms.items.len == 0) return Vec3.zero;
        var sum = Vec3.zero;
        for (self.atoms.items) |a| sum = sum.add(a.position);
        return sum.scale(1.0 / @as(f32, @floatFromInt(self.atoms.items.len)));
    }

    /// Unit vector from `from_atom` toward the neighbor across `bond_id`.
    pub fn bondDirection(self: *const Molecule, from_atom: AtomId, bond_id: usize) Vec3 {
        const b = self.bonds.items[bond_id];
        const neighbor = b.other(from_atom);
        return self.atoms.items[neighbor].position.sub(self.atoms.items[from_atom].position).normalize();
    }
};

test "addFirstAtom places a tetra at the origin with no bonds" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const id = try mol.addFirstAtom(.tetra);
    try std.testing.expectEqual(@as(usize, 0), id);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items.len);
    try std.testing.expect(mol.atoms.items[0].position.approxEq(Vec3.zero, 1e-6));
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items[0].bonds.len);
}

test "addAtom creates a neighbor at rest_length and bonds both ends" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const dir = Vec3.init(0, 0, 1);
    const b = try mol.addAtom(a, dir, .mono);
    try std.testing.expectEqual(@as(usize, 1), b);
    try std.testing.expectEqual(@as(usize, 1), mol.bonds.items.len);
    // New atom sits rest_length away along dir.
    try std.testing.expect(mol.atoms.items[b].position.approxEq(dir.scale(constants.default.rest_length), 1e-5));
    // Both atoms reference the bond.
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[a].bonds.len);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[b].bonds.len);
}

test "centerOfMass averages atom positions" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // at (0,0,1)
    try std.testing.expect(mol.centerOfMass().approxEq(Vec3.init(0, 0, 0.5), 1e-5));
}

test "bondDirection returns the unit vector from an atom to its bonded neighbor" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const b = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    const bond_id = mol.atoms.items[a].bonds.get(0);
    try std.testing.expect(mol.bondDirection(a, bond_id).approxEq(Vec3.init(0, 0, 1), 1e-5));
    try std.testing.expect(mol.bondDirection(b, bond_id).approxEq(Vec3.init(0, 0, -1), 1e-5));
}

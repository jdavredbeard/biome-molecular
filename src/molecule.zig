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
const physics = @import("physics.zig");

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

    /// Remove the most recently added atom and its bond(s). Intended for undoing
    /// the last `addAtom` (e.g. a placement ghost): that atom's bonds are the
    /// trailing entries of `bonds`, so they pop cleanly without invalidating
    /// other bond ids. Asserts there is at least one atom.
    pub fn removeLastAtom(self: *Molecule) void {
        std.debug.assert(self.atoms.items.len > 0);
        const last_index = self.atoms.items.len - 1;
        const last = self.atoms.items[last_index];

        // Detach each of this atom's bonds from the neighbor's bond list.
        for (last.bonds.slice()) |bond_id| {
            const neighbor = self.bonds.items[bond_id].other(last.id);
            const nb = &self.atoms.items[neighbor].bonds;
            var i: usize = 0;
            while (i < nb.len) : (i += 1) {
                if (nb.get(i) == bond_id) {
                    _ = nb.swapRemove(i);
                    break;
                }
            }
        }

        // Pop this atom's bonds (the trailing entries) and the atom itself.
        var remaining = last.bonds.len;
        while (remaining > 0) : (remaining -= 1) _ = self.bonds.pop();
        _ = self.atoms.pop();
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

    /// Recompute all open bond points across the molecule into `out`
    /// (cleared first). IDs are assigned sequentially and are valid only
    /// until the next recompute.
    pub fn openBondPoints(self: *const Molecule, out: *std.ArrayList(OpenBondPoint)) !void {
        out.clearRetainingCapacity();
        var next_id: BondPointId = 0;
        for (self.atoms.items) |a| {
            // Gather unit directions of this atom's existing bonds.
            var existing: std.BoundedArray(Vec3, 4) = .{};
            for (a.bonds.slice()) |bond_id| {
                existing.appendAssumeCapacity(self.bondDirection(a.id, bond_id));
            }
            var dirs: std.BoundedArray(Vec3, 4) = .{};
            geometry.openDirections(a.atom_type, existing.slice(), &dirs);
            for (dirs.slice()) |d| {
                try out.append(.{ .parent_atom = a.id, .direction = d, .id = next_id });
                next_id += 1;
            }
        }
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

test "openBondPoints: lone tetra exposes 4 open points" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    var out = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer out.deinit();
    try mol.openBondPoints(&out);

    try std.testing.expectEqual(@as(usize, 4), out.items.len);
    for (out.items) |p| {
        try std.testing.expectEqual(@as(AtomId, 0), p.parent_atom);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.direction.length(), 1e-5);
    }
}

test "openBondPoints: after one bond, parent exposes its remaining open points" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, geometry.canonical(.tetra)[0], .mono); // mono caps -> no open points there

    var out = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer out.deinit();
    try mol.openBondPoints(&out);

    // Tetra parent now has 1 bond -> 3 open points; mono child has 0.
    try std.testing.expectEqual(@as(usize, 3), out.items.len);
    const want = atom_mod.preferredAngle(.tetra);
    const used = geometry.canonical(.tetra)[0];
    for (out.items) |p| {
        try std.testing.expectEqual(@as(AtomId, a), p.parent_atom);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(used, p.direction), 1e-3);
    }
}

test "end-to-end: build a tetra+3 molecule, settle it, bonds reach rest length" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.tetra);

    // Attach three mono caps along three of the tetra's open directions.
    var open = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer open.deinit();
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        try mol.openBondPoints(&open);
        // Always grab an open point on the center atom.
        var dir: Vec3 = undefined;
        for (open.items) |p| {
            if (p.parent_atom == center) {
                dir = p.direction;
                break;
            }
        }
        _ = try mol.addAtom(center, dir, .mono);
    }
    try std.testing.expectEqual(@as(usize, 4), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 3), mol.bonds.items.len);

    // Settle.
    var settled = false;
    var iters: usize = 0;
    while (!settled and iters < 20000) : (iters += 1) {
        settled = try physics.simulate(&mol, constants.default, std.testing.allocator);
    }
    try std.testing.expect(settled);

    // Every bond should be near rest length, and no atoms overlapping.
    for (mol.bonds.items) |b| {
        const d = mol.atoms.items[b.atom_a].position.distance(mol.atoms.items[b.atom_b].position);
        try std.testing.expectApproxEqAbs(constants.default.rest_length, d, 0.1);
    }
}

test "removeLastAtom undoes the last addAtom" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    try std.testing.expectEqual(@as(usize, 2), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 1), mol.bonds.items.len);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[a].bonds.len);

    mol.removeLastAtom();

    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.bonds.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items[a].bonds.len);
}

test "removeLastAtom on a lone first atom leaves it empty" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);
    mol.removeLastAtom();
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.bonds.items.len);
}

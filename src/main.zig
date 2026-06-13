const std = @import("std");
const lib = @import("root.zig");
const Vec3 = lib.math.Vec3;
const Molecule = lib.molecule.Molecule;
const OpenBondPoint = lib.molecule.OpenBondPoint;
const constants = lib.constants;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mol = Molecule.init(allocator);
    defer mol.deinit();

    const center = try mol.addFirstAtom(.tetra);

    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();

    // Cap all four tetra bonds with mono atoms.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try mol.openBondPoints(&open);
        var dir: ?Vec3 = null;
        for (open.items) |p| {
            if (p.parent_atom == center) {
                dir = p.direction;
                break;
            }
        }
        if (dir) |d| _ = try mol.addAtom(center, d, .mono) else break;
    }

    var settled = false;
    var frames: usize = 0;
    while (!settled and frames < 100000) : (frames += 1) {
        settled = try lib.physics.simulate(&mol, constants.default, allocator);
    }

    std.debug.print("settled after {d} frames\n", .{frames});
    for (mol.atoms.items) |a| {
        std.debug.print("atom {d} ({s}) pos=({d:.3}, {d:.3}, {d:.3})\n", .{
            a.id, @tagName(a.atom_type), a.position.x, a.position.y, a.position.z,
        });
    }
}

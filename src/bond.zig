const std = @import("std");

const AtomId = @import("atom.zig").AtomId;

pub const BondId = usize;

pub const Bond = struct {
    atom_a: AtomId,
    atom_b: AtomId,
    id: BondId,

    /// Given one endpoint, return the other.
    pub fn other(self: Bond, id: AtomId) AtomId {
        return if (self.atom_a == id) self.atom_b else self.atom_a;
    }
};

test "Bond.other returns the opposite endpoint" {
    const b = Bond{ .atom_a = 3, .atom_b = 7, .id = 0 };
    try std.testing.expectEqual(@as(usize, 7), b.other(3));
    try std.testing.expectEqual(@as(usize, 3), b.other(7));
}

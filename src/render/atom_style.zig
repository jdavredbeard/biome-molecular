const std = @import("std");
const AtomType = @import("../atom.zig").AtomType;

pub const Style = struct {
    radius: f32,
    color: [3]f32,
};

/// Visual radius + RGB color per atom type. Sizes grow with bond count so the
/// structure is readable; colors are distinct.
pub fn styleFor(t: AtomType) Style {
    return switch (t) {
        .mono => .{ .radius = 0.25, .color = .{ 0.80, 0.80, 0.85 } }, // light grey
        .linear => .{ .radius = 0.32, .color = .{ 0.30, 0.55, 0.95 } }, // blue
        .trigonal => .{ .radius = 0.38, .color = .{ 0.30, 0.80, 0.45 } }, // green
        .tetra => .{ .radius = 0.45, .color = .{ 0.95, 0.55, 0.25 } }, // orange
    };
}

/// Bonds render as thin cylinders of this radius.
pub const bond_radius: f32 = 0.08;

/// Bond cylinder color (neutral grey).
pub const bond_color = [3]f32{ 0.6, 0.6, 0.65 };

test "each atom type has a distinct radius, increasing with bond count" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), styleFor(.mono).radius, 1e-6);
    try std.testing.expect(styleFor(.linear).radius > styleFor(.mono).radius);
    try std.testing.expect(styleFor(.trigonal).radius > styleFor(.linear).radius);
    try std.testing.expect(styleFor(.tetra).radius > styleFor(.trigonal).radius);
}

test "colors differ between types" {
    const a = styleFor(.mono).color;
    const b = styleFor(.tetra).color;
    try std.testing.expect(a[0] != b[0] or a[1] != b[1] or a[2] != b[2]);
}

test "bond style has a small positive radius" {
    try std.testing.expect(bond_radius > 0 and bond_radius < styleFor(.mono).radius);
}

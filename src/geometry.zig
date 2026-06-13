const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom = @import("atom.zig");
const AtomType = atom.AtomType;

const sqrt3_over_2: f32 = 0.8660254; // sqrt(3)/2
const inv_sqrt3: f32 = 0.5773503; // 1/sqrt(3)

/// Canonical (zero-existing-bond) open directions for an atom type.
/// Pairwise angles equal the type's preferred angle; all unit length.
pub fn canonical(t: AtomType) []const Vec3 {
    return switch (t) {
        .mono => &mono_dirs,
        .linear => &linear_dirs,
        .trigonal => &trigonal_dirs,
        .tetra => &tetra_dirs,
    };
}

const mono_dirs = [_]Vec3{Vec3.init(0, 0, 1)};

const linear_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(0, 0, -1),
};

// Three directions in the XZ plane, 120 degrees apart.
const trigonal_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(sqrt3_over_2, 0, -0.5),
    Vec3.init(-sqrt3_over_2, 0, -0.5),
};

// Four vertices of a regular tetrahedron, normalized. Pairwise dot = -1/3.
const tetra_dirs = [_]Vec3{
    Vec3.init(inv_sqrt3, inv_sqrt3, inv_sqrt3),
    Vec3.init(inv_sqrt3, -inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, -inv_sqrt3, inv_sqrt3),
};

/// Compute open bond directions for an atom of type `t` given the unit
/// directions of its already-existing bonds. Results are written to `out`
/// (cleared first). All returned vectors are unit length.
pub fn openDirections(
    t: AtomType,
    existing: []const Vec3,
    out: *std.BoundedArray(Vec3, 4),
) void {
    out.len = 0;
    const cano = canonical(t);
    const m = existing.len;
    if (m >= cano.len) return; // fully bonded: no open points

    if (m == 0) {
        for (cano) |d| out.appendAssumeCapacity(d);
        return;
    }

    if (m == 1) {
        switch (t) {
            .mono => {}, // unreachable: cano.len == 1, handled above
            .linear => out.appendAssumeCapacity(existing[0].neg()),
            .trigonal, .tetra => alignWithDOF(cano, existing[0], out),
        }
        return;
    }

    // m >= 2 handled in Task 8.
    openDirectionsMulti(t, existing, out);
}

/// One-existing-bond case for trigonal/tetra. Aligns the canonical frame so
/// canonical[0] maps onto the existing bond, then rotates the remaining
/// directions about the bond axis to keep one open point as close to world +Y
/// as possible (resolves the rotational degree of freedom deterministically).
fn alignWithDOF(cano: []const Vec3, e: Vec3, out: *std.BoundedArray(Vec3, 4)) void {
    const r = math.rotationAxisAngle(cano[0], e);
    var cand: std.BoundedArray(Vec3, 4) = .{};
    for (cano[1..]) |c| cand.appendAssumeCapacity(math.rodrigues(c, r.axis, r.angle));

    // Maximize the +Y component of cand[0] over rotation phi about axis e.
    // y(phi) = a*cos(phi) + b*sin(phi) + const, maximized at phi = atan2(b, a).
    const v0 = cand.get(0);
    const a = v0.y - e.y * e.dot(v0);
    const b = e.cross(v0).y;
    var phi: f32 = 0;
    if (a * a + b * b > 1e-10) phi = std.math.atan2(b, a);

    for (cand.slice()) |v| out.appendAssumeCapacity(math.rodrigues(v, e, phi));
}

// Placeholder until Task 8; keeps the file compiling.
fn openDirectionsMulti(t: AtomType, existing: []const Vec3, out: *std.BoundedArray(Vec3, 4)) void {
    _ = t;
    _ = existing;
    _ = out;
}

test "canonical direction counts match bond counts" {
    try std.testing.expectEqual(@as(usize, 1), canonical(.mono).len);
    try std.testing.expectEqual(@as(usize, 2), canonical(.linear).len);
    try std.testing.expectEqual(@as(usize, 3), canonical(.trigonal).len);
    try std.testing.expectEqual(@as(usize, 4), canonical(.tetra).len);
}

test "canonical directions are unit vectors" {
    inline for (.{ .mono, .linear, .trigonal, .tetra }) |t| {
        for (canonical(t)) |d| {
            try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-5);
        }
    }
}

test "canonical pairwise angles equal the preferred angle" {
    inline for (.{ .linear, .trigonal, .tetra }) |t| {
        const dirs = canonical(t);
        const want = atom.preferredAngle(t);
        for (dirs, 0..) |di, i| {
            for (dirs[i + 1 ..]) |dj| {
                try std.testing.expectApproxEqAbs(want, math.angleBetween(di, dj), 1e-3);
            }
        }
    }
}

test "openDirections with 0 bonds returns the canonical set" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    openDirections(.tetra, &.{}, &out);
    try std.testing.expectEqual(@as(usize, 4), out.len);
    for (out.slice(), 0..) |d, i| {
        try std.testing.expect(d.approxEq(canonical(.tetra)[i], 1e-5));
    }
}

test "openDirections: mono with 1 bond has no open points" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    openDirections(.mono, &.{Vec3.init(0, 0, 1)}, &out);
    try std.testing.expectEqual(@as(usize, 0), out.len);
}

test "openDirections: linear with 1 bond points opposite" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(0, 0, 1);
    openDirections(.linear, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 1), out.len);
    try std.testing.expect(out.get(0).approxEq(e.neg(), 1e-5));
}

test "openDirections: tetra with 1 bond yields 3 dirs at the tetrahedral angle" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(0, 0, 1);
    openDirections(.tetra, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 3), out.len);
    const want = atom.preferredAngle(.tetra);
    for (out.slice()) |d| {
        try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-4);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e, d), 1e-3);
    }
    // Open dirs are also at the tetrahedral angle to each other.
    try std.testing.expectApproxEqAbs(want, math.angleBetween(out.get(0), out.get(1)), 1e-3);
}

test "openDirections: trigonal with 1 bond yields 2 coplanar dirs at 120 deg" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(1, 0, 0);
    openDirections(.trigonal, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 2), out.len);
    const want = atom.preferredAngle(.trigonal);
    for (out.slice()) |d| {
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e, d), 1e-3);
    }
}

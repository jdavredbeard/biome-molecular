const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;
const Mat4 = @import("../mat4.zig").Mat4;
const Molecule = @import("../molecule.zig").Molecule;
const OpenBondPoint = @import("../molecule.zig").OpenBondPoint;
const atom_style = @import("atom_style.zig");

pub const marker_offset: f32 = 0.6;
pub const marker_radius: f32 = 0.12;
const selected_scale: f32 = 1.6;
const marker_color = [3]f32{ 0.40, 0.85, 0.90 };
const selected_color = [3]f32{ 0.75, 1.0, 1.0 };

/// Per-instance GPU data: a model matrix and an RGBA color (w unused).
/// `extern` for a stable layout matching the WGSL instance attributes.
pub const Instance = extern struct {
    model: [16]f32,
    color: [4]f32,
};

fn make(model: Mat4, color: [3]f32) Instance {
    return .{ .model = model.m, .color = .{ color[0], color[1], color[2], 1.0 } };
}

// Per-duplicate hue/value shifts so successive atoms of the same type look
// distinctly different (not just brighter/darker). Ordinal 0 = exact base.
const hue_shifts = [_]f32{ 0.0, 0.13, -0.17, 0.27, -0.31, 0.42, -0.46, 0.20 };
const val_shifts = [_]f32{ 0.0, 0.12, -0.14, -0.07, 0.16, -0.18, 0.09, -0.05 };

fn rgbToHsv(c: [3]f32) [3]f32 {
    const r = c[0];
    const g = c[1];
    const b = c[2];
    const max = @max(r, @max(g, b));
    const min = @min(r, @min(g, b));
    const d = max - min;
    const v = max;
    const s = if (max <= 1e-6) 0.0 else d / max;
    var h: f32 = 0;
    if (d > 1e-6) {
        if (max == r) {
            h = @mod((g - b) / d, 6.0);
        } else if (max == g) {
            h = (b - r) / d + 2.0;
        } else {
            h = (r - g) / d + 4.0;
        }
        h /= 6.0;
        if (h < 0) h += 1.0;
    }
    return .{ h, s, v };
}

fn hsvToRgb(c: [3]f32) [3]f32 {
    const h = c[0];
    const s = c[1];
    const v = c[2];
    const i = @floor(h * 6.0);
    const f = h * 6.0 - i;
    const p = v * (1.0 - s);
    const q = v * (1.0 - f * s);
    const t = v * (1.0 - (1.0 - f) * s);
    const sector = @as(i32, @intFromFloat(i)) ;
    return switch (@mod(sector, 6)) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        else => .{ v, p, q },
    };
}

fn variedColor(base: [3]f32, ordinal: usize) [3]f32 {
    if (ordinal == 0) return base;
    var hsv = rgbToHsv(base);
    hsv[0] = @mod(hsv[0] + hue_shifts[ordinal % hue_shifts.len] + 1.0, 1.0);
    hsv[2] = std.math.clamp(hsv[2] * (1.0 + val_shifts[ordinal % val_shifts.len]), 0.0, 1.0);
    return hsvToRgb(hsv);
}

/// One sphere instance per atom: translate to the atom, scale by its radius.
/// Atoms of a type that already appears earlier get a slightly shifted shade so
/// duplicates of the same type are visually distinguishable.
pub fn atomInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const atoms = mol.atoms.items;
    const out = try allocator.alloc(Instance, atoms.len);
    var type_counts = [_]usize{0} ** 4;
    for (atoms, 0..) |atom, i| {
        const style = atom_style.styleFor(atom.atom_type);
        const ordinal = type_counts[@intFromEnum(atom.atom_type)];
        type_counts[@intFromEnum(atom.atom_type)] += 1;
        const color = variedColor(style.color, ordinal);
        const model = Mat4.translation(atom.position).mul(Mat4.scale(Vec3.init(style.radius, style.radius, style.radius)));
        out[i] = make(model, color);
    }
    return out;
}

/// One cylinder instance per bond: orient + scale the unit (+Y) cylinder from
/// atom A to atom B with the fixed bond radius.
pub fn bondInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const bonds = mol.bonds.items;
    const out = try allocator.alloc(Instance, bonds.len);
    const y_axis = Vec3.init(0, 1, 0);
    for (bonds, 0..) |bond, i| {
        const pa = mol.atoms.items[bond.atom_a].position;
        const pb = mol.atoms.items[bond.atom_b].position;
        const dir = pb.sub(pa);
        const len = dir.length();
        const rot = rotationToward(y_axis, dir);
        const model = Mat4.translation(pa)
            .mul(rot)
            .mul(Mat4.scale(Vec3.init(atom_style.bond_radius, len, atom_style.bond_radius)));
        out[i] = make(model, atom_style.bond_color);
    }
    return out;
}

/// One marker instance per open bond point. The `selected` index is drawn
/// larger (scaled by `selected_scale * pulse`) and brighter. Markers sit
/// `marker_offset` out from their parent atom along the open direction.
pub fn openPointInstances(allocator: std.mem.Allocator, mol: *const Molecule, selected: usize, pulse: f32) ![]Instance {
    var pts = std.ArrayList(OpenBondPoint).init(allocator);
    defer pts.deinit();
    try mol.openBondPoints(&pts);

    const out = try allocator.alloc(Instance, pts.items.len);
    for (pts.items, 0..) |p, i| {
        const parent = mol.atoms.items[p.parent_atom].position;
        const pos = parent.add(p.direction.scale(marker_offset));
        const is_sel = (i == selected);
        const r = if (is_sel) marker_radius * selected_scale * pulse else marker_radius;
        const color = if (is_sel) selected_color else marker_color;
        const model = Mat4.translation(pos).mul(Mat4.scale(Vec3.init(r, r, r)));
        out[i] = make(model, color);
    }
    return out;
}


/// Rotation mapping unit vector `from` onto the direction of `to`.
fn rotationToward(from: Vec3, to: Vec3) Mat4 {
    const d = to.normalize();
    const dot = std.math.clamp(from.dot(d), -1.0, 1.0);
    if (dot > 0.9999) return Mat4.identity;
    if (dot < -0.9999) {
        // 180 deg about any axis perpendicular to `from`.
        return Mat4.fromAxisAngle(@import("../math.zig").anyPerpendicular(from), std.math.pi);
    }
    const axis = from.cross(d).normalize();
    return Mat4.fromAxisAngle(axis, std.math.acos(dot));
}

fn modelOf(inst: Instance) Mat4 {
    return .{ .m = inst.model };
}

test "atomInstances: one per atom; model places a unit sphere at the atom, scaled by radius" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);

    const insts = try atomInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 2), insts.len);

    // Atom 0 is a tetra at origin: sphere center maps to origin; the +X surface
    // point (1,0,0) maps to (tetra_radius, 0, 0).
    const m0 = modelOf(insts[0]);
    try std.testing.expect(m0.mulPoint(Vec3.zero).approxEq(Vec3.zero, 1e-5));
    const r = atom_style.styleFor(.tetra).radius;
    try std.testing.expect(m0.mulPoint(Vec3.init(1, 0, 0)).approxEq(Vec3.init(r, 0, 0), 1e-5));
}

test "bondInstances: one per bond; cylinder endpoints map to the bonded atoms" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const b = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // bond from origin to (0,0,1)

    const insts = try bondInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 1), insts.len);

    const m = modelOf(insts[0]);
    const pa = mol.atoms.items[a].position;
    const pb = mol.atoms.items[b].position;
    // Unit cylinder runs y in [0,1]; its endpoints must map to the two atoms.
    try std.testing.expect(m.mulPoint(Vec3.init(0, 0, 0)).approxEq(pa, 1e-4));
    try std.testing.expect(m.mulPoint(Vec3.init(0, 1, 0)).approxEq(pb, 1e-4));
}

fn scaleX(inst: Instance) f32 {
    return Vec3.init(inst.model[0], inst.model[1], inst.model[2]).length();
}

test "openPointInstances: one marker per open point, selected larger, offset placement" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra); // lone tetra at origin -> 4 open points

    const insts = try openPointInstances(std.testing.allocator, &mol, 0, 1.0);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 4), insts.len);

    // Selected (index 0) is scaled larger than the others.
    for (insts[1..]) |other| {
        try std.testing.expect(scaleX(insts[0]) > scaleX(other));
    }
    // Each marker sits `marker_offset` from its parent (atom 0 at the origin).
    const m0 = Mat4{ .m = insts[1].model };
    const center = m0.mulPoint(Vec3.zero);
    try std.testing.expectApproxEqAbs(marker_offset, center.length(), 1e-4);
}

test "atomInstances: same-type atoms get distinguishable shades" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .tetra); // second tetra

    const insts = try atomInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    // First of a type keeps the exact style color.
    const base = atom_style.styleFor(.tetra).color;
    try std.testing.expectApproxEqAbs(base[0], insts[0].color[0], 1e-6);
    // The second tetra differs in at least one channel.
    try std.testing.expect(insts[0].color[0] != insts[1].color[0] or
        insts[0].color[1] != insts[1].color[1] or
        insts[0].color[2] != insts[1].color[2]);
}


const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");
const Mat4 = lib.mat4.Mat4;
const Vec3 = lib.math.Vec3;
const Quaternion = lib.quaternion.Quaternion;
const Molecule = lib.molecule.Molecule;
const OpenBondPoint = lib.molecule.OpenBondPoint;
const AtomType = lib.atom.AtomType;
const nav = lib.navigation;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const slerp_ms: f32 = 300.0;
const pulse_omega: f32 = 4.0;
const atom_types = [_]AtomType{ .mono, .linear, .trigonal, .tetra };
const default_type_index: usize = 3; // Tetra
// In place mode the selected point swings to the upper-right for a 3/4 view.
const place_view_dir = Vec3.init(0.55, 0.55, 0.6);

const Mode = enum { navigate, place };

fn smoothstep(t: f32) f32 {
    const c = std.math.clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
}

/// Number of open bond points belonging to `atom_id`.
fn countOpenForAtom(open: []const OpenBondPoint, atom_id: usize) usize {
    var n: usize = 0;
    for (open) |p| {
        if (p.parent_atom == atom_id) n += 1;
    }
    return n;
}

/// Flat index into `open` of the `node`-th open point on `atom_id`, or null.
fn flatIndexFor(open: []const OpenBondPoint, atom_id: usize, node: usize) ?usize {
    var n: usize = 0;
    for (open, 0..) |p, i| {
        if (p.parent_atom == atom_id) {
            if (n == node) return i;
            n += 1;
        }
    }
    return null;
}

/// The first atom that has any open points (its id), or null if none.
fn firstAtomWithOpen(open: []const OpenBondPoint) ?usize {
    return if (open.len > 0) open[0].parent_atom else null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mol = Molecule.init(allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();
    try mol.openBondPoints(&open);

    const window = try win.Window.create(1280, 800, "Biome: Molecular");
    defer window.destroy();
    var gpu = try Gpu.init(window);
    defer gpu.deinit();

    var sphere = try lib.mesh.icosphere(allocator, 2);
    defer sphere.deinit(allocator);
    gpu.uploadSphere(sphere.vertices, sphere.indices);

    var cyl = try lib.mesh.cylinder(allocator, 16);
    defer cyl.deinit(allocator);
    gpu.uploadCylinder(cyl.vertices, cyl.indices);

    var mode: Mode = .navigate;
    // Two-level selection: an atom, then a node (open point) on that atom.
    // `selected` is the derived flat index into `open` of the active node.
    var selected_atom: usize = 0;
    var node_in_atom: usize = 0;
    var node_active = false; // false: atom-level (atom pulses); true: node-level (node pulses too)
    var selected: usize = flatIndexFor(open.items, selected_atom, node_in_atom) orelse 0;
    var ghost_id: ?usize = null;
    var ghost_type_index: usize = default_type_index;
    var settling = false;

    var q = Quaternion.identity;
    var q_start = q;
    var q_target = q;
    var anim_start = std.time.milliTimestamp();
    var animating = false;

    var prev_left = false;
    var prev_right = false;
    var prev_up = false;
    var prev_down = false;
    var prev_s = false;
    var prev_a = false;
    var prev_d = false;
    var prev_f = false;

    const epoch = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();
        if (window.keyPressed(win.KEY_ESCAPE)) break;
        const cmd_held = window.keyPressed(win.KEY_LEFT_SUPER) or window.keyPressed(win.KEY_RIGHT_SUPER);
        if (cmd_held and window.keyPressed(win.KEY_W)) break;

        const left = window.keyPressed(win.KEY_LEFT);
        const right = window.keyPressed(win.KEY_RIGHT);
        const up = window.keyPressed(win.KEY_UP);
        const down = window.keyPressed(win.KEY_DOWN);
        const s_key = window.keyPressed(win.KEY_S);
        const a_key = window.keyPressed(win.KEY_A);
        const d_key = window.keyPressed(win.KEY_D);
        const f_key = window.keyPressed(win.KEY_F);
        const left_edge = left and !prev_left;
        const right_edge = right and !prev_right;
        const up_edge = up and !prev_up;
        const down_edge = down and !prev_down;
        const s_edge = s_key and !prev_s;
        const a_edge = a_key and !prev_a;
        const d_edge = d_key and !prev_d;
        const f_edge = f_key and !prev_f;

        switch (mode) {
            .navigate => {
                // Level 1: arrows directionally select the ATOM (rotates so its
                // active node faces the camera).
                if (open.items.len > 0 and (left_edge or right_edge or up_edge or down_edge)) {
                    node_active = false; // any arrow returns to atom-selection level
                    var dx: f32 = 0;
                    var dy: f32 = 0;
                    if (left_edge) dx -= 1;
                    if (right_edge) dx += 1;
                    if (up_edge) dy += 1;
                    if (down_edge) dy -= 1;
                    const dlen = @sqrt(dx * dx + dy * dy);
                    if (dlen > 0) {
                        dx /= dlen;
                        dy /= dlen;
                        const com = mol.centerOfMass();
                        // Candidate atoms = those with open points (dedup via first occurrence).
                        var ids = std.ArrayList(usize).init(allocator);
                        defer ids.deinit();
                        var vps = std.ArrayList(Vec3).init(allocator);
                        defer vps.deinit();
                        for (open.items) |p| {
                            var seen = false;
                            for (ids.items) |id| {
                                if (id == p.parent_atom) seen = true;
                            }
                            if (seen) continue;
                            try ids.append(p.parent_atom);
                            const ap = mol.atoms.items[p.parent_atom].position;
                            try vps.append(q.rotateVec(ap.sub(com)));
                        }
                        var cur: usize = 0;
                        for (ids.items, 0..) |id, i| {
                            if (id == selected_atom) cur = i;
                        }
                        // Pick the atom in the pressed direction; if none lines up
                        // (e.g. a colinear molecule viewed end-on), fall back to the
                        // next/previous atom so an arrow always advances.
                        const picked: ?usize = nav.directionalSelect(vps.items, cur, dx, dy) orelse blk: {
                            if (ids.items.len <= 1) break :blk null;
                            const cdir: nav.Direction = if (dx > 0 or dy > 0) .next else .prev;
                            break :blk nav.cycle(cur, ids.items.len, cdir);
                        };
                        if (picked) |idx| {
                            selected_atom = ids.items[idx];
                            node_in_atom = 0;
                            node_active = false;
                            selected = flatIndexFor(open.items, selected_atom, node_in_atom) orelse selected;
                            // Rotate the ATOM to the front about a fixed world axis
                            // in the press direction (predictable: Left always turns
                            // the molecule the same way), rather than a shortest arc.
                            const rel = mol.atoms.items[selected_atom].position.sub(com);
                            if (rel.length() > 1e-3) {
                                const rd = q.rotateVec(rel.normalize());
                                var axis: Vec3 = undefined;
                                var angle: f32 = 0;
                                if (@abs(dx) >= @abs(dy)) {
                                    axis = Vec3.init(0, 1, 0); // yaw
                                    angle = -std.math.atan2(rd.x, rd.z);
                                } else {
                                    axis = Vec3.init(1, 0, 0); // pitch
                                    angle = std.math.atan2(rd.y, rd.z);
                                }
                                q_start = q;
                                q_target = Quaternion.fromAxisAngle(axis, angle).mul(q);
                                anim_start = std.time.milliTimestamp();
                                animating = true;
                            }
                        }
                    }
                }
                // Level 2: D cycles the nodes on the selected atom.
                if (d_edge) {
                    const count = countOpenForAtom(open.items, selected_atom);
                    if (count > 0) {
                        node_in_atom = (node_in_atom + 1) % count;
                        node_active = true;
                        selected = flatIndexFor(open.items, selected_atom, node_in_atom) orelse selected;
                        q_start = q;
                        q_target = nav.targetOrientation(open.items[selected].direction);
                        anim_start = std.time.milliTimestamp();
                        animating = true;
                    }
                }
                // Placement requires a node to be selected first (press D).
                if (open.items.len > 0 and s_edge and node_active) {
                    const p = open.items[selected];
                    ghost_type_index = default_type_index;
                    ghost_id = try mol.addAtom(p.parent_atom, p.direction, atom_types[ghost_type_index]);
                    mode = .place;
                    settling = true;
                    q_start = q;
                    q_target = Quaternion.rotationBetween(p.direction, place_view_dir);
                    anim_start = std.time.milliTimestamp();
                    animating = true;
                }
            },
            .place => {
                // Repeated S scrolls through the atom types to place.
                if (s_edge) {
                    ghost_type_index = nav.cycle(ghost_type_index, atom_types.len, .next);
                    mol.atoms.items[ghost_id.?].atom_type = atom_types[ghost_type_index];
                }
                if (a_edge) {
                    mol.removeLastAtom();
                    ghost_id = null;
                    mode = .navigate;
                    settling = true;
                    try mol.openBondPoints(&open);
                    reselect(open.items, &selected_atom, &node_in_atom, &selected);
                    node_active = false;
                    if (open.items.len > 0) {
                        q_start = q;
                        q_target = nav.targetOrientation(open.items[selected].direction);
                        anim_start = std.time.milliTimestamp();
                        animating = true;
                    }
                }
                if (f_edge) {
                    const gid = ghost_id.?;
                    ghost_id = null;
                    mode = .navigate;
                    try mol.openBondPoints(&open);
                    // Continue building from the newly placed atom if it has open
                    // points, else fall back to any atom with open points.
                    if (countOpenForAtom(open.items, gid) > 0) {
                        selected_atom = gid;
                        node_in_atom = 0;
                        selected = flatIndexFor(open.items, selected_atom, node_in_atom) orelse 0;
                    } else {
                        reselect(open.items, &selected_atom, &node_in_atom, &selected);
                    }
                    node_active = false;
                    if (open.items.len > 0) {
                        q_start = q;
                        q_target = nav.targetOrientation(open.items[selected].direction);
                        anim_start = std.time.milliTimestamp();
                        animating = true;
                    }
                }
            },
        }
        prev_left = left;
        prev_right = right;
        prev_up = up;
        prev_down = down;
        prev_s = s_key;
        prev_a = a_key;
        prev_d = d_key;
        prev_f = f_key;

        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        if (settling) {
            const done = try lib.physics.simulate(&mol, lib.constants.default, allocator);
            if (done) settling = false;
        }

        if (animating) {
            const t = @as(f32, @floatFromInt(std.time.milliTimestamp() - anim_start)) / slerp_ms;
            if (t >= 1.0) {
                q = q_target;
                animating = false;
            } else {
                q = q_start.slerp(q_target, smoothstep(t));
            }
        }

        const bounds = lib.camera.boundingSphere(&mol);
        const center = bounds.center;
        const radius = bounds.radius + lib.scene.marker_offset + lib.scene.marker_radius;
        const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(radius));
        const view = Mat4.lookAt(eye, center, Vec3.init(0, 1, 0));

        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - epoch)) / 1000.0;
        const wave = @sin(elapsed_s * pulse_omega);
        const pulse = 1.0 + 0.15 * wave; // node markers
        const atom_pulse = 1.0 + 0.05 * wave; // atoms (subtler)

        // Atoms (ghost drawn separately, translucent, in place mode).
        const atoms = try lib.scene.atomInstances(allocator, &mol);
        defer allocator.free(atoms);
        // Atom-level feedback: the selected atom pulses (size only), but only at
        // the atom level — once node selection is active it stops.
        if (mode == .navigate and !node_active and selected_atom < atoms.len) {
            var j: usize = 0;
            while (j < 12) : (j += 1) atoms[selected_atom].model[j] *= atom_pulse;
        }
        if (mode == .place) {
            const gid = ghost_id.?; // == atoms.len - 1
            atoms[gid].color[3] = 0.4;
            var j: usize = 0;
            while (j < 12) : (j += 1) atoms[gid].model[j] *= atom_pulse; // subtle ghost pulse
            gpu.uploadAtoms(atoms[0..gid]);
            gpu.uploadGhost(atoms[gid .. gid + 1]);
        } else {
            gpu.uploadAtoms(atoms);
            gpu.uploadGhost(atoms[0..0]);
        }

        // Bonds (ghost's bond drawn translucent in place mode).
        const bonds = try lib.scene.bondInstances(allocator, &mol);
        defer allocator.free(bonds);
        if (mode == .place and bonds.len > 0) {
            const last = bonds.len - 1;
            bonds[last].color[3] = 0.4;
            gpu.uploadBonds(bonds[0..last]);
            gpu.uploadGhostBonds(bonds[last .. last + 1]);
        } else {
            gpu.uploadBonds(bonds);
            gpu.uploadGhostBonds(bonds[0..0]);
        }

        // Node-level feedback: the active node pulses only once D has been pressed.
        const marker_selected = if (mode == .navigate and node_active) selected else std.math.maxInt(usize);
        const markers = try lib.scene.openPointInstances(allocator, &mol, marker_selected, pulse);
        defer allocator.free(markers);
        gpu.uploadMarkers(markers);

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(view);
        const model_pre = Mat4.translation(center).mul(q.toMat4()).mul(Mat4.translation(center.neg()));

        gpu.setUniforms(view_proj.m, model_pre.m, light_dir, .{ eye.x, eye.y, eye.z });
        gpu.renderFrame();
    }
}

/// After the molecule changes, ensure the selection points at a valid atom/node.
fn reselect(open: []const OpenBondPoint, selected_atom: *usize, node_in_atom: *usize, selected: *usize) void {
    if (countOpenForAtom(open, selected_atom.*) == 0) {
        selected_atom.* = firstAtomWithOpen(open) orelse 0;
        node_in_atom.* = 0;
    } else if (node_in_atom.* >= countOpenForAtom(open, selected_atom.*)) {
        node_in_atom.* = 0;
    }
    selected.* = flatIndexFor(open, selected_atom.*, node_in_atom.*) orelse 0;
}

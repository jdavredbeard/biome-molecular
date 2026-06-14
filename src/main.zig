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
// In place mode the selected point swings to the upper-right for a 3/4 view
// (more depth than the face-on navigate view), aiding placement.
const place_view_dir = Vec3.init(0.55, 0.55, 0.6);

const Mode = enum { navigate, place };

fn smoothstep(t: f32) f32 {
    const c = std.math.clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
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
    var selected: usize = 0;
    var ghost_id: ?usize = null;
    var ghost_type_index: usize = default_type_index;
    var settling = false;

    var q = if (open.items.len > 0) nav.targetOrientation(open.items[0].direction) else Quaternion.identity;
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
        const f_key = window.keyPressed(win.KEY_F);
        const left_edge = left and !prev_left;
        const right_edge = right and !prev_right;
        const up_edge = up and !prev_up;
        const down_edge = down and !prev_down;
        const s_edge = s_key and !prev_s;
        const a_edge = a_key and !prev_a;
        const f_edge = f_key and !prev_f;

        switch (mode) {
            .navigate => {
                // Spatial selection: from the selected node's screen position,
                // rotate to the nearest open point in the pressed direction.
                if (open.items.len > 0 and (left_edge or right_edge or up_edge or down_edge)) {
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
                        // Project each open point's marker into the current view space.
                        const com = mol.centerOfMass();
                        const vps = try allocator.alloc(Vec3, open.items.len);
                        defer allocator.free(vps);
                        for (open.items, 0..) |p, i| {
                            const wp = mol.atoms.items[p.parent_atom].position.add(p.direction.scale(lib.scene.marker_offset));
                            vps[i] = q.rotateVec(wp.sub(com));
                        }
                        if (nav.directionalSelect(vps, selected, dx, dy)) |idx| {
                            selected = idx;
                            q_start = q;
                            q_target = nav.targetOrientation(open.items[selected].direction);
                            anim_start = std.time.milliTimestamp();
                            animating = true;
                        }
                    }
                }
                if (open.items.len > 0 and s_edge) {
                    const p = open.items[selected];
                    ghost_type_index = default_type_index;
                    ghost_id = try mol.addAtom(p.parent_atom, p.direction, atom_types[ghost_type_index]);
                    mode = .place;
                    settling = true;
                    // Swing to a diagonal 3/4 view for placement.
                    q_start = q;
                    q_target = Quaternion.rotationBetween(p.direction, place_view_dir);
                    anim_start = std.time.milliTimestamp();
                    animating = true;
                }
            },
            .place => {
                if (left_edge) {
                    ghost_type_index = nav.cycle(ghost_type_index, atom_types.len, .prev);
                    mol.atoms.items[ghost_id.?].atom_type = atom_types[ghost_type_index];
                }
                if (right_edge) {
                    ghost_type_index = nav.cycle(ghost_type_index, atom_types.len, .next);
                    mol.atoms.items[ghost_id.?].atom_type = atom_types[ghost_type_index];
                }
                if (a_edge) {
                    mol.removeLastAtom();
                    ghost_id = null;
                    mode = .navigate;
                    settling = true;
                    try mol.openBondPoints(&open);
                    if (selected >= open.items.len) selected = 0;
                    // Swing back to the face-on navigate view.
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
                    selected = 0;
                    for (open.items, 0..) |p, i| {
                        if (p.parent_atom == gid) {
                            selected = i;
                            break;
                        }
                    }
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
        prev_f = f_key;

        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        // Animated re-fold (after add/cancel).
        if (settling) {
            const done = try lib.physics.simulate(&mol, lib.constants.default, allocator);
            if (done) settling = false;
        }

        // Rotation slerp.
        if (animating) {
            const t = @as(f32, @floatFromInt(std.time.milliTimestamp() - anim_start)) / slerp_ms;
            if (t >= 1.0) {
                q = q_target;
                animating = false;
            } else {
                q = q_start.slerp(q_target, smoothstep(t));
            }
        }

        // Camera: keep the center of mass framed (recomputed as the molecule grows/folds).
        const bounds = lib.camera.boundingSphere(&mol);
        const center = bounds.center;
        const radius = bounds.radius + lib.scene.marker_offset + lib.scene.marker_radius;
        const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(radius));
        const view = Mat4.lookAt(eye, center, Vec3.init(0, 1, 0));

        // Atoms. In place mode the ghost (always the last atom) is drawn
        // separately as a translucent, true-color preview; the opaque pass
        // excludes it so the re-fold behind it stays visible.
        const atoms = try lib.scene.atomInstances(allocator, &mol);
        defer allocator.free(atoms);
        if (mode == .place) {
            const gid = ghost_id.?; // == atoms.len - 1
            atoms[gid].color[3] = 0.4; // translucent
            gpu.uploadAtoms(atoms[0..gid]);
            gpu.uploadGhost(atoms[gid .. gid + 1]);
        } else {
            gpu.uploadAtoms(atoms);
            gpu.uploadGhost(atoms[0..0]);
        }

        // Bonds. In place mode the ghost's bond (always the last bond) is drawn
        // translucent alongside the ghost atom.
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

        // Markers: in navigate mode highlight the selected open point; in place
        // mode show all open connection points uniformly (no highlight) so they
        // don't disappear while placing.
        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - epoch)) / 1000.0;
        const pulse = 1.0 + 0.15 * @sin(elapsed_s * pulse_omega);
        const marker_selected = if (mode == .navigate) selected else std.math.maxInt(usize);
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

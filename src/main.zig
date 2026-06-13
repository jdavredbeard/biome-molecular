const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");
const Mat4 = lib.mat4.Mat4;
const Vec3 = lib.math.Vec3;
const Quaternion = lib.quaternion.Quaternion;
const Molecule = lib.molecule.Molecule;
const OpenBondPoint = lib.molecule.OpenBondPoint;
const nav = lib.navigation;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const slerp_ms: f32 = 300.0; // rotation animation duration
const pulse_omega: f32 = 4.0; // selected-marker pulse speed (rad/s)

fn smoothstep(t: f32) f32 {
    const c = std.math.clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sandbox starts with a single Tetra at the origin (4 open bond points).
    var mol = Molecule.init(allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    // Snapshot the open points once (static while we only navigate).
    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();
    try mol.openBondPoints(&open);
    const open_count = open.items.len;

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

    const atoms = try lib.scene.atomInstances(allocator, &mol);
    defer allocator.free(atoms);
    gpu.uploadAtoms(atoms);

    const bonds = try lib.scene.bondInstances(allocator, &mol);
    defer allocator.free(bonds);
    gpu.uploadBonds(bonds);

    // Fixed camera framing the molecule + its markers.
    const bounds = lib.camera.boundingSphere(&mol);
    const center = bounds.center;
    const radius = bounds.radius + lib.scene.marker_offset + lib.scene.marker_radius;
    const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(radius));
    const view = Mat4.lookAt(eye, center, Vec3.init(0, 1, 0));

    // Selection + orientation animation state.
    var selected: usize = 0;
    var q = if (open_count > 0) nav.targetOrientation(open.items[0].direction) else Quaternion.identity;
    var q_start = q;
    var q_target = q;
    var anim_start = std.time.milliTimestamp();
    var animating = false;

    var prev_left = false;
    var prev_right = false;
    const epoch = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();
        if (window.keyPressed(win.KEY_ESCAPE)) break;
        const cmd_held = window.keyPressed(win.KEY_LEFT_SUPER) or window.keyPressed(win.KEY_RIGHT_SUPER);
        if (cmd_held and window.keyPressed(win.KEY_W)) break;

        // Left/Right cycle the selection (rising edge); re-target the rotation.
        const left = window.keyPressed(win.KEY_LEFT);
        const right = window.keyPressed(win.KEY_RIGHT);
        var changed = false;
        if (open_count > 0 and left and !prev_left) {
            selected = nav.cycle(selected, open_count, .prev);
            changed = true;
        }
        if (open_count > 0 and right and !prev_right) {
            selected = nav.cycle(selected, open_count, .next);
            changed = true;
        }
        prev_left = left;
        prev_right = right;
        if (changed) {
            q_start = q;
            q_target = nav.targetOrientation(open.items[selected].direction);
            anim_start = std.time.milliTimestamp();
            animating = true;
        }

        // Pause when hidden (avoids Metal drawable exhaustion).
        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        // Advance the slerp.
        if (animating) {
            const t = @as(f32, @floatFromInt(std.time.milliTimestamp() - anim_start)) / slerp_ms;
            if (t >= 1.0) {
                q = q_target;
                animating = false;
            } else {
                q = q_start.slerp(q_target, smoothstep(t));
            }
        }

        // Repack markers each frame so the selected one pulses.
        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - epoch)) / 1000.0;
        const pulse = 1.0 + 0.15 * @sin(elapsed_s * pulse_omega);
        const markers = try lib.scene.openPointInstances(allocator, &mol, selected, pulse);
        defer allocator.free(markers);
        gpu.uploadMarkers(markers);

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(view);
        const model_pre = Mat4.translation(center).mul(q.toMat4()).mul(Mat4.translation(center.neg()));

        gpu.setUniforms(view_proj.m, model_pre.m, light_dir, .{ eye.x, eye.y, eye.z });
        gpu.renderFrame();
    }
}

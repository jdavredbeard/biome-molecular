const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");
const Mat4 = lib.mat4.Mat4;
const Vec3 = lib.math.Vec3;
const Molecule = lib.molecule.Molecule;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const spin_rad_per_s: f32 = 0.6; // turntable speed (~10.5s per revolution)

const Camera = struct { center: Vec3, view: Mat4, eye: Vec3 };

fn cameraFor(mol: *const Molecule) Camera {
    const b = lib.camera.boundingSphere(mol);
    return .{
        .center = b.center,
        .view = lib.camera.viewMatrix(b),
        .eye = Vec3.init(b.center.x, b.center.y, b.center.z + lib.camera.cameraDistance(b.radius)),
    };
}

/// Upload the selected example's instances, refit the camera, update the title.
fn showExample(allocator: std.mem.Allocator, gpu: *Gpu, window: win.Window, molecules: []Molecule, idx: usize, cam: *Camera) !void {
    const atoms = try lib.scene.atomInstances(allocator, &molecules[idx]);
    defer allocator.free(atoms);
    gpu.uploadAtoms(atoms);

    const bonds = try lib.scene.bondInstances(allocator, &molecules[idx]);
    defer allocator.free(bonds);
    gpu.uploadBonds(bonds);

    cam.* = cameraFor(&molecules[idx]);

    var buf: [128]u8 = undefined;
    const title = try std.fmt.bufPrintZ(&buf, "{s} ({d}/{d})", .{ lib.examples.all[idx].name, idx + 1, lib.examples.all.len });
    window.setTitle(title.ptr);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build and physics-settle every example up front; switching is then instant.
    const n = lib.examples.all.len;
    var molecules: [n]Molecule = undefined;
    var built: usize = 0;
    defer for (molecules[0..built]) |*m| m.deinit();
    for (lib.examples.all, 0..) |ex, i| {
        molecules[i] = try ex.build(allocator);
        built = i + 1;
        var settled = false;
        var it: usize = 0;
        while (!settled and it < 20000) : (it += 1) {
            settled = try lib.physics.simulate(&molecules[i], lib.constants.default, allocator);
        }
    }

    const window = try win.Window.create(1280, 800, "Biome: Molecular");
    defer window.destroy();

    var gpu = try Gpu.init(window);

    // Shared meshes (uploaded once; instances change per example).
    var sphere = try lib.mesh.icosphere(allocator, 2);
    defer sphere.deinit(allocator);
    gpu.uploadSphere(sphere.vertices, sphere.indices);

    var cyl = try lib.mesh.cylinder(allocator, 16);
    defer cyl.deinit(allocator);
    gpu.uploadCylinder(cyl.vertices, cyl.indices);

    var current: usize = 0;
    var cam = cameraFor(&molecules[current]);
    try showExample(allocator, &gpu, window, molecules[0..], current, &cam);

    var prev_left = false;
    var prev_right = false;
    const start = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();
        if (window.keyPressed(win.KEY_ESCAPE)) break;

        // Left/Right cycle examples (rising edge so one switch per press).
        const left = window.keyPressed(win.KEY_LEFT);
        const right = window.keyPressed(win.KEY_RIGHT);
        if (left and !prev_left) {
            current = (current + n - 1) % n;
            try showExample(allocator, &gpu, window, molecules[0..], current, &cam);
        }
        if (right and !prev_right) {
            current = (current + 1) % n;
            try showExample(allocator, &gpu, window, molecules[0..], current, &cam);
        }
        prev_left = left;
        prev_right = right;

        // Pause rendering when hidden (avoids Metal drawable-pool exhaustion).
        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(cam.view);

        // Turntable: spin the molecule about its center in world space.
        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - start)) / 1000.0;
        const angle = elapsed_s * spin_rad_per_s;
        const spin = Mat4.translation(cam.center)
            .mul(Mat4.fromAxisAngle(Vec3.init(0, 1, 0), angle))
            .mul(Mat4.translation(cam.center.neg()));

        gpu.setUniforms(view_proj.m, spin.m, light_dir, .{ cam.eye.x, cam.eye.y, cam.eye.z });
        gpu.renderFrame();
    }
}

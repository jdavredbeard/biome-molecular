const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");
const Mat4 = lib.mat4.Mat4;
const Vec3 = lib.math.Vec3;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const spin_rad_per_s: f32 = 0.6; // turntable speed (~10.5s per revolution)

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build and settle a sample molecule (methane: tetra + 4 mono caps).
    var mol = try lib.examples.buildMethane(allocator);
    defer mol.deinit();
    var settled = false;
    var iters: usize = 0;
    while (!settled and iters < 20000) : (iters += 1) {
        settled = try lib.physics.simulate(&mol, lib.constants.default, allocator);
    }

    const window = try win.Window.create(1280, 800, "Biome: Molecular");
    defer window.destroy();

    var gpu = try Gpu.init(window);

    // Upload the shared sphere mesh and per-atom instances.
    var sphere = try lib.mesh.icosphere(allocator, 2);
    defer sphere.deinit(allocator);
    gpu.uploadSphere(sphere.vertices, sphere.indices);

    const atoms = try lib.scene.atomInstances(allocator, &mol);
    defer allocator.free(atoms);
    gpu.uploadAtoms(atoms);

    var cyl = try lib.mesh.cylinder(allocator, 16);
    defer cyl.deinit(allocator);
    gpu.uploadCylinder(cyl.vertices, cyl.indices);

    const bonds = try lib.scene.bondInstances(allocator, &mol);
    defer allocator.free(bonds);
    gpu.uploadBonds(bonds);

    // Fixed camera framing the settled molecule; the molecule spins in place.
    const bounds = lib.camera.boundingSphere(&mol);
    const center = bounds.center;
    const view = lib.camera.viewMatrix(bounds);
    const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(bounds.radius));

    const start = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();

        // Skip rendering when the window isn't visible on screen (occluded,
        // minimized, or zero-sized). Presenting into a hidden Metal layer
        // exhausts the drawable pool and hangs the app.
        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(view);

        // Turntable: spin the molecule about its center in world space (camera +
        // light stay fixed, so shading shifts across the surface as it turns).
        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - start)) / 1000.0;
        const angle = elapsed_s * spin_rad_per_s;
        const spin = Mat4.translation(center)
            .mul(Mat4.fromAxisAngle(Vec3.init(0, 1, 0), angle))
            .mul(Mat4.translation(center.neg()));

        gpu.setUniforms(view_proj.m, spin.m, light_dir, .{ eye.x, eye.y, eye.z });
        gpu.renderFrame();
    }
}

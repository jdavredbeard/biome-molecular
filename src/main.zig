const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");

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

    // Camera framing the settled molecule.
    const sphere_bounds = lib.camera.boundingSphere(&mol);
    const view = lib.camera.viewMatrix(sphere_bounds);
    var fb = window.framebufferSize();
    const aspect = @as(f32, @floatFromInt(fb[0])) / @as(f32, @floatFromInt(fb[1]));
    const proj = lib.camera.projectionMatrix(aspect);
    const view_proj = proj.mul(view);
    const eye = lib.math.Vec3.init(sphere_bounds.center.x, sphere_bounds.center.y, sphere_bounds.center.z + lib.camera.cameraDistance(sphere_bounds.radius));
    gpu.setUniforms(view_proj.m, .{ -0.6, 0.7, 0.5 }, .{ eye.x, eye.y, eye.z });

    while (!window.shouldClose()) {
        window.pollEvents();
        const size = window.framebufferSize();
        if (size[0] != gpu.width or size[1] != gpu.height) {
            gpu.resize(size[0], size[1]);
            fb = size;
            const a = @as(f32, @floatFromInt(fb[0])) / @as(f32, @floatFromInt(fb[1]));
            const vp = lib.camera.projectionMatrix(a).mul(view);
            gpu.setUniforms(vp.m, .{ -0.6, 0.7, 0.5 }, .{ eye.x, eye.y, eye.z });
        }
        gpu.renderFrame();
    }
}

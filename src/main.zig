const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;

pub fn main() !void {
    const window = try win.Window.create(1280, 800, "Biome: Molecular");
    defer window.destroy();

    var gpu = try Gpu.init(window);

    while (!window.shouldClose()) {
        window.pollEvents();
        const size = window.framebufferSize();
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);
        gpu.renderClear();
    }
}

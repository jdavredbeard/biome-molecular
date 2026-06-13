const std = @import("std");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("webgpu/webgpu.h");
    @cInclude("webgpu/wgpu.h");
    @cInclude("metal_layer.h");
});

pub const KEY_LEFT = c.GLFW_KEY_LEFT;
pub const KEY_RIGHT = c.GLFW_KEY_RIGHT;
pub const KEY_ESCAPE = c.GLFW_KEY_ESCAPE;

pub const Window = struct {
    handle: *c.GLFWwindow,

    pub fn create(width: i32, height: i32, title: [*:0]const u8) !Window {
        if (c.glfwInit() == 0) return error.GlfwInitFailed;
        // We render with WebGPU/Metal, not OpenGL — tell GLFW not to make a GL context.
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        const h = c.glfwCreateWindow(width, height, title, null, null) orelse return error.WindowCreateFailed;
        return .{ .handle = h };
    }

    pub fn shouldClose(self: Window) bool {
        return c.glfwWindowShouldClose(self.handle) != 0;
    }

    pub fn pollEvents(_: Window) void {
        c.glfwPollEvents();
    }

    pub fn keyPressed(self: Window, key: c_int) bool {
        return c.glfwGetKey(self.handle, key) == c.GLFW_PRESS;
    }

    pub fn setTitle(self: Window, title: [*:0]const u8) void {
        c.glfwSetWindowTitle(self.handle, title);
    }

    pub fn framebufferSize(self: Window) [2]u32 {
        var w: c_int = 0;
        var hgt: c_int = 0;
        c.glfwGetFramebufferSize(self.handle, &w, &hgt);
        return .{ @intCast(w), @intCast(hgt) };
    }

    /// Create a wgpu surface backed by a CAMetalLayer attached to this window.
    pub fn createSurface(self: Window, instance: c.WGPUInstance) c.WGPUSurface {
        const metal_layer = c.biome_attach_metal_layer(@ptrCast(self.handle));
        var from_layer = c.WGPUSurfaceSourceMetalLayer{
            .chain = .{ .next = null, .sType = c.WGPUSType_SurfaceSourceMetalLayer },
            .layer = metal_layer,
        };
        const desc = c.WGPUSurfaceDescriptor{
            .nextInChain = @ptrCast(&from_layer),
            .label = .{ .data = null, .length = 0 },
        };
        return c.wgpuInstanceCreateSurface(instance, &desc);
    }

    pub fn destroy(self: Window) void {
        c.glfwDestroyWindow(self.handle);
        c.glfwTerminate();
    }
};

const std = @import("std");
const win = @import("../platform/window.zig");
const c = win.c;

/// Minimal wgpu-native (v29) renderer. Task 11: device/surface/clear frame.
pub const Gpu = struct {
    instance: c.WGPUInstance,
    surface: c.WGPUSurface,
    adapter: c.WGPUAdapter,
    device: c.WGPUDevice,
    queue: c.WGPUQueue,
    format: c.WGPUTextureFormat,
    width: u32,
    height: u32,

    pub fn init(window: win.Window) !Gpu {
        const instance = c.wgpuCreateInstance(null) orelse return error.NoInstance;
        const surface = window.createSurface(instance) orelse return error.NoSurface;

        var adapter: c.WGPUAdapter = null;
        const adapter_opts = std.mem.zeroInit(c.WGPURequestAdapterOptions, .{ .compatibleSurface = surface });
        const adapter_cb = c.WGPURequestAdapterCallbackInfo{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = onAdapter,
            .userdata1 = @ptrCast(&adapter),
            .userdata2 = null,
        };
        _ = c.wgpuInstanceRequestAdapter(instance, &adapter_opts, adapter_cb);
        var spins: u32 = 0;
        while (adapter == null and spins < 100) : (spins += 1) c.wgpuInstanceProcessEvents(instance);
        if (adapter == null) return error.NoAdapter;

        var device: c.WGPUDevice = null;
        const device_cb = c.WGPURequestDeviceCallbackInfo{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = onDevice,
            .userdata1 = @ptrCast(&device),
            .userdata2 = null,
        };
        _ = c.wgpuAdapterRequestDevice(adapter, null, device_cb);
        spins = 0;
        while (device == null and spins < 100) : (spins += 1) c.wgpuInstanceProcessEvents(instance);
        if (device == null) return error.NoDevice;

        const queue = c.wgpuDeviceGetQueue(device);
        const size = window.framebufferSize();

        var gpu = Gpu{
            .instance = instance,
            .surface = surface,
            .adapter = adapter,
            .device = device,
            .queue = queue,
            .format = c.WGPUTextureFormat_BGRA8Unorm,
            .width = size[0],
            .height = size[1],
        };
        gpu.configureSurface();
        return gpu;
    }

    fn configureSurface(self: *Gpu) void {
        const config = std.mem.zeroInit(c.WGPUSurfaceConfiguration, .{
            .device = self.device,
            .format = self.format,
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .width = self.width,
            .height = self.height,
            .alphaMode = c.WGPUCompositeAlphaMode_Auto,
            .presentMode = c.WGPUPresentMode_Fifo,
        });
        c.wgpuSurfaceConfigure(self.surface, &config);
    }

    pub fn resize(self: *Gpu, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.width = width;
        self.height = height;
        self.configureSurface();
    }

    /// Render one frame: clear to a dark background (geometry added in Task 12).
    pub fn renderClear(self: *Gpu) void {
        var surface_tex: c.WGPUSurfaceTexture = std.mem.zeroes(c.WGPUSurfaceTexture);
        c.wgpuSurfaceGetCurrentTexture(self.surface, &surface_tex);
        if (surface_tex.texture == null) return;

        const view = c.wgpuTextureCreateView(surface_tex.texture, null);
        const encoder = c.wgpuDeviceCreateCommandEncoder(self.device, null);

        const color_attachment = std.mem.zeroInit(c.WGPURenderPassColorAttachment, .{
            .view = view,
            .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
            .loadOp = c.WGPULoadOp_Clear,
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = c.WGPUColor{ .r = 0.09, .g = 0.10, .b = 0.14, .a = 1.0 },
        });
        const pass_desc = std.mem.zeroInit(c.WGPURenderPassDescriptor, .{
            .colorAttachmentCount = @as(usize, 1),
            .colorAttachments = &color_attachment,
        });
        const pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &pass_desc);
        c.wgpuRenderPassEncoderEnd(pass);

        const cmd = c.wgpuCommandEncoderFinish(encoder, null);
        c.wgpuQueueSubmit(self.queue, 1, &cmd);
        _ = c.wgpuSurfacePresent(self.surface);

        c.wgpuCommandBufferRelease(cmd);
        c.wgpuRenderPassEncoderRelease(pass);
        c.wgpuCommandEncoderRelease(encoder);
        c.wgpuTextureViewRelease(view);
        c.wgpuTextureRelease(surface_tex.texture);
    }
};

fn onAdapter(
    status: c.WGPURequestAdapterStatus,
    adapter: c.WGPUAdapter,
    message: c.WGPUStringView,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.C) void {
    _ = status;
    _ = message;
    _ = userdata2;
    const out: *c.WGPUAdapter = @ptrCast(@alignCast(userdata1.?));
    out.* = adapter;
}

fn onDevice(
    status: c.WGPURequestDeviceStatus,
    device: c.WGPUDevice,
    message: c.WGPUStringView,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.C) void {
    _ = status;
    _ = message;
    _ = userdata2;
    const out: *c.WGPUDevice = @ptrCast(@alignCast(userdata1.?));
    out.* = device;
}

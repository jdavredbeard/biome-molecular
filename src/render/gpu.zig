const std = @import("std");
const win = @import("../platform/window.zig");
const lib = @import("biome_molecular_lib");
const c = win.c;

/// Uniforms shared by all draws (must match the WGSL `Uniforms` block).
pub const Uniforms = extern struct {
    view_proj: [16]f32,
    model_pre: [16]f32,
    light_dir: [4]f32,
    camera_pos: [4]f32,
};

const no_label = c.WGPUStringView{ .data = null, .length = 0 };

fn sv(s: []const u8) c.WGPUStringView {
    return .{ .data = @ptrCast(s.ptr), .length = s.len };
}

/// wgpu-native (v29) renderer. Task 12: instanced lit spheres for atoms.
pub const Gpu = struct {
    instance: c.WGPUInstance,
    surface: c.WGPUSurface,
    adapter: c.WGPUAdapter,
    device: c.WGPUDevice,
    queue: c.WGPUQueue,
    format: c.WGPUTextureFormat,
    width: u32,
    height: u32,

    pipeline: c.WGPURenderPipeline = null,
    bind_group: c.WGPUBindGroup = null,
    uniform_buffer: c.WGPUBuffer = null,
    depth_texture: c.WGPUTexture = null,
    depth_view: c.WGPUTextureView = null,

    sphere_vbuf: c.WGPUBuffer = null,
    sphere_ibuf: c.WGPUBuffer = null,
    sphere_index_count: u32 = 0,
    atom_ibuf: c.WGPUBuffer = null,
    atom_count: u32 = 0,

    cyl_vbuf: c.WGPUBuffer = null,
    cyl_ibuf: c.WGPUBuffer = null,
    cyl_index_count: u32 = 0,
    bond_ibuf: c.WGPUBuffer = null,
    bond_count: u32 = 0,

    pub fn init(window: win.Window) !Gpu {
        const instance = c.wgpuCreateInstance(null) orelse return error.NoInstance;
        const surface = window.createSurface(instance) orelse return error.NoSurface;

        var adapter: c.WGPUAdapter = null;
        const adapter_opts = std.mem.zeroInit(c.WGPURequestAdapterOptions, .{ .compatibleSurface = surface });
        _ = c.wgpuInstanceRequestAdapter(instance, &adapter_opts, .{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = onAdapter,
            .userdata1 = @ptrCast(&adapter),
            .userdata2 = null,
        });
        var spins: u32 = 0;
        while (adapter == null and spins < 100) : (spins += 1) c.wgpuInstanceProcessEvents(instance);
        if (adapter == null) return error.NoAdapter;

        var device: c.WGPUDevice = null;
        _ = c.wgpuAdapterRequestDevice(adapter, null, .{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = onDevice,
            .userdata1 = @ptrCast(&device),
            .userdata2 = null,
        });
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
        gpu.createDepth();
        gpu.createPipeline();
        return gpu;
    }

    /// Release all GPU resources, in reverse order of creation.
    pub fn deinit(self: *Gpu) void {
        if (self.bond_ibuf != null) c.wgpuBufferRelease(self.bond_ibuf);
        if (self.cyl_ibuf != null) c.wgpuBufferRelease(self.cyl_ibuf);
        if (self.cyl_vbuf != null) c.wgpuBufferRelease(self.cyl_vbuf);
        if (self.atom_ibuf != null) c.wgpuBufferRelease(self.atom_ibuf);
        if (self.sphere_ibuf != null) c.wgpuBufferRelease(self.sphere_ibuf);
        if (self.sphere_vbuf != null) c.wgpuBufferRelease(self.sphere_vbuf);
        if (self.bind_group != null) c.wgpuBindGroupRelease(self.bind_group);
        if (self.uniform_buffer != null) c.wgpuBufferRelease(self.uniform_buffer);
        if (self.pipeline != null) c.wgpuRenderPipelineRelease(self.pipeline);
        if (self.depth_view != null) c.wgpuTextureViewRelease(self.depth_view);
        if (self.depth_texture != null) c.wgpuTextureRelease(self.depth_texture);
        c.wgpuQueueRelease(self.queue);
        c.wgpuDeviceRelease(self.device);
        c.wgpuAdapterRelease(self.adapter);
        c.wgpuSurfaceRelease(self.surface);
        c.wgpuInstanceRelease(self.instance);
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

    fn createDepth(self: *Gpu) void {
        const desc = std.mem.zeroInit(c.WGPUTextureDescriptor, .{
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .dimension = c.WGPUTextureDimension_2D,
            .size = c.WGPUExtent3D{ .width = self.width, .height = self.height, .depthOrArrayLayers = 1 },
            .format = c.WGPUTextureFormat_Depth24Plus,
            .mipLevelCount = 1,
            .sampleCount = 1,
        });
        self.depth_texture = c.wgpuDeviceCreateTexture(self.device, &desc);
        self.depth_view = c.wgpuTextureCreateView(self.depth_texture, null);
    }

    fn createBuffer(self: *Gpu, data: []const u8, usage: u64) c.WGPUBuffer {
        const desc = std.mem.zeroInit(c.WGPUBufferDescriptor, .{
            .usage = usage | c.WGPUBufferUsage_CopyDst,
            .size = data.len,
        });
        const buf = c.wgpuDeviceCreateBuffer(self.device, &desc);
        c.wgpuQueueWriteBuffer(self.queue, buf, 0, data.ptr, data.len);
        return buf;
    }

    fn createPipeline(self: *Gpu) void {
        const wgsl = @embedFile("shaders/mesh.wgsl");
        var wgsl_src = c.WGPUShaderSourceWGSL{
            .chain = .{ .next = null, .sType = c.WGPUSType_ShaderSourceWGSL },
            .code = sv(wgsl),
        };
        const module = c.wgpuDeviceCreateShaderModule(self.device, &.{
            .nextInChain = @ptrCast(&wgsl_src),
            .label = no_label,
        });

        const bgl_entry = std.mem.zeroInit(c.WGPUBindGroupLayoutEntry, .{
            .binding = 0,
            .visibility = c.WGPUShaderStage_Vertex | c.WGPUShaderStage_Fragment,
            .buffer = std.mem.zeroInit(c.WGPUBufferBindingLayout, .{ .type = c.WGPUBufferBindingType_Uniform }),
        });
        const bgl = c.wgpuDeviceCreateBindGroupLayout(self.device, &std.mem.zeroInit(c.WGPUBindGroupLayoutDescriptor, .{
            .entryCount = @as(usize, 1),
            .entries = &bgl_entry,
        }));
        const layout = c.wgpuDeviceCreatePipelineLayout(self.device, &std.mem.zeroInit(c.WGPUPipelineLayoutDescriptor, .{
            .bindGroupLayoutCount = @as(usize, 1),
            .bindGroupLayouts = &bgl,
        }));

        const mesh_attrs = [_]c.WGPUVertexAttribute{
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x3, .offset = 0, .shaderLocation = 0 },
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x3, .offset = 12, .shaderLocation = 1 },
        };
        const inst_attrs = [_]c.WGPUVertexAttribute{
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x4, .offset = 0, .shaderLocation = 2 },
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x4, .offset = 16, .shaderLocation = 3 },
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x4, .offset = 32, .shaderLocation = 4 },
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x4, .offset = 48, .shaderLocation = 5 },
            .{ .nextInChain = null, .format = c.WGPUVertexFormat_Float32x4, .offset = 64, .shaderLocation = 6 },
        };
        const vbls = [_]c.WGPUVertexBufferLayout{
            .{ .nextInChain = null, .stepMode = c.WGPUVertexStepMode_Vertex, .arrayStride = 24, .attributeCount = 2, .attributes = &mesh_attrs },
            .{ .nextInChain = null, .stepMode = c.WGPUVertexStepMode_Instance, .arrayStride = 80, .attributeCount = 5, .attributes = &inst_attrs },
        };

        const color_target = std.mem.zeroInit(c.WGPUColorTargetState, .{
            .format = self.format,
            .writeMask = c.WGPUColorWriteMask_All,
        });
        const frag = std.mem.zeroInit(c.WGPUFragmentState, .{
            .module = module,
            .entryPoint = sv("fs_main"),
            .targetCount = @as(usize, 1),
            .targets = &color_target,
        });
        const depth = std.mem.zeroInit(c.WGPUDepthStencilState, .{
            .format = c.WGPUTextureFormat_Depth24Plus,
            .depthWriteEnabled = c.WGPUOptionalBool_True,
            .depthCompare = c.WGPUCompareFunction_Less,
            .stencilFront = std.mem.zeroInit(c.WGPUStencilFaceState, .{ .compare = c.WGPUCompareFunction_Always }),
            .stencilBack = std.mem.zeroInit(c.WGPUStencilFaceState, .{ .compare = c.WGPUCompareFunction_Always }),
        });
        const desc = std.mem.zeroInit(c.WGPURenderPipelineDescriptor, .{
            .layout = layout,
            .vertex = std.mem.zeroInit(c.WGPUVertexState, .{
                .module = module,
                .entryPoint = sv("vs_main"),
                .bufferCount = @as(usize, 2),
                .buffers = &vbls,
            }),
            .primitive = std.mem.zeroInit(c.WGPUPrimitiveState, .{
                .topology = c.WGPUPrimitiveTopology_TriangleList,
                .frontFace = c.WGPUFrontFace_CCW,
                .cullMode = c.WGPUCullMode_None,
            }),
            .depthStencil = &depth,
            .multisample = std.mem.zeroInit(c.WGPUMultisampleState, .{ .count = 1, .mask = 0xFFFFFFFF }),
            .fragment = &frag,
        });
        self.pipeline = c.wgpuDeviceCreateRenderPipeline(self.device, &desc);

        self.uniform_buffer = c.wgpuDeviceCreateBuffer(self.device, &std.mem.zeroInit(c.WGPUBufferDescriptor, .{
            .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
            .size = @as(u64, @sizeOf(Uniforms)),
        }));
        const bg_entry = std.mem.zeroInit(c.WGPUBindGroupEntry, .{
            .binding = 0,
            .buffer = self.uniform_buffer,
            .offset = 0,
            .size = @as(u64, @sizeOf(Uniforms)),
        });
        self.bind_group = c.wgpuDeviceCreateBindGroup(self.device, &std.mem.zeroInit(c.WGPUBindGroupDescriptor, .{
            .layout = bgl,
            .entryCount = @as(usize, 1),
            .entries = &bg_entry,
        }));
    }

    pub fn uploadSphere(self: *Gpu, vertices: []const lib.mesh.Vertex, indices: []const u32) void {
        self.sphere_vbuf = self.createBuffer(std.mem.sliceAsBytes(vertices), c.WGPUBufferUsage_Vertex);
        self.sphere_ibuf = self.createBuffer(std.mem.sliceAsBytes(indices), c.WGPUBufferUsage_Index);
        self.sphere_index_count = @intCast(indices.len);
    }

    pub fn uploadAtoms(self: *Gpu, instances: []const lib.scene.Instance) void {
        if (self.atom_ibuf != null) c.wgpuBufferRelease(self.atom_ibuf);
        self.atom_ibuf = self.createBuffer(std.mem.sliceAsBytes(instances), c.WGPUBufferUsage_Vertex);
        self.atom_count = @intCast(instances.len);
    }

    pub fn uploadCylinder(self: *Gpu, vertices: []const lib.mesh.Vertex, indices: []const u32) void {
        self.cyl_vbuf = self.createBuffer(std.mem.sliceAsBytes(vertices), c.WGPUBufferUsage_Vertex);
        self.cyl_ibuf = self.createBuffer(std.mem.sliceAsBytes(indices), c.WGPUBufferUsage_Index);
        self.cyl_index_count = @intCast(indices.len);
    }

    pub fn uploadBonds(self: *Gpu, instances: []const lib.scene.Instance) void {
        if (self.bond_ibuf != null) c.wgpuBufferRelease(self.bond_ibuf);
        self.bond_ibuf = self.createBuffer(std.mem.sliceAsBytes(instances), c.WGPUBufferUsage_Vertex);
        self.bond_count = @intCast(instances.len);
    }

    pub fn setUniforms(self: *Gpu, view_proj: [16]f32, model_pre: [16]f32, light_dir: [3]f32, camera_pos: [3]f32) void {
        const u = Uniforms{
            .view_proj = view_proj,
            .model_pre = model_pre,
            .light_dir = .{ light_dir[0], light_dir[1], light_dir[2], 0 },
            .camera_pos = .{ camera_pos[0], camera_pos[1], camera_pos[2], 0 },
        };
        c.wgpuQueueWriteBuffer(self.queue, self.uniform_buffer, 0, &u, @sizeOf(Uniforms));
    }

    pub fn resize(self: *Gpu, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.width = width;
        self.height = height;
        self.configureSurface();
        if (self.depth_view != null) c.wgpuTextureViewRelease(self.depth_view);
        if (self.depth_texture != null) c.wgpuTextureRelease(self.depth_texture);
        self.createDepth();
    }

    pub fn renderFrame(self: *Gpu) void {
        var st: c.WGPUSurfaceTexture = std.mem.zeroes(c.WGPUSurfaceTexture);
        c.wgpuSurfaceGetCurrentTexture(self.surface, &st);
        switch (st.status) {
            c.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal,
            c.WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal,
            => {},
            // The surface went stale (window occluded/backgrounded/resized).
            // Reconfigure and skip this frame so we recover when shown again.
            c.WGPUSurfaceGetCurrentTextureStatus_Timeout,
            c.WGPUSurfaceGetCurrentTextureStatus_Outdated,
            c.WGPUSurfaceGetCurrentTextureStatus_Lost,
            => {
                if (st.texture != null) c.wgpuTextureRelease(st.texture);
                self.configureSurface();
                return;
            },
            else => {
                if (st.texture != null) c.wgpuTextureRelease(st.texture);
                return;
            },
        }
        if (st.texture == null) return;

        const view = c.wgpuTextureCreateView(st.texture, null);
        const encoder = c.wgpuDeviceCreateCommandEncoder(self.device, null);

        const color_att = std.mem.zeroInit(c.WGPURenderPassColorAttachment, .{
            .view = view,
            .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
            .loadOp = c.WGPULoadOp_Clear,
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = c.WGPUColor{ .r = 0.09, .g = 0.10, .b = 0.14, .a = 1.0 },
        });
        const depth_att = std.mem.zeroInit(c.WGPURenderPassDepthStencilAttachment, .{
            .view = self.depth_view,
            .depthLoadOp = c.WGPULoadOp_Clear,
            .depthStoreOp = c.WGPUStoreOp_Store,
            .depthClearValue = 1.0,
        });
        const pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &std.mem.zeroInit(c.WGPURenderPassDescriptor, .{
            .colorAttachmentCount = @as(usize, 1),
            .colorAttachments = &color_att,
            .depthStencilAttachment = &depth_att,
        }));

        if (self.pipeline != null) {
            c.wgpuRenderPassEncoderSetPipeline(pass, self.pipeline);
            c.wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, null);

            if (self.sphere_index_count > 0 and self.atom_count > 0) {
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.sphere_vbuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 1, self.atom_ibuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetIndexBuffer(pass, self.sphere_ibuf, c.WGPUIndexFormat_Uint32, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderDrawIndexed(pass, self.sphere_index_count, self.atom_count, 0, 0, 0);
            }

            if (self.cyl_index_count > 0 and self.bond_count > 0) {
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.cyl_vbuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 1, self.bond_ibuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetIndexBuffer(pass, self.cyl_ibuf, c.WGPUIndexFormat_Uint32, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderDrawIndexed(pass, self.cyl_index_count, self.bond_count, 0, 0, 0);
            }
        }

        c.wgpuRenderPassEncoderEnd(pass);
        const cmd = c.wgpuCommandEncoderFinish(encoder, null);
        c.wgpuQueueSubmit(self.queue, 1, &cmd);
        _ = c.wgpuSurfacePresent(self.surface);

        c.wgpuCommandBufferRelease(cmd);
        c.wgpuRenderPassEncoderRelease(pass);
        c.wgpuCommandEncoderRelease(encoder);
        c.wgpuTextureViewRelease(view);
        c.wgpuTextureRelease(st.texture);
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

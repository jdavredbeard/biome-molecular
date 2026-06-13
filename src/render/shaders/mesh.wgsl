struct Uniforms {
    view_proj : mat4x4<f32>,
    light_dir : vec4<f32>,   // xyz = key light direction (world), w unused
    camera_pos : vec4<f32>,
};
@group(0) @binding(0) var<uniform> u : Uniforms;

struct VsIn {
    @location(0) position : vec3<f32>,
    @location(1) normal   : vec3<f32>,
    // instance: a model matrix (4 columns) + color
    @location(2) m0 : vec4<f32>,
    @location(3) m1 : vec4<f32>,
    @location(4) m2 : vec4<f32>,
    @location(5) m3 : vec4<f32>,
    @location(6) color : vec4<f32>,
};

struct VsOut {
    @builtin(position) clip : vec4<f32>,
    @location(0) world_normal : vec3<f32>,
    @location(1) color : vec3<f32>,
};

@vertex
fn vs_main(in : VsIn) -> VsOut {
    let model = mat4x4<f32>(in.m0, in.m1, in.m2, in.m3);
    let world = model * vec4<f32>(in.position, 1.0);
    var out : VsOut;
    out.clip = u.view_proj * world;
    // Rotation-only normal transform is fine (uniform xz scale); normalize covers it.
    out.world_normal = normalize((model * vec4<f32>(in.normal, 0.0)).xyz);
    out.color = in.color.rgb;
    return out;
}

@fragment
fn fs_main(in : VsOut) -> @location(0) vec4<f32> {
    // Flat directional shade for now (3-point lighting comes in Task 14).
    let n = normalize(in.world_normal);
    let l = normalize(u.light_dir.xyz);
    let diffuse = max(dot(n, l), 0.0);
    let ambient = 0.2;
    let shade = ambient + diffuse * 0.8;
    return vec4<f32>(in.color * shade, 1.0);
}

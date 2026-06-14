struct Uniforms {
    view_proj : mat4x4<f32>,
    model_pre : mat4x4<f32>, // world-space pre-transform applied to every instance (turntable spin)
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
    @location(1) color : vec4<f32>,
};

@vertex
fn vs_main(in : VsIn) -> VsOut {
    let model = u.model_pre * mat4x4<f32>(in.m0, in.m1, in.m2, in.m3);
    let world = model * vec4<f32>(in.position, 1.0);
    var out : VsOut;
    out.clip = u.view_proj * world;
    // Normals transform with the full model (incl. turntable spin) so lighting,
    // which is fixed in world space, shifts across the surface as it turns.
    out.world_normal = normalize((model * vec4<f32>(in.normal, 0.0)).xyz);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in : VsOut) -> @location(0) vec4<f32> {
    let n = normalize(in.world_normal);

    // Three directional lights (world space), matching the design spec.
    let key_dir  = normalize(vec3<f32>(-0.6,  0.7, 0.5));  // warm, upper-left
    let fill_dir = normalize(vec3<f32>( 0.6, -0.4, 0.5));  // cool, lower-right
    let rim_dir  = normalize(vec3<f32>( 0.0,  0.2, -1.0)); // behind

    let key  = max(dot(n, key_dir), 0.0)  * vec3<f32>(1.0, 0.95, 0.85) * 0.9;
    let fill = max(dot(n, fill_dir), 0.0) * vec3<f32>(0.7, 0.8, 1.0)  * 0.35;
    let rim  = pow(max(dot(n, rim_dir), 0.0), 2.0) * vec3<f32>(0.6, 0.7, 1.0) * 0.6;
    let ambient = vec3<f32>(0.12, 0.12, 0.15);

    let lit = in.color.rgb * (ambient + key + fill) + rim;
    return vec4<f32>(lit, in.color.a);
}

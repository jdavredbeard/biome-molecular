# WebGPU Renderer (static example browser) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that renders physics-settled molecules from the headless core as lit 3D spheres (atoms) and cylinders (bonds), with a library of example molecules the user scrolls through with the arrow keys (name shown in the window title).

**Architecture:** A new renderer layer consumes the unmodified headless core. CPU-side math (matrices, meshes, camera, instance packing, example builders) is pure and TDD'd. The GPU layer (wgpu-native via `@cImport`) and windowing (GLFW + a macOS `CAMetalLayer` surface) are verified by building and looking. The riskiest piece — getting a wgpu surface and a clear-color frame — is built and pinned **first**, before any geometry.

**Tech Stack:** Zig 0.14.0, wgpu-native (prebuilt, via `build.zig.zon`), GLFW (Homebrew), Metal/QuartzCore/Cocoa/IOKit/Foundation frameworks, WGSL shaders.

---

## Reading notes for the implementer

- **Two kinds of tasks.** Tasks 1–9 are **TDD**: write the failing test, watch it fail, implement, watch it pass, commit. The code in these tasks is exact — type it as written. Tasks 10–17 are **GPU/interop**: there is no unit test; you verify by `zig build run` and looking at the window. The Zig code in GPU tasks is a **reference against the pinned wgpu-native header** — the wgpu C API is a set of descriptor structs whose field names shift between versions. If your pinned header differs, the Zig compiler errors will name the exact field; adjust to match. Do **not** change the algorithm, only the spelling of struct fields.
- **Toolchain:** `~/.local/bin/zig` (must report `0.14.0`). Build/test: `zig build test`. Run: `zig build run`.
- **Do not modify the headless core** (`math.zig`, `atom.zig`, `bond.zig`, `constants.zig`, `geometry.zig`, `molecule.zig`, `physics.zig`). The renderer only reads it. (`mat4.zig` is new general math; it may import `math.zig`.)
- **Branch:** all work on a feature branch off `main` (the controller creates it).

## File Structure

| File | Kind | Responsibility |
|------|------|----------------|
| `src/mat4.zig` | TDD | `Mat4` column-major 4×4: identity, mul, mulPoint, perspective (z∈[0,1]), lookAt, translation, scale, fromAxisAngle. |
| `src/render/mesh.zig` | TDD | `Vertex`, `Mesh`; `icosphere(subdiv)`, `cylinder(segments)`. |
| `src/render/atom_style.zig` | TDD | per-`AtomType` radius + color; fixed bond radius + color. |
| `src/render/camera.zig` | TDD | bounding sphere, camera distance, view/projection matrices. |
| `src/render/scene.zig` | TDD | `Instance`; pack a `Molecule` into atom + bond instance arrays. |
| `src/examples.zig` | TDD | list of named example molecule builders. |
| `src/render/shaders/mesh.wgsl` | manual | instanced vertex + 3-point Phong fragment shader. |
| `src/platform/metal_layer.m` | manual | tiny Objective-C: attach a `CAMetalLayer` to an `NSWindow`, return it. |
| `src/platform/window.zig` | manual | GLFW window, input, the Metal-layer + wgpu surface glue. |
| `src/render/gpu.zig` | manual | wgpu-native device/surface/pipelines/buffers; per-frame draw; instance updates. |
| `src/main.zig` | manual | build+settle examples, create window+GPU, run the loop, handle switching. |
| `build.zig`, `build.zig.zon` | manual | wgpu-native dep, GLFW + framework linking, `.m` compile; test step stays dependency-free. |

---

## Task 1: Mat4 — construction and multiply

**Files:**
- Create: `src/mat4.zig`
- Modify: `src/root.zig` (export `mat4`)

- [ ] **Step 1: Export the module and write failing tests**

Add to `src/root.zig` after the existing `pub const physics = ...` line:
```zig
pub const mat4 = @import("mat4.zig");
```
And add `_ = mat4;` inside the existing `test { ... }` block in `src/root.zig`.

Create `src/mat4.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

// Implementation added in later steps.

fn expectMat(expected: [16]f32, actual: Mat4) !void {
    for (expected, actual.m) |e, a| try std.testing.expectApproxEqAbs(e, a, 1e-5);
}

test "identity is the multiplicative identity" {
    const i = Mat4.identity;
    try expectMat(.{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, i);
    const a = Mat4.translation(Vec3.init(3, 4, 5));
    try expectMat(a.m, a.mul(i));
    try expectMat(a.m, i.mul(a));
}

test "mulPoint applies translation then is identity-safe" {
    const t = Mat4.translation(Vec3.init(1, 2, 3));
    const p = t.mulPoint(Vec3.init(10, 20, 30));
    try std.testing.expect(p.approxEq(Vec3.init(11, 22, 33), 1e-5));
}

test "scale then translate composes as translate*scale" {
    // model = T * S : scale first, then translate.
    const m = Mat4.translation(Vec3.init(5, 0, 0)).mul(Mat4.scale(Vec3.init(2, 2, 2)));
    const p = m.mulPoint(Vec3.init(1, 0, 0)); // scaled to (2,0,0) then +5 -> (7,0,0)
    try std.testing.expect(p.approxEq(Vec3.init(7, 0, 0), 1e-5));
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `Mat4` undefined.

- [ ] **Step 3: Implement the core of Mat4**

Insert into `src/mat4.zig` after the imports (before the tests). Layout is **column-major**: element at row `r`, column `c` is `m[c*4 + r]` (matches WGSL/Metal).
```zig
/// Column-major 4x4 matrix. m[col*4 + row]. Points are column vectors: p' = M*p.
pub const Mat4 = struct {
    m: [16]f32,

    pub const identity = Mat4{ .m = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    } };

    /// Standard matrix product a*b.
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: [16]f32 = undefined;
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) sum += a.m[k * 4 + row] * b.m[col * 4 + k];
                out[col * 4 + row] = sum;
            }
        }
        return .{ .m = out };
    }

    /// Transform a point (w = 1), with perspective divide if w != 1.
    pub fn mulPoint(self: Mat4, p: Vec3) Vec3 {
        const x = self.m[0] * p.x + self.m[4] * p.y + self.m[8] * p.z + self.m[12];
        const y = self.m[1] * p.x + self.m[5] * p.y + self.m[9] * p.z + self.m[13];
        const z = self.m[2] * p.x + self.m[6] * p.y + self.m[10] * p.z + self.m[14];
        const w = self.m[3] * p.x + self.m[7] * p.y + self.m[11] * p.z + self.m[15];
        if (@abs(w) > 1e-8 and @abs(w - 1.0) > 1e-8) {
            return Vec3.init(x / w, y / w, z / w);
        }
        return Vec3.init(x, y, z);
    }

    pub fn translation(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[12] = v.x;
        r.m[13] = v.y;
        r.m[14] = v.z;
        return r;
    }

    pub fn scale(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[0] = v.x;
        r.m[5] = v.y;
        r.m[10] = v.z;
        return r;
    }
};
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/mat4.zig src/root.zig
git commit -m "feat: add Mat4 with identity, mul, mulPoint, translation, scale"
```

---

## Task 2: Mat4 — rotation, lookAt, perspective

**Files:**
- Modify: `src/mat4.zig`

- [ ] **Step 1: Append failing tests**

Append to `src/mat4.zig`:
```zig
test "fromAxisAngle rotates +Y 90deg about +Z to -X... and +Z onto +X" {
    // Rotate the unit +Y vector by 90 deg about +Z -> -X.
    const r = Mat4.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(r.mulPoint(Vec3.init(0, 1, 0)).approxEq(Vec3.init(-1, 0, 0), 1e-5));
}

test "lookAt places the camera so the target maps in front (negative z)" {
    const view = Mat4.lookAt(Vec3.init(0, 0, 5), Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    // The origin (target) should be 5 units in front of the camera => view-space z = -5.
    const p = view.mulPoint(Vec3.init(0, 0, 0));
    try std.testing.expect(p.approxEq(Vec3.init(0, 0, -5), 1e-4));
}

test "perspective maps the near plane to z=0 and far plane to z=1 (WebGPU clip space)" {
    const proj = Mat4.perspective(std.math.pi / 2.0, 1.0, 1.0, 100.0);
    // A point on the near plane (view-space z = -near) -> clip z 0 after divide.
    const near_pt = proj.mulPoint(Vec3.init(0, 0, -1));
    try std.testing.expectApproxEqAbs(@as(f32, 0), near_pt.z, 1e-3);
    // A point on the far plane (view-space z = -far) -> clip z 1 after divide.
    const far_pt = proj.mulPoint(Vec3.init(0, 0, -100));
    try std.testing.expectApproxEqAbs(@as(f32, 1), far_pt.z, 1e-3);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `fromAxisAngle`, `lookAt`, `perspective` undefined.

- [ ] **Step 3: Implement rotation, lookAt, perspective**

Add these methods inside the `Mat4` struct in `src/mat4.zig` (before the closing `};`):
```zig
    /// Rotation about a unit axis by angle radians (column-major Rodrigues).
    pub fn fromAxisAngle(axis: Vec3, angle: f32) Mat4 {
        const a = axis.normalize();
        const c = @cos(angle);
        const s = @sin(angle);
        const t = 1.0 - c;
        const x = a.x;
        const y = a.y;
        const z = a.z;
        var r = Mat4.identity;
        // Column 0
        r.m[0] = t * x * x + c;
        r.m[1] = t * x * y + s * z;
        r.m[2] = t * x * z - s * y;
        // Column 1
        r.m[4] = t * x * y - s * z;
        r.m[5] = t * y * y + c;
        r.m[6] = t * y * z + s * x;
        // Column 2
        r.m[8] = t * x * z + s * y;
        r.m[9] = t * y * z - s * x;
        r.m[10] = t * z * z + c;
        return r;
    }

    /// Right-handed view matrix looking from `eye` toward `center`.
    pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
        const f = center.sub(eye).normalize(); // forward
        const s = f.cross(up).normalize(); // right
        const u = s.cross(f); // true up
        var r = Mat4.identity;
        r.m[0] = s.x;
        r.m[4] = s.y;
        r.m[8] = s.z;
        r.m[1] = u.x;
        r.m[5] = u.y;
        r.m[9] = u.z;
        r.m[2] = -f.x;
        r.m[6] = -f.y;
        r.m[10] = -f.z;
        r.m[12] = -s.dot(eye);
        r.m[13] = -u.dot(eye);
        r.m[14] = f.dot(eye);
        return r;
    }

    /// Perspective projection with WebGPU/Metal clip space (z in [0, 1]).
    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const fl = 1.0 / @tan(fovy / 2.0);
        var r = Mat4{ .m = .{0} ** 16 };
        r.m[0] = fl / aspect;
        r.m[5] = fl;
        r.m[10] = far / (near - far);
        r.m[11] = -1.0;
        r.m[14] = (far * near) / (near - far);
        return r;
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/mat4.zig
git commit -m "feat: add Mat4 fromAxisAngle, lookAt, perspective (z in [0,1])"
```

---

## Task 3: Mesh types and icosphere generation

**Files:**
- Create: `src/render/mesh.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const mesh = @import("render/mesh.zig");` and `_ = mesh;` in the test block.

Create `src/render/mesh.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;

// Implementation added in later steps.

test "icosphere subdiv 0 has 20 triangles, all vertices unit length, normal == position" {
    var m = try icosphere(std.testing.allocator, 0);
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 20 * 3), m.indices.len);
    for (m.vertices) |v| {
        const p = Vec3.init(v.position[0], v.position[1], v.position[2]);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.length(), 1e-4);
        const n = Vec3.init(v.normal[0], v.normal[1], v.normal[2]);
        try std.testing.expect(n.approxEq(p, 1e-4));
    }
}

test "icosphere subdiv 2 quadruples triangle count per level" {
    var m = try icosphere(std.testing.allocator, 2);
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 20 * 16 * 3), m.indices.len); // 4^2 = 16
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `icosphere` undefined.

- [ ] **Step 3: Implement Vertex/Mesh and icosphere**

Insert into `src/render/mesh.zig` after the imports (before tests):
```zig
/// GPU-ready vertex: position + normal, tightly packed f32x3 each.
pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []u32,

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

fn vert(p: Vec3) Vertex {
    const n = p.normalize();
    return .{ .position = .{ n.x, n.y, n.z }, .normal = .{ n.x, n.y, n.z } };
}

/// Unit icosphere centered at the origin. `subdivisions` of 0 => base
/// icosahedron (20 faces); each level multiplies the face count by 4. Vertices
/// are emitted per-triangle (no dedup); since normal == position on a unit
/// sphere there is no shading seam.
pub fn icosphere(allocator: std.mem.Allocator, subdivisions: u5) !Mesh {
    const t: f32 = (1.0 + @sqrt(5.0)) / 2.0;
    const base = [_]Vec3{
        Vec3.init(-1, t, 0), Vec3.init(1, t, 0),  Vec3.init(-1, -t, 0), Vec3.init(1, -t, 0),
        Vec3.init(0, -1, t), Vec3.init(0, 1, t),  Vec3.init(0, -1, -t), Vec3.init(0, 1, -t),
        Vec3.init(t, 0, -1), Vec3.init(t, 0, 1),  Vec3.init(-t, 0, -1), Vec3.init(-t, 0, 1),
    };
    const faces = [_][3]usize{
        .{ 0, 11, 5 }, .{ 0, 5, 1 },  .{ 0, 1, 7 },   .{ 0, 7, 10 }, .{ 0, 10, 11 },
        .{ 1, 5, 9 },  .{ 5, 11, 4 }, .{ 11, 10, 2 }, .{ 10, 7, 6 }, .{ 7, 1, 8 },
        .{ 3, 9, 4 },  .{ 3, 4, 2 },  .{ 3, 2, 6 },   .{ 3, 6, 8 },  .{ 3, 8, 9 },
        .{ 4, 9, 5 },  .{ 2, 4, 11 }, .{ 6, 2, 10 },  .{ 8, 6, 7 },  .{ 9, 8, 1 },
    };

    var tris = std.ArrayList([3]Vec3).init(allocator);
    defer tris.deinit();
    for (faces) |f| try tris.append(.{ base[f[0]], base[f[1]], base[f[2]] });

    var level: u5 = 0;
    while (level < subdivisions) : (level += 1) {
        var next = std.ArrayList([3]Vec3).init(allocator);
        for (tris.items) |tri| {
            const a = tri[0];
            const b = tri[1];
            const c = tri[2];
            const ab = a.add(b).scale(0.5);
            const bc = b.add(c).scale(0.5);
            const ca = c.add(a).scale(0.5);
            try next.append(.{ a, ab, ca });
            try next.append(.{ ab, b, bc });
            try next.append(.{ ca, bc, c });
            try next.append(.{ ab, bc, ca });
        }
        tris.deinit();
        tris = next;
    }

    var vertices = try allocator.alloc(Vertex, tris.items.len * 3);
    var indices = try allocator.alloc(u32, tris.items.len * 3);
    for (tris.items, 0..) |tri, i| {
        vertices[i * 3 + 0] = vert(tri[0]);
        vertices[i * 3 + 1] = vert(tri[1]);
        vertices[i * 3 + 2] = vert(tri[2]);
        indices[i * 3 + 0] = @intCast(i * 3 + 0);
        indices[i * 3 + 1] = @intCast(i * 3 + 1);
        indices[i * 3 + 2] = @intCast(i * 3 + 2);
    }
    return .{ .vertices = vertices, .indices = indices };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/mesh.zig src/root.zig
git commit -m "feat: add Vertex/Mesh types and unit icosphere generation"
```

---

## Task 4: Cylinder mesh generation

**Files:**
- Modify: `src/render/mesh.zig`

- [ ] **Step 1: Append failing tests**

Append to `src/render/mesh.zig`:
```zig
test "cylinder spans y in [0,1] with unit radius and radial side normals" {
    var m = try cylinder(std.testing.allocator, 16);
    defer m.deinit(std.testing.allocator);
    // Side vertices: every vertex y is 0 or 1; xz radius ~1 for side ring verts.
    var saw_y0 = false;
    var saw_y1 = false;
    for (m.vertices) |v| {
        try std.testing.expect(v.position[1] >= -1e-4 and v.position[1] <= 1.0 + 1e-4);
        if (@abs(v.position[1]) < 1e-4) saw_y0 = true;
        if (@abs(v.position[1] - 1.0) < 1e-4) saw_y1 = true;
        const n = Vec3.init(v.normal[0], v.normal[1], v.normal[2]);
        try std.testing.expectApproxEqAbs(@as(f32, 1), n.length(), 1e-4);
    }
    try std.testing.expect(saw_y0 and saw_y1);
    // Indices are whole triangles.
    try std.testing.expect(m.indices.len % 3 == 0);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `cylinder` undefined.

- [ ] **Step 3: Implement cylinder**

Insert into `src/render/mesh.zig` after `icosphere` (before tests):
```zig
/// Unit cylinder along +Y: y in [0, 1], radius 1, `segments` around. Includes
/// a side wall (radial normals) and two end caps (+/-Y normals). Vertices are
/// emitted per-triangle (no dedup).
pub fn cylinder(allocator: std.mem.Allocator, segments: u32) !Mesh {
    var verts = std.ArrayList(Vertex).init(allocator);
    defer verts.deinit();
    var idx = std.ArrayList(u32).init(allocator);
    defer idx.deinit();

    const seg_f: f32 = @floatFromInt(segments);
    var s: u32 = 0;
    while (s < segments) : (s += 1) {
        const a0: f32 = (@as(f32, @floatFromInt(s)) / seg_f) * 2.0 * std.math.pi;
        const a1: f32 = (@as(f32, @floatFromInt(s + 1)) / seg_f) * 2.0 * std.math.pi;
        const c0 = @cos(a0);
        const z0 = @sin(a0);
        const c1 = @cos(a1);
        const z1 = @sin(a1);

        const n0 = [3]f32{ c0, 0, z0 };
        const n1 = [3]f32{ c1, 0, z1 };
        const b0 = Vertex{ .position = .{ c0, 0, z0 }, .normal = n0 };
        const b1 = Vertex{ .position = .{ c1, 0, z1 }, .normal = n1 };
        const t0 = Vertex{ .position = .{ c0, 1, z0 }, .normal = n0 };
        const t1 = Vertex{ .position = .{ c1, 1, z1 }, .normal = n1 };

        // Side quad (two triangles): b0, b1, t1 and b0, t1, t0.
        const base: u32 = @intCast(verts.items.len);
        try verts.appendSlice(&.{ b0, b1, t1, b0, t1, t0 });
        var k: u32 = 0;
        while (k < 6) : (k += 1) try idx.append(base + k);

        // Bottom cap triangle: center(0,0,0), b1, b0 (normal -Y).
        const bn = [3]f32{ 0, -1, 0 };
        const bc = Vertex{ .position = .{ 0, 0, 0 }, .normal = bn };
        const bottom: u32 = @intCast(verts.items.len);
        try verts.appendSlice(&.{
            bc,
            .{ .position = .{ c1, 0, z1 }, .normal = bn },
            .{ .position = .{ c0, 0, z0 }, .normal = bn },
        });
        try idx.appendSlice(&.{ bottom, bottom + 1, bottom + 2 });

        // Top cap triangle: center(0,1,0), t0, t1 (normal +Y).
        const tn = [3]f32{ 0, 1, 0 };
        const tc = Vertex{ .position = .{ 0, 1, 0 }, .normal = tn };
        const top: u32 = @intCast(verts.items.len);
        try verts.appendSlice(&.{
            tc,
            .{ .position = .{ c0, 1, z0 }, .normal = tn },
            .{ .position = .{ c1, 1, z1 }, .normal = tn },
        });
        try idx.appendSlice(&.{ top, top + 1, top + 2 });
    }

    return .{ .vertices = try verts.toOwnedSlice(), .indices = try idx.toOwnedSlice() };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/mesh.zig
git commit -m "feat: add unit cylinder mesh generation"
```

---

## Task 5: Atom styles (radius + color)

**Files:**
- Create: `src/render/atom_style.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const atom_style = @import("render/atom_style.zig");` and `_ = atom_style;` in the test block.

Create `src/render/atom_style.zig` with tests only:
```zig
const std = @import("std");
const AtomType = @import("../atom.zig").AtomType;

// Implementation added in the next step.

test "each atom type has a distinct radius, increasing with bond count" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), styleFor(.mono).radius, 1e-6);
    try std.testing.expect(styleFor(.linear).radius > styleFor(.mono).radius);
    try std.testing.expect(styleFor(.trigonal).radius > styleFor(.linear).radius);
    try std.testing.expect(styleFor(.tetra).radius > styleFor(.trigonal).radius);
}

test "colors differ between types" {
    const a = styleFor(.mono).color;
    const b = styleFor(.tetra).color;
    try std.testing.expect(a[0] != b[0] or a[1] != b[1] or a[2] != b[2]);
}

test "bond style has a small positive radius" {
    try std.testing.expect(bond_radius > 0 and bond_radius < styleFor(.mono).radius);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `styleFor`/`bond_radius` undefined.

- [ ] **Step 3: Implement styles**

Insert into `src/render/atom_style.zig` after the imports (before tests):
```zig
pub const Style = struct {
    radius: f32,
    color: [3]f32,
};

/// Visual radius + RGB color per atom type. Sizes grow with bond count so the
/// structure is readable; colors are distinct.
pub fn styleFor(t: AtomType) Style {
    return switch (t) {
        .mono => .{ .radius = 0.25, .color = .{ 0.80, 0.80, 0.85 } }, // light grey
        .linear => .{ .radius = 0.32, .color = .{ 0.30, 0.55, 0.95 } }, // blue
        .trigonal => .{ .radius = 0.38, .color = .{ 0.30, 0.80, 0.45 } }, // green
        .tetra => .{ .radius = 0.45, .color = .{ 0.95, 0.55, 0.25 } }, // orange
    };
}

/// Bonds render as thin cylinders of this radius.
pub const bond_radius: f32 = 0.08;

/// Bond cylinder color (neutral grey).
pub const bond_color = [3]f32{ 0.6, 0.6, 0.65 };
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/atom_style.zig src/root.zig
git commit -m "feat: add per-atom-type visual styles and bond style"
```

---

## Task 6: Camera (bounding sphere, distance, view/projection)

**Files:**
- Create: `src/render/camera.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const camera = @import("render/camera.zig");` and `_ = camera;` in the test block.

Create `src/render/camera.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;
const Mat4 = @import("../mat4.zig").Mat4;
const Molecule = @import("../molecule.zig").Molecule;

// Implementation added in later steps.

test "boundingSphere centers on the centroid and covers all atoms incl. radius" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // mono at (0,0,1)

    const s = boundingSphere(&mol);
    try std.testing.expect(s.center.approxEq(Vec3.init(0, 0, 0.5), 1e-4));
    // Radius reaches the far atom's surface: dist(center, atom) + atom radius.
    try std.testing.expect(s.radius > 0.5);
}

test "cameraDistance applies the 2.5x factor with a floor of 5.0" {
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), cameraDistance(0.1), 1e-5); // floored
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), cameraDistance(10.0), 1e-5); // 10*2.5
}

test "view looks at the bounding-sphere center from +z; center maps to -distance" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    const s = boundingSphere(&mol);
    const v = viewMatrix(s);
    const center_view = v.mulPoint(s.center);
    try std.testing.expectApproxEqAbs(@as(f32, -cameraDistance(s.radius)), center_view.z, 1e-3);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `boundingSphere`/`cameraDistance`/`viewMatrix` undefined.

- [ ] **Step 3: Implement the camera**

Insert into `src/render/camera.zig` after the imports (before tests):
```zig
const atom_style = @import("atom_style.zig");

pub const Sphere = struct { center: Vec3, radius: f32 };

/// Smallest-ish sphere enclosing all atoms (centroid center; radius reaches the
/// farthest atom's painted surface). Empty molecule -> unit sphere at origin.
pub fn boundingSphere(mol: *const Molecule) Sphere {
    const atoms = mol.atoms.items;
    if (atoms.len == 0) return .{ .center = Vec3.zero, .radius = 1.0 };
    var center = Vec3.zero;
    for (atoms) |atom| center = center.add(atom.position);
    center = center.scale(1.0 / @as(f32, @floatFromInt(atoms.len)));
    var radius: f32 = 0;
    for (atoms) |atom| {
        const reach = center.distance(atom.position) + atom_style.styleFor(atom.atom_type).radius;
        if (reach > radius) radius = reach;
    }
    return .{ .center = center, .radius = radius };
}

/// Camera pull-back distance: 2.5x the bounding radius, never closer than 5.0.
pub fn cameraDistance(radius: f32) f32 {
    return @max(radius * 2.5, 5.0);
}

/// View matrix: camera on +Z looking at the sphere center.
pub fn viewMatrix(s: Sphere) Mat4 {
    const eye = Vec3.init(s.center.x, s.center.y, s.center.z + cameraDistance(s.radius));
    return Mat4.lookAt(eye, s.center, Vec3.init(0, 1, 0));
}

/// Projection matrix for the given aspect ratio (45 deg vertical FOV).
pub fn projectionMatrix(aspect: f32) Mat4 {
    return Mat4.perspective(std.math.pi / 4.0, aspect, 0.1, 1000.0);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/camera.zig src/root.zig
git commit -m "feat: add camera bounding sphere, distance, view/projection"
```

---

## Task 7: Scene — pack a Molecule into instance data

**Files:**
- Create: `src/render/scene.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const scene = @import("render/scene.zig");` and `_ = scene;` in the test block.

Create `src/render/scene.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;
const Mat4 = @import("../mat4.zig").Mat4;
const Molecule = @import("../molecule.zig").Molecule;
const atom_style = @import("atom_style.zig");

// Implementation added in later steps.

fn modelOf(inst: Instance) Mat4 {
    return .{ .m = inst.model };
}

test "atomInstances: one per atom; model places a unit sphere at the atom, scaled by radius" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);

    const insts = try atomInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 2), insts.len);

    // Atom 0 is a tetra at origin: sphere center maps to origin; the +X surface
    // point (1,0,0) maps to (tetra_radius, 0, 0).
    const m0 = modelOf(insts[0]);
    try std.testing.expect(m0.mulPoint(Vec3.zero).approxEq(Vec3.zero, 1e-5));
    const r = atom_style.styleFor(.tetra).radius;
    try std.testing.expect(m0.mulPoint(Vec3.init(1, 0, 0)).approxEq(Vec3.init(r, 0, 0), 1e-5));
}

test "bondInstances: one per bond; cylinder endpoints map to the bonded atoms" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const b = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // bond from origin to (0,0,1)

    const insts = try bondInstances(std.testing.allocator, &mol);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 1), insts.len);

    const m = modelOf(insts[0]);
    const pa = mol.atoms.items[a].position;
    const pb = mol.atoms.items[b].position;
    // Unit cylinder runs y in [0,1]; its endpoints must map to the two atoms.
    try std.testing.expect(m.mulPoint(Vec3.init(0, 0, 0)).approxEq(pa, 1e-4));
    try std.testing.expect(m.mulPoint(Vec3.init(0, 1, 0)).approxEq(pb, 1e-4));
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `Instance`/`atomInstances`/`bondInstances` undefined.

- [ ] **Step 3: Implement the scene packer**

Insert into `src/render/scene.zig` after the imports (before tests):
```zig
/// Per-instance GPU data: a model matrix and an RGBA color (w unused).
/// `extern` for a stable layout matching the WGSL instance attributes.
pub const Instance = extern struct {
    model: [16]f32,
    color: [4]f32,
};

fn make(model: Mat4, color: [3]f32) Instance {
    return .{ .model = model.m, .color = .{ color[0], color[1], color[2], 1.0 } };
}

/// One sphere instance per atom: translate to the atom, scale by its radius.
pub fn atomInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const atoms = mol.atoms.items;
    const out = try allocator.alloc(Instance, atoms.len);
    for (atoms, 0..) |atom, i| {
        const style = atom_style.styleFor(atom.atom_type);
        const model = Mat4.translation(atom.position).mul(Mat4.scale(Vec3.init(style.radius, style.radius, style.radius)));
        out[i] = make(model, style.color);
    }
    return out;
}

/// One cylinder instance per bond: orient + scale the unit (+Y) cylinder from
/// atom A to atom B with the fixed bond radius.
pub fn bondInstances(allocator: std.mem.Allocator, mol: *const Molecule) ![]Instance {
    const bonds = mol.bonds.items;
    const out = try allocator.alloc(Instance, bonds.len);
    const y_axis = Vec3.init(0, 1, 0);
    for (bonds, 0..) |bond, i| {
        const pa = mol.atoms.items[bond.atom_a].position;
        const pb = mol.atoms.items[bond.atom_b].position;
        const dir = pb.sub(pa);
        const len = dir.length();
        const rot = rotationToward(y_axis, dir);
        const model = Mat4.translation(pa)
            .mul(rot)
            .mul(Mat4.scale(Vec3.init(atom_style.bond_radius, len, atom_style.bond_radius)));
        out[i] = make(model, atom_style.bond_color);
    }
    return out;
}

/// Rotation mapping unit vector `from` onto the direction of `to`.
fn rotationToward(from: Vec3, to: Vec3) Mat4 {
    const d = to.normalize();
    const dot = std.math.clamp(from.dot(d), -1.0, 1.0);
    if (dot > 0.9999) return Mat4.identity;
    if (dot < -0.9999) {
        // 180 deg about any axis perpendicular to `from`.
        return Mat4.fromAxisAngle(@import("../math.zig").anyPerpendicular(from), std.math.pi);
    }
    const axis = from.cross(d).normalize();
    return Mat4.fromAxisAngle(axis, std.math.acos(dot));
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/scene.zig src/root.zig
git commit -m "feat: pack Molecule into atom/bond GPU instance data"
```

---

## Task 8: Example molecule builders (part 1)

**Files:**
- Create: `src/examples.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const examples = @import("examples.zig");` and `_ = examples;` in the test block.

Create `src/examples.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("math.zig").Vec3;
const Molecule = @import("molecule.zig").Molecule;
const OpenBondPoint = @import("molecule.zig").OpenBondPoint;

// Implementation added in later steps.

test "methane: 1 tetra + 4 mono caps, 4 bonds" {
    var mol = try buildMethane(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 5), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 4), mol.bonds.items.len);
}

test "linear chain: 6 atoms, 5 bonds" {
    var mol = try buildChain(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 6), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 5), mol.bonds.items.len);
}

test "trigonal star: 1 trigonal + 3 mono, 3 bonds" {
    var mol = try buildTrigonalStar(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 4), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 3), mol.bonds.items.len);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — builders undefined.

- [ ] **Step 3: Implement the helper and the first three builders**

Insert into `src/examples.zig` after the imports (before tests):
```zig
const AtomType = @import("atom.zig").AtomType;

/// Place `atom_type` on the first currently-open bond point of `parent`.
/// Returns the new atom id. Asserts the parent has an open point.
fn addOnOpenPoint(mol: *Molecule, scratch: *std.ArrayList(OpenBondPoint), parent: usize, atom_type: AtomType) !usize {
    try mol.openBondPoints(scratch);
    for (scratch.items) |p| {
        if (p.parent_atom == parent) return try mol.addAtom(parent, p.direction, atom_type);
    }
    unreachable; // caller guarantees an open point exists on `parent`
}

pub fn buildMethane(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var i: usize = 0;
    while (i < 4) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c, .mono);
    return mol;
}

pub fn buildChain(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    var prev = try mol.addFirstAtom(.linear);
    var i: usize = 1;
    while (i < 6) : (i += 1) {
        // A linear atom with one bond opens straight ahead; reuse +Z for simplicity.
        prev = try mol.addAtom(prev, Vec3.init(0, 0, 1), .linear);
    }
    return mol;
}

pub fn buildTrigonalStar(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c = try mol.addFirstAtom(.trigonal);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var i: usize = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c, .mono);
    return mol;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/examples.zig src/root.zig
git commit -m "feat: add methane, chain, trigonal-star example builders"
```

---

## Task 9: Example builders (part 2) and the registry

**Files:**
- Modify: `src/examples.zig`

- [ ] **Step 1: Append failing tests**

Append to `src/examples.zig`:
```zig
test "ethane-like: two tetra + 6 mono caps = 8 atoms, 7 bonds" {
    var mol = try buildEthane(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 8), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 7), mol.bonds.items.len);
}

test "branched blob: tetra + 4 tetra + 12 mono caps = 17 atoms, 16 bonds" {
    var mol = try buildBranchedBlob(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 17), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 16), mol.bonds.items.len);
}

test "trigonal sheet: trigonal + 3 trigonal + 6 mono caps = 10 atoms, 9 bonds" {
    var mol = try buildTrigonalSheet(std.testing.allocator);
    defer mol.deinit();
    try std.testing.expectEqual(@as(usize, 10), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 9), mol.bonds.items.len);
}

test "registry lists every example and each builds + settles" {
    const physics = @import("physics.zig");
    const constants = @import("constants.zig");
    try std.testing.expect(all.len == 6);
    for (all) |ex| {
        var mol = try ex.build(std.testing.allocator);
        defer mol.deinit();
        try std.testing.expect(mol.atoms.items.len >= 1);
        var settled = false;
        var iters: usize = 0;
        while (!settled and iters < 20000) : (iters += 1) {
            settled = try physics.simulate(&mol, constants.default, std.testing.allocator);
        }
        try std.testing.expect(settled);
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `buildEthane`/`buildBranchedBlob`/`buildTrigonalSheet`/`all` undefined.

- [ ] **Step 3: Implement the remaining builders and the registry**

Insert into `src/examples.zig` after `buildTrigonalStar` (before tests):
```zig
pub fn buildEthane(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const c0 = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    const c1 = try addOnOpenPoint(&mol, &scratch, c0, .tetra); // tetra-tetra bond
    // Cap the 3 remaining open points on each tetra with mono.
    var i: usize = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c0, .mono);
    i = 0;
    while (i < 3) : (i += 1) _ = try addOnOpenPoint(&mol, &scratch, c1, .mono);
    return mol;
}

pub fn buildBranchedBlob(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const center = try mol.addFirstAtom(.tetra);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var arms: [4]usize = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) arms[i] = try addOnOpenPoint(&mol, &scratch, center, .tetra);
    // Cap each arm's 3 remaining points with mono.
    for (arms) |arm| {
        var j: usize = 0;
        while (j < 3) : (j += 1) _ = try addOnOpenPoint(&mol, &scratch, arm, .mono);
    }
    return mol;
}

pub fn buildTrigonalSheet(allocator: std.mem.Allocator) !Molecule {
    var mol = Molecule.init(allocator);
    errdefer mol.deinit();
    const center = try mol.addFirstAtom(.trigonal);
    var scratch = std.ArrayList(OpenBondPoint).init(allocator);
    defer scratch.deinit();
    var arms: [3]usize = undefined;
    var i: usize = 0;
    while (i < 3) : (i += 1) arms[i] = try addOnOpenPoint(&mol, &scratch, center, .trigonal);
    // Each outer trigonal has 2 remaining open points -> cap with mono.
    for (arms) |arm| {
        var j: usize = 0;
        while (j < 2) : (j += 1) _ = try addOnOpenPoint(&mol, &scratch, arm, .mono);
    }
    return mol;
}

pub const Example = struct {
    name: []const u8,
    build: *const fn (std.mem.Allocator) anyerror!Molecule,
};

pub const all = [_]Example{
    .{ .name = "Methane", .build = buildMethane },
    .{ .name = "Linear chain", .build = buildChain },
    .{ .name = "Trigonal star", .build = buildTrigonalStar },
    .{ .name = "Ethane-like", .build = buildEthane },
    .{ .name = "Branched blob", .build = buildBranchedBlob },
    .{ .name = "Trigonal sheet", .build = buildTrigonalSheet },
};
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS. (If a `_ ...len` count assertion fails, the geometry produced a different number of open points than expected for that type+bond-count — re-read `geometry.openDirections` and fix the expected count in the test to match reality; do not change the core.)

- [ ] **Step 5: Commit**
```bash
git add src/examples.zig
git commit -m "feat: add ethane/branched/sheet examples and the registry"
```

---

## Task 10: Acquire wgpu-native and confirm the C API (GPU SPIKE)

> From here on, tasks are GPU/interop: **no unit tests**, verify by building/running. Get this one fully working before writing any more GPU code — it pins the exact wgpu-native API everything else is written against.

**Files:**
- Modify: `build.zig.zon`, `build.zig`
- Create: `src/render/gpu_probe.zig` (temporary; deleted at the end of this task)

- [ ] **Step 1: Add the wgpu-native dependency**

Pick the latest stable wgpu-native release for `aarch64-macos` from https://github.com/gfx-rs/wgpu-native/releases (e.g. the `wgpu-macos-aarch64-release.zip` asset of a tagged release). Record the exact tag you chose in a comment. Fetch and pin it:
```bash
cd /Users/jonathandavenport/projects/biome-molecular
~/.local/bin/zig fetch --save=wgpu_native "https://github.com/gfx-rs/wgpu-native/releases/download/<TAG>/wgpu-macos-aarch64-release.zip"
```
This adds a `wgpu_native` entry (url + hash) to `build.zig.zon` `.dependencies`. The unzipped package contains `lib/libwgpu_native.a` (and/or `.dylib`) plus `include/webgpu/webgpu.h` and `include/wgpu.h`.

- [ ] **Step 2: Verify the dependency layout**

Run:
```bash
ls $(find ~/.cache/zig -type d -name 'wgpu*' 2>/dev/null | head -1) 2>/dev/null || echo "inspect via build"
```
Note the relative paths to `include/` and `lib/` inside the package (you'll reference them in `build.zig`). If unsure, the next step's build errors will reveal the structure.

- [ ] **Step 3: Wire the dependency into build.zig for a probe executable**

In `build.zig`, after the existing `exe` is defined (or near it), add a probe step. Add this inside `pub fn build`:
```zig
    // --- wgpu-native probe (temporary, Task 10) ---
    const wgpu_dep = b.dependency("wgpu_native", .{});
    const probe = b.addExecutable(.{
        .name = "gpu_probe",
        .root_source_file = b.path("src/render/gpu_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    probe.addIncludePath(wgpu_dep.path("include"));
    probe.addLibraryPath(wgpu_dep.path("lib"));
    probe.linkSystemLibrary("wgpu_native");
    probe.linkFramework("Metal");
    probe.linkFramework("QuartzCore");
    probe.linkFramework("Foundation");
    probe.linkFramework("CoreFoundation");
    probe.linkLibC();
    const run_probe = b.addRunArtifact(probe);
    const probe_step = b.step("probe", "Run the wgpu-native API probe");
    probe_step.dependOn(&run_probe.step);
```
(If the package's headers are under a different subdir, e.g. `include/webgpu`, adjust `addIncludePath` so that `@cImport`-ing `"webgpu/webgpu.h"` resolves.)

- [ ] **Step 4: Write the probe**

Create `src/render/gpu_probe.zig`:
```zig
const std = @import("std");
const c = @cImport({
    @cInclude("webgpu/webgpu.h");
    @cInclude("wgpu.h");
});

pub fn main() void {
    const instance = c.wgpuCreateInstance(null);
    if (instance == null) {
        std.debug.print("wgpuCreateInstance returned null\n", .{});
        return;
    }
    std.debug.print("wgpu-native OK: created instance {*}\n", .{instance});
    c.wgpuInstanceRelease(instance);
}
```

- [ ] **Step 5: Build and run the probe**

Run: `~/.local/bin/zig build probe`
Expected: prints `wgpu-native OK: created instance 0x...`.

Troubleshooting:
- Header not found → fix `addIncludePath` / the `@cInclude` path to match the package layout.
- Link error (`_wgpuCreateInstance` undefined) → fix `addLibraryPath`/`linkSystemLibrary` name (the lib may be `libwgpu_native.a` → `"wgpu_native"`, or `libwgpu.a` → `"wgpu"`).
- If `wgpuInstanceRelease` doesn't exist, the version uses a different release fn (e.g. `wgpuInstanceDrop`); note the actual name — this tells you the API generation you're on.

- [ ] **Step 6: Record the API generation, remove the probe, keep the dependency**

In `build.zig.zon`, leave the `wgpu_native` dependency. In `build.zig`, **remove** the probe block from Step 3. Delete the probe file:
```bash
rm src/render/gpu_probe.zig
```
Add a short note to the top of (soon-to-exist) usage by recording, in your commit message, the wgpu-native tag and whether strings are `const char*` or `WGPUStringView`, and the release-fn naming (`*Release` vs `*Drop`). Verify the normal build still works:
```bash
~/.local/bin/zig build test
```
Expected: PASS (unchanged; tests don't touch wgpu).

- [ ] **Step 7: Commit**
```bash
git add build.zig build.zig.zon
git commit -m "build: add and verify wgpu-native dependency (<TAG>, strings=<...>, release=<...>)"
```

---

## Task 11: GLFW window + Metal layer + clear-color frame (GPU SPIKE)

> Goal: a window that shows a solid clear color, proving GLFW + the `CAMetalLayer` surface + wgpu device/swapchain all work. No geometry yet.

**Files:**
- Create: `src/platform/metal_layer.m`, `src/platform/metal_layer.h`, `src/platform/window.zig`, `src/render/gpu.zig`
- Modify: `src/main.zig`, `build.zig`

- [ ] **Step 1: Install GLFW**

Run: `brew install glfw && ls $(brew --prefix glfw)/include/GLFW/glfw3.h`
Expected: the header path prints.

- [ ] **Step 2: Objective-C Metal-layer glue**

Create `src/platform/metal_layer.h`:
```c
#pragma once
// Returns a CAMetalLayer* (as void*) attached to the given Cocoa NSWindow* (void*).
void *biome_attach_metal_layer(void *ns_window);
```
Create `src/platform/metal_layer.m`:
```objc
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#include "metal_layer.h"

void *biome_attach_metal_layer(void *ns_window) {
    NSWindow *window = (__bridge NSWindow *)ns_window;
    NSView *view = [window contentView];
    CAMetalLayer *layer = [CAMetalLayer layer];
    [view setWantsLayer:YES];
    [view setLayer:layer];
    return (__bridge void *)layer;
}
```

- [ ] **Step 3: Build wiring for the app executable**

Replace the existing `exe` linking in `build.zig` so the app links wgpu, GLFW, the `.m` file, and frameworks. Ensure the `exe` (the one run by `zig build run`) has:
```zig
    const wgpu_dep = b.dependency("wgpu_native", .{});
    exe.addIncludePath(wgpu_dep.path("include"));
    exe.addLibraryPath(wgpu_dep.path("lib"));
    exe.linkSystemLibrary("wgpu_native");

    const glfw_prefix = "/opt/homebrew/opt/glfw"; // `brew --prefix glfw`
    exe.addIncludePath(.{ .cwd_relative = glfw_prefix ++ "/include" });
    exe.addLibraryPath(.{ .cwd_relative = glfw_prefix ++ "/lib" });
    exe.linkSystemLibrary("glfw");

    exe.addIncludePath(b.path("src/platform"));
    exe.addCSourceFile(.{ .file = b.path("src/platform/metal_layer.m"), .flags = &.{"-fobjc-arc"} });

    exe.linkFramework("Metal");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("Cocoa");
    exe.linkFramework("IOKit");
    exe.linkFramework("Foundation");
    exe.linkLibC();
```
(The `test` step must NOT get these — keep test wiring as-is.)

- [ ] **Step 4: Window module**

Create `src/platform/window.zig`. This wraps GLFW and produces a wgpu surface. Adjust the wgpu surface-descriptor field names to your pinned header (Task 10); the structure (chained `SurfaceSourceMetalLayer`/`SurfaceDescriptorFromMetalLayer`) is what varies by version.
```zig
const std = @import("std");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cDefine("GLFW_EXPOSE_NATIVE_COCOA", "1");
    @cInclude("GLFW/glfw3native.h");
    @cInclude("webgpu/webgpu.h");
    @cInclude("wgpu.h");
    @cInclude("metal_layer.h");
});

pub const c_api = c;

pub const Window = struct {
    handle: *c.GLFWwindow,

    pub fn create(width: i32, height: i32, title: [*:0]const u8) !Window {
        if (c.glfwInit() == 0) return error.GlfwInitFailed;
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API); // no GL context
        const h = c.glfwCreateWindow(width, height, title, null, null) orelse return error.WindowCreateFailed;
        return .{ .handle = h };
    }

    pub fn shouldClose(self: Window) bool {
        return c.glfwWindowShouldClose(self.handle) != 0;
    }

    pub fn pollEvents(_: Window) void {
        c.glfwPollEvents();
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

    /// Create a wgpu surface backed by a CAMetalLayer on this window.
    pub fn createSurface(self: Window, instance: c.WGPUInstance) c.WGPUSurface {
        const ns_window = c.glfwGetCocoaWindow(self.handle);
        const metal_layer = c.biome_attach_metal_layer(ns_window);
        var from_layer = c.WGPUSurfaceSourceMetalLayer{
            .chain = .{ .sType = c.WGPUSType_SurfaceSourceMetalLayer, .next = null },
            .layer = metal_layer,
        };
        const desc = c.WGPUSurfaceDescriptor{
            .nextInChain = @ptrCast(&from_layer),
            .label = .{ .data = null, .length = 0 }, // if label is `const char*`, use null instead
        };
        return c.wgpuInstanceCreateSurface(instance, &desc);
    }

    pub fn destroy(self: Window) void {
        c.glfwDestroyWindow(self.handle);
        c.glfwTerminate();
    }
};
```

- [ ] **Step 5: GPU module — device, surface config, clear-color frame**

Create `src/render/gpu.zig`. This is the version-sensitive part — keep the **sequence** (instance→surface→adapter→device→queue→configure→per-frame: getCurrentTexture→view→encoder→renderpass(clear)→submit→present) and adjust struct field names to your header. Use synchronous-style adapter/device requests via callbacks that store the result.
```zig
const std = @import("std");
const win = @import("../platform/window.zig");
const c = win.c_api;

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
        const surface = window.createSurface(instance);

        // Request adapter (callback stores into `adapter`).
        var adapter: c.WGPUAdapter = null;
        const opts = c.WGPURequestAdapterOptions{ .compatibleSurface = surface };
        c.wgpuInstanceRequestAdapter(instance, &opts, onAdapter, @ptrCast(&adapter));
        if (adapter == null) return error.NoAdapter;

        // Request device (callback stores into `device`).
        var device: c.WGPUDevice = null;
        c.wgpuAdapterRequestDevice(adapter, null, onDevice, @ptrCast(&device));
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
        const config = c.WGPUSurfaceConfiguration{
            .device = self.device,
            .format = self.format,
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .width = self.width,
            .height = self.height,
            .presentMode = c.WGPUPresentMode_Fifo,
            .alphaMode = c.WGPUCompositeAlphaMode_Auto,
        };
        c.wgpuSurfaceConfigure(self.surface, &config);
    }

    pub fn resize(self: *Gpu, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.width = width;
        self.height = height;
        self.configureSurface();
    }

    /// Render one frame: just a clear color for now.
    pub fn renderClear(self: *Gpu) void {
        var surface_tex: c.WGPUSurfaceTexture = undefined;
        c.wgpuSurfaceGetCurrentTexture(self.surface, &surface_tex);
        const view = c.wgpuTextureCreateView(surface_tex.texture, null);

        const encoder = c.wgpuDeviceCreateCommandEncoder(self.device, null);
        const color_attachment = c.WGPURenderPassColorAttachment{
            .view = view,
            .loadOp = c.WGPULoadOp_Clear,
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = .{ .r = 0.04, .g = 0.04, .b = 0.06, .a = 1.0 },
            .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
        };
        const pass_desc = c.WGPURenderPassDescriptor{
            .colorAttachmentCount = 1,
            .colorAttachments = &color_attachment,
        };
        const pass = c.wgpuRenderPassEncoderBegin(encoder, &pass_desc); // name may be wgpuCommandEncoderBeginRenderPass
        c.wgpuRenderPassEncoderEnd(pass);

        const cmd = c.wgpuCommandEncoderFinish(encoder, null);
        c.wgpuQueueSubmit(self.queue, 1, &cmd);
        c.wgpuSurfacePresent(self.surface);

        c.wgpuTextureViewRelease(view);
    }
};

fn onAdapter(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, msg: anytype, userdata: ?*anyopaque) callconv(.C) void {
    _ = status;
    _ = msg;
    const out: *c.WGPUAdapter = @ptrCast(@alignCast(userdata.?));
    out.* = adapter;
}

fn onDevice(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, msg: anytype, userdata: ?*anyopaque) callconv(.C) void {
    _ = status;
    _ = msg;
    const out: *c.WGPUDevice = @ptrCast(@alignCast(userdata.?));
    out.* = device;
}
```
Notes: the callback signatures vary by version (older take `const char* message`; newer take `WGPUStringView`). Match your header — the `anytype` placeholders above must become the concrete types your header declares, or the compiler will reject the function-pointer cast. `wgpuCommandEncoderBeginRenderPass` vs `wgpuRenderPassEncoderBegin` likewise — use whichever your header exports.

- [ ] **Step 6: Minimal main loop showing the clear color**

Replace `src/main.zig` with:
```zig
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
```

- [ ] **Step 7: Build, run, and visually verify**

Run: `~/.local/bin/zig build run`
Expected: a 1280×800 window opens showing a solid dark blue-grey background (`0.04, 0.04, 0.06`). Resizing keeps it filled. Closing the window exits cleanly. Take a screenshot to confirm.

If it builds but the window is black/garbage: the surface format or present mode is wrong for Metal — try `WGPUTextureFormat_BGRA8Unorm` (set) and confirm `wgpuSurfaceGetCurrentTexture` returns `status == Success`.

- [ ] **Step 8: Commit**
```bash
git add build.zig src/platform/ src/render/gpu.zig src/main.zig
git commit -m "feat: GLFW window + Metal-layer wgpu surface rendering a clear frame"
```

---

## Task 12: Shader + render pipeline for instanced meshes (atoms)

> Render the example molecule's atoms as instanced spheres (flat-shaded for now; lighting added in Task 14). Verify visually.

**Files:**
- Create: `src/render/shaders/mesh.wgsl`
- Modify: `src/render/gpu.zig`, `src/main.zig`

- [ ] **Step 1: Write the WGSL shader**

Create `src/render/shaders/mesh.wgsl`:
```wgsl
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
```

- [ ] **Step 2: Extend Gpu with mesh/instance buffers, a uniform buffer, and a pipeline**

Modify `src/render/gpu.zig`: add fields and methods to upload a mesh + instances, build the pipeline with two vertex buffers (mesh at step Vertex, instance at step Instance), a uniform bind group, and a depth texture. Keep the wgpu sequence; adapt field names. Add (sketch — fill in against your header):
- Fields: `pipeline`, `uniform_buffer`, `bind_group`, `sphere_vbuf`, `sphere_ibuf`, `sphere_index_count`, `atom_ibuf` (instance buffer), `atom_count`, `depth_view`.
- `createBuffer(data, usage)` helper using `wgpuDeviceCreateBuffer` + `wgpuQueueWriteBuffer`.
- `uploadSphere(mesh)` and `uploadAtomInstances(instances)`.
- `createDepthTexture()` (format `Depth24Plus`, size = framebuffer), recreated on resize.
- `createPipeline()`: vertex state with two `WGPUVertexBufferLayout`s — buffer 0 (mesh): attributes location 0 (float32x3 @ offset 0) and 1 (float32x3 @ offset 12), arrayStride 24, stepMode Vertex; buffer 1 (instance): locations 2–5 (float32x4 at offsets 0/16/32/48) for the model columns and location 6 (float32x4 at offset 64) for color, arrayStride 80, stepMode Instance. Depth-stencil state: format Depth24Plus, depthWriteEnabled true, depthCompare Less. Fragment target format = `self.format`.
- `setUniforms(view_proj: [16]f32, light_dir: [3]f32, camera_pos: [3]f32)` writes the uniform buffer.

Because this is long and version-specific, implement it incrementally and lean on compiler errors. The shader module is created with `wgpuDeviceCreateShaderModule` from the WGSL source embedded via `@embedFile("shaders/mesh.wgsl")`.

- [ ] **Step 3: Replace renderClear with a geometry render**

Modify `renderClear` (rename to `renderFrame`) so the render pass also: sets the pipeline, binds group 0 (uniforms), sets vertex buffer 0 (sphere mesh), vertex buffer 1 (atom instances), index buffer, and calls `wgpuRenderPassEncoderDrawIndexed(pass, sphere_index_count, atom_count, 0, 0, 0)`. Attach the depth texture to the render pass (`depthStencilAttachment`).

- [ ] **Step 4: Wire main.zig to build+settle one example and upload it**

Modify `src/main.zig` to (for now) build + settle `examples.all[0]` (Methane), compute the camera, pack atom instances via `scene.atomInstances`, upload mesh (`mesh.icosphere(alloc, 2)`) and instances, set uniforms, and call `renderFrame` in the loop. Use a `GeneralPurposeAllocator`.

- [ ] **Step 5: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: a window showing 5 shaded spheres (one larger orange tetra in the middle, four light-grey monos around it) on the dark background, correctly depth-sorted. Screenshot to confirm.

- [ ] **Step 6: Commit**
```bash
git add src/render/shaders/mesh.wgsl src/render/gpu.zig src/main.zig
git commit -m "feat: instanced sphere rendering of atoms with depth + uniforms"
```

---

## Task 13: Render bonds (instanced cylinders)

**Files:**
- Modify: `src/render/gpu.zig`, `src/main.zig`

- [ ] **Step 1: Add cylinder mesh + bond instance buffers and a second draw**

Modify `src/render/gpu.zig`: add `cyl_vbuf`, `cyl_ibuf`, `cyl_index_count`, `bond_ibuf`, `bond_count`; add `uploadCylinder(mesh)` and `uploadBondInstances(instances)` (mirroring the atom equivalents). In `renderFrame`, after drawing atoms, set the cylinder vertex buffer + bond instance buffer + cylinder index buffer and issue a second `wgpuRenderPassEncoderDrawIndexed(pass, cyl_index_count, bond_count, 0, 0, 0)` within the same render pass (same pipeline — the vertex layout is identical).

- [ ] **Step 2: Wire main.zig to upload cylinder mesh + bond instances**

Modify `src/main.zig`: also upload `mesh.cylinder(alloc, 16)` and `scene.bondInstances(alloc, &mol)`.

- [ ] **Step 3: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: the methane molecule now shows thin grey cylinders connecting the central tetra to each mono, joining the sphere centers. Screenshot.

- [ ] **Step 4: Commit**
```bash
git add src/render/gpu.zig src/main.zig
git commit -m "feat: render bonds as instanced cylinders"
```

---

## Task 14: 3-point Phong lighting

**Files:**
- Modify: `src/render/shaders/mesh.wgsl`, `src/render/gpu.zig`

- [ ] **Step 1: Replace the flat shade with 3-point Phong in the fragment shader**

Replace the `fs_main` in `src/render/shaders/mesh.wgsl` with:
```wgsl
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

    let lit = in.color * (ambient + key + fill) + rim;
    return vec4<f32>(lit, 1.0);
}
```
(The lights are constants in the shader; `Uniforms.light_dir`/`camera_pos` are no longer required by the fragment shader but keep the uniform struct as-is so the pipeline/bindings don't change. They become useful later for specular.)

- [ ] **Step 2: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: spheres and cylinders now show smooth directional shading — warm highlight from the upper-left, cooler fill from the lower-right, subtle rim glow on edges. The molecule reads as clearly 3D. Screenshot.

- [ ] **Step 3: Commit**
```bash
git add src/render/shaders/mesh.wgsl
git commit -m "feat: 3-point Phong lighting in the fragment shader"
```

---

## Task 15: Example browser — switch examples with arrow keys

**Files:**
- Modify: `src/platform/window.zig`, `src/render/gpu.zig`, `src/main.zig`

- [ ] **Step 1: Add key-edge input to the window**

Modify `src/platform/window.zig`: add a small key-edge helper. Store, in the `Window` struct, the previous pressed-state of Left/Right (and detect Escape). Add:
```zig
    pub fn keyPressed(self: Window, key: c_int) bool {
        return c.glfwGetKey(self.handle, key) == c.GLFW_PRESS;
    }
```
Expose key constants `c.GLFW_KEY_LEFT`, `c.GLFW_KEY_RIGHT`, `c.GLFW_KEY_ESCAPE` via `pub const KEY_LEFT = c.GLFW_KEY_LEFT;` etc. (Edge detection — only switch once per press — is handled in `main.zig`.)

- [ ] **Step 2: Add instance-buffer replacement to Gpu**

Modify `src/render/gpu.zig`: ensure `uploadAtomInstances` and `uploadBondInstances` release any previous instance buffer before creating the new one (so switching examples with different atom/bond counts works). Set `atom_count`/`bond_count` accordingly. (If a buffer handle is non-null, call its `*Release`/`*Drop` before reassigning.)

- [ ] **Step 3: Pre-settle all examples and switch on arrow keys in main.zig**

Modify `src/main.zig`:
- At startup, build + `physics.simulate`-settle every `examples.all[i]` into an array of `Molecule` (kept alive for the program).
- Track `current: usize`. A function `showCurrent(...)` repacks atom+bond instances from `molecules[current]`, uploads them, recomputes the camera (`camera.boundingSphere`/`viewMatrix`/`projectionMatrix` with the live aspect), sets uniforms, and updates the window title to `"<name> (<i+1>/<N>)"` (format into a stack buffer, null-terminate).
- In the loop: detect a rising edge on Left/Right (compare against a stored `prev_left`/`prev_right` bool), wrap `current`, call `showCurrent`. Exit on Escape.
- On resize, recompute the projection (aspect changed) and re-set uniforms, and recreate the depth texture.

- [ ] **Step 4: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: opens on Methane (title `Methane (1/6)`). Pressing Right cycles Methane → Linear chain → Trigonal star → Ethane-like → Branched blob → Trigonal sheet → wraps; Left goes back. Each molecule is correctly framed (camera re-fits), lit, and the title updates. Escape exits. Screenshot a couple of them.

- [ ] **Step 5: Commit**
```bash
git add src/platform/window.zig src/render/gpu.zig src/main.zig
git commit -m "feat: arrow-key example browser with per-example camera + title"
```

---

## Task 16: Resource cleanup and final polish

**Files:**
- Modify: `src/render/gpu.zig`, `src/main.zig`

- [ ] **Step 1: Add a Gpu.deinit and free everything**

Modify `src/render/gpu.zig`: add `pub fn deinit(self: *Gpu) void` that releases (in reverse creation order) the pipeline, bind group, buffers (mesh + instance + uniform), depth texture/view, queue, device, adapter, surface, and instance, using your header's `*Release`/`*Drop` functions. In `src/main.zig`, `defer gpu.deinit();`, `defer` freeing every settled `Molecule` and any heap mesh/instance slices, and `defer _ = gpa.deinit();` to confirm no leaks at exit.

- [ ] **Step 2: Build, run, verify clean exit**

Run: `~/.local/bin/zig build run`
Expected: app runs as before; on closing the window the process exits with no GPA leak report printed to stderr. Run `~/.local/bin/zig build test` one more time — still all green (CPU tests unaffected).

- [ ] **Step 3: Commit**
```bash
git add src/render/gpu.zig src/main.zig
git commit -m "chore: release GPU resources and free molecules on exit"
```

---

## Task 17: README run instructions

**Files:**
- Create or modify: `README.md`

- [ ] **Step 1: Document the renderer**

Add a section to `README.md` covering: prerequisites (`brew install glfw`, Zig 0.14.0), how the wgpu-native dependency is pinned, `zig build test` (headless tests), `zig build run` (the example browser), and the controls (Left/Right to switch examples, Escape to quit). List the example molecules.

- [ ] **Step 2: Commit**
```bash
git add README.md
git commit -m "docs: renderer prerequisites, build, and controls"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Static render of settled molecules (spheres + cylinders) → Tasks 11–14 ✓
- Atoms as instanced lit spheres → Tasks 12, 14 ✓; bonds as instanced lit cylinders → Tasks 13, 14 ✓
- 3-point Phong, dark background, depth → Tasks 11 (clear/depth), 12 (depth), 14 (Phong) ✓
- Fixed camera from bounding sphere, `max(r*2.5, 5)` → Task 6, applied in 12/15 ✓
- `Mat4` math → Tasks 1–2 ✓; meshes (icosphere/cylinder) → Tasks 3–4 ✓; atom styles → Task 5 ✓; scene packing → Task 7 ✓
- Example library + arrow-key scroll + window-title label → Tasks 8–9 (builders), 15 (browser) ✓
- wgpu-native + GLFW, macOS frameworks, Metal-layer surface → Tasks 10–11 ✓
- CPU TDD + manual GPU verification → Tasks 1–9 TDD, 10–17 manual ✓
- Core unmodified → only new files + `root.zig` exports + `build.zig`/`main.zig` ✓
- Cleanup/no leaks → Task 16 ✓; run docs → Task 17 ✓

**Deferred per spec (no tasks, intentional):** open-bond markers, radial menu, navigation/slerp, auto-zoom animation, in-window text, puzzle mode, non-macOS targets.

**Placeholder scan:** GPU tasks (10–17) intentionally describe wgpu calls as "adapt field names to your pinned header" — this is not a vague-requirement placeholder but a necessary consequence of a version-sensitive C API; the algorithm/sequence and all CPU code are fully specified. Tasks 12 Step 2 and 15 Step 3 are described as structured sketches rather than verbatim code because the exact wgpu struct spellings are unknown until Task 10 pins them; every field/attribute/offset they need is enumerated.

**Type consistency:** `Instance` layout (model `[16]f32` + color `[4]f32`, arrayStride 80) is consistent between `scene.zig` (Task 7) and the vertex buffer layout / WGSL `@location`s (Tasks 12). `Vertex` (pos+normal, stride 24) consistent between `mesh.zig` (Tasks 3–4) and the pipeline layout (Task 12). `styleFor`/`bond_radius`/`bond_color` names consistent between Tasks 5 and 7. `boundingSphere`/`cameraDistance`/`viewMatrix`/`projectionMatrix` consistent between Task 6 and Tasks 12/15. Example builder names (`buildMethane`…`buildTrigonalSheet`) and `all` consistent between Tasks 8–9 and 15.

**Known risk acknowledged in-plan:** Task 9's exact atom/bond counts assume `geometry.openDirections` yields (tetra:4, trigonal:3 from 0 bonds; and the remaining counts after each placement). If a count differs, the instruction is to correct the test expectation to match the core, not to change the core.

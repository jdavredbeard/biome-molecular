# Navigation (sandbox bond-point selection & rotation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the renderer app into the sandbox: start with a single Tetra at the origin, show its open bond points as markers, and let Left/Right cycle the selection while the molecule smoothly rotates (quaternion slerp) to bring the selected point to face the camera.

**Architecture:** A new `Quaternion` type drives a molecule orientation that replaces the turntable. Pure logic (quaternion math, selection cycling, target orientation, marker instance packing) is TDD'd; the marker rendering and slerp animation feel are verified by running. Reuses the existing instanced sphere pipeline for markers.

**Tech Stack:** Zig 0.14.0, the existing wgpu-native renderer, WGSL (unchanged).

---

## Reading notes for the implementer

- **Toolchain:** `~/.local/bin/zig` (must report `0.14.0`). Tests: `~/.local/bin/zig build test`. Run: `~/.local/bin/zig build run`.
- **Two kinds of tasks.** Tasks 1–4 are **TDD** (write failing test → run fail → implement → run pass → commit; code is exact). Tasks 5–6 are **GPU/app** changes verified by `zig build run` and looking — there is no unit test for the window/animation. Task 7 is docs.
- **Don't modify the headless core physics/geometry/data model.** This plan adds `quaternion.zig`, `navigation.zig`, extends `render/scene.zig` and `render/gpu.zig`, and rewrites `main.zig`. `examples.zig` stays (its tests keep running) but `main` stops using it.
- **Quaternion convention:** unit quaternion `{w,x,y,z}`, rotates a vector as `v' = q v q*`. `mul(a,b)` is the Hamilton product (apply `b` then `a`). `toMat4` is column-major to match `Mat4` (`m[col*4+row]`, `v' = M·v`).
- **Branch:** all work on a feature branch off `main` (the controller creates it).

## File Structure

| File | Kind | Responsibility |
|------|------|----------------|
| `src/quaternion.zig` | TDD | `Quaternion`: identity, fromAxisAngle, mul, normalize, dot/add/sub/scale/neg, rotateVec, slerp, rotationBetween, toMat4. |
| `src/navigation.zig` | TDD | `cycle(index,len,dir)` selection wrap; `targetOrientation(dir)` = rotation bringing `dir` to +Z. |
| `src/render/scene.zig` | TDD | add `openPointInstances(mol, selected, pulse)` — marker instances (selected larger/brighter). |
| `src/render/gpu.zig` | manual | marker instance buffer + a third draw over the sphere mesh. |
| `src/main.zig` | manual | sandbox loop: single Tetra, selection state, slerp orientation, render atoms+bonds+markers, Left/Right input. |
| `README.md` | docs | update controls to the sandbox navigation. |

---

## Task 1: Quaternion — construction, multiply, rotateVec

**Files:**
- Create: `src/quaternion.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const quaternion = @import("quaternion.zig");` and `_ = quaternion;` inside the existing `test { ... }` block.

Create `src/quaternion.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

// Implementation added in later steps.

test "fromAxisAngle + rotateVec rotates +X 90deg about +Z to +Y" {
    const q = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    const v = q.rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(v.approxEq(Vec3.init(0, 1, 0), 1e-5));
}

test "mul composes rotations (two 90deg about Z = 180deg)" {
    const q90 = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    const q180 = q90.mul(q90);
    const v = q180.rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(v.approxEq(Vec3.init(-1, 0, 0), 1e-5));
}

test "identity rotates nothing and normalize keeps unit length" {
    const v = Quaternion.identity.rotateVec(Vec3.init(3, -2, 1));
    try std.testing.expect(v.approxEq(Vec3.init(3, -2, 1), 1e-6));
    const q = Quaternion{ .w = 2, .x = 0, .y = 0, .z = 0 }; // length 2
    const n = q.normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.length(), 1e-6);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `Quaternion` undefined.

- [ ] **Step 3: Implement the core**

Insert into `src/quaternion.zig` after the imports (before the tests):
```zig
/// Unit quaternion rotation. v' = q v q*. mul(a, b) applies b then a.
pub const Quaternion = struct {
    w: f32,
    x: f32,
    y: f32,
    z: f32,

    pub const identity = Quaternion{ .w = 1, .x = 0, .y = 0, .z = 0 };

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quaternion {
        const a = axis.normalize();
        const h = angle * 0.5;
        const s = @sin(h);
        return .{ .w = @cos(h), .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn mul(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    pub fn dot(a: Quaternion, b: Quaternion) f32 {
        return a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn add(a: Quaternion, b: Quaternion) Quaternion {
        return .{ .w = a.w + b.w, .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Quaternion, b: Quaternion) Quaternion {
        return .{ .w = a.w - b.w, .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Quaternion, s: f32) Quaternion {
        return .{ .w = a.w * s, .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Quaternion) Quaternion {
        return .{ .w = -a.w, .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn length(a: Quaternion) f32 {
        return @sqrt(a.dot(a));
    }

    pub fn normalize(a: Quaternion) Quaternion {
        const len = a.length();
        if (len < 1e-8) return Quaternion.identity;
        return a.scale(1.0 / len);
    }

    /// Rotate a vector: v' = v + w*t + qv x t, where qv = (x,y,z), t = 2*(qv x v).
    pub fn rotateVec(q: Quaternion, v: Vec3) Vec3 {
        const qv = Vec3.init(q.x, q.y, q.z);
        const t = qv.cross(v).scale(2.0);
        return v.add(t.scale(q.w)).add(qv.cross(t));
    }
};
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/quaternion.zig src/root.zig
git commit -m "feat: add Quaternion (fromAxisAngle, mul, rotateVec)"
```

---

## Task 2: Quaternion — slerp, rotationBetween, toMat4

**Files:**
- Modify: `src/quaternion.zig`

- [ ] **Step 1: Append failing tests**

Append to `src/quaternion.zig`:
```zig
const Mat4 = @import("mat4.zig").Mat4;

test "slerp endpoints and midpoint" {
    const a = Quaternion.identity;
    const b = Quaternion.fromAxisAngle(Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(a.slerp(b, 0).rotateVec(Vec3.init(1, 0, 0)).approxEq(Vec3.init(1, 0, 0), 1e-5));
    try std.testing.expect(a.slerp(b, 1).rotateVec(Vec3.init(1, 0, 0)).approxEq(Vec3.init(0, 1, 0), 1e-5));
    // Halfway = 45 deg about Z: (1,0,0) -> (cos45, sin45, 0).
    const h = a.slerp(b, 0.5).rotateVec(Vec3.init(1, 0, 0));
    try std.testing.expect(h.approxEq(Vec3.init(0.70710677, 0.70710677, 0), 1e-4));
}

test "slerp takes the shortest path (negative dot)" {
    const a = Quaternion.identity;
    const b = Quaternion.identity.neg(); // same rotation, opposite sign
    const m = a.slerp(b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.length(), 1e-5);
    try std.testing.expect(m.rotateVec(Vec3.init(1, 2, 3)).approxEq(Vec3.init(1, 2, 3), 1e-4));
}

test "rotationBetween maps from onto to (incl. parallel and antiparallel)" {
    const from = Vec3.init(1, 0, 0);
    const to = Vec3.init(0, 0, 1);
    const q = Quaternion.rotationBetween(from, to);
    try std.testing.expect(q.rotateVec(from).approxEq(to, 1e-5));
    try std.testing.expect(Quaternion.rotationBetween(from, from).rotateVec(from).approxEq(from, 1e-5));
    const anti = Quaternion.rotationBetween(from, from.neg());
    try std.testing.expect(anti.rotateVec(from).approxEq(from.neg(), 1e-4));
}

test "toMat4 agrees with rotateVec" {
    const q = Quaternion.fromAxisAngle(Vec3.init(1, 1, 0).normalize(), 0.9);
    const v = Vec3.init(1, 2, 3);
    const by_mat = q.toMat4().mulPoint(v);
    const by_quat = q.rotateVec(v);
    try std.testing.expect(by_mat.approxEq(by_quat, 1e-4));
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `slerp`, `rotationBetween`, `toMat4` undefined.

- [ ] **Step 3: Implement**

Add these methods inside the `Quaternion` struct in `src/quaternion.zig` (before the closing `};`). Note: `Mat4` is imported at the top of the test block in Step 1 — move that `const Mat4 = @import("mat4.zig").Mat4;` line up to sit beside the other imports at the top of the file (just under `const Vec3 = ...`).
```zig
    /// Spherical linear interpolation along the shortest arc.
    pub fn slerp(a: Quaternion, b: Quaternion, t: f32) Quaternion {
        var bb = b;
        var d = a.dot(b);
        if (d < 0) {
            bb = b.neg();
            d = -d;
        }
        if (d > 0.9995) {
            // Nearly parallel: linear interpolation + renormalize.
            return a.add(bb.sub(a).scale(t)).normalize();
        }
        const theta0 = std.math.acos(d);
        const theta = theta0 * t;
        const sin0 = @sin(theta0);
        const s0 = @sin(theta0 - theta) / sin0;
        const s1 = @sin(theta) / sin0;
        return a.scale(s0).add(bb.scale(s1));
    }

    /// Shortest-arc rotation mapping unit vector `from` onto unit vector `to`.
    pub fn rotationBetween(from: Vec3, to: Vec3) Quaternion {
        const f = from.normalize();
        const t = to.normalize();
        const d = std.math.clamp(f.dot(t), -1.0, 1.0);
        if (d > 0.999999) return Quaternion.identity;
        if (d < -0.999999) {
            const axis = @import("math.zig").anyPerpendicular(f);
            return Quaternion.fromAxisAngle(axis, std.math.pi);
        }
        const c = f.cross(t);
        return (Quaternion{ .w = 1.0 + d, .x = c.x, .y = c.y, .z = c.z }).normalize();
    }

    /// Column-major rotation matrix (matches Mat4: m[col*4+row], v' = M*v).
    pub fn toMat4(q: Quaternion) Mat4 {
        const x = q.x;
        const y = q.y;
        const z = q.z;
        const w = q.w;
        var m = Mat4.identity;
        m.m[0] = 1 - 2 * (y * y + z * z);
        m.m[1] = 2 * (x * y + w * z);
        m.m[2] = 2 * (x * z - w * y);
        m.m[4] = 2 * (x * y - w * z);
        m.m[5] = 1 - 2 * (x * x + z * z);
        m.m[6] = 2 * (y * z + w * x);
        m.m[8] = 2 * (x * z + w * y);
        m.m[9] = 2 * (y * z - w * x);
        m.m[10] = 1 - 2 * (x * x + y * y);
        return m;
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/quaternion.zig
git commit -m "feat: add Quaternion slerp, rotationBetween, toMat4"
```

---

## Task 3: Navigation helpers (cycle + target orientation)

**Files:**
- Create: `src/navigation.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Export and write failing tests**

Add to `src/root.zig`: `pub const navigation = @import("navigation.zig");` and `_ = navigation;` inside the test block.

Create `src/navigation.zig` with tests only:
```zig
const std = @import("std");
const Vec3 = @import("math.zig").Vec3;

// Implementation added in the next step.

test "cycle wraps next and prev (incl. len 1)" {
    try std.testing.expectEqual(@as(usize, 1), cycle(0, 4, .next));
    try std.testing.expectEqual(@as(usize, 0), cycle(3, 4, .next));
    try std.testing.expectEqual(@as(usize, 3), cycle(0, 4, .prev));
    try std.testing.expectEqual(@as(usize, 2), cycle(3, 4, .prev));
    try std.testing.expectEqual(@as(usize, 0), cycle(0, 1, .next));
    try std.testing.expectEqual(@as(usize, 0), cycle(0, 1, .prev));
}

test "targetOrientation brings a direction to +Z" {
    const dir = Vec3.init(1, 0, 0);
    const q = targetOrientation(dir);
    try std.testing.expect(q.rotateVec(dir).approxEq(Vec3.init(0, 0, 1), 1e-5));
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `cycle`, `targetOrientation` undefined.

- [ ] **Step 3: Implement**

Insert into `src/navigation.zig` after the imports (before the tests):
```zig
const Quaternion = @import("quaternion.zig").Quaternion;

pub const Direction = enum { prev, next };

/// Next/previous index over `len` items, wrapping. Returns 0 if len == 0.
pub fn cycle(index: usize, len: usize, dir: Direction) usize {
    if (len == 0) return 0;
    return switch (dir) {
        .next => (index + 1) % len,
        .prev => (index + len - 1) % len,
    };
}

/// Orientation that rotates an open point's outward direction to face the
/// camera (+Z). Shortest-arc, so roll is minimized.
pub fn targetOrientation(dir: Vec3) Quaternion {
    return Quaternion.rotationBetween(dir, Vec3.init(0, 0, 1));
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/navigation.zig src/root.zig
git commit -m "feat: add navigation selection cycling and target orientation"
```

---

## Task 4: Open-bond-point marker instances

**Files:**
- Modify: `src/render/scene.zig`

- [ ] **Step 1: Append failing tests**

Append to `src/render/scene.zig`:
```zig
fn scaleX(inst: Instance) f32 {
    return Vec3.init(inst.model[0], inst.model[1], inst.model[2]).length();
}

test "openPointInstances: one marker per open point, selected larger, offset placement" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra); // lone tetra at origin -> 4 open points

    const insts = try openPointInstances(std.testing.allocator, &mol, 0, 1.0);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 4), insts.len);

    // Selected (index 0) is scaled larger than the others.
    for (insts[1..]) |other| {
        try std.testing.expect(scaleX(insts[0]) > scaleX(other));
    }
    // Each marker sits `marker_offset` from its parent (atom 0 at the origin).
    const m0 = Mat4{ .m = insts[1].model };
    const center = m0.mulPoint(Vec3.zero);
    try std.testing.expectApproxEqAbs(marker_offset, center.length(), 1e-4);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `openPointInstances` / `marker_offset` undefined.

- [ ] **Step 3: Implement**

Add this near the top of `src/render/scene.zig` (after the existing imports — `OpenBondPoint` import + the marker constants):
```zig
const OpenBondPoint = @import("../molecule.zig").OpenBondPoint;

pub const marker_offset: f32 = 0.6;
pub const marker_radius: f32 = 0.12;
const selected_scale: f32 = 1.6;
const marker_color = [3]f32{ 0.40, 0.85, 0.90 };
const selected_color = [3]f32{ 0.75, 1.0, 1.0 };
```
And add this function (after `bondInstances`, before the tests):
```zig
/// One marker instance per open bond point. The `selected` index is drawn
/// larger (scaled by `selected_scale * pulse`) and brighter. Markers sit
/// `marker_offset` out from their parent atom along the open direction.
pub fn openPointInstances(allocator: std.mem.Allocator, mol: *const Molecule, selected: usize, pulse: f32) ![]Instance {
    var pts = std.ArrayList(OpenBondPoint).init(allocator);
    defer pts.deinit();
    try mol.openBondPoints(&pts);

    const out = try allocator.alloc(Instance, pts.items.len);
    for (pts.items, 0..) |p, i| {
        const parent = mol.atoms.items[p.parent_atom].position;
        const pos = parent.add(p.direction.scale(marker_offset));
        const is_sel = (i == selected);
        const r = if (is_sel) marker_radius * selected_scale * pulse else marker_radius;
        const color = if (is_sel) selected_color else marker_color;
        const model = Mat4.translation(pos).mul(Mat4.scale(Vec3.init(r, r, r)));
        out[i] = make(model, color);
    }
    return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add src/render/scene.zig
git commit -m "feat: pack open-bond-point markers into instance data"
```

---

## Task 5: Render the markers (GPU)

> GPU task — no unit test; verified in Task 6 once `main` drives it. Build must stay green.

**Files:**
- Modify: `src/render/gpu.zig`

- [ ] **Step 1: Add marker buffer fields**

In `src/render/gpu.zig`, add to the `Gpu` struct fields (next to the bond buffers):
```zig
    marker_ibuf: c.WGPUBuffer = null,
    marker_count: u32 = 0,
```

- [ ] **Step 2: Add the upload function**

After `uploadBonds` in `src/render/gpu.zig`:
```zig
    pub fn uploadMarkers(self: *Gpu, instances: []const lib.scene.Instance) void {
        if (self.marker_ibuf != null) c.wgpuBufferRelease(self.marker_ibuf);
        if (instances.len == 0) {
            self.marker_ibuf = null;
            self.marker_count = 0;
            return;
        }
        self.marker_ibuf = self.createBuffer(std.mem.sliceAsBytes(instances), c.WGPUBufferUsage_Vertex);
        self.marker_count = @intCast(instances.len);
    }
```

- [ ] **Step 3: Draw markers (third draw, sphere mesh)**

In `renderFrame`, after the bond draw block (still inside the `if (self.pipeline != null)` block), add:
```zig
            if (self.sphere_index_count > 0 and self.marker_count > 0) {
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.sphere_vbuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetVertexBuffer(pass, 1, self.marker_ibuf, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderSetIndexBuffer(pass, self.sphere_ibuf, c.WGPUIndexFormat_Uint32, 0, c.WGPU_WHOLE_SIZE);
                c.wgpuRenderPassEncoderDrawIndexed(pass, self.sphere_index_count, self.marker_count, 0, 0, 0);
            }
```

- [ ] **Step 4: Release on deinit**

In `Gpu.deinit`, add (with the other buffer releases, before the sphere buffers):
```zig
        if (self.marker_ibuf != null) c.wgpuBufferRelease(self.marker_ibuf);
```

- [ ] **Step 5: Build to verify it compiles**

Run: `~/.local/bin/zig build`
Expected: builds with no errors (markers aren't drawn yet — `marker_count` is 0 until `main` uploads them in Task 6).

- [ ] **Step 6: Commit**
```bash
git add src/render/gpu.zig
git commit -m "feat: marker instance buffer and draw in the renderer"
```

---

## Task 6: Sandbox loop — selection, slerp rotation, markers (app)

> GPU/app task — verified by `zig build run` and looking.

**Files:**
- Modify: `src/main.zig`

- [ ] **Step 1: Replace `main.zig` with the sandbox**

Replace the entire contents of `src/main.zig` with:
```zig
const std = @import("std");
const win = @import("platform/window.zig");
const Gpu = @import("render/gpu.zig").Gpu;
const lib = @import("biome_molecular_lib");
const Mat4 = lib.mat4.Mat4;
const Vec3 = lib.math.Vec3;
const Quaternion = lib.quaternion.Quaternion;
const Molecule = lib.molecule.Molecule;
const OpenBondPoint = lib.molecule.OpenBondPoint;
const nav = lib.navigation;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const slerp_ms: f32 = 300.0; // rotation animation duration
const pulse_omega: f32 = 4.0; // selected-marker pulse speed (rad/s)

fn smoothstep(t: f32) f32 {
    const c = std.math.clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sandbox starts with a single Tetra at the origin (4 open bond points).
    var mol = Molecule.init(allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    // Snapshot the open points once (static while we only navigate).
    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();
    try mol.openBondPoints(&open);
    const open_count = open.items.len;

    const window = try win.Window.create(1280, 800, "Biome: Molecular");
    defer window.destroy();
    var gpu = try Gpu.init(window);
    defer gpu.deinit();

    var sphere = try lib.mesh.icosphere(allocator, 2);
    defer sphere.deinit(allocator);
    gpu.uploadSphere(sphere.vertices, sphere.indices);

    var cyl = try lib.mesh.cylinder(allocator, 16);
    defer cyl.deinit(allocator);
    gpu.uploadCylinder(cyl.vertices, cyl.indices);

    const atoms = try lib.scene.atomInstances(allocator, &mol);
    defer allocator.free(atoms);
    gpu.uploadAtoms(atoms);

    const bonds = try lib.scene.bondInstances(allocator, &mol);
    defer allocator.free(bonds);
    gpu.uploadBonds(bonds);

    // Fixed camera framing the molecule + its markers.
    const bounds = lib.camera.boundingSphere(&mol);
    const center = bounds.center;
    const radius = bounds.radius + lib.scene.marker_offset + lib.scene.marker_radius;
    const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(radius));
    const view = Mat4.lookAt(eye, center, Vec3.init(0, 1, 0));

    // Selection + orientation animation state.
    var selected: usize = 0;
    var q = if (open_count > 0) nav.targetOrientation(open.items[0].direction) else Quaternion.identity;
    var q_start = q;
    var q_target = q;
    var anim_start = std.time.milliTimestamp();
    var animating = false;

    var prev_left = false;
    var prev_right = false;
    const epoch = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();
        if (window.keyPressed(win.KEY_ESCAPE)) break;
        const cmd_held = window.keyPressed(win.KEY_LEFT_SUPER) or window.keyPressed(win.KEY_RIGHT_SUPER);
        if (cmd_held and window.keyPressed(win.KEY_W)) break;

        // Left/Right cycle the selection (rising edge); re-target the rotation.
        const left = window.keyPressed(win.KEY_LEFT);
        const right = window.keyPressed(win.KEY_RIGHT);
        var changed = false;
        if (open_count > 0 and left and !prev_left) {
            selected = nav.cycle(selected, open_count, .prev);
            changed = true;
        }
        if (open_count > 0 and right and !prev_right) {
            selected = nav.cycle(selected, open_count, .next);
            changed = true;
        }
        prev_left = left;
        prev_right = right;
        if (changed) {
            q_start = q;
            q_target = nav.targetOrientation(open.items[selected].direction);
            anim_start = std.time.milliTimestamp();
            animating = true;
        }

        // Pause when hidden (avoids Metal drawable exhaustion).
        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        // Advance the slerp.
        if (animating) {
            const t = @as(f32, @floatFromInt(std.time.milliTimestamp() - anim_start)) / slerp_ms;
            if (t >= 1.0) {
                q = q_target;
                animating = false;
            } else {
                q = q_start.slerp(q_target, smoothstep(t));
            }
        }

        // Repack markers each frame so the selected one pulses.
        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - epoch)) / 1000.0;
        const pulse = 1.0 + 0.15 * @sin(elapsed_s * pulse_omega);
        const markers = try lib.scene.openPointInstances(allocator, &mol, selected, pulse);
        defer allocator.free(markers);
        gpu.uploadMarkers(markers);

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(view);
        const model_pre = Mat4.translation(center).mul(q.toMat4()).mul(Mat4.translation(center.neg()));

        gpu.setUniforms(view_proj.m, model_pre.m, light_dir, .{ eye.x, eye.y, eye.z });
        gpu.renderFrame();
    }
}
```

- [ ] **Step 2: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: a single Tetra (orange sphere) at center with **four cyan marker spheres** around it, **one larger and brighter (the selected point) gently pulsing**. Pressing **Right/Left** moves the highlight to the next/previous marker and the whole molecule **smoothly rotates (~300 ms)** so the selected marker swings to the front (facing you). Re-pressing mid-rotation retargets smoothly. Escape/Cmd-W quit. Survives tab-away.

If selecting a point rotates it to the **back** instead of the front: in `src/navigation.zig` change `targetOrientation` to map to `Vec3.init(0, 0, -1)` instead of `+Z`, rebuild, and re-verify (the sign note from the spec).

- [ ] **Step 3: Commit**
```bash
git add src/main.zig
git commit -m "feat: sandbox bond-point navigation with slerp rotation and markers"
```

---

## Task 7: Update the README controls

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the overview and controls**

In `README.md`, replace the example-browser description and controls with the sandbox:
- Overview: the renderer now opens the **sandbox** — a single Tetra with navigable open bond points (the example browser was a renderer stepping-stone and has been retired; example builders remain for tests).
- Controls table:

| Input | Action |
|-------|--------|
| **Left / Right arrows** | Select the previous / next open bond point; the molecule rotates to face it |
| **Escape** / **Cmd-W** / close | Quit |

Remove the "Example molecules" cycling description (or note the builders are test fixtures). Keep prerequisites/build/run sections.

- [ ] **Step 2: Verify build + tests still green**

Run: `~/.local/bin/zig build test`
Expected: PASS (all prior tests + the new quaternion/navigation/scene tests).

- [ ] **Step 3: Commit**
```bash
git add README.md
git commit -m "docs: update controls for sandbox bond-point navigation"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Sandbox single-Tetra start, open points shown → Task 6 ✓
- Ordered Left/Right cycling → Task 3 (`cycle`), wired in Task 6 ✓
- Quaternion slerp rotation bringing selected dir to camera, shortest-path, ~300 ms ease → Tasks 1–2 (`slerp`, `rotationBetween`, `toMat4`), Task 3 (`targetOrientation`), Task 6 (animation + re-target) ✓
- Open-point markers, selected larger/brighter/pulsing → Task 4 (instances), Task 5 (draw), Task 6 (pulse) ✓
- Retire turntable/example browser → Task 6 rewrite ✓
- Camera fixed, molecule rotates → Task 6 (`model_pre` from `q`) ✓
- Re-target on input (not queue) → Task 6 ✓
- TDD math vs manual rendering → Tasks 1–4 TDD, 5–6 manual ✓

**Deferred per spec (no tasks, intentional):** placement/radial menu, spatial traversal, additive glow halos, auto-zoom, input queuing, example browser as a feature.

**Placeholder scan:** none — marker constants, durations, pulse formula, and the sign-flip fallback are all concrete.

**Type consistency:** `Quaternion` methods (`fromAxisAngle/mul/dot/add/sub/scale/neg/normalize/length/rotateVec/slerp/rotationBetween/toMat4`) are consistent between Tasks 1–2 and their callers (`navigation.targetOrientation`, `main`). `toMat4` returns `Mat4` (column-major) consumed by `main`'s `model_pre`. `openPointInstances(allocator, mol, selected, pulse)` signature matches between Task 4 and Task 6; `lib.scene.marker_offset`/`marker_radius` are `pub` (used by Task 6's camera padding). `nav.cycle`/`nav.Direction` (`.prev`/`.next`) consistent between Task 3 and Task 6. Marker draw reuses `sphere_vbuf`/`sphere_ibuf`/`sphere_index_count` from the existing renderer.

**Known live-verification points (from spec risks):** camera-facing sign (+Z vs −Z, one-line flip in Task 6 Step 2 / `navigation.zig`); slerp shortest-path (covered by the negative-dot test in Task 2 and visually).

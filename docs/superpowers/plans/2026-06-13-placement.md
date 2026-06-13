# Atom Placement (ghost preview) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a place mode to the sandbox: pressing S drops a greyed ghost atom at the selected bond point and the molecule re-folds; Left/Right cycle the ghost's type; F finalizes it (becomes real), A cancels it (removed, molecule relaxes).

**Architecture:** A new `Molecule.removeLastAtom` (the cancel primitive) and a `scene.ghostMarkerInstances` helper are pure and TDD'd. The modal state machine and the animated re-fold live in `main.zig`, reusing the physics engine (`simulate`) and the existing instanced renderer (no new pipeline).

**Tech Stack:** Zig 0.14.0, the existing wgpu-native renderer + physics core.

---

## Reading notes for the implementer

- **Toolchain:** `~/.local/bin/zig` (must report `0.14.0`). Tests: `~/.local/bin/zig build test`. Run: `~/.local/bin/zig build run`.
- **Tasks 1–2 are TDD** (write failing test → run fail → implement → run pass → commit; code is exact). **Task 3 is the app rewrite**, verified by `zig build run` and looking (no unit test). **Task 4 is docs.**
- **Physics reality (intended):** a freshly placed atom has one bond, so its *type* doesn't change the fold — only its size and onward open-point count differ. The molecule re-folds when the ghost is *added* and when it's *removed*, not when the type is cycled.
- **Branch:** all work on a feature branch off `main` (the controller creates it).

## File Structure

| File | Kind | Responsibility |
|------|------|----------------|
| `src/molecule.zig` | TDD | add `removeLastAtom()` — pop the last atom + its bond, update the parent's bond list. |
| `src/render/scene.zig` | TDD | add `ghostMarkerInstances(mol, ghost_id)` + `ghost_color`. |
| `src/platform/window.zig` | manual | add `KEY_A`, `KEY_S`, `KEY_F` constants. |
| `src/main.zig` | manual | mode state machine (navigate/place), ghost lifecycle, animated settle, contextual input. |
| `README.md` | docs | document place-mode controls. |

---

## Task 1: Molecule.removeLastAtom

**Files:**
- Modify: `src/molecule.zig`

- [ ] **Step 1: Append the failing test**

Append to `src/molecule.zig` (the `Vec3`/`std`/`constants` imports it needs already exist at the top of the file from earlier tasks):
```zig
test "removeLastAtom undoes the last addAtom" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    try std.testing.expectEqual(@as(usize, 2), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 1), mol.bonds.items.len);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[a].bonds.len);

    mol.removeLastAtom();

    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.bonds.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items[a].bonds.len);
}

test "removeLastAtom on a lone first atom leaves it empty" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);
    mol.removeLastAtom();
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 0), mol.bonds.items.len);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — no `removeLastAtom`.

- [ ] **Step 3: Implement**

Add this method inside the `Molecule` struct in `src/molecule.zig` (e.g. after `addAtom`, before the closing `};`):
```zig
    /// Remove the most recently added atom and its bond(s). Intended for undoing
    /// the last `addAtom` (e.g. a placement ghost): that atom's bonds are the
    /// trailing entries of `bonds`, so they pop cleanly without invalidating
    /// other bond ids. Asserts there is at least one atom.
    pub fn removeLastAtom(self: *Molecule) void {
        std.debug.assert(self.atoms.items.len > 0);
        const last_index = self.atoms.items.len - 1;
        const last = self.atoms.items[last_index];

        // Detach each of this atom's bonds from the neighbor's bond list.
        for (last.bonds.slice()) |bond_id| {
            const neighbor = self.bonds.items[bond_id].other(last.id);
            const nb = &self.atoms.items[neighbor].bonds;
            var i: usize = 0;
            while (i < nb.len) : (i += 1) {
                if (nb.get(i) == bond_id) {
                    _ = nb.swapRemove(i);
                    break;
                }
            }
        }

        // Pop this atom's bonds (the trailing entries) and the atom itself.
        var remaining = last.bonds.len;
        while (remaining > 0) : (remaining -= 1) _ = self.bonds.pop();
        _ = self.atoms.pop();
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/zig build test`
Expected: PASS.

If `swapRemove` is not a method on `std.BoundedArray` in your Zig 0.14, replace the inner removal with an in-place shift:
```zig
                if (nb.get(i) == bond_id) {
                    var j = i;
                    while (j + 1 < nb.len) : (j += 1) nb.set(j, nb.get(j + 1));
                    nb.len -= 1;
                    break;
                }
```
and re-run. (Likewise, if `self.bonds.pop()`/`self.atoms.pop()` return an optional in your version, discard with `_ = ... .?;` only if non-empty — but here they are guaranteed non-empty.)

- [ ] **Step 5: Commit**
```bash
git add src/molecule.zig
git commit -m "feat: add Molecule.removeLastAtom (undo last placement)"
```

---

## Task 2: Ghost marker instances

**Files:**
- Modify: `src/render/scene.zig`

- [ ] **Step 1: Append the failing test**

Append to `src/render/scene.zig`:
```zig
test "ghostMarkerInstances: one grey marker per the ghost atom's open points" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const g = try mol.addAtom(a, Vec3.init(0, 0, 1), .tetra); // ghost tetra: 1 bond -> 3 open points

    const insts = try ghostMarkerInstances(std.testing.allocator, &mol, g);
    defer std.testing.allocator.free(insts);
    try std.testing.expectEqual(@as(usize, 3), insts.len);
    for (insts) |inst| {
        try std.testing.expectEqual(ghost_color[0], inst.color[0]);
        try std.testing.expectEqual(ghost_color[1], inst.color[1]);
        try std.testing.expectEqual(ghost_color[2], inst.color[2]);
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/zig build test`
Expected: FAIL — `ghostMarkerInstances` / `ghost_color` undefined.

- [ ] **Step 3: Implement**

Add the constant near the other marker constants at the top of `src/render/scene.zig`:
```zig
pub const ghost_color = [3]f32{ 0.45, 0.45, 0.50 };
```
And add this function after `openPointInstances` (before the tests):
```zig
/// Dim-grey marker instances for the open bond points belonging to `ghost_id`
/// only (the placement preview's onward branch points). Uniform size/color.
pub fn ghostMarkerInstances(allocator: std.mem.Allocator, mol: *const Molecule, ghost_id: usize) ![]Instance {
    var pts = std.ArrayList(OpenBondPoint).init(allocator);
    defer pts.deinit();
    try mol.openBondPoints(&pts);

    var count: usize = 0;
    for (pts.items) |p| {
        if (p.parent_atom == ghost_id) count += 1;
    }
    const out = try allocator.alloc(Instance, count);
    var i: usize = 0;
    for (pts.items) |p| {
        if (p.parent_atom != ghost_id) continue;
        const parent = mol.atoms.items[p.parent_atom].position;
        const pos = parent.add(p.direction.scale(marker_offset));
        const model = Mat4.translation(pos).mul(Mat4.scale(Vec3.init(marker_radius, marker_radius, marker_radius)));
        out[i] = make(model, ghost_color);
        i += 1;
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
git commit -m "feat: add grey ghost-atom marker instances"
```

---

## Task 3: Place mode — ghost lifecycle and modal input (app)

> App task — verified by `zig build run` and looking.

**Files:**
- Modify: `src/platform/window.zig`, `src/main.zig`

- [ ] **Step 1: Add key constants**

In `src/platform/window.zig`, add after the existing `KEY_*` constants:
```zig
pub const KEY_A = c.GLFW_KEY_A;
pub const KEY_S = c.GLFW_KEY_S;
pub const KEY_F = c.GLFW_KEY_F;
```

- [ ] **Step 2: Replace `src/main.zig` with the place-mode sandbox**

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
const AtomType = lib.atom.AtomType;
const nav = lib.navigation;

const light_dir = [3]f32{ -0.6, 0.7, 0.5 };
const slerp_ms: f32 = 300.0;
const pulse_omega: f32 = 4.0;
const atom_types = [_]AtomType{ .mono, .linear, .trigonal, .tetra };
const default_type_index: usize = 3; // Tetra

const Mode = enum { navigate, place };

fn smoothstep(t: f32) f32 {
    const c = std.math.clamp(t, 0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mol = Molecule.init(allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();
    try mol.openBondPoints(&open);

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

    var mode: Mode = .navigate;
    var selected: usize = 0;
    var ghost_id: ?usize = null;
    var ghost_type_index: usize = default_type_index;
    var settling = false;

    var q = if (open.items.len > 0) nav.targetOrientation(open.items[0].direction) else Quaternion.identity;
    var q_start = q;
    var q_target = q;
    var anim_start = std.time.milliTimestamp();
    var animating = false;

    var prev_left = false;
    var prev_right = false;
    var prev_s = false;
    var prev_a = false;
    var prev_f = false;

    const epoch = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        window.pollEvents();
        if (window.keyPressed(win.KEY_ESCAPE)) break;
        const cmd_held = window.keyPressed(win.KEY_LEFT_SUPER) or window.keyPressed(win.KEY_RIGHT_SUPER);
        if (cmd_held and window.keyPressed(win.KEY_W)) break;

        const left = window.keyPressed(win.KEY_LEFT);
        const right = window.keyPressed(win.KEY_RIGHT);
        const s_key = window.keyPressed(win.KEY_S);
        const a_key = window.keyPressed(win.KEY_A);
        const f_key = window.keyPressed(win.KEY_F);
        const left_edge = left and !prev_left;
        const right_edge = right and !prev_right;
        const s_edge = s_key and !prev_s;
        const a_edge = a_key and !prev_a;
        const f_edge = f_key and !prev_f;

        switch (mode) {
            .navigate => {
                if (open.items.len > 0 and left_edge) {
                    selected = nav.cycle(selected, open.items.len, .prev);
                    q_start = q;
                    q_target = nav.targetOrientation(open.items[selected].direction);
                    anim_start = std.time.milliTimestamp();
                    animating = true;
                }
                if (open.items.len > 0 and right_edge) {
                    selected = nav.cycle(selected, open.items.len, .next);
                    q_start = q;
                    q_target = nav.targetOrientation(open.items[selected].direction);
                    anim_start = std.time.milliTimestamp();
                    animating = true;
                }
                if (open.items.len > 0 and s_edge) {
                    const p = open.items[selected];
                    ghost_type_index = default_type_index;
                    ghost_id = try mol.addAtom(p.parent_atom, p.direction, atom_types[ghost_type_index]);
                    mode = .place;
                    settling = true;
                }
            },
            .place => {
                if (left_edge) {
                    ghost_type_index = nav.cycle(ghost_type_index, atom_types.len, .prev);
                    mol.atoms.items[ghost_id.?].atom_type = atom_types[ghost_type_index];
                }
                if (right_edge) {
                    ghost_type_index = nav.cycle(ghost_type_index, atom_types.len, .next);
                    mol.atoms.items[ghost_id.?].atom_type = atom_types[ghost_type_index];
                }
                if (a_edge) {
                    mol.removeLastAtom();
                    ghost_id = null;
                    mode = .navigate;
                    settling = true;
                    try mol.openBondPoints(&open);
                    if (selected >= open.items.len) selected = 0;
                }
                if (f_edge) {
                    const gid = ghost_id.?;
                    ghost_id = null;
                    mode = .navigate;
                    try mol.openBondPoints(&open);
                    selected = 0;
                    for (open.items, 0..) |p, i| {
                        if (p.parent_atom == gid) {
                            selected = i;
                            break;
                        }
                    }
                    if (open.items.len > 0) {
                        q_start = q;
                        q_target = nav.targetOrientation(open.items[selected].direction);
                        anim_start = std.time.milliTimestamp();
                        animating = true;
                    }
                }
            },
        }
        prev_left = left;
        prev_right = right;
        prev_s = s_key;
        prev_a = a_key;
        prev_f = f_key;

        const size = window.framebufferSize();
        if (!window.visibleOnScreen() or size[0] == 0 or size[1] == 0) {
            std.time.sleep(16 * std.time.ns_per_ms);
            continue;
        }
        if (size[0] != gpu.width or size[1] != gpu.height) gpu.resize(size[0], size[1]);

        // Animated re-fold (after add/cancel).
        if (settling) {
            const done = try lib.physics.simulate(&mol, lib.constants.default, allocator);
            if (done) settling = false;
        }

        // Rotation slerp.
        if (animating) {
            const t = @as(f32, @floatFromInt(std.time.milliTimestamp() - anim_start)) / slerp_ms;
            if (t >= 1.0) {
                q = q_target;
                animating = false;
            } else {
                q = q_start.slerp(q_target, smoothstep(t));
            }
        }

        // Camera: keep the center of mass framed (recomputed as the molecule grows/folds).
        const bounds = lib.camera.boundingSphere(&mol);
        const center = bounds.center;
        const radius = bounds.radius + lib.scene.marker_offset + lib.scene.marker_radius;
        const eye = Vec3.init(center.x, center.y, center.z + lib.camera.cameraDistance(radius));
        const view = Mat4.lookAt(eye, center, Vec3.init(0, 1, 0));

        // Atoms (grey out the ghost in place mode).
        const atoms = try lib.scene.atomInstances(allocator, &mol);
        defer allocator.free(atoms);
        if (mode == .place) {
            if (ghost_id) |gid| {
                atoms[gid].color = .{ lib.scene.ghost_color[0], lib.scene.ghost_color[1], lib.scene.ghost_color[2], 1.0 };
            }
        }
        gpu.uploadAtoms(atoms);

        const bonds = try lib.scene.bondInstances(allocator, &mol);
        defer allocator.free(bonds);
        gpu.uploadBonds(bonds);

        const elapsed_s = @as(f32, @floatFromInt(std.time.milliTimestamp() - epoch)) / 1000.0;
        const pulse = 1.0 + 0.15 * @sin(elapsed_s * pulse_omega);
        if (mode == .navigate) {
            const markers = try lib.scene.openPointInstances(allocator, &mol, selected, pulse);
            defer allocator.free(markers);
            gpu.uploadMarkers(markers);
        } else {
            const markers = try lib.scene.ghostMarkerInstances(allocator, &mol, ghost_id.?);
            defer allocator.free(markers);
            gpu.uploadMarkers(markers);
        }

        const aspect = @as(f32, @floatFromInt(gpu.width)) / @as(f32, @floatFromInt(gpu.height));
        const view_proj = lib.camera.projectionMatrix(aspect).mul(view);
        const model_pre = Mat4.translation(center).mul(q.toMat4()).mul(Mat4.translation(center.neg()));

        gpu.setUniforms(view_proj.m, model_pre.m, light_dir, .{ eye.x, eye.y, eye.z });
        gpu.renderFrame();
    }
}
```

- [ ] **Step 3: Build, run, visually verify**

Run: `~/.local/bin/zig build run`
Expected: from the Tetra sandbox (navigate with Left/Right as before), press **S** → a **dim-grey ghost atom** appears at the selected point with grey onward markers, and the molecule **animates a small re-fold** to accommodate it. **Left/Right** change the ghost's size and the number of grey onward markers (Mono none … Tetra three). **A** removes the ghost and the molecule **relaxes back**. **F** commits it (now in its type color) and the selection jumps to an open point on the new atom (rotating to face it), so you can immediately **S** again to keep building. Build several atoms in a row — it folds sensibly and stays framed. Escape/Cmd-W quit; survives tab-away.

If anything is off (ghost not grey, wrong marker count, molecule jumps, can't keep building), describe it.

- [ ] **Step 4: Commit**
```bash
git add src/platform/window.zig src/main.zig
git commit -m "feat: ghost-preview atom placement (place mode, finalize/cancel)"
```

---

## Task 4: Update README controls

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add place-mode controls**

In `README.md`, update the controls table and overview to include placement. Replace the controls table with:
```markdown
| Input | Action |
|-------|--------|
| **Left / Right arrows** | Navigate: select prev/next open bond point (molecule rotates to face it). Place: cycle the ghost atom type |
| **S** | Enter place mode (a grey ghost atom previews placement at the selected point) |
| **F** | Finalize placement (the ghost becomes a real atom) |
| **A** | Cancel placement (remove the ghost, return to navigate) |
| **Escape** / **Cmd-W** / close | Quit |
```
And update the overview bullet to mention you can now build molecules: enter place mode with S, choose a type with the arrows, and finalize with F — the molecule folds via the physics engine as atoms are added.

- [ ] **Step 2: Verify build + tests**

Run: `~/.local/bin/zig build test`
Expected: PASS (all prior tests + `removeLastAtom` and `ghostMarkerInstances`).

- [ ] **Step 3: Commit**
```bash
git add README.md
git commit -m "docs: document place-mode controls"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Two modes + key map (Left/Right contextual, S enter, F finalize, A cancel, Esc/Cmd-W quit) → Task 3 ✓
- Enter place adds ghost (default Tetra) + animated re-fold → Task 3 (`settling` + `simulate`) ✓
- Cycle type = instant size/color/onward-marker swap, no re-fold → Task 3 (type mutate, no `settling`) ✓
- Cancel removes ghost + animated relax → Task 1 (`removeLastAtom`) + Task 3 ✓
- Finalize commits + selection to new atom's first open point (rotates to it) → Task 3 ✓
- Ghost greyed via dim color (no blend) → Task 2 (`ghost_color`) + Task 3 (atom recolor) ✓
- Ghost onward grey markers → Task 2 (`ghostMarkerInstances`) + Task 3 ✓
- Reuse marker buffer / re-upload instances → Task 3 (per-frame uploads) ✓
- TDD core/scene, manual app → Tasks 1–2 TDD, Task 3 manual ✓

**Deferred per spec (no tasks, intentional):** radial menu/text, alpha transparency, animated auto-zoom (a per-frame snap-refit keeps it framed; the *animated* zoom is later), multi-step undo, puzzle mode.

**Placeholder scan:** none — all constants (`ghost_color`, default type index, durations), the `swapRemove` fallback, and the full `main.zig` are concrete.

**Type consistency:** `removeLastAtom()` (Task 1) called in Task 3. `ghostMarkerInstances(allocator, mol, ghost_id)` and `ghost_color` (Task 2) used in Task 3 with matching signature; `ghost_color` is `pub`. `atom_types`/`default_type_index` and `nav.cycle`/`nav.targetOrientation` consistent. `Instance.color` is `[4]f32` (set with `.{r,g,b,1.0}`). `KEY_A/KEY_S/KEY_F` added in Task 3 Step 1 before use in Step 2. Marker upload reuses `gpu.uploadMarkers` (existing). `lib.scene.marker_offset`/`marker_radius` are `pub` (used for camera padding + ghost markers).

**Known live-verification points:** settle/re-fold pacing and the per-frame camera re-fit (both tunable by eye); that `removeLastAtom`'s trailing-bond assumption holds for the ghost (it always does, since the ghost is the last `addAtom`).

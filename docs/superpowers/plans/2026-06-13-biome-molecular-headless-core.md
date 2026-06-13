# Biome: Molecular — Headless Core (Model + Physics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-logic core of Biome: Molecular — the molecule data model, open-bond-point geometry, and the folding physics engine — as a headless, fully unit-tested Zig library with no rendering.

**Architecture:** Plain-data structs (`Atom`, `Bond`, `Molecule`) plus stateless modules for geometry (computing where new atoms attach) and physics (springs, angle preferences, repulsion, damped integration). Everything is deterministic and testable from `zig build test`. Rendering, navigation, and the radial menu are intentionally out of scope and handled by later plans; this plan produces a working simulation you can drive from `main.zig` and dump to text.

**Tech Stack:** Zig 0.14.0, `std` only (no third-party dependencies). Tests are co-located `test { ... }` blocks aggregated through `src/root.zig` and run with `zig build test`.

---

## Scope

**In scope:** `Vec3` math + rotation helpers, atom/bond types, open-bond-point direction computation (0/1/2+ existing bonds with the +Y disambiguation heuristic), the `Molecule` container (`addFirstAtom`, `addAtom`, `centerOfMass`, `openBondPoints`), and physics (spring force, harmonic angle force, steric repulsion, semi-implicit damped Verlet integration, kinetic-energy convergence).

**Out of scope (later plans):** WebGPU renderer, window/input, quaternion navigation & slerp, radial menu, auto-zoom camera, puzzle mode. `Molecule` deliberately does **not** carry `rotation`/`target_rotation` fields yet (those belong to the navigation plan) — YAGNI.

## File Structure

| File | Responsibility |
|------|----------------|
| `build.zig`, `build.zig.zon` | Build + `test` step (from `zig init`, minimally edited). |
| `src/root.zig` | Library root: re-exports public API and aggregates every module's tests. |
| `src/math.zig` | `Vec3` and rotation helpers (`rodrigues`, `angleBetween`, `anyPerpendicular`, `rotationAxisAngle`). |
| `src/atom.zig` | `AtomType`, `Atom`, `AtomId`, `preferredAngle`, `maxBonds`. |
| `src/bond.zig` | `Bond`, `BondId`, `other()`. |
| `src/constants.zig` | `Constants` tuning struct + `default`. |
| `src/geometry.zig` | `canonical()` directions and `openDirections()` for 0/1/2+ existing bonds. |
| `src/molecule.zig` | `Molecule`, `OpenBondPoint`, `addFirstAtom`, `addAtom`, `centerOfMass`, `openBondPoints`. |
| `src/physics.zig` | `computeForces`, `step`, `kineticEnergy`, `simulate`. |
| `src/main.zig` | Headless demo: build a small molecule, settle it, print atom positions. |

---

## Task 1: Project scaffold & test harness

**Files:**
- Create: `build.zig`, `build.zig.zon`, `src/root.zig`, `src/main.zig` (via `zig init`, then edited)

- [ ] **Step 1: Install Zig 0.14.0 and verify**

Run:
```bash
# macOS (Homebrew). If a different 0.14.x is installed that is fine.
brew install zig || true
zig version
```
Expected: prints `0.14.0` (or another `0.14.x`). If `zig` is missing, install from https://ziglang.org/download/ and ensure it is on `PATH`. Do not proceed until `zig version` works.

- [ ] **Step 2: Scaffold the project with `zig init`**

Run:
```bash
cd /Users/jonathandavenport/projects/biome-molecular
zig init
```
Expected: creates `build.zig`, `build.zig.zon`, `src/main.zig`, `src/root.zig`. This sidesteps hand-writing `build.zig.zon` (which requires a `.fingerprint` field in 0.14).

- [ ] **Step 3: Verify the scaffold's test step works (proof the toolchain + build are good)**

Run:
```bash
zig build test
```
Expected: PASS with no output (the scaffold ships trivial passing tests). If this fails, the toolchain/build is broken — fix before writing any feature code.

- [ ] **Step 4: Replace `src/root.zig` with our library root + test aggregator**

Replace the entire contents of `src/root.zig` with:
```zig
//! Biome: Molecular — headless core library root.
//! Re-exports the public API and aggregates every module's tests.

pub const math = @import("math.zig");
pub const atom = @import("atom.zig");
pub const bond = @import("bond.zig");
pub const constants = @import("constants.zig");
pub const geometry = @import("geometry.zig");
pub const molecule = @import("molecule.zig");
pub const physics = @import("physics.zig");

test {
    // Pull every module's tests into the `zig build test` run.
    _ = math;
    _ = atom;
    _ = bond;
    _ = constants;
    _ = geometry;
    _ = molecule;
    _ = physics;
}
```

- [ ] **Step 5: Create placeholder module files so `root.zig` compiles**

Create each of these files with a single line so imports resolve (they get real content in later tasks):

`src/math.zig`:
```zig
const std = @import("std");
```
`src/atom.zig`:
```zig
const std = @import("std");
```
`src/bond.zig`:
```zig
const std = @import("std");
```
`src/constants.zig`:
```zig
const std = @import("std");
```
`src/geometry.zig`:
```zig
const std = @import("std");
```
`src/molecule.zig`:
```zig
const std = @import("std");
```
`src/physics.zig`:
```zig
const std = @import("std");
```

- [ ] **Step 6: Replace `src/main.zig` with a stub headless entry point**

Replace the entire contents of `src/main.zig` with:
```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("biome-molecular headless core\n", .{});
}
```

- [ ] **Step 7: Verify the project still builds and tests pass**

Run:
```bash
zig build test && zig build run
```
Expected: tests PASS (no output) and `zig build run` prints `biome-molecular headless core`.

- [ ] **Step 8: Commit**

```bash
git add build.zig build.zig.zon src/
git commit -m "chore: scaffold headless core project and test harness"
```

---

## Task 2: Vec3 math type

**Files:**
- Modify: `src/math.zig`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `src/math.zig` with the tests only (implementation comes next):
```zig
const std = @import("std");

// Implementation added in the next step.

test "Vec3 add/sub/scale/neg" {
    const a = Vec3.init(1, 2, 3);
    const b = Vec3.init(4, 5, 6);
    try expectVec(Vec3.init(5, 7, 9), a.add(b));
    try expectVec(Vec3.init(-3, -3, -3), a.sub(b));
    try expectVec(Vec3.init(2, 4, 6), a.scale(2));
    try expectVec(Vec3.init(-1, -2, -3), a.neg());
}

test "Vec3 dot/cross" {
    const a = Vec3.init(1, 0, 0);
    const b = Vec3.init(0, 1, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.dot(b), 1e-6);
    try expectVec(Vec3.init(0, 0, 1), a.cross(b));
    try std.testing.expectApproxEqAbs(@as(f32, 32), Vec3.init(1, 2, 3).dot(Vec3.init(4, 5, 6)), 1e-5);
}

test "Vec3 length/normalize/distance" {
    const v = Vec3.init(3, 4, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 25), v.lengthSq(), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), v.length(), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v.normalize().length(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 5), Vec3.init(0, 0, 0).distance(Vec3.init(0, 3, 4)), 1e-5);
}

test "Vec3 normalize of zero is zero" {
    try expectVec(Vec3.zero, Vec3.zero.normalize());
}

fn expectVec(expected: Vec3, actual: Vec3) !void {
    try std.testing.expect(expected.approxEq(actual, 1e-5));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `Vec3` is undefined.

- [ ] **Step 3: Write the implementation**

Insert this `Vec3` definition into `src/math.zig` immediately after the `const std` line (before the tests):
```zig
pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn lengthSq(a: Vec3) f32 {
        return a.dot(a);
    }

    pub fn length(a: Vec3) f32 {
        return @sqrt(a.lengthSq());
    }

    pub fn normalize(a: Vec3) Vec3 {
        const len = a.length();
        if (len < 1e-8) return Vec3.zero;
        return a.scale(1.0 / len);
    }

    pub fn distance(a: Vec3, b: Vec3) f32 {
        return a.sub(b).length();
    }

    pub fn approxEq(a: Vec3, b: Vec3, tol: f32) bool {
        return @abs(a.x - b.x) <= tol and @abs(a.y - b.y) <= tol and @abs(a.z - b.z) <= tol;
    }
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/math.zig
git commit -m "feat: add Vec3 math type"
```

---

## Task 3: Rotation helpers

**Files:**
- Modify: `src/math.zig`

- [ ] **Step 1: Write the failing tests**

Append these tests to the end of `src/math.zig`:
```zig
test "angleBetween orthogonal and parallel" {
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), angleBetween(Vec3.init(1, 0, 0), Vec3.init(0, 1, 0)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), angleBetween(Vec3.init(0, 0, 2), Vec3.init(0, 0, 5)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), angleBetween(Vec3.init(1, 0, 0), Vec3.init(-1, 0, 0)), 1e-5);
}

test "rodrigues rotates 90 degrees about Z" {
    const out = rodrigues(Vec3.init(1, 0, 0), Vec3.init(0, 0, 1), std.math.pi / 2.0);
    try std.testing.expect(out.approxEq(Vec3.init(0, 1, 0), 1e-5));
}

test "anyPerpendicular is unit and orthogonal" {
    const inputs = [_]Vec3{ Vec3.init(0, 0, 1), Vec3.init(1, 0, 0), Vec3.init(1, 1, 1).normalize() };
    for (inputs) |v| {
        const p = anyPerpendicular(v);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.length(), 1e-5);
        try std.testing.expectApproxEqAbs(@as(f32, 0), p.dot(v), 1e-5);
    }
}

test "rotationAxisAngle maps from onto to" {
    const from = Vec3.init(1, 0, 0);
    const to = Vec3.init(0, 0, 1);
    const r = rotationAxisAngle(from, to);
    const moved = rodrigues(from, r.axis, r.angle);
    try std.testing.expect(moved.approxEq(to, 1e-5));
}

test "rotationAxisAngle handles antiparallel" {
    const from = Vec3.init(0, 0, 1);
    const to = Vec3.init(0, 0, -1);
    const r = rotationAxisAngle(from, to);
    const moved = rodrigues(from, r.axis, r.angle);
    try std.testing.expect(moved.approxEq(to, 1e-5));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `angleBetween`, `rodrigues`, `anyPerpendicular`, `rotationAxisAngle` undefined.

- [ ] **Step 3: Write the implementation**

Insert these declarations into `src/math.zig` after the `Vec3` struct (before the tests):
```zig
/// Angle in radians between two vectors. Clamps to avoid NaN from rounding.
pub fn angleBetween(a: Vec3, b: Vec3) f32 {
    const denom = a.length() * b.length();
    if (denom < 1e-8) return 0;
    const c = std.math.clamp(a.dot(b) / denom, -1.0, 1.0);
    return std.math.acos(c);
}

/// Rotate `v` around unit `axis` by `angle` radians (Rodrigues' formula).
pub fn rodrigues(v: Vec3, axis: Vec3, angle: f32) Vec3 {
    const c = @cos(angle);
    const s = @sin(angle);
    const term1 = v.scale(c);
    const term2 = axis.cross(v).scale(s);
    const term3 = axis.scale(axis.dot(v) * (1.0 - c));
    return term1.add(term2).add(term3);
}

/// Return an arbitrary unit vector perpendicular to `v` (assumes |v| ~ 1).
pub fn anyPerpendicular(v: Vec3) Vec3 {
    // Cross with whichever basis axis is least aligned with v.
    const ref = if (@abs(v.x) < 0.9) Vec3.init(1, 0, 0) else Vec3.init(0, 1, 0);
    return v.cross(ref).normalize();
}

pub const AxisAngle = struct { axis: Vec3, angle: f32 };

/// Shortest-arc rotation taking unit vector `from` onto unit vector `to`.
pub fn rotationAxisAngle(from: Vec3, to: Vec3) AxisAngle {
    const d = std.math.clamp(from.dot(to), -1.0, 1.0);
    const axis = from.cross(to);
    if (axis.length() < 1e-6) {
        // Parallel (d ~ 1) -> no rotation; antiparallel (d ~ -1) -> 180 deg about any perpendicular.
        if (d > 0) return .{ .axis = Vec3.init(0, 0, 1), .angle = 0 };
        return .{ .axis = anyPerpendicular(from), .angle = std.math.pi };
    }
    return .{ .axis = axis.normalize(), .angle = std.math.acos(d) };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/math.zig
git commit -m "feat: add rotation helpers (rodrigues, angleBetween, rotationAxisAngle)"
```

---

## Task 4: Constants

**Files:**
- Modify: `src/constants.zig`

- [ ] **Step 1: Write the failing test**

Replace the contents of `src/constants.zig` with:
```zig
const std = @import("std");

// Implementation added in the next step.

test "default constants match the design spec" {
    const c = default;
    try std.testing.expectEqual(@as(f32, 10.0), c.k_spring);
    try std.testing.expectEqual(@as(f32, 1.0), c.rest_length);
    try std.testing.expectEqual(@as(f32, 5.0), c.k_angle);
    try std.testing.expectEqual(@as(f32, 2.0), c.k_repel);
    try std.testing.expectEqual(@as(f32, 0.8), c.repulsion_threshold);
    try std.testing.expectEqual(@as(f32, 0.98), c.damping);
    try std.testing.expectEqual(@as(f32, 0.001), c.convergence_threshold);
    try std.testing.expectEqual(@as(f32, 0.016), c.dt);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: FAIL — `default` undefined.

- [ ] **Step 3: Write the implementation**

Insert after the `const std` line in `src/constants.zig`:
```zig
/// Physics tuning constants. Values are starting points from the design spec
/// and will be adjusted through playtesting.
pub const Constants = struct {
    k_spring: f32 = 10.0,
    rest_length: f32 = 1.0,
    k_angle: f32 = 5.0,
    k_repel: f32 = 2.0,
    repulsion_threshold: f32 = 0.8,
    damping: f32 = 0.98,
    convergence_threshold: f32 = 0.001,
    dt: f32 = 0.016,
};

pub const default = Constants{};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/constants.zig
git commit -m "feat: add physics tuning constants"
```

---

## Task 5: Atom and bond types

**Files:**
- Modify: `src/atom.zig`, `src/bond.zig`

- [ ] **Step 1: Write the failing tests for atom.zig**

Replace the contents of `src/atom.zig` with:
```zig
const std = @import("std");

// Implementation added in the next step.

test "maxBonds per atom type" {
    try std.testing.expectEqual(@as(usize, 1), maxBonds(.mono));
    try std.testing.expectEqual(@as(usize, 2), maxBonds(.linear));
    try std.testing.expectEqual(@as(usize, 3), maxBonds(.trigonal));
    try std.testing.expectEqual(@as(usize, 4), maxBonds(.tetra));
}

test "preferredAngle per atom type (radians)" {
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), preferredAngle(.linear), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0 * std.math.pi / 3.0), preferredAngle(.trigonal), 1e-5);
    // 109.47 degrees = acos(-1/3).
    try std.testing.expectApproxEqAbs(@as(f32, 1.9106332), preferredAngle(.tetra), 1e-4);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `maxBonds`, `preferredAngle`, `AtomType` undefined.

- [ ] **Step 3: Write the implementation for atom.zig**

Insert after the `const std` line in `src/atom.zig`:
```zig
const Vec3 = @import("math.zig").Vec3;
const BondId = @import("bond.zig").BondId;

pub const AtomId = usize;

pub const AtomType = enum {
    mono, // 1 bond, no angle preference
    linear, // 2 bonds, 180 degrees
    trigonal, // 3 bonds, 120 degrees
    tetra, // 4 bonds, 109.5 degrees
};

pub const Atom = struct {
    position: Vec3,
    velocity: Vec3 = Vec3.zero,
    atom_type: AtomType,
    bonds: std.BoundedArray(BondId, 4) = .{},
    id: AtomId,
};

pub fn maxBonds(t: AtomType) usize {
    return switch (t) {
        .mono => 1,
        .linear => 2,
        .trigonal => 3,
        .tetra => 4,
    };
}

/// Preferred angle between any two bonds at this atom, in radians.
pub fn preferredAngle(t: AtomType) f32 {
    return switch (t) {
        .mono => 0, // single bond: no angle constraint
        .linear => std.math.pi,
        .trigonal => 2.0 * std.math.pi / 3.0,
        .tetra => @floatCast(std.math.acos(@as(f64, -1.0) / 3.0)),
    };
}
```

- [ ] **Step 4: Write the failing test for bond.zig**

Replace the contents of `src/bond.zig` with:
```zig
const std = @import("std");

// Implementation added in the next step.

test "Bond.other returns the opposite endpoint" {
    const b = Bond{ .atom_a = 3, .atom_b = 7, .id = 0 };
    try std.testing.expectEqual(@as(usize, 7), b.other(3));
    try std.testing.expectEqual(@as(usize, 3), b.other(7));
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `Bond` undefined.

- [ ] **Step 6: Write the implementation for bond.zig**

Insert after the `const std` line in `src/bond.zig`:
```zig
const AtomId = @import("atom.zig").AtomId;

pub const BondId = usize;

pub const Bond = struct {
    atom_a: AtomId,
    atom_b: AtomId,
    id: BondId,

    /// Given one endpoint, return the other.
    pub fn other(self: Bond, id: AtomId) AtomId {
        return if (self.atom_a == id) self.atom_b else self.atom_a;
    }
};
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/atom.zig src/bond.zig
git commit -m "feat: add Atom, AtomType, Bond types with angle/bond metadata"
```

---

## Task 6: Canonical bond-point directions

**Files:**
- Modify: `src/geometry.zig`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `src/geometry.zig` with:
```zig
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom = @import("atom.zig");
const AtomType = atom.AtomType;

// Implementation added in later steps.

test "canonical direction counts match bond counts" {
    try std.testing.expectEqual(@as(usize, 1), canonical(.mono).len);
    try std.testing.expectEqual(@as(usize, 2), canonical(.linear).len);
    try std.testing.expectEqual(@as(usize, 3), canonical(.trigonal).len);
    try std.testing.expectEqual(@as(usize, 4), canonical(.tetra).len);
}

test "canonical directions are unit vectors" {
    inline for (.{ .mono, .linear, .trigonal, .tetra }) |t| {
        for (canonical(t)) |d| {
            try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-5);
        }
    }
}

test "canonical pairwise angles equal the preferred angle" {
    inline for (.{ .linear, .trigonal, .tetra }) |t| {
        const dirs = canonical(t);
        const want = atom.preferredAngle(t);
        for (dirs, 0..) |di, i| {
            for (dirs[i + 1 ..]) |dj| {
                try std.testing.expectApproxEqAbs(want, math.angleBetween(di, dj), 1e-3);
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `canonical` undefined.

- [ ] **Step 3: Write the implementation**

Insert this after the imports in `src/geometry.zig` (before the tests):
```zig
const sqrt3_over_2: f32 = 0.8660254; // sqrt(3)/2
const inv_sqrt3: f32 = 0.5773503; // 1/sqrt(3)

/// Canonical (zero-existing-bond) open directions for an atom type.
/// Pairwise angles equal the type's preferred angle; all unit length.
pub fn canonical(t: AtomType) []const Vec3 {
    return switch (t) {
        .mono => &mono_dirs,
        .linear => &linear_dirs,
        .trigonal => &trigonal_dirs,
        .tetra => &tetra_dirs,
    };
}

const mono_dirs = [_]Vec3{Vec3.init(0, 0, 1)};

const linear_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(0, 0, -1),
};

// Three directions in the XZ plane, 120 degrees apart.
const trigonal_dirs = [_]Vec3{
    Vec3.init(0, 0, 1),
    Vec3.init(sqrt3_over_2, 0, -0.5),
    Vec3.init(-sqrt3_over_2, 0, -0.5),
};

// Four vertices of a regular tetrahedron, normalized. Pairwise dot = -1/3.
const tetra_dirs = [_]Vec3{
    Vec3.init(inv_sqrt3, inv_sqrt3, inv_sqrt3),
    Vec3.init(inv_sqrt3, -inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, inv_sqrt3, -inv_sqrt3),
    Vec3.init(-inv_sqrt3, -inv_sqrt3, inv_sqrt3),
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/geometry.zig
git commit -m "feat: add canonical bond-point directions per atom type"
```

---

## Task 7: Open directions — 0 and 1 existing bond

**Files:**
- Modify: `src/geometry.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/geometry.zig`:
```zig
test "openDirections with 0 bonds returns the canonical set" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    openDirections(.tetra, &.{}, &out);
    try std.testing.expectEqual(@as(usize, 4), out.len);
    for (out.slice(), 0..) |d, i| {
        try std.testing.expect(d.approxEq(canonical(.tetra)[i], 1e-5));
    }
}

test "openDirections: mono with 1 bond has no open points" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    openDirections(.mono, &.{Vec3.init(0, 0, 1)}, &out);
    try std.testing.expectEqual(@as(usize, 0), out.len);
}

test "openDirections: linear with 1 bond points opposite" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(0, 0, 1);
    openDirections(.linear, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 1), out.len);
    try std.testing.expect(out.get(0).approxEq(e.neg(), 1e-5));
}

test "openDirections: tetra with 1 bond yields 3 dirs at the tetrahedral angle" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(0, 0, 1);
    openDirections(.tetra, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 3), out.len);
    const want = atom.preferredAngle(.tetra);
    for (out.slice()) |d| {
        try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-4);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e, d), 1e-3);
    }
    // Open dirs are also at the tetrahedral angle to each other.
    try std.testing.expectApproxEqAbs(want, math.angleBetween(out.get(0), out.get(1)), 1e-3);
}

test "openDirections: trigonal with 1 bond yields 2 coplanar dirs at 120 deg" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const e = Vec3.init(1, 0, 0);
    openDirections(.trigonal, &.{e}, &out);
    try std.testing.expectEqual(@as(usize, 2), out.len);
    const want = atom.preferredAngle(.trigonal);
    for (out.slice()) |d| {
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e, d), 1e-3);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `openDirections` undefined.

- [ ] **Step 3: Write the implementation (0-bond and 1-bond branches)**

Insert this into `src/geometry.zig` after the `canonical` block (before the tests). The 2+ branch is filled in Task 8; until then it leaves `out` empty:
```zig
/// Compute open bond directions for an atom of type `t` given the unit
/// directions of its already-existing bonds. Results are written to `out`
/// (cleared first). All returned vectors are unit length.
pub fn openDirections(
    t: AtomType,
    existing: []const Vec3,
    out: *std.BoundedArray(Vec3, 4),
) void {
    out.len = 0;
    const cano = canonical(t);
    const m = existing.len;
    if (m >= cano.len) return; // fully bonded: no open points

    if (m == 0) {
        for (cano) |d| out.appendAssumeCapacity(d);
        return;
    }

    if (m == 1) {
        switch (t) {
            .mono => {}, // unreachable: cano.len == 1, handled above
            .linear => out.appendAssumeCapacity(existing[0].neg()),
            .trigonal, .tetra => alignWithDOF(cano, existing[0], out),
        }
        return;
    }

    // m >= 2 handled in Task 8.
    openDirectionsMulti(t, existing, out);
}

/// One-existing-bond case for trigonal/tetra. Aligns the canonical frame so
/// canonical[0] maps onto the existing bond, then rotates the remaining
/// directions about the bond axis to keep one open point as close to world +Y
/// as possible (resolves the rotational degree of freedom deterministically).
fn alignWithDOF(cano: []const Vec3, e: Vec3, out: *std.BoundedArray(Vec3, 4)) void {
    const r = math.rotationAxisAngle(cano[0], e);
    var cand: std.BoundedArray(Vec3, 4) = .{};
    for (cano[1..]) |c| cand.appendAssumeCapacity(math.rodrigues(c, r.axis, r.angle));

    // Maximize the +Y component of cand[0] over rotation phi about axis e.
    // y(phi) = a*cos(phi) + b*sin(phi) + const, maximized at phi = atan2(b, a).
    const v0 = cand.get(0);
    const a = v0.y - e.y * e.dot(v0);
    const b = e.cross(v0).y;
    var phi: f32 = 0;
    if (a * a + b * b > 1e-10) phi = std.math.atan2(b, a);

    for (cand.slice()) |v| out.appendAssumeCapacity(math.rodrigues(v, e, phi));
}

// Placeholder until Task 8; keeps the file compiling.
fn openDirectionsMulti(t: AtomType, existing: []const Vec3, out: *std.BoundedArray(Vec3, 4)) void {
    _ = t;
    _ = existing;
    _ = out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS (the new 0/1-bond tests pass; the 2+ branch is still a stub but untested).

- [ ] **Step 5: Commit**

```bash
git add src/geometry.zig
git commit -m "feat: compute open bond directions for 0 and 1 existing bonds"
```

---

## Task 8: Open directions — 2+ existing bonds

**Files:**
- Modify: `src/geometry.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/geometry.zig`:
```zig
test "openDirections: tetra with 2 bonds yields 2 dirs satisfying all angles" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const c = canonical(.tetra);
    const e0 = c[0];
    const e1 = c[1];
    openDirections(.tetra, &.{ e0, e1 }, &out);
    try std.testing.expectEqual(@as(usize, 2), out.len);
    const want = atom.preferredAngle(.tetra);
    for (out.slice()) |d| {
        try std.testing.expectApproxEqAbs(@as(f32, 1), d.length(), 1e-4);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e0, d), 1e-3);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(e1, d), 1e-3);
    }
    try std.testing.expectApproxEqAbs(want, math.angleBetween(out.get(0), out.get(1)), 1e-3);
}

test "openDirections: tetra with 3 bonds yields the 4th vertex" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const c = canonical(.tetra);
    openDirections(.tetra, &.{ c[0], c[1], c[2] }, &out);
    try std.testing.expectEqual(@as(usize, 1), out.len);
    try std.testing.expect(out.get(0).approxEq(c[3], 1e-3));
}

test "openDirections: trigonal with 2 bonds yields the 3rd in-plane dir" {
    var out: std.BoundedArray(Vec3, 4) = .{};
    const c = canonical(.trigonal);
    openDirections(.trigonal, &.{ c[0], c[1] }, &out);
    try std.testing.expectEqual(@as(usize, 1), out.len);
    try std.testing.expect(out.get(0).approxEq(c[2], 1e-3));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `openDirectionsMulti` is a stub that produces 0 directions.

- [ ] **Step 3: Replace the stub with the real multi-bond implementation**

In `src/geometry.zig`, replace the placeholder `openDirectionsMulti` function with:
```zig
/// Two-or-more-existing-bond case. The remaining directions are fully
/// determined by the existing bonds and the type's geometry (closed forms
/// derived from sum-to-zero / tetrahedral identities).
fn openDirectionsMulti(t: AtomType, existing: []const Vec3, out: *std.BoundedArray(Vec3, 4)) void {
    switch (t) {
        .mono, .linear => {}, // never reach here with m >= 2 (handled by m >= cano.len)
        .trigonal => {
            // 3 coplanar unit vectors sum to zero -> last = -(e0 + e1).
            out.appendAssumeCapacity(existing[0].add(existing[1]).neg().normalize());
        },
        .tetra => {
            if (existing.len == 2) {
                // Regular-tetrahedron identity: the four unit vertices sum to
                // zero and have pairwise dot -1/3. Given e0, e1:
                //   u = e0 + e1, |u|^2 = 4/3
                //   r0,r1 = -u/2 +/- w, where w = normalize(e0 x e1) * sqrt(2/3)
                const e0 = existing[0];
                const e1 = existing[1];
                const u = e0.add(e1);
                const half_neg = u.scale(-0.5);
                const axis = e0.cross(e1).normalize();
                const w = axis.scale(@sqrt(2.0 / 3.0));
                out.appendAssumeCapacity(half_neg.add(w));
                out.appendAssumeCapacity(half_neg.sub(w));
            } else {
                // 3 existing -> 4th vertex closes the sum to zero.
                const s = existing[0].add(existing[1]).add(existing[2]);
                out.appendAssumeCapacity(s.neg().normalize());
            }
        },
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/geometry.zig
git commit -m "feat: compute open bond directions for 2+ existing bonds"
```

---

## Task 9: Molecule container — atoms, bonds, center of mass

**Files:**
- Modify: `src/molecule.zig`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `src/molecule.zig` with:
```zig
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const AtomId = atom_mod.AtomId;
const AtomType = atom_mod.AtomType;
const bond_mod = @import("bond.zig");
const Bond = bond_mod.Bond;
const geometry = @import("geometry.zig");
const constants = @import("constants.zig");

// Implementation added in later steps.

test "addFirstAtom places a tetra at the origin with no bonds" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const id = try mol.addFirstAtom(.tetra);
    try std.testing.expectEqual(@as(usize, 0), id);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items.len);
    try std.testing.expect(mol.atoms.items[0].position.approxEq(Vec3.zero, 1e-6));
    try std.testing.expectEqual(@as(usize, 0), mol.atoms.items[0].bonds.len);
}

test "addAtom creates a neighbor at rest_length and bonds both ends" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const dir = Vec3.init(0, 0, 1);
    const b = try mol.addAtom(a, dir, .mono);
    try std.testing.expectEqual(@as(usize, 1), b);
    try std.testing.expectEqual(@as(usize, 1), mol.bonds.items.len);
    // New atom sits rest_length away along dir.
    try std.testing.expect(mol.atoms.items[b].position.approxEq(dir.scale(constants.default.rest_length), 1e-5));
    // Both atoms reference the bond.
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[a].bonds.len);
    try std.testing.expectEqual(@as(usize, 1), mol.atoms.items[b].bonds.len);
}

test "centerOfMass averages atom positions" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // at (0,0,1)
    try std.testing.expect(mol.centerOfMass().approxEq(Vec3.init(0, 0, 0.5), 1e-5));
}

test "bondDirection returns the unit vector from an atom to its bonded neighbor" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    const b = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    const bond_id = mol.atoms.items[a].bonds.get(0);
    try std.testing.expect(mol.bondDirection(a, bond_id).approxEq(Vec3.init(0, 0, 1), 1e-5));
    try std.testing.expect(mol.bondDirection(b, bond_id).approxEq(Vec3.init(0, 0, -1), 1e-5));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `Molecule` undefined.

- [ ] **Step 3: Write the implementation**

Insert this after the imports in `src/molecule.zig` (before the tests):
```zig
pub const BondPointId = usize;

pub const OpenBondPoint = struct {
    parent_atom: AtomId,
    direction: Vec3, // unit vector from the parent atom, at the preferred angle
    id: BondPointId,
};

pub const Molecule = struct {
    atoms: std.ArrayList(Atom),
    bonds: std.ArrayList(Bond),
    rest_length: f32,

    pub fn init(allocator: std.mem.Allocator) Molecule {
        return .{
            .atoms = std.ArrayList(Atom).init(allocator),
            .bonds = std.ArrayList(Bond).init(allocator),
            .rest_length = constants.default.rest_length,
        };
    }

    pub fn deinit(self: *Molecule) void {
        self.atoms.deinit();
        self.bonds.deinit();
    }

    /// Place the first atom at the origin. Errors if atoms already exist.
    pub fn addFirstAtom(self: *Molecule, atom_type: AtomType) !AtomId {
        std.debug.assert(self.atoms.items.len == 0);
        const id: AtomId = self.atoms.items.len;
        try self.atoms.append(.{ .position = Vec3.zero, .atom_type = atom_type, .id = id });
        return id;
    }

    /// Place a new atom at `parent.position + direction * rest_length` and bond
    /// it to `parent`. `direction` should be a unit vector (typically an open
    /// bond point's direction).
    pub fn addAtom(self: *Molecule, parent: AtomId, direction: Vec3, atom_type: AtomType) !AtomId {
        const parent_pos = self.atoms.items[parent].position;
        const new_pos = parent_pos.add(direction.scale(self.rest_length));
        const new_id: AtomId = self.atoms.items.len;
        try self.atoms.append(.{ .position = new_pos, .atom_type = atom_type, .id = new_id });

        const bond_id = self.bonds.items.len;
        try self.bonds.append(.{ .atom_a = parent, .atom_b = new_id, .id = bond_id });
        self.atoms.items[parent].bonds.appendAssumeCapacity(bond_id);
        self.atoms.items[new_id].bonds.appendAssumeCapacity(bond_id);
        return new_id;
    }

    pub fn centerOfMass(self: *const Molecule) Vec3 {
        if (self.atoms.items.len == 0) return Vec3.zero;
        var sum = Vec3.zero;
        for (self.atoms.items) |a| sum = sum.add(a.position);
        return sum.scale(1.0 / @as(f32, @floatFromInt(self.atoms.items.len)));
    }

    /// Unit vector from `from_atom` toward the neighbor across `bond_id`.
    pub fn bondDirection(self: *const Molecule, from_atom: AtomId, bond_id: usize) Vec3 {
        const b = self.bonds.items[bond_id];
        const neighbor = b.other(from_atom);
        return self.atoms.items[neighbor].position.sub(self.atoms.items[from_atom].position).normalize();
    }
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/molecule.zig
git commit -m "feat: add Molecule container with addAtom, centerOfMass, bondDirection"
```

---

## Task 10: Molecule.openBondPoints

**Files:**
- Modify: `src/molecule.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/molecule.zig`:
```zig
test "openBondPoints: lone tetra exposes 4 open points" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.tetra);

    var out = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer out.deinit();
    try mol.openBondPoints(&out);

    try std.testing.expectEqual(@as(usize, 4), out.items.len);
    for (out.items) |p| {
        try std.testing.expectEqual(@as(AtomId, 0), p.parent_atom);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.direction.length(), 1e-5);
    }
}

test "openBondPoints: after one bond, parent exposes its remaining open points" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.tetra);
    _ = try mol.addAtom(a, geometry.canonical(.tetra)[0], .mono); // mono caps -> no open points there

    var out = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer out.deinit();
    try mol.openBondPoints(&out);

    // Tetra parent now has 1 bond -> 3 open points; mono child has 0.
    try std.testing.expectEqual(@as(usize, 3), out.items.len);
    const want = atom_mod.preferredAngle(.tetra);
    const used = geometry.canonical(.tetra)[0];
    for (out.items) |p| {
        try std.testing.expectEqual(@as(AtomId, a), p.parent_atom);
        try std.testing.expectApproxEqAbs(want, math.angleBetween(used, p.direction), 1e-3);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `openBondPoints` undefined.

- [ ] **Step 3: Write the implementation**

Add this method inside the `Molecule` struct in `src/molecule.zig` (e.g. after `bondDirection`):
```zig
    /// Recompute all open bond points across the molecule into `out`
    /// (cleared first). IDs are assigned sequentially and are valid only
    /// until the next recompute.
    pub fn openBondPoints(self: *const Molecule, out: *std.ArrayList(OpenBondPoint)) !void {
        out.clearRetainingCapacity();
        var next_id: BondPointId = 0;
        for (self.atoms.items) |a| {
            // Gather unit directions of this atom's existing bonds.
            var existing: std.BoundedArray(Vec3, 4) = .{};
            for (a.bonds.slice()) |bond_id| {
                existing.appendAssumeCapacity(self.bondDirection(a.id, bond_id));
            }
            var dirs: std.BoundedArray(Vec3, 4) = .{};
            geometry.openDirections(a.atom_type, existing.slice(), &dirs);
            for (dirs.slice()) |d| {
                try out.append(.{ .parent_atom = a.id, .direction = d, .id = next_id });
                next_id += 1;
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/molecule.zig
git commit -m "feat: compute open bond points across the whole molecule"
```

---

## Task 11: Physics — spring forces

**Files:**
- Modify: `src/physics.zig`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `src/physics.zig` with:
```zig
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const atom_mod = @import("atom.zig");
const constants = @import("constants.zig");
const Constants = constants.Constants;
const molecule = @import("molecule.zig");
const Molecule = molecule.Molecule;

// Implementation added in later steps.

test "spring: stretched bond pulls atoms together" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    // Place neighbor at distance 2.0 (stretched: rest_length = 1.0).
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2);

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addSpringForces(&mol, constants.default, &forces);

    // F = k*(dist - rest) = 10*(2-1) = 10. Atom a pulled toward +Z, atom b toward -Z.
    try std.testing.expectApproxEqAbs(@as(f32, 10), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -10), forces[1].z, 1e-3);
    // Equal and opposite.
    try std.testing.expect(forces[0].add(forces[1]).approxEq(Vec3.zero, 1e-4));
}

test "spring: compressed bond pushes atoms apart" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 0.5); // compressed

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addSpringForces(&mol, constants.default, &forces);

    // F = 10*(0.5-1) = -5. Atom a pushed toward -Z, atom b toward +Z.
    try std.testing.expectApproxEqAbs(@as(f32, -5), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 5), forces[1].z, 1e-3);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `addSpringForces` undefined.

- [ ] **Step 3: Write the implementation**

Insert this after the imports in `src/physics.zig` (before the tests):
```zig
/// Accumulate Hooke's-law spring forces for every bond into `forces`
/// (indexed by atom id). `forces.len` must equal the atom count.
/// F = k_spring * (dist - rest_length), directed along the bond.
pub fn addSpringForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (mol.bonds.items) |b| {
        const pa = mol.atoms.items[b.atom_a].position;
        const pb = mol.atoms.items[b.atom_b].position;
        const delta = pb.sub(pa);
        const dist = delta.length();
        if (dist < 1e-8) continue;
        const dir = delta.scale(1.0 / dist);
        const f = c.k_spring * (dist - c.rest_length);
        // Positive f (stretched) pulls a toward b and b toward a.
        forces[b.atom_a] = forces[b.atom_a].add(dir.scale(f));
        forces[b.atom_b] = forces[b.atom_b].add(dir.scale(-f));
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/physics.zig
git commit -m "feat: add spring forces between bonded atoms"
```

---

## Task 12: Physics — angle forces

**Files:**
- Modify: `src/physics.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/physics.zig`:
```zig
test "angle: forces on the three atoms sum to zero (momentum conserved)" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(center, Vec3.init(1, 0, 0), .mono); // neighbor 1 at +X
    _ = try mol.addAtom(center, Vec3.init(0, 1, 0), .mono); // neighbor 2 at +Y (90 deg, want 180)

    var forces = [_]Vec3{Vec3.zero} ** 3;
    addAngleForces(&mol, constants.default, &forces);

    const total = forces[0].add(forces[1]).add(forces[2]);
    try std.testing.expect(total.approxEq(Vec3.zero, 1e-4));
}

test "angle: a bent linear atom is pushed toward straight (angle increases)" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.linear);
    const n1 = try mol.addAtom(center, Vec3.init(1, 0, 0), .mono);
    const n2 = try mol.addAtom(center, Vec3.init(0, 1, 0), .mono);

    const before = math.angleBetween(
        mol.atoms.items[n1].position.sub(mol.atoms.items[center].position),
        mol.atoms.items[n2].position.sub(mol.atoms.items[center].position),
    );

    // Take one tiny explicit step using only angle forces.
    var forces = [_]Vec3{Vec3.zero} ** 3;
    addAngleForces(&mol, constants.default, &forces);
    const h: f32 = 0.01;
    for (mol.atoms.items, 0..) |*atom, i| atom.position = atom.position.add(forces[i].scale(h));

    const after = math.angleBetween(
        mol.atoms.items[n1].position.sub(mol.atoms.items[center].position),
        mol.atoms.items[n2].position.sub(mol.atoms.items[center].position),
    );
    try std.testing.expect(after > before); // moving toward 180 degrees
}

test "angle: a single-bond atom contributes no angle force" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(1, 0, 0), .mono);

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addAngleForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `addAngleForces` undefined.

- [ ] **Step 3: Write the implementation**

Insert this into `src/physics.zig` after `addSpringForces`:
```zig
/// Accumulate harmonic angle forces. For each atom with >= 2 bonds, every pair
/// of bonds (i, j) is pushed toward the atom's preferred angle. Forces are
/// applied to the neighbor atoms perpendicular to each bond (per the design
/// spec), with the reaction applied to the central atom so total momentum is
/// conserved.
pub fn addAngleForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (mol.atoms.items) |center| {
        const n = center.bonds.len;
        if (n < 2) continue;
        const preferred = atom_mod.preferredAngle(center.atom_type);
        const cpos = center.position;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const ni = mol.bonds.items[center.bonds.get(i)].other(center.id);
            const bond_i = mol.atoms.items[ni].position.sub(cpos);
            const li2 = bond_i.lengthSq();
            if (li2 < 1e-12) continue;

            var j: usize = i + 1;
            while (j < n) : (j += 1) {
                const nj = mol.bonds.items[center.bonds.get(j)].other(center.id);
                const bond_j = mol.atoms.items[nj].position.sub(cpos);
                const lj2 = bond_j.lengthSq();
                if (lj2 < 1e-12) continue;

                const li = @sqrt(li2);
                const lj = @sqrt(lj2);
                const cos_a = std.math.clamp(bond_i.dot(bond_j) / (li * lj), -1.0, 1.0);
                const angle = std.math.acos(cos_a);
                const delta = angle - preferred;
                // Positive magnitude => bonds should open (angle < preferred).
                const magnitude = -c.k_angle * delta;

                // In-plane unit vectors perpendicular to each bond, then negated
                // to point in the angle-OPENING direction. The force on a
                // neighbor must be perpendicular to ITS OWN bond so it changes
                // the angle, not the bond length. (a x b) x a is the rejection
                // of b from a, i.e. perpendicular to a in the (a,b) plane.
                const cross_ij = bond_i.cross(bond_j);
                if (cross_ij.lengthSq() < 1e-12) continue; // collinear: no torque axis
                const perp_i = cross_ij.cross(bond_i).normalize().neg();
                const perp_j = bond_j.cross(cross_ij).normalize().neg();

                const fi = perp_i.scale(magnitude / li);
                const fj = perp_j.scale(magnitude / lj);

                forces[ni] = forces[ni].add(fi);
                forces[nj] = forces[nj].add(fj);
                forces[center.id] = forces[center.id].add(fi.add(fj).neg()); // reaction
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/physics.zig
git commit -m "feat: add harmonic angle forces per atom type"
```

---

## Task 13: Physics — non-bonded repulsion

**Files:**
- Modify: `src/physics.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/physics.zig`:
```zig
test "repulsion: close non-bonded atoms push apart" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    // Two unbonded atoms 0.5 apart along Z (< repulsion_threshold 0.8).
    _ = try mol.addFirstAtom(.mono);
    try mol.atoms.append(.{ .position = Vec3.init(0, 0, 0.5), .atom_type = .mono, .id = 1 });

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);

    // F = k_repel / dist^2 = 2 / 0.25 = 8. Atom 0 toward -Z, atom 1 toward +Z.
    try std.testing.expectApproxEqAbs(@as(f32, -8), forces[0].z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 8), forces[1].z, 1e-3);
}

test "repulsion: atoms beyond the threshold feel nothing" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    try mol.atoms.append(.{ .position = Vec3.init(0, 0, 1.5), .atom_type = .mono, .id = 1 });

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}

test "repulsion: directly bonded atoms are excluded" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono); // bonded, dist 1.0 anyway
    mol.atoms.items[1].position = Vec3.init(0, 0, 0.5); // pull within threshold

    var forces = [_]Vec3{Vec3.zero} ** 2;
    addRepulsionForces(&mol, constants.default, &forces);
    try std.testing.expect(forces[0].approxEq(Vec3.zero, 1e-6));
    try std.testing.expect(forces[1].approxEq(Vec3.zero, 1e-6));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `addRepulsionForces` undefined.

- [ ] **Step 3: Write the implementation**

Insert this into `src/physics.zig` after `addAngleForces`:
```zig
/// Accumulate steric repulsion between non-bonded atom pairs closer than
/// `repulsion_threshold`. F = k_repel / dist^2, directed apart.
pub fn addRepulsionForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    const atoms = mol.atoms.items;
    var i: usize = 0;
    while (i < atoms.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < atoms.len) : (j += 1) {
            if (areBonded(mol, atoms[i].id, atoms[j].id)) continue;
            const delta = atoms[j].position.sub(atoms[i].position);
            const dist = delta.length();
            if (dist >= c.repulsion_threshold or dist < 1e-6) continue;
            const dir = delta.scale(1.0 / dist);
            const f = c.k_repel / (dist * dist);
            forces[atoms[i].id] = forces[atoms[i].id].add(dir.scale(-f));
            forces[atoms[j].id] = forces[atoms[j].id].add(dir.scale(f));
        }
    }
}

fn areBonded(mol: *const Molecule, a: atom_mod.AtomId, b: atom_mod.AtomId) bool {
    for (mol.atoms.items[a].bonds.slice()) |bond_id| {
        if (mol.bonds.items[bond_id].other(a) == b) return true;
    }
    return false;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/physics.zig
git commit -m "feat: add non-bonded steric repulsion"
```

---

## Task 14: Physics — integration, kinetic energy, convergence

**Files:**
- Modify: `src/physics.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/physics.zig`:
```zig
test "computeForces aggregates spring + angle + repulsion" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2); // stretched bond

    var forces = [_]Vec3{Vec3.zero} ** 2;
    computeForces(&mol, constants.default, &forces);
    // At minimum the spring contribution must be present.
    try std.testing.expect(@abs(forces[0].z) > 1e-3);
}

test "kineticEnergy sums 0.5*v^2 over atoms" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    _ = try mol.addFirstAtom(.mono);
    mol.atoms.items[0].velocity = Vec3.init(0, 0, 2); // KE = 0.5 * 4 = 2
    try std.testing.expectApproxEqAbs(@as(f32, 2), kineticEnergy(&mol), 1e-5);
}

test "simulate settles a stretched two-atom bond toward rest length" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const a = try mol.addFirstAtom(.linear);
    _ = try mol.addAtom(a, Vec3.init(0, 0, 1), .mono);
    mol.atoms.items[1].position = Vec3.init(0, 0, 2); // stretched

    var settled = false;
    var iterations: usize = 0;
    while (!settled and iterations < 5000) : (iterations += 1) {
        settled = try simulate(&mol, constants.default, std.testing.allocator);
    }
    try std.testing.expect(settled);
    const dist = mol.atoms.items[0].position.distance(mol.atoms.items[1].position);
    try std.testing.expectApproxEqAbs(constants.default.rest_length, dist, 0.05);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `computeForces`, `kineticEnergy`, `simulate` undefined.

- [ ] **Step 3: Write the implementation**

Insert this into `src/physics.zig` after `addRepulsionForces`:
```zig
/// Number of integration substeps run per `simulate` call for stability.
pub const substeps: usize = 4;

/// Zero `forces`, then accumulate spring + angle + repulsion contributions.
pub fn computeForces(mol: *const Molecule, c: Constants, forces: []Vec3) void {
    for (forces) |*f| f.* = Vec3.zero;
    addSpringForces(mol, c, forces);
    addAngleForces(mol, c, forces);
    addRepulsionForces(mol, c, forces);
}

/// Total kinetic energy assuming unit mass: sum of 0.5 * |v|^2.
pub fn kineticEnergy(mol: *const Molecule) f32 {
    var ke: f32 = 0;
    for (mol.atoms.items) |a| ke += 0.5 * a.velocity.lengthSq();
    return ke;
}

/// One integration substep: semi-implicit (symplectic) Euler with velocity
/// damping. Unit mass, so acceleration == force.
fn step(mol: *Molecule, c: Constants, dt: f32, forces: []Vec3) void {
    computeForces(mol, c, forces);
    for (mol.atoms.items, 0..) |*a, i| {
        a.velocity = a.velocity.add(forces[i].scale(dt));
        a.velocity = a.velocity.scale(c.damping);
        a.position = a.position.add(a.velocity.scale(dt));
    }
}

/// Advance the simulation by one frame (`substeps` substeps of `c.dt /
/// substeps` each). Returns true once the molecule reaches equilibrium:
/// both kinetic energy AND net force are below the convergence threshold.
/// (Kinetic energy alone is insufficient — it dips to ~0 at every oscillation
/// turning point, where the restoring force is still large, which would report
/// "settled" mid-swing far from rest.)
pub fn simulate(mol: *Molecule, c: Constants, allocator: std.mem.Allocator) !bool {
    const forces = try allocator.alloc(Vec3, mol.atoms.items.len);
    defer allocator.free(forces);
    const sub_dt = c.dt / @as(f32, @floatFromInt(substeps));
    var s: usize = 0;
    while (s < substeps) : (s += 1) step(mol, c, sub_dt, forces);
    // Re-evaluate forces at the final positions to test for true rest.
    computeForces(mol, c, forces);
    return kineticEnergy(mol) < c.convergence_threshold and netForceSq(forces) < c.convergence_threshold;
}

/// Sum of squared force magnitudes across all atoms (a scalar "how far from
/// force equilibrium" measure).
fn netForceSq(forces: []const Vec3) f32 {
    var sum: f32 = 0;
    for (forces) |f| sum += f.lengthSq();
    return sum;
}
```

> **Convergence note (correction applied during implementation):** The design
> doc specifies "simulation runs until kinetic energy drops below a threshold."
> That criterion alone produces a false positive — KE momentarily hits ~0 at
> each oscillation turning point while the spring force is still large, so the
> molecule reports "settled" mid-swing (verified: a stretched 2-atom bond
> "settled" at dist 0.886 instead of 1.0). Equilibrium requires BOTH low KE and
> low net force, which is what the corrected `simulate` checks.

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/physics.zig
git commit -m "feat: add damped Verlet integration and convergence detection"
```

---

## Task 15: Headless demo + end-to-end integration test

**Files:**
- Modify: `src/main.zig`
- Modify: `src/molecule.zig` (add the integration test)

- [ ] **Step 1: Write the failing end-to-end test**

Append to `src/molecule.zig`:
```zig
const physics = @import("physics.zig");

test "end-to-end: build a tetra+3 molecule, settle it, bonds reach rest length" {
    var mol = Molecule.init(std.testing.allocator);
    defer mol.deinit();
    const center = try mol.addFirstAtom(.tetra);

    // Attach three mono caps along three of the tetra's open directions.
    var open = std.ArrayList(OpenBondPoint).init(std.testing.allocator);
    defer open.deinit();
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        try mol.openBondPoints(&open);
        // Always grab an open point on the center atom.
        var dir: Vec3 = undefined;
        for (open.items) |p| {
            if (p.parent_atom == center) {
                dir = p.direction;
                break;
            }
        }
        _ = try mol.addAtom(center, dir, .mono);
    }
    try std.testing.expectEqual(@as(usize, 4), mol.atoms.items.len);
    try std.testing.expectEqual(@as(usize, 3), mol.bonds.items.len);

    // Settle.
    var settled = false;
    var iters: usize = 0;
    while (!settled and iters < 20000) : (iters += 1) {
        settled = try physics.simulate(&mol, constants.default, std.testing.allocator);
    }
    try std.testing.expect(settled);

    // Every bond should be near rest length, and no atoms overlapping.
    for (mol.bonds.items) |b| {
        const d = mol.atoms.items[b.atom_a].position.distance(mol.atoms.items[b.atom_b].position);
        try std.testing.expectApproxEqAbs(constants.default.rest_length, d, 0.1);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — `physics` not yet imported / test newly added and exercising the full stack. (If it compiles but fails on convergence, treat that as a real signal — see the debugging note below.)

- [ ] **Step 3: Confirm the test passes against the existing implementation**

The implementation already exists (Tasks 9–14); this test wires it together. Run: `zig build test`
Expected: PASS. If it does **not** converge or bonds are off, do not loosen the assertion — invoke `superpowers:systematic-debugging` and inspect force balance/constants.

- [ ] **Step 4: Write the headless demo in main.zig**

Replace the contents of `src/main.zig` with:
```zig
const std = @import("std");
const lib = @import("root.zig");
const Vec3 = lib.math.Vec3;
const Molecule = lib.molecule.Molecule;
const OpenBondPoint = lib.molecule.OpenBondPoint;
const constants = lib.constants;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mol = Molecule.init(allocator);
    defer mol.deinit();

    const center = try mol.addFirstAtom(.tetra);

    var open = std.ArrayList(OpenBondPoint).init(allocator);
    defer open.deinit();

    // Cap all four tetra bonds with mono atoms.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try mol.openBondPoints(&open);
        var dir: ?Vec3 = null;
        for (open.items) |p| {
            if (p.parent_atom == center) {
                dir = p.direction;
                break;
            }
        }
        if (dir) |d| _ = try mol.addAtom(center, d, .mono) else break;
    }

    var settled = false;
    var frames: usize = 0;
    while (!settled and frames < 100000) : (frames += 1) {
        settled = try lib.physics.simulate(&mol, constants.default, allocator);
    }

    std.debug.print("settled after {d} frames\n", .{frames});
    for (mol.atoms.items) |a| {
        std.debug.print("atom {d} ({s}) pos=({d:.3}, {d:.3}, {d:.3})\n", .{
            a.id, @tagName(a.atom_type), a.position.x, a.position.y, a.position.z,
        });
    }
}
```

- [ ] **Step 5: Verify the demo builds and runs**

Run: `zig build test && zig build run`
Expected: tests PASS; `zig build run` prints `settled after N frames` followed by 5 atom lines (1 tetra + 4 mono), with the four mono atoms spread around the center.

- [ ] **Step 6: Commit**

```bash
git add src/main.zig src/molecule.zig
git commit -m "feat: headless demo and end-to-end folding integration test"
```

---

## Self-Review (completed by plan author)

**Spec coverage (headless-core slice):**
- Atom types + bond counts + preferred angles → Task 5 ✓
- Open bond point directions (0 / 1 / 2+ existing bonds, +Y disambiguation) → Tasks 6–8 ✓
- Data model (`Atom`, `Bond`, `OpenBondPoint`, `Molecule`, `addAtom`, `openBondPoints`) → Tasks 5, 9, 10 ✓
- Bond springs (Hooke) → Task 11 ✓
- Angle forces (harmonic, per spec formula, applied to neighbors) → Task 12 ✓
- Non-bonded repulsion (`c/dist^2`, threshold) → Task 13 ✓
- Damped Verlet integration, substeps, kinetic-energy convergence → Task 14 ✓
- Tuning constants (all 8) → Task 4 ✓
- Animated/settling loop usable frame-by-frame (`simulate` returns settled flag) → Tasks 14, 15 ✓

**Deliberately deferred (documented in Scope):** WebGPU rendering, window/input, quaternion `rotation`/`target_rotation` + slerp navigation, radial menu, auto-zoom camera, puzzle mode.

**Type/name consistency:** `Vec3` method names (`add/sub/scale/neg/dot/cross/length/lengthSq/normalize/distance/approxEq`) used identically across all tasks. `Constants` field names match `constants.zig` and the spec table. `addSpringForces`/`addAngleForces`/`addRepulsionForces`/`computeForces`/`step`/`simulate`/`kineticEnergy` names consistent between physics impl and tests. `openDirections`/`canonical`/`openBondPoints`/`bondDirection` consistent across geometry and molecule.

**Known toolchain risk:** Targets Zig 0.14.0. Two APIs to watch if a different 0.14.x is used — `std.math.atan2(y, x)` (two-arg form) in `alignWithDOF`, and managed `std.ArrayList(T).init(allocator)` in `molecule.zig`. Task 1 verifies the toolchain and build before any feature code, so an API mismatch surfaces immediately rather than mid-plan.

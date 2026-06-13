# Biome: Molecular — WebGPU Renderer (static example browser)

## Overview

A native macOS windowed application that renders settled molecules from the headless core in 3D, with a small built-in library of example molecules the user can scroll through to visually inspect. This is the first rendering subsystem built on top of the merged headless core (math, data model, geometry, physics).

At startup the app builds and physics-settles a curated set of example molecules, then displays one at a time: **atoms as lit spheres, bonds as lit cylinders**, framed by a fixed camera against a dark background. Left/Right arrow keys cycle through the examples; the current example's name is shown in the window title bar.

The render is **static** per example — the molecule is settled once at startup and then just redrawn each frame. There is no per-frame physics, no atom placement, no quaternion navigation, and no on-screen text/HUD in this plan.

## Goals

- Stand up a custom WebGPU renderer (wgpu-native, no engine) on macOS.
- Render real `Molecule` data: instanced spheres for atoms, instanced cylinders for bonds, 3-point Phong lighting.
- Provide a scrollable list of example molecules for visual inspection.
- Keep all CPU-side logic pure and unit-tested; verify the GPU path by running and looking.

## Non-goals (deferred to later plans)

- Open-bond-point markers (glowing additive markers).
- The radial atom-placement menu and atom placement.
- Quaternion-based molecule navigation / slerp rotation.
- Auto-zoom animation, smooth camera interpolation.
- In-window text rendering / HUD (window-title labeling only for now).
- Puzzle mode. Windows/Linux/WASM targets (structure should not preclude them, but only macOS is built and tested).

## Platform & Dependencies

- **Target:** macOS, Apple Silicon (aarch64), Zig 0.14.0. Metal backend via wgpu-native.
- **wgpu-native:** prebuilt release binary from gfx-rs/wgpu-native (macos-aarch64), pulled via `build.zig.zon` (url + hash). Provides `libwgpu_native` plus `webgpu.h` / `wgpu.h`, consumed through Zig `@cImport`.
- **GLFW:** system install via Homebrew (`brew install glfw`), linked in `build.zig`. Provides windowing + keyboard input + the native Cocoa window handle.
- **macOS frameworks linked:** Metal, QuartzCore, Cocoa, IOKit, Foundation.
- The `zig build test` step stays pure Zig with **no** GPU/GLFW dependencies — only the executable links them.

## Architecture

The renderer is a new consumer of the headless core. **The core is not modified.** Renderer code lives under `src/render/` and `src/platform/`, with general-purpose matrix math in `src/mat4.zig`.

### CPU-side modules (pure, TDD'd)

| File | Responsibility |
|------|----------------|
| `src/mat4.zig` | `Mat4` (4×4 f32, **column-major** to match WGSL): `identity`, `mul`, `perspective(fovy, aspect, near, far)`, `lookAt(eye, center, up)`, `translation(Vec3)`, `scale(Vec3)`, `fromAxisAngle(axis, angle)`. |
| `src/render/mesh.zig` | CPU mesh generation: `icosphere(subdivisions)` and unit `cylinder(segments)`. Each returns vertices (position + normal) and a triangle index list. |
| `src/render/atom_style.zig` | Per-`AtomType` visual radius and RGB color (distinct size/color per type so structure is readable). |
| `src/render/camera.zig` | `boundingSphere(molecule) → {center, radius}`; camera distance `max(radius * 2.5, 5.0)`; `view` and `projection` matrices. |
| `src/render/scene.zig` | Pack a `Molecule` into instance data: per-atom `Instance{ model: Mat4, color }` and per-bond `Instance{ model: Mat4, color }`. Atom model = `translate(pos) · scale(radius)`. Bond model = `translate(A) · fromAxisAngle(+Y → B−A) · scale(r, |B−A|, r)`. |

### GPU-side modules (manual visual verification)

| File | Responsibility |
|------|----------------|
| `src/render/gpu.zig` | wgpu-native wrapper: instance/adapter/device/queue creation, surface configuration, swapchain, depth texture, two render pipelines (atom pass, bond pass), the shared mesh buffers, per-instance buffers, a uniform buffer, and per-frame encode/submit/present. Supports re-uploading instance buffers when the selected example changes. |
| `src/render/shaders/sphere.wgsl`, `src/render/shaders/cylinder.wgsl` | Instanced vertex shader (`viewProj · model · vertex`) + Phong fragment shader (3-point lighting). `@embedFile`'d into the binary. (May share one shader if practical; two is the default.) |
| `src/platform/window.zig` | GLFW window creation, the macOS `CAMetalLayer` surface glue (attach a `CAMetalLayer` to the GLFW `NSWindow` and create the wgpu surface from it), keyboard polling (Left/Right/close), window-resize handling, and setting the window title. |
| `src/main.zig` | Repurposed from the headless demo: build + settle all examples, create window + GPU, run the draw loop, handle example switching. |

## Key technical decisions

### Instancing
One shared mesh per primitive (sphere, cylinder) in a vertex+index buffer, plus a per-instance buffer holding `{ model: Mat4, color: vec3 }`. One draw call per pass with `instanceCount = atom count` (atoms) or `bond count` (bonds). A uniform buffer holds the `viewProj` matrix and the three light directions/colors.

### Cylinder orientation
The cylinder mesh is a unit cylinder along **+Y**, spanning `y ∈ [0, 1]` with radius 1. A bond from A to B with radius `r` uses model matrix `translate(A) · fromAxisAngle(+Y → normalize(B−A)) · scale(r, |B−A|, r)`. Verified in tests by asserting the transform maps the cylinder's two end-center points to A and B.

### Normals under non-uniform scale
Bond cylinders use non-uniform scale `(r, L, r)` where x and z scale equally. Cylinder side normals are radial (in the local xz plane) and end-cap normals are ±Y; under a scale whose x and z components are equal, these normals retain their correct direction after `normalize()` in the shader. Therefore **no separate normal matrix is needed** — the shader transforms normals by the model's rotation and normalizes. (This holds specifically because x-scale == z-scale.)

### Lighting
3-point Phong computed in the fragment shader:
- Key light: warm, upper-left, brightest.
- Fill light: cool, lower-right, dimmer.
- Rim light: from behind, for edge definition.
No shadows. Dark, minimal background (clear color).

### Camera
Fixed perspective camera at `(0, 0, z)` looking at the molecule's bounding-sphere center, with `z = max(bounding_radius * 2.5, 5.0)`. Recomputed once whenever the selected example changes (not animated in this plan).

### Depth
A depth texture + depth-stencil state (depth test/write, less) so overlapping spheres and cylinders occlude correctly.

## Example molecules

`src/examples.zig` exposes an ordered list of `{ name: []const u8, build: fn(allocator) !Molecule }`. All examples are acyclic (the core API builds trees — `addAtom` always adds one new bonded atom; ring closure is not yet supported). At startup each is built and `physics.simulate`-settled into a stored snapshot; switching is instant.

Initial set (easily adjustable):

1. **Methane** — tetra center + 4 mono caps.
2. **Linear chain** — 6 linear atoms in a row.
3. **Trigonal star** — trigonal center + 3 mono caps (flat triangle).
4. **Ethane-like** — two tetra atoms bonded, remaining bond points capped with mono.
5. **Branched blob** — tetra center + 4 tetra neighbors, each capped with mono (larger 3D fold; exercises repulsion).
6. **Trigonal sheet** — trigonal center + 3 trigonal neighbors + mono caps (flat-ish).

Examples are constructed by placing atoms on open bond points (via `openBondPoints` + `addAtom`), matching how the eventual game builds molecules.

## Window, input, and main loop

- **Window:** GLFW window (e.g. 1280×800), resizable. Title shows `"<example name> (<i>/<N>)"`.
- **Input:** Left/Right arrow cycles the selected example index (wrapping). On change: repack instances from the selected snapshot, update GPU instance buffers, recompute the camera, update the window title. Escape or window-close exits.
- **Resize:** reconfigure the surface and recreate the depth texture at the new size; recompute projection aspect.
- **Loop:** poll events → (if selection changed) rebuild scene buffers → render one frame (clear, atom pass, bond pass, present). No physics runs in the loop.

## Build system changes

- `build.zig.zon`: add the wgpu-native prebuilt dependency (url + hash).
- `build.zig`: for the executable only — add the wgpu-native include path and link its library; link system GLFW and the macOS frameworks (Metal, QuartzCore, Cocoa, IOKit, Foundation); compile the small Objective-C surface-glue translation unit if one is used. The library/test modules remain dependency-free.

## Testing strategy & definition of done

**TDD'd (pure CPU logic):**
- `Mat4`: identity, multiply (against hand-computed products), `perspective`/`lookAt` (known entries / transforming known points), `fromAxisAngle` (rotates a known vector), `translation`/`scale`.
- `mesh.zig`: icosphere vertex/triangle counts per subdivision level; every icosphere vertex is unit length; cylinder ring/cap vertex counts and endpoint ring positions; all normals unit length.
- `atom_style.zig`: each `AtomType` maps to its expected radius/color; types are visually distinct.
- `camera.zig`: bounding sphere of a known atom set; distance formula incl. the `5.0` floor; projection/view matrix sanity (e.g. a point on the bounding sphere projects inside the frustum).
- `scene.zig`: instance counts equal atom/bond counts; atom model places a unit sphere at the atom's position scaled by its radius; bond model maps cylinder endpoints to the bonded atoms' positions; colors match `atom_style`.
- `examples.zig`: each example builds without error and yields its expected atom and bond counts; each settles.

**Manual visual verification (GPU path):**
- `zig build run` opens a window showing a correctly-lit molecule (recognizable spheres at atom positions joined by cylinders, properly framed against a dark background).
- Left/Right cycles through all examples; the window title updates; each renders correctly and is framed.

**Definition of done:** all CPU-side tests pass under `zig build test`, and `zig build run` shows the example browser working — each molecule correctly rendered, lit, framed, and switchable via arrow keys with the title updating.

## Risks / unknowns

- **wgpu-native + GLFW surface glue on macOS** is the riskiest integration point (attaching a `CAMetalLayer` and creating the wgpu surface). Mitigated by following wgpu-native's published examples; this is the first thing to get working (a clear-color frame) before any geometry.
- **Zig 0.14 `@cImport` of webgpu.h/wgpu.h** may need minor shims; isolate all C interop in `gpu.zig`/`window.zig`.
- **Prebuilt wgpu-native version pinning** — pick a specific release tag whose `webgpu.h` API matches the code; record it in `build.zig.zon`.
- Manual visual verification means rendering regressions aren't caught automatically; acceptable for a solo project at this stage.

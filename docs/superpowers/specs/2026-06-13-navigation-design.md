# Biome: Molecular — Navigation (sandbox bond-point selection & rotation)

## Overview

The first slice of the interactive sandbox game loop. The app starts with a
single Tetra atom at the origin (the spec's opening state), shows its open bond
points as markers, and lets the player cycle through those points with the
arrow keys. Selecting a point smoothly rotates the whole molecule so the
selected point faces the camera. The selected marker is visually highlighted.

This is the spec's **core interaction** ("rotating the molecule by selecting
bond points -- the molecule spins to bring your selection to the front"). It
builds directly on the existing renderer and replaces the example-browser /
turntable affordances that were used to bring the renderer up.

Atom **placement** (the radial menu and adding atoms) is the next plan; this one
is look-and-navigate only.

## Goals

- Replace the turntable/example-browser with a single-molecule **sandbox** that
  starts with one Tetra at the origin.
- Render open bond points as markers; highlight the selected one.
- Cycle the selection with Left/Right (ordered, wrapping).
- Rotate the molecule via quaternion **slerp** to bring the selected point's
  outward direction toward the camera (~300 ms, ease-in-out, shortest-path).
- Keep all pure logic (quaternion math, selection, target orientation) unit-tested;
  verify the rendering/animation by running and looking.

## Non-goals (deferred)

- Atom placement, the radial menu, re-folding on placement (next plan).
- **Spatial** traversal (nearest open point in a screen direction) — we use
  ordered cycling for now.
- Additive "glow" halo markers (we use solid bright spheres); auto-zoom camera
  animation; input *queuing* during animation (we re-target instead).
- The example browser as a shipping feature (`examples.zig` stays for tests).

## App model

The window opens showing a single settled Tetra at the origin with its four
open bond points as markers, one of them selected (index 0). Controls:

| Input | Action |
|-------|--------|
| Left / Right arrows | Select previous / next open bond point (wrapping) |
| Escape / Cmd-W / close | Quit |

The camera is fixed and frames the molecule; the **molecule rotates** (it does
not orbit the camera). There is no idle turntable spin — the molecule is still
except while animating to a newly selected point.

## Rotation model (core interaction)

The molecule carries a current **orientation quaternion** `q` (a rotation about
its center of mass), applied to atoms, bonds, and markers alike via the model
pre-transform `model_pre = translate(center) · q.toMat4() · translate(-center)`.
This replaces the time-based turntable matrix.

On selection change:

1. Take the selected open point's outward unit direction `dir` (in the
   molecule's local frame, from `OpenBondPoint.direction`).
2. Compute `q_target = rotationBetween(dir, +Z)` — the shortest-arc rotation
   mapping `dir` onto the camera-facing axis (+Z, toward the camera). Shortest
   arc inherently minimizes roll, matching the spec's "roll resolved by
   minimizing rotation."
3. Record `q_start = q` (current orientation) and start a ~300 ms timer.
4. Each frame, `q = slerp(q_start, q_target, ease(t))` where `t` goes 0→1 over
   the duration and `ease` is smoothstep (ease-in-out). When `t` reaches 1, `q`
   rests at `q_target`.

**Re-targeting:** if the selection changes mid-animation, set `q_start =` the
current (partially-slerped) `q`, set the new `q_target`, and reset the timer.
This interrupts smoothly rather than queuing inputs.

Sign note: "+Z faces the camera" assumes the camera sits on +Z looking toward
the origin (as the renderer's `viewMatrix` does). If, on first run, selecting a
point turns it *away* from the camera, flip the target axis to −Z. This is the
one thing to confirm visually.

## Open-bond-point markers

Open points render as small bright spheres (reusing the existing instanced
sphere pipeline — markers are simply another per-instance buffer), positioned at
`parent.position + dir · marker_offset` (e.g. `marker_offset ≈ 0.6`). Colors:

- **Unselected:** a dim cool color (e.g. desaturated cyan).
- **Selected:** larger radius, brighter, with a gentle scale **pulse**
  (`scale = base · (1 + 0.15·sin(time·ω))`).

Marker instances are repacked each frame (there are only a handful) so the pulse
and selection animate. Markers share the molecule's `model_pre`, so they rotate
with it; depth-tested normally against atoms/bonds.

## Architecture / files

### New, pure, TDD'd

- `src/quaternion.zig` — `Quaternion { w, x, y, z }`: `identity`,
  `fromAxisAngle(axis, angle)`, `mul`, `normalize`, `slerp(a, b, t)` (shortest
  path), `rotateVec(q, v)`, `toMat4()` (column-major, matching `Mat4`), and
  `rotationBetween(from, to)` (shortest-arc unit `from`→`to`, with the
  antiparallel case handled via an arbitrary perpendicular axis).
- `src/navigation.zig` — pure helpers:
  - `cycle(index: usize, len: usize, dir: enum { prev, next }) usize` (wrapping).
  - `targetOrientation(dir: Vec3) Quaternion` = `rotationBetween(dir, +Z)`.

### Modified

- `src/render/scene.zig` — add
  `openPointInstances(allocator, molecule, selected: usize, pulse: f32) ![]Instance`
  producing one marker instance per open point (selected one scaled up by
  `pulse` and given the bright color). Reuses the `Instance` layout.
- `src/render/gpu.zig` — add a marker instance buffer (`uploadMarkers`) and a
  third `drawIndexed` over the sphere mesh in `renderFrame`, after atoms/bonds,
  using the same pipeline.
- `src/main.zig` — replace the example-browser/turntable loop with the sandbox:
  build + settle a single Tetra; compute its open points; hold selection state;
  on Left/Right update selection and re-target the orientation; each frame
  advance the slerp, repack markers (pulse), set `model_pre` from `q`, and draw
  atoms + bonds + markers. Camera framed once (molecule is static in this plan).

### Unchanged / reused

`molecule.openBondPoints`, `mat4.zig`, `camera.zig`, `mesh.zig`,
`atom_style.zig`, the GPU pipeline, the window/occlusion handling.

## Testing strategy & definition of done

**TDD'd:**
- `Quaternion`: `fromAxisAngle` + `rotateVec` rotate a known vector; `mul`
  composes rotations; `slerp(a,b,0)=a`, `slerp(a,b,1)=b`, midpoint is unit-norm;
  `rotationBetween(from,to)` applied to `from` yields `to` (incl. parallel and
  antiparallel cases); `toMat4` agrees with `rotateVec` on sample vectors.
- `navigation.cycle`: next/prev wrap correctly over N (incl. N=1).
- `navigation.targetOrientation`: rotating the input dir by the result yields +Z.
- `scene.openPointInstances`: one instance per open point; the selected index is
  scaled larger than the others; positions are at `parent + dir·offset`.

**Manual (visual):**
- `zig build run` opens on a single Tetra with four markers, one highlighted.
- Left/Right move the highlight; the molecule smoothly rotates so the selected
  point swings to the front and faces the camera; re-pressing mid-animation
  retargets smoothly. The selected marker pulses. Escape/Cmd-W quit; survives
  occlusion/tab-away (existing handling).

**Definition of done:** all CPU tests green under `zig build test`, and the
sandbox runs with correct, smooth bond-point navigation verified by eye.

## Risks / unknowns

- **Camera-facing sign** (+Z vs −Z) — confirm on first run; one-line flip.
- **Slerp shortest path** — must negate one quaternion when their dot is
  negative, or the molecule may spin the long way around. Covered by a test
  (midpoint stays close to both endpoints) and by visual check.
- Marker offset/size are tuning values; adjust by eye so markers read clearly
  without overlapping atoms.

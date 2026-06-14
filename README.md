# Biome: Molecular

A 3D molecular-building game written in Zig with a custom WebGPU renderer. You
build molecules by placing atoms on open bond points; simplified molecular
forces (spring bonds, angle preferences, steric repulsion) cause the structure
to fold into 3D shapes.

This repository currently contains:

- **Headless core** — the data model (atoms, bonds, molecule), bond-point
  geometry, and the folding physics engine. Pure logic, fully unit-tested.
- **Renderer** — a native macOS WebGPU renderer that draws molecules as lit
  spheres (atoms) and cylinders (bonds).
- **Sandbox** — the app opens on a single Tetra at the origin. You navigate to
  an atom, drill into one of its open bond points, and place a new atom there
  with a live ghost preview; the molecule re-folds via the physics engine.

Puzzle mode is planned for future work. (The earlier example-browser was a
renderer stepping-stone; its molecule builders remain as test fixtures in
`examples.zig`.)

## Prerequisites

- **macOS on Apple Silicon (aarch64).** The renderer targets Metal via
  wgpu-native; only macOS is built/tested today. (The headless core is
  platform-independent.)
- **Zig 0.14.0.** Exactly this version (the build and code target the 0.14 API).
- **GLFW** for windowing:
  ```sh
  brew install glfw
  ```
  The build expects it at `/opt/homebrew/opt/glfw` (the Homebrew default).
- **wgpu-native** is fetched automatically as a Zig package dependency
  (pinned in `build.zig.zon` to a specific release); no manual install needed.
  The first build downloads it.

## Build, test, run

```sh
# Run the headless unit tests (data model, geometry, physics, renderer math).
zig build test

# Launch the renderer (the example browser).
zig build run
```

`zig build test` requires no GPU or GLFW; only the executable links the native
graphics dependencies.

## Controls

Building a molecule is a two-level select, then place:

| Input | Action |
|-------|--------|
| **Arrow keys** | Select an **atom** — rotates the nearest atom in that screen direction to the front (the selected atom pulses) |
| **D** | Drill into the selected atom's **open bond points** — cycles them (the active node pulses); an arrow returns to atom selection |
| **S** | After D: enter **placement** (a translucent ghost atom appears and the molecule re-folds). Press **S** again to scroll the atom type to place |
| **F** | Finalize placement (the ghost becomes a real atom) |
| **A** | Cancel placement (remove the ghost; the molecule relaxes back) |
| **Escape** / **Cmd-W** / close | Quit |

The camera is fixed and frames the molecule; the molecule rotates (it doesn't
orbit). Placement swings to a 3/4 view; same-type atoms are drawn in slightly
varied hues so duplicates are distinguishable.

## Project layout

```
src/
  math.zig        Vec3 + rotation helpers
  mat4.zig        4x4 matrices (view/projection/model)
  atom.zig        Atom, AtomType, preferred angles
  bond.zig        Bond
  constants.zig   physics tuning constants
  geometry.zig    open bond-point direction computation
  molecule.zig    Molecule container (atoms, bonds, open points)
  physics.zig     spring/angle/repulsion forces, damped Verlet integration
  examples.zig    the built-in example molecules
  render/         meshes, camera, instance packing, WGSL shader, wgpu renderer
  platform/       GLFW window + macOS CAMetalLayer surface glue
  main.zig        the example-browser application
```

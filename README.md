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
- **Sandbox navigation** — the app opens on a single Tetra at the origin with
  its open bond points shown as markers. You cycle the selected point with the
  arrow keys and the molecule rotates to bring it to face the camera.

Atom placement, the radial menu, and puzzle mode are planned for future work and
are not yet implemented. (The earlier example-browser was a renderer
stepping-stone; its molecule builders remain as test fixtures in `examples.zig`.)

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

| Input | Action |
|-------|--------|
| **Left / Right arrows** | Select the previous / next open bond point; the molecule rotates to bring it to face the camera |
| **Escape** or **Cmd-W** | Quit |
| Window close button | Quit |

The selected open bond point is shown as a larger, brighter, gently pulsing
marker. The camera is fixed and frames the molecule; the molecule rotates
(it doesn't orbit). Selecting a point slerps the molecule's orientation over
~300 ms so the chosen point swings to the front.

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

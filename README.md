# Biome: Molecular

A 3D molecular-building game written in Zig with a custom WebGPU renderer. You
build molecules by placing atoms on open bond points; simplified molecular
forces (spring bonds, angle preferences, steric repulsion) cause the structure
to fold into 3D shapes.

This repository currently contains:

- **Headless core** — the data model (atoms, bonds, molecule), bond-point
  geometry, and the folding physics engine. Pure logic, fully unit-tested.
- **Renderer** — a native macOS WebGPU renderer that displays settled molecules
  as lit spheres (atoms) and cylinders (bonds), with a small library of example
  molecules you can scroll through (a "turntable" example browser).

Navigation, atom placement, the radial menu, and puzzle mode are planned for
future work and are not yet implemented.

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
| **Left / Right arrows** | Switch to the previous / next example molecule (wraps around) |
| **Escape** or **Cmd-W** | Quit |
| Window close button | Quit |

The selected molecule's name and index (e.g. `Branched blob (5/6)`) is shown in
the window title bar. Each molecule is physics-settled at startup and slowly
rotates (a turntable) so you can see its shape from all sides; the camera
auto-frames each one.

## Example molecules

1. **Methane** — a tetrahedral atom capped with four terminal atoms.
2. **Linear chain** — six linear atoms in a row.
3. **Trigonal star** — a trigonal atom with three terminal caps (flat triangle).
4. **Ethane-like** — two tetrahedral atoms bonded, the rest capped.
5. **Branched blob** — a tetrahedral center with four tetrahedral arms, all capped.
6. **Trigonal sheet** — a trigonal center with three trigonal arms, all capped.

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

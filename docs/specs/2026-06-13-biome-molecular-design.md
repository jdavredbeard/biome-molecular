# Biome: Molecular

A 3D molecular building game written in Zig with WebGPU rendering. You build molecules by navigating open bond points and placing atoms. Simplified molecular forces (spring bonds + angle preferences) cause the molecule to fold into complex 3D shapes. The core interaction is rotating the molecule by selecting bond points -- the molecule spins to bring your selection to the front.

## Modes

- **Sandbox** -- build freely, watch it fold. No win condition, no constraints. The fun is building and watching the physics. The game starts with a single Tetra atom at the origin, with its 4 open bond points visible. The player immediately begins navigating and placing.
- **Puzzle (v2)** -- achieve a target shape with a given set of atoms. Layered on once sandbox feels good.

## Atoms

Four types, named to evoke chemistry without simulating it:

| Type | Bond Points | Preferred Angle | Description |
|------|-------------|-----------------|-------------|
| Mono | 1 | n/a | Terminal node. Caps a bond. Small sphere. |
| Linear | 2 | 180 degrees | Straight connector. Two bonds pointing opposite directions. |
| Trigonal | 3 | 120 degrees | Flat triangle. Three bonds in a plane, equally spaced. |
| Tetra | 4 | 109.5 degrees | 3D tetrahedral geometry. Four bonds pointing toward the vertices of a tetrahedron. |

Each atom type has a distinct visual size and color so the molecule's structure is readable at a glance.

### Open Bond Points

When an atom is placed, any bond points not yet connected to another atom are **open**. Open bond points are the attachment sites for new atoms. They are rendered as small highlighted markers extending from the atom at the preferred angles.

## Physics

### Bond Springs

Each bond between two atoms acts as a spring:

- **Rest length** -- the natural distance between bonded atoms. All bonds share the same rest length (simplification).
- **Spring force** -- when compressed below rest length, atoms repel. When stretched beyond, atoms attract. Force is proportional to displacement (Hooke's law): `F = -k * (distance - rest_length)`.

### Angle Forces

Each atom pushes its bonds toward preferred angles:

- A Linear atom pushes its two bonds toward 180 degrees apart.
- A Trigonal atom pushes its three bonds toward 120 degrees in a plane.
- A Tetra atom pushes its four bonds toward 109.5 degrees (tetrahedral).
- A Mono atom has no angle preference (only one bond).

For each pair of bonds (i, j) at an atom, compute the angle between them. The restoring force is applied as a linear force on the bonded neighbor atoms, perpendicular to each bond direction:

```
angle = acos(dot(bond_i, bond_j) / (|bond_i| * |bond_j|))
delta = angle - preferred_angle
magnitude = -k_angle * delta

// Force is applied perpendicular to each bond, in the plane of the two bonds
// This pushes neighbor atoms apart (if angle too small) or together (if too large)
perp_i = normalize(bond_j - bond_i * dot(bond_j, bond_i) / |bond_i|^2)
perp_j = normalize(bond_i - bond_j * dot(bond_i, bond_j) / |bond_j|^2)

force_on_neighbor_i = perp_i * magnitude / |bond_i|
force_on_neighbor_j = perp_j * magnitude / |bond_j|
```

This is the standard harmonic angle potential used in molecular dynamics. The force is applied to the neighbor atoms (not as torque on a rigid body), which is compatible with Verlet particle integration. This is what causes folding -- when you add a new atom, its angle forces push on neighbors, which push on their neighbors, rippling through the molecule.

### Repulsion

Non-bonded atoms that get too close repel each other (steric repulsion). This prevents the molecule from collapsing into itself:

- `F_repel = c / distance^2` when `distance < repulsion_threshold`
- No force (attraction or repulsion) between non-bonded atoms when `distance >= repulsion_threshold`.

### Simulation

After each atom placement, the molecule runs a physics simulation to settle into equilibrium:

- **Integration method** -- Verlet integration with damping. Simple, stable, good for spring systems.
- **Damping** -- velocity is multiplied by a damping factor (e.g., 0.98) each step to prevent perpetual oscillation. The molecule should settle, not bounce forever.
- **Animated** -- the folding plays out over multiple frames so the player can watch the molecule reshape. Not instant.
- **No gravity** -- the molecule floats in empty space.
- **Convergence** -- simulation runs until the total kinetic energy drops below a threshold, then stops. The molecule is at rest and the player can navigate again.

### Tuning Constants

These values will need tuning through playtesting:

| Constant | Description | Starting Value |
|----------|-------------|----------------|
| `k_spring` | Bond spring stiffness | 10.0 |
| `rest_length` | Bond rest length | 1.0 |
| `k_angle` | Angle correction stiffness | 5.0 |
| `k_repel` | Non-bonded repulsion strength | 2.0 |
| `repulsion_threshold` | Distance below which repulsion activates | 0.8 |
| `damping` | Velocity damping per step | 0.98 |
| `convergence_threshold` | Kinetic energy below which simulation stops | 0.001 |
| `dt` | Simulation timestep | 0.016 (60Hz) |

## Navigation & UI

### Core Interaction

The molecule is always centered on screen. The camera is fixed -- the molecule rotates, not the camera. The player navigates by cycling through open bond points. Selecting a bond point rotates the whole molecule so that point faces the camera.

### Controls

| Key | Action |
|-----|--------|
| Left/Right arrows | Cycle through open bond points. The molecule smoothly rotates to bring the selected point to the front. |
| Enter/Space | Open radial menu to place an atom at the selected bond point. |
| Escape | Close radial menu without placing. |

### Open Bond Point Traversal

Arrow keys cycle through all open bond points across the entire molecule. The traversal order is spatial -- left/right moves to the nearest open bond point in that direction relative to the current view. This keeps navigation intuitive as the molecule rotates.

When the selected bond point changes, the molecule smoothly interpolates its rotation (slerp on a quaternion) to bring the new selection to the front. The rotation animation should be fast but visible (roughly 300ms).

### Visual Feedback

- **Atoms** -- rendered as spheres. Size and color vary by type.
- **Bonds** -- rendered as cylinders connecting atom centers.
- **Open bond points** -- rendered as small glowing markers (e.g., translucent spheres or halos) at the position where a new atom would attach, extending from the parent atom at the preferred angle.
- **Selected bond point** -- brighter, pulsing, larger than unselected open points. Visually distinct so it's immediately clear where you're about to place.
- **Background** -- dark, minimal. The molecule is the focus.

### Radial Menu

When the player presses Enter/Space at a selected bond point:

- A radial menu appears centered on the selected bond point.
- Shows the 4 atom types arranged in a circle: Mono, Linear, Trigonal, Tetra.
- Each option shows the atom's name, a small icon/preview of its shape, and its bond count.
- Arrow keys or mouse to select. Enter to confirm. Escape to cancel.
- After placing, the menu closes and the molecule begins its physics simulation (animated folding).

### Molecule Rotation

The rotation model:

- The molecule's center of mass is always at the screen center.
- When a new bond point is selected, compute the quaternion rotation that would bring that point to the front (facing the camera along the negative Z axis). Roll is resolved by minimizing rotation from the current orientation (shortest-path slerp), which prevents disorienting spins.
- Interpolate from the current rotation to the target using slerp over ~300ms.
- During rotation animation, input is queued. When the rotation completes, queued bond point selections are processed using the view orientation at that moment (post-rotation). "Left" is always computed relative to the resting view, never mid-animation.

## Rendering

### Tech Stack

- **Zig** -- all game logic, physics, and rendering code.
- **WebGPU** via `wgpu-native` -- GPU rendering API. Native desktop target (Linux, macOS, Windows). Potential WASM+WebGPU browser target later.
- **No engine** -- custom renderer. The scene is simple enough (spheres, cylinders, a menu) that a full engine is unnecessary.

### Render Pipeline

1. **Atom pass** -- instanced rendering of spheres. Each atom is an instance with position, radius, and color. Use a sphere mesh (icosphere or UV sphere) rendered with basic Phong lighting.
2. **Bond pass** -- instanced rendering of cylinders. Each bond is an instance with start position, end position, and radius. Oriented cylinder mesh.
3. **Open bond point pass** -- instanced small spheres with additive blending for the glow effect. Selected point gets a pulsing scale animation.
4. **UI pass** -- radial menu rendered as screen-space quads with text. Only visible when menu is open.

### Lighting

Simple 3-point lighting:
- Key light (warm, upper left)
- Fill light (cool, lower right, dimmer)
- Rim light (behind, for edge definition)

No shadows needed initially. Atoms and bonds get enough depth cue from Phong shading.

### Camera

Fixed perspective camera:
- Position: `(0, 0, z)` where `z` is computed from the molecule's bounding sphere radius: `z = bounding_radius * 2.5` (padding factor). Minimum `z = 5.0` so the camera doesn't clip into a single atom.
- Look-at: origin (molecule center of mass).
- Auto-zoom: `z` is recomputed after each placement settles (not during physics simulation). Smooth interpolation to new `z` over ~500ms.

## Data Model

### Atom

```zig
const Atom = struct {
    position: Vec3,
    velocity: Vec3,
    atom_type: AtomType,
    bonds: BoundedArray(BondId, 4), // max 4 bonds (Tetra)
    id: AtomId,
};

const AtomType = enum {
    mono,     // 1 bond, no angle pref
    linear,   // 2 bonds, 180 deg
    trigonal,  // 3 bonds, 120 deg
    tetra,    // 4 bonds, 109.5 deg
};
```

### Bond

```zig
const Bond = struct {
    atom_a: AtomId,
    atom_b: AtomId,
    id: BondId,
};
```

### Open Bond Point

```zig
const OpenBondPoint = struct {
    parent_atom: AtomId,
    direction: Vec3, // unit vector from parent atom, at preferred angle
    id: BondPointId,
};
```

Open bond points are recomputed whenever the molecule changes. The algorithm for computing open directions given existing bonds:

**0 existing bonds** (only possible for the first atom): use the canonical directions for the atom type:
- Mono: `+Z`
- Linear: `+Z`, `-Z`
- Trigonal: three vectors in the XZ plane at 120 degrees
- Tetra: four vectors pointing toward the vertices of a regular tetrahedron

**1 existing bond**: align the canonical frame so that the first canonical direction matches the existing bond direction. The remaining directions follow by rotating the canonical frame. For atom types with a rotational degree of freedom around the bond axis (Trigonal with 1 bond, Tetra with 1 bond), choose the rotation that keeps one open point as close to "up" (world +Y) as possible. This prevents arbitrary spinning.

**2+ existing bonds**: the open directions are fully determined by the existing bond directions and the preferred angles. Compute the directions that satisfy the angle constraints relative to all existing bonds. For Tetra with 2 bonds, the 2 remaining directions are the two vectors that form the correct tetrahedral angles with both existing bonds.

### Molecule

```zig
const Molecule = struct {
    atoms: ArrayList(Atom),
    bonds: ArrayList(Bond),
    rotation: Quaternion, // current world rotation
    target_rotation: Quaternion, // rotation target for animation

    fn openBondPoints(self: *Molecule) []OpenBondPoint { ... }
    fn addAtom(self: *Molecule, bond_point: BondPointId, atom_type: AtomType) void { ... }
    fn simulate(self: *Molecule, dt: f32) bool { ... } // returns true when settled
};
```

## Game Loop

```
1. Process input
   - Arrow keys: select next/prev open bond point, set target rotation
   - Enter/Space: open radial menu (if bond point selected)
   - Radial menu input: select atom type, place atom
2. Update
   - Interpolate molecule rotation toward target (slerp)
   - If physics active: run simulation step(s)
   - Recompute open bond points if molecule changed
3. Render
   - Clear frame
   - Render atoms, bonds, open bond points
   - Render UI (radial menu if open)
   - Present frame
```

### Physics Substeps

The physics simulation may need multiple substeps per frame for stability. Run `N` simulation steps per frame (e.g., 4) with `dt / N` timestep each, then render once. This keeps the simulation stable without tying it to frame rate.

## Implementation Plan

### Phase 1: Window and Renderer

- Set up Zig project with wgpu-native dependency
- Create a window (via platform-specific code or a minimal windowing lib like GLFW via Zig)
- Initialize WebGPU device, surface, swap chain
- Render a single colored sphere (proof of life)
- Add basic Phong lighting
- Render a cylinder between two points

### Phase 2: Molecule Data Model

- Implement Atom, Bond, OpenBondPoint, Molecule structs
- Place a single Tetra atom at the origin
- Compute and display its 4 open bond points
- Render the molecule (1 atom, 4 open points)

### Phase 3: Navigation

- Implement bond point selection (arrow keys)
- Implement molecule rotation (quaternion slerp) to face selected point
- Visual feedback: highlight selected bond point

### Phase 4: Placement

- Implement radial menu (screen-space rendering)
- Place atoms at selected bond points
- Update molecule data model (add atom, add bond, recompute open points)
- Initial position for new atom: at the bond point's direction * rest_length from parent

### Phase 5: Physics

- Implement spring forces between bonded atoms
- Implement angle forces per atom type
- Implement non-bonded repulsion
- Verlet integration with damping
- Animated settling after each placement
- Convergence detection

### Phase 6: Polish

- Auto-zoom camera as molecule grows
- Atom type colors and sizing
- Smooth animations throughout
- Performance profiling (large molecules)

### Phase 7: Puzzle Mode (v2)

- Target shape definition format
- Shape comparison / scoring algorithm
- Puzzle UI (show target, show progress)
- Puzzle set / level progression

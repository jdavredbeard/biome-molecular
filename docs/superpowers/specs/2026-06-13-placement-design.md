# Biome: Molecular — Atom Placement (ghost preview)

## Overview

Closes the build-a-molecule loop. From the sandbox's navigate mode (where the
player selects an open bond point and the molecule rotates to face it), the
player enters a **place mode** that shows a greyed-out **ghost atom** at the
selected point, previewing how the molecule folds with it. The player cycles
the ghost's atom type, then either finalizes (the atom becomes real) or cancels
(the ghost is removed and the molecule relaxes back).

This builds on the merged navigation work and reuses the physics engine
(`simulate`) for the live re-fold and the renderer's instanced sphere/cylinder
pipeline for the ghost.

## Goals

- Add a **place mode** with a live ghost-atom preview at the selected point.
- Cycle the ghost's type (Mono/Linear/Trigonal/Tetra), updating its size and the
  greyed markers showing its onward open bond points.
- **Finalize** to commit the atom; **cancel** to remove it. The existing molecule
  animates its fold to accommodate (on add) or relax (on cancel).
- Keep the physics/data-model changes pure and unit-tested; verify the modal
  interaction and animation by running.

## Non-goals (deferred)

- A radial menu or any text/labels (the ghost preview replaces the radial menu).
- Alpha-blended transparency for the ghost (we use a dim grey solid color).
- Undo beyond the in-progress ghost; multi-atom history.
- Per-type fold differences for a freshly placed atom (physically a single-bond
  atom folds identically across types — only its size and onward open-point count
  differ; this is intended).
- Puzzle mode; spatial traversal; auto-zoom.

## Interaction model — two modes

The sandbox starts in **Navigate mode** (existing). Placement adds **Place mode**.

| Key | Navigate mode | Place mode |
|-----|---------------|------------|
| Left / Right | cycle selected open bond point (rotate to face it) | cycle the ghost atom type |
| **S** | enter Place mode | — |
| **F** | — | **finalize** (ghost becomes a real atom) |
| **A** | — | **cancel** (remove ghost, return to Navigate) |
| Escape / Cmd-W | quit | quit |

## Ghost preview behavior

- **Enter Place (S):** add a ghost atom of the default type (**Tetra**) at the
  selected open point — placed at `parent.position + direction · rest_length`,
  bonded to the parent — then run the physics so the molecule **animates its
  fold** to accommodate the new atom. The ghost atom renders dim grey; its
  onward open bond points render as dim-grey markers (showing branch potential).
- **Cycle type (Left/Right):** change the ghost atom's type. Its size/color and
  its onward grey markers update **instantly** — no re-fold, because a single-bond
  atom settles identically regardless of type (spring/repulsion are
  type-independent and the atom's own angle preference is inactive with one bond).
- **Cancel (A):** remove the ghost atom and its bond; the molecule **animates
  back** (relaxes) to its pre-ghost shape. Return to Navigate mode.
- **Finalize (F):** the ghost becomes a normal atom (rendered in its type color).
  Recompute the open bond points and set the selection to the **first open point
  on the newly placed atom** (so the player keeps building outward); if the atom
  has no open points (Mono), reset the selection to index 0. Return to Navigate
  mode. No re-fold is needed (already settled with the atom).

During Place mode, the Navigate-mode selection markers are hidden; only the
ghost's onward markers show.

## Physics & rendering details

- Animated re-fold (`simulate` advanced over frames) runs only on **enter Place**
  (molecule absorbs the new atom) and **cancel** (molecule relaxes). Type cycling
  and finalize need no re-fold.
- The ghost's "greyed-out" look is a dim grey color through the existing opaque
  pipeline — no alpha-blend pass. The ghost atom body and its onward markers both
  use this grey.
- Marker rendering reuses the existing marker instance buffer: in Navigate mode it
  holds the selection markers (as today); in Place mode it holds the ghost's
  onward markers. Atom instances are re-uploaded when the ghost is added, its type
  changes, or it's finalized (so its color/size reflects ghost-grey vs type).
- The molecule's orientation quaternion is unchanged by placement (the selected
  point stays facing the camera); only atom positions move as it re-folds.

## Architecture / files

### Core (pure, TDD'd)

- `src/molecule.zig` — add **`removeLastAtom(self)`**: pop the most recently
  added atom and its (single) bond, removing that bond id from the parent atom's
  bond list. This is the ghost-cancel primitive (and a natural "undo last
  placement"). Asserts there is at least one atom; handles the last atom having
  0 or 1 bonds.

### Renderer (pure part TDD'd)

- `src/render/scene.zig` — add **`ghostMarkerInstances(allocator, mol, ghost_id)`**:
  dim-grey marker instances for the open bond points whose `parent_atom ==
  ghost_id`, positioned at `parent + dir · marker_offset`. (The selected-marker
  scaling logic in `openPointInstances` is not used here — all ghost markers are
  uniform.) A `ghost_color` constant is added.

### App (manual verification)

- `src/main.zig` — extend the loop with a `Mode { navigate, place }` state
  machine and ghost lifecycle:
  - Navigate: existing behavior; **S** → add ghost (Tetra), start a settle
    animation, switch to Place, set `ghost_type`.
  - Place: **Left/Right** change `ghost_type` (mutate the ghost atom's type,
    re-upload atoms + ghost markers); **A** → `removeLastAtom`, start a settle
    animation, switch to Navigate; **F** → recolor the atom to its type
    (re-upload atoms), recompute open points, set selection to the new atom's
    first open point (or 0), switch to Navigate.
  - The settle animation: while active, advance `simulate` each frame and
    re-upload atom + bond instances until settled (then stop). Input that changes
    the molecule is accepted between settles; cycling type during a settle is fine
    (visual only).

The renderer's GPU module already supports re-uploading atom/bond/marker
instance buffers; no pipeline changes.

## Testing strategy & definition of done

**TDD'd:**
- `removeLastAtom`: after `addFirstAtom` + `addAtom`, calling it restores the
  atom count, bond count, and the parent's bond-list length to their pre-add
  values; the parent no longer references the removed bond.
- `ghostMarkerInstances`: for a tetra parent + a freshly added ghost atom of a
  given type, returns exactly the ghost atom's open-point count (Mono 0, Linear 1,
  Trigonal 2, Tetra 3), all using `ghost_color`, positioned `marker_offset` from
  the ghost.

**Manual (visual):**
- `zig build run`: from the Tetra sandbox, **S** shows a grey ghost at the
  selected point and the molecule folds to fit; **Left/Right** change the ghost's
  size and its grey onward markers; **A** removes it and the molecule relaxes
  back; **F** commits it (now colored) and the selection advances to the new
  atom so you can keep building. Building several atoms in a row works and folds
  sensibly. Escape/Cmd-W quit; survives tab-away.

**Definition of done:** all CPU tests green under `zig build test`, and the
full build-a-molecule loop (navigate → place → cycle → finalize/cancel, repeat)
works smoothly as verified by eye.

## Risks / unknowns

- **Settle animation pacing** — the existing `simulate` runs substeps per call;
  re-folding over frames should look smooth, but the per-frame instance re-upload
  during settling is new in this loop. Tunable; verify by eye.
- **Selection-after-finalize** indexing — recomputed open points must be queried
  consistently (same ordering as the markers) so the post-finalize selection
  lands on the intended point. Covered by re-querying once and indexing.
- **removeLastAtom invariants** — only valid for removing the just-added ghost
  (the last atom, with its single bond). Documented as such; not a general
  arbitrary-atom delete.

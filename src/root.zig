//! Biome: Molecular — headless core library root.
//! Re-exports the public API and aggregates every module's tests.

pub const math = @import("math.zig");
pub const atom = @import("atom.zig");
pub const bond = @import("bond.zig");
pub const constants = @import("constants.zig");
pub const geometry = @import("geometry.zig");
pub const molecule = @import("molecule.zig");
pub const physics = @import("physics.zig");
pub const mat4 = @import("mat4.zig");
pub const mesh = @import("render/mesh.zig");

test {
    // Pull every module's tests into the `zig build test` run.
    _ = math;
    _ = atom;
    _ = bond;
    _ = constants;
    _ = geometry;
    _ = molecule;
    _ = physics;
    _ = mat4;
    _ = mesh;
}

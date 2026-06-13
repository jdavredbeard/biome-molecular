const std = @import("std");
const Vec3 = @import("../math.zig").Vec3;

/// GPU-ready vertex: position + normal, tightly packed f32x3 each.
pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []u32,

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

fn vert(p: Vec3) Vertex {
    const n = p.normalize();
    return .{ .position = .{ n.x, n.y, n.z }, .normal = .{ n.x, n.y, n.z } };
}

/// Unit icosphere centered at the origin. `subdivisions` of 0 => base
/// icosahedron (20 faces); each level multiplies the face count by 4. Vertices
/// are emitted per-triangle (no dedup); since normal == position on a unit
/// sphere there is no shading seam.
pub fn icosphere(allocator: std.mem.Allocator, subdivisions: u5) !Mesh {
    const t: f32 = (1.0 + @sqrt(5.0)) / 2.0;
    const base = [_]Vec3{
        Vec3.init(-1, t, 0), Vec3.init(1, t, 0),  Vec3.init(-1, -t, 0), Vec3.init(1, -t, 0),
        Vec3.init(0, -1, t), Vec3.init(0, 1, t),  Vec3.init(0, -1, -t), Vec3.init(0, 1, -t),
        Vec3.init(t, 0, -1), Vec3.init(t, 0, 1),  Vec3.init(-t, 0, -1), Vec3.init(-t, 0, 1),
    };
    const faces = [_][3]usize{
        .{ 0, 11, 5 }, .{ 0, 5, 1 },  .{ 0, 1, 7 },   .{ 0, 7, 10 }, .{ 0, 10, 11 },
        .{ 1, 5, 9 },  .{ 5, 11, 4 }, .{ 11, 10, 2 }, .{ 10, 7, 6 }, .{ 7, 1, 8 },
        .{ 3, 9, 4 },  .{ 3, 4, 2 },  .{ 3, 2, 6 },   .{ 3, 6, 8 },  .{ 3, 8, 9 },
        .{ 4, 9, 5 },  .{ 2, 4, 11 }, .{ 6, 2, 10 },  .{ 8, 6, 7 },  .{ 9, 8, 1 },
    };

    var tris = std.ArrayList([3]Vec3).init(allocator);
    defer tris.deinit();
    for (faces) |f| try tris.append(.{ base[f[0]], base[f[1]], base[f[2]] });

    var level: u5 = 0;
    while (level < subdivisions) : (level += 1) {
        var next = std.ArrayList([3]Vec3).init(allocator);
        for (tris.items) |tri| {
            const a = tri[0];
            const b = tri[1];
            const c = tri[2];
            const ab = a.add(b).scale(0.5);
            const bc = b.add(c).scale(0.5);
            const ca = c.add(a).scale(0.5);
            try next.append(.{ a, ab, ca });
            try next.append(.{ ab, b, bc });
            try next.append(.{ ca, bc, c });
            try next.append(.{ ab, bc, ca });
        }
        tris.deinit();
        tris = next;
    }

    const vertices = try allocator.alloc(Vertex, tris.items.len * 3);
    const indices = try allocator.alloc(u32, tris.items.len * 3);
    for (tris.items, 0..) |tri, i| {
        vertices[i * 3 + 0] = vert(tri[0]);
        vertices[i * 3 + 1] = vert(tri[1]);
        vertices[i * 3 + 2] = vert(tri[2]);
        indices[i * 3 + 0] = @intCast(i * 3 + 0);
        indices[i * 3 + 1] = @intCast(i * 3 + 1);
        indices[i * 3 + 2] = @intCast(i * 3 + 2);
    }
    return .{ .vertices = vertices, .indices = indices };
}

test "icosphere subdiv 0 has 20 triangles, all vertices unit length, normal == position" {
    var m = try icosphere(std.testing.allocator, 0);
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 20 * 3), m.indices.len);
    for (m.vertices) |v| {
        const p = Vec3.init(v.position[0], v.position[1], v.position[2]);
        try std.testing.expectApproxEqAbs(@as(f32, 1), p.length(), 1e-4);
        const n = Vec3.init(v.normal[0], v.normal[1], v.normal[2]);
        try std.testing.expect(n.approxEq(p, 1e-4));
    }
}

test "icosphere subdiv 2 quadruples triangle count per level" {
    var m = try icosphere(std.testing.allocator, 2);
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 20 * 16 * 3), m.indices.len); // 4^2 = 16
}

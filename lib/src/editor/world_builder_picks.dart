import 'dart:math' as math;

import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../splines/splines.dart';
import '../terrain/terrain.dart';
import '../tiles/tiles.dart';
import 'tool_parts.dart';

/// Where a ray from the eye meets the kit's pieces, exactly: a tile's
/// cell, a swept road's triangles, a terrain's ground. What picks them, and what is placed
/// and stacked on them; a ray through the gaps between them passes on
/// (an infinite distance), as through an arch.
final class WorldBuilderRayTest implements EntityRayTest, EntitySurfaceTest {
  const WorldBuilderRayTest();

  @override
  double? distanceTo(Entity entity, Ray3D ray) => surfaceHit(entity, ray)?.t;

  @override
  RayTriangleHit? surfaceHit(Entity entity, Ray3D ray) {
    final tiles = entity.getComponent<GridTiles3DComponent>();
    final sweep = entity.getComponent<SplineSweep3DComponent>();
    final terrain = entity.getComponent<Terrain3DComponent>();
    final transform = entity.getComponent<TransformComponent>();
    if ((tiles == null && sweep == null && terrain == null) ||
        transform == null) {
      return null;
    }
    final (toWorld, toLocal) = spaceOf(entity);
    if (toWorld.determinant() == 0) return null;
    // In its space, the direction left unscaled: the same t as the world's.
    final origin = Vector3.zero(), direction = Vector3.zero();
    toLocal.transformPointInto(ray.origin, origin);
    toLocal.transformDirectionInto(ray.direction, direction);

    RayTriangleHit? best;
    // Whether it knows its own shape yet: tiles once their library is in.
    var known = false;
    void consider(RayTriangleHit? hit) {
      if (hit != null && hit.t >= 0 && (best == null || hit.t < best!.t)) {
        best = hit;
      }
    }

    if (tiles != null && tiles.loaded != null) {
      known = true;
      consider(cellHit(tiles, origin, direction));
    }
    final spline = sweep?.spline ?? entity.getComponent<Spline3DComponent>();
    if (sweep != null && spline != null) {
      final mesh = SplineSweeper.meshFor(sweep, spline);
      if (mesh != null) {
        known = true;
        consider(
          RayTriangles.nearest(
            ModelGeometry(mesh.positions, mesh.indices),
            origin,
            direction,
          ),
        );
      }
    }
    if (terrain != null && terrain.loaded != null) {
      known = true;
      consider(groundHit(terrain, origin, direction));
    }
    final hit = best;
    if (hit == null) {
      return known ? RayTriangleHit(double.infinity, Vector3(0, -1, 0)) : null;
    }
    // Square to the surface in the world too, however unevenly the entity
    // is scaled: turned by the inverse's transpose.
    final normal = Vector3.zero();
    normalToWorld(toLocal, hit.normal, normal);
    if (normal.lengthSquared == 0) return null;
    return RayTriangleHit(hit.t, normal);
  }

  /// Where the ray from [origin] along [direction] (in its space) first
  /// meets [terrain]'s ground, and the ground's normal there: marched in
  /// half cells through the box its ground fills, then narrowed down.
  /// Holes let it through.
  static RayTriangleHit? groundHit(
    Terrain3DComponent terrain,
    Vector3 origin,
    Vector3 direction,
  ) {
    final data = terrain.loaded;
    if (data == null) return null;
    final cell = terrain.cellSize, start = terrain.origin;
    final reach = terrain.size;
    final (low, high) = data.heightRange;
    // The part of the ray inside the box the ground fills: over the square,
    // between its lowest and highest ground (+Y is down: up is -y).
    var t0 = 0.0, t1 = double.infinity;
    bool clip(double o, double d, double lo, double hi) {
      if (d.abs() < 1e-12) return o >= lo && o <= hi;
      var a = (lo - o) / d, b = (hi - o) / d;
      if (a > b) (a, b) = (b, a);
      if (a > t0) t0 = a;
      if (b < t1) t1 = b;
      return t0 <= t1;
    }

    if (!clip(origin.x, direction.x, start, start + reach) ||
        !clip(origin.z, direction.z, start, start + reach) ||
        !clip(origin.y, direction.y, -high - 1e-3, -low + 1e-3) ||
        !t1.isFinite) {
      return null;
    }
    // Above the ground is y + height < 0 (+Y is down).
    double above(double t) {
      final x = (origin.x + direction.x * t - start) / cell,
          z = (origin.z + direction.z * t - start) / cell;
      return origin.y + direction.y * t + data.heightAt(x, z);
    }

    // Whether the triangle of ground under the ray at [t] is left out: a
    // hole at any of its corners, the rule the terrain is drawn and solid
    // by. Each cell is split from its (i + 1, j) corner to its (i, j + 1).
    bool holeAt(double t) {
      final x = (origin.x + direction.x * t - start) / cell,
          z = (origin.z + direction.z * t - start) / cell;
      final last = data.resolution - 1;
      if (x < 0 || z < 0 || x > last || z > last) return false;
      final i = math.min(x.floor(), last - 1),
          j = math.min(z.floor(), last - 1);
      if (data.isHole(i + 1, j) || data.isHole(i, j + 1)) return true;
      return (x - i) + (z - j) <= 1
          ? data.isHole(i, j)
          : data.isHole(i + 1, j + 1);
    }

    final speed = direction.length;
    if (speed == 0) return null;
    final step = cell * 0.5 / speed;
    var t = t0, was = above(t);
    while (t < t1) {
      final next = math.min(t + step, t1);
      final now = above(next);
      if (was < 0 && now >= 0) {
        var lo = t, hi = next;
        for (var k = 0; k < 20; k++) {
          final mid = (lo + hi) / 2;
          if (above(mid) < 0) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        if (!holeAt(hi)) {
          final x = (origin.x + direction.x * hi - start) / cell,
              z = (origin.z + direction.z * hi - start) / cell;
          final dx =
              (data.heightAt(x + 0.5, z) - data.heightAt(x - 0.5, z)) / cell;
          final dz =
              (data.heightAt(x, z + 0.5) - data.heightAt(x, z - 0.5)) / cell;
          return RayTriangleHit(hi, Vector3(-dx, -1, -dz)..normalize());
        }
      }
      t = next;
      was = now;
    }
    return null;
  }

  /// The nearest of [tiles]' cells the ray from [origin] along
  /// [direction] (in their space) enters, and the face it enters by; a
  /// cell the ray starts in is passed over.
  ///
  /// The ray is walked cell by cell through the box the cells fill (a 3-D
  /// DDA), from where it enters that box: a look at the cells it passes,
  /// not at every cell of the grid.
  static RayTriangleHit? cellHit(
    GridTiles3DComponent tiles,
    Vector3 origin,
    Vector3 direction,
  ) {
    final size = tiles.loaded?.cellSize;
    if (size == null || size <= 0 || tiles.cells.isEmpty) return null;
    final (lx, ly, lz, hx, hy, hz) = _cellBounds(tiles);
    final ox = origin.x, oy = origin.y, oz = origin.z;
    final dx = direction.x, dy = direction.y, dz = direction.z;

    // Where the ray is inside the box the cells fill.
    var enter = double.negativeInfinity, exit = double.infinity;
    var enterAxis = -1;
    bool slab(int axis, double o, double d, double lo, double hi) {
      if (d.abs() < 1e-12) return o >= lo && o <= hi;
      var a = (lo - o) / d, b = (hi - o) / d;
      if (a > b) (a, b) = (b, a);
      if (a > enter) {
        enter = a;
        enterAxis = axis;
      }
      if (b < exit) exit = b;
      return enter <= exit;
    }

    if (!slab(0, ox, dx, lx * size, (hx + 1) * size) ||
        !slab(1, oy, dy, ly * size, (hy + 1) * size) ||
        !slab(2, oz, dz, lz * size, (hz + 1) * size) ||
        exit < 0) {
      return null;
    }

    // The first cell: where the ray comes into the box, or — starting in
    // it — the cell it starts in, which is passed over.
    final inside = enter < 0;
    var t = inside ? -1.0 : enter;
    var axis = inside ? -1 : enterAxis;
    final s = inside ? 0.0 : enter;
    int cellOf(double o, double d, int lo, int hi) =>
        ((o + d * s) / size).floor().clamp(lo, hi);
    var cx = cellOf(ox, dx, lx, hx),
        cy = cellOf(oy, dy, ly, hy),
        cz = cellOf(oz, dz, lz, hz);
    // A ray coming in through a face starts in the cell on its inner side.
    if (!inside) {
      if (enterAxis == 0) cx = dx > 0 ? lx : hx;
      if (enterAxis == 1) cy = dy > 0 ? ly : hy;
      if (enterAxis == 2) cz = dz > 0 ? lz : hz;
    }

    final stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
    final stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
    final stepZ = dz > 0 ? 1 : (dz < 0 ? -1 : 0);
    double next(int cell, int step, double o, double d) => step == 0
        ? double.infinity
        : ((cell + (step > 0 ? 1 : 0)) * size - o) / d;
    var tx = next(cx, stepX, ox, dx),
        ty = next(cy, stepY, oy, dy),
        tz = next(cz, stepZ, oz, dz);
    final ex = stepX == 0 ? double.infinity : size / dx.abs();
    final ey = stepY == 0 ? double.infinity : size / dy.abs();
    final ez = stepZ == 0 ? double.infinity : size / dz.abs();

    while (true) {
      if (t >= 0 &&
          axis >= 0 &&
          tiles.cells.containsKey(GridTiles3DComponent.keyOf(cx, cy, cz))) {
        final normal = Vector3.zero();
        final facing = switch (axis) {
          0 => dx > 0 ? -1.0 : 1.0,
          1 => dy > 0 ? -1.0 : 1.0,
          _ => dz > 0 ? -1.0 : 1.0,
        };
        switch (axis) {
          case 0:
            normal.x = facing;
          case 1:
            normal.y = facing;
          default:
            normal.z = facing;
        }
        return RayTriangleHit(t, normal);
      }
      if (tx <= ty && tx <= tz) {
        cx += stepX;
        t = tx;
        tx += ex;
        axis = 0;
      } else if (ty <= tz) {
        cy += stepY;
        t = ty;
        ty += ey;
        axis = 1;
      } else {
        cz += stepZ;
        t = tz;
        tz += ez;
        axis = 2;
      }
      if (!t.isFinite ||
          t > exit + 1e-9 ||
          cx < lx ||
          cx > hx ||
          cy < ly ||
          cy > hy ||
          cz < lz ||
          cz > hz) {
        return null;
      }
    }
  }

  // Each grid's cells' box, in cells, while its cells stay the same.
  static final Expando<(int, int, (int, int, int, int, int, int))> _bounds =
      Expando();

  /// The lowest and highest cell of [tiles] on each axis.
  static (int, int, int, int, int, int) _cellBounds(
    GridTiles3DComponent tiles,
  ) {
    final known = _bounds[tiles];
    if (known != null &&
        known.$1 == tiles.revision &&
        known.$2 == tiles.cells.length) {
      return known.$3;
    }
    var lx = 1 << 30, ly = 1 << 30, lz = 1 << 30;
    var hx = -(1 << 30), hy = -(1 << 30), hz = -(1 << 30);
    for (final key in tiles.cells.keys) {
      final c = GridTiles3DComponent.cellOf(key);
      if (c.x < lx) lx = c.x;
      if (c.y < ly) ly = c.y;
      if (c.z < lz) lz = c.z;
      if (c.x > hx) hx = c.x;
      if (c.y > hy) hy = c.y;
      if (c.z > hz) hz = c.z;
    }
    final box = (lx, ly, lz, hx, hy, hz);
    _bounds[tiles] = (tiles.revision, tiles.cells.length, box);
    return box;
  }
}

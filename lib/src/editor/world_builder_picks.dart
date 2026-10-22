import 'dart:math' as math;

import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../splines/spline_components.dart';
import '../splines/spline_sweep.dart';
import '../terrain/terrain_component.dart';
import '../tiles/grid_tiles.dart';

/// Where a ray from the eye meets the kit's pieces, exactly: a tile's
/// cell, a swept road's triangles, a terrain's ground. What picks them, and what is placed
/// and stacked on them; a ray through the gaps between them passes on
/// (an infinite distance), as through an arch.
final class WorldBuilderRayTest implements EntityRayTest, EntitySurfaceTest {
  const WorldBuilderRayTest();

  @override
  double? distanceTo(Entity entity, Ray3 ray) => surfaceHit(entity, ray)?.t;

  @override
  RayTriangleHit? surfaceHit(Entity entity, Ray3 ray) {
    final tiles = entity.getComponent<GridTiles3D>();
    final sweep = entity.getComponent<SplineSweep3D>();
    final terrain = entity.getComponent<Terrain3D>();
    final transform = entity.getComponent<TransformComponent>();
    if ((tiles == null && sweep == null && terrain == null) || transform == null) return null;
    final toWorld = Matrix4.identity();
    transform.localToWorldInto(toWorld);
    final toLocal = Matrix4.identity();
    if (toLocal.copyInverse(toWorld) == 0) return null;
    // In its space, the direction left unscaled: the same t as the world's.
    final origin = Vector3.zero(), direction = Vector3.zero();
    toLocal.transformPointInto(ray.origin, origin);
    toLocal.transformDirectionInto(ray.direction, direction);

    RayTriangleHit? best;
    // Whether it knows its own shape yet: tiles once their library is in.
    var known = false;
    void consider(RayTriangleHit? hit) {
      if (hit != null && hit.t >= 0 && (best == null || hit.t < best!.t)) best = hit;
    }

    if (tiles != null && tiles.loaded != null) {
      known = true;
      consider(cellHit(tiles, origin, direction));
    }
    final spline = sweep?.spline ?? entity.getComponent<Spline3D>();
    if (sweep != null && spline != null) {
      final mesh = SplineSweeper.meshFor(sweep, spline);
      if (mesh != null) {
        known = true;
        consider(RayTriangles.nearest(ModelGeometry(mesh.positions, mesh.indices), origin, direction));
      }
    }
    if (terrain != null && terrain.loaded != null) {
      known = true;
      consider(groundHit(terrain, origin, direction));
    }
    final hit = best;
    if (hit == null) return known ? RayTriangleHit(double.infinity, Vector3(0, -1, 0)) : null;
    final normal = Vector3.zero();
    toWorld.transformDirectionInto(hit.normal, normal);
    if (normal.lengthSquared == 0) return null;
    return RayTriangleHit(hit.t, normal..normalize());
  }

  /// Where the ray from [origin] along [direction] (in its space) first
  /// meets [terrain]'s ground, and the ground's normal there: marched in
  /// half cells through the box its ground fills, then narrowed down.
  /// Holes let it through.
  static RayTriangleHit? groundHit(Terrain3D terrain, Vector3 origin, Vector3 direction) {
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
      final x = (origin.x + direction.x * t - start) / cell, z = (origin.z + direction.z * t - start) / cell;
      return origin.y + direction.y * t + data.heightAt(x, z);
    }

    bool holeAt(double t) {
      final i = ((origin.x + direction.x * t - start) / cell).round(), j = ((origin.z + direction.z * t - start) / cell).round();
      return i >= 0 && j >= 0 && i < data.resolution && j < data.resolution && data.isHole(i, j);
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
          final x = (origin.x + direction.x * hi - start) / cell, z = (origin.z + direction.z * hi - start) / cell;
          final dx = (data.heightAt(x + 0.5, z) - data.heightAt(x - 0.5, z)) / cell;
          final dz = (data.heightAt(x, z + 0.5) - data.heightAt(x, z - 0.5)) / cell;
          return RayTriangleHit(hi, Vector3(-dx, -1, -dz)..normalize());
        }
      }
      t = next;
      was = now;
    }
    return null;
  }

  /// The nearest of [tiles]' cells the ray from [origin] along
  /// [direction] (in their space) enters, and the face it enters by.
  static RayTriangleHit? cellHit(GridTiles3D tiles, Vector3 origin, Vector3 direction) {
    final size = tiles.loaded?.cellSize;
    if (size == null) return null;
    double? best;
    final normal = Vector3.zero();
    final o = [origin.x, origin.y, origin.z], d = [direction.x, direction.y, direction.z];
    for (final key in tiles.cells.keys) {
      final c = GridTiles3D.cellOf(key);
      final lo = [c.x * size, c.y * size, c.z * size];
      var near = double.negativeInfinity, far = double.infinity;
      var axis = -1;
      for (var a = 0; a < 3 && near <= far; a++) {
        if (d[a].abs() < 1e-12) {
          if (o[a] < lo[a] || o[a] > lo[a] + size) far = double.negativeInfinity;
          continue;
        }
        var t0 = (lo[a] - o[a]) / d[a], t1 = (lo[a] + size - o[a]) / d[a];
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t0 > near) {
          near = t0;
          axis = a;
        }
        if (t1 < far) far = t1;
      }
      if (near > far || far < 0 || axis < 0 || near < 0) continue;
      if (best == null || near < best) {
        best = near;
        normal.setValues(0, 0, 0);
        final facing = d[axis] > 0 ? -1.0 : 1.0;
        switch (axis) {
          case 0:
            normal.x = facing;
          case 1:
            normal.y = facing;
          default:
            normal.z = facing;
        }
      }
    }
    return best == null ? null : RayTriangleHit(best, normal);
  }
}

// Picking the kit's pieces: a terrain picked through a hole only where no
// ground is drawn; a picked surface's normal square to it in the world
// however unevenly its entity is scaled; and a grid's cells found by
// walking the ray, the same cell and face a look at every cell finds.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

/// The nearest of [tiles]' cells a ray enters, by looking at every cell:
/// what the walk along the ray must agree with.
RayTriangleHit? _everyCell(GridTiles3DComponent tiles, Vector3 o, Vector3 d) {
  final size = tiles.loaded!.cellSize;
  double? best;
  var bestAxis = -1;
  final oo = [o.x, o.y, o.z], dd = [d.x, d.y, d.z];
  for (final key in tiles.cells.keys) {
    final c = GridTiles3DComponent.cellOf(key);
    final lo = [c.x * size, c.y * size, c.z * size];
    var near = double.negativeInfinity, far = double.infinity, axis = -1;
    for (var a = 0; a < 3 && near <= far; a++) {
      if (dd[a].abs() < 1e-12) {
        if (oo[a] < lo[a] || oo[a] > lo[a] + size) {
          far = double.negativeInfinity;
        }
        continue;
      }
      var t0 = (lo[a] - oo[a]) / dd[a], t1 = (lo[a] + size - oo[a]) / dd[a];
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
      bestAxis = axis;
    }
  }
  if (best == null) return null;
  final n = Vector3.zero();
  final facing = dd[bestAxis] > 0 ? -1.0 : 1.0;
  switch (bestAxis) {
    case 0:
      n.x = facing;
    case 1:
      n.y = facing;
    default:
      n.z = facing;
  }
  return RayTriangleHit(best, n);
}

void main() {
  test('a terrain picked through a hole only where no ground is drawn', () {
    // 9 samples a metre apart, from -4: sample (i, j) at x = i - 4.
    final terrain = Terrain3DComponent(size: 8)
      ..loaded = (TerrainData(9)..setHole(2, 2, true));
    RayTriangleHit? down(double i, double j) => WorldBuilderRayTest.groundHit(
      terrain,
      Vector3(i - 4, -5, j - 4),
      Vector3(0, 1, 0),
    );
    expect(
      down(2.8, 2.8),
      isNotNull,
      reason: 'the far triangle of its cell has no hole corner',
    );
    expect(down(2.2, 2.2), isNull, reason: 'the near one has');
    expect(
      down(2.6, 1.6),
      isNull,
      reason: 'both of that cell have the hole for a corner',
    );
    expect(down(5.5, 5.5), isNotNull);
  });

  test(
    'a picked surface faces square to it in the world, scaled three times as deep',
    () {
      // Ground rising half a metre a metre along Z.
      final data = TerrainData(9);
      for (var j = 0; j < 9; j++) {
        for (var i = 0; i < 9; i++) {
          data.heights[data.index(i, j)] = j * 0.5;
        }
      }
      final world = World()..initialize();
      final entity = world.createEntityWithComponents([
        TransformComponent(scale: Vector3(1, 1, 3)),
        Terrain3DComponent(size: 8)..loaded = data,
      ]);
      final hit = const WorldBuilderRayTest().surfaceHit(
        entity,
        Ray3D.originDirection(Vector3(0, -20, 0), Vector3(0, 1, 0)),
      )!;
      // Along the slope, in the world: a metre along Z in its space is three
      // in the world's, and half a metre up (-Y).
      final along = Vector3(0, -0.5, 3)..normalize();
      expect(hit.normal.dot(along), closeTo(0, 1e-6), reason: '${hit.normal}');
      expect(hit.normal.y, lessThan(0), reason: 'facing up');
      expect(hit.normal.length, closeTo(1, 1e-9));
    },
  );

  test(
    'a grid\'s cells: the walk along the ray finds what a look at every cell does',
    () {
      final random = math.Random(7);
      final tiles = GridTiles3DComponent()..loaded = MeshLibrary(cellSize: 2);
      for (var k = 0; k < 400; k++) {
        tiles.setTile(
          random.nextInt(24) - 12,
          -random.nextInt(6),
          random.nextInt(24) - 12,
          1,
        );
      }
      var hits = 0;
      for (var k = 0; k < 2000; k++) {
        final origin = Vector3(
          random.nextDouble() * 80 - 40,
          random.nextDouble() * 40 - 30,
          random.nextDouble() * 80 - 40,
        );
        final direction = Vector3(
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
        );
        // Some along an axis, exactly.
        if (k % 5 == 0) direction.setValues(0, 1, 0);
        if (k % 7 == 0) direction.setValues(1, 0, 0);
        final walked = WorldBuilderRayTest.cellHit(tiles, origin, direction);
        final every = _everyCell(tiles, origin, direction);
        expect(
          walked == null,
          every == null,
          reason: 'ray $k from $origin along $direction',
        );
        if (walked == null || every == null) continue;
        hits++;
        expect(walked.t, closeTo(every.t, 1e-6), reason: 'ray $k');
        expect(
          [walked.normal.x, walked.normal.y, walked.normal.z],
          [every.normal.x, every.normal.y, every.normal.z],
          reason: 'ray $k',
        );
      }
      expect(hits, greaterThan(200), reason: 'enough rays hit to tell');
    },
  );
}

// A sweep along a spline: its mesh, made again only when it changes, and
// solid once tied to its spline.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

Spline3DComponent _spline(
  List<List<double>> points, {
  bool closed = false,
  SplineInterpolation curve = SplineInterpolation.linear,
}) => Spline3DComponent(
  points: [
    for (final p in points) SplinePoint(position: Vector3(p[0], p[1], p[2])),
  ],
  closed: closed,
  interpolation: curve,
);

/// The volume [mesh] holds: positive when its faces wind anticlockwise
/// seen from outside.
double _volume(SweptMesh mesh) {
  final p = mesh.positions, idx = mesh.indices;
  Vector3 at(int i) => Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]);
  var v = 0.0;
  for (var i = 0; i < idx.length; i += 3) {
    v += at(idx[i]).dot(at(idx[i + 1]).cross(at(idx[i + 2])));
  }
  return v / 6;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a sweep', () {
    test('a road: closed, facing out, its top on the spline', () {
      final sweep = SplineSweep3DComponent(
        profile: SweepProfile.road,
        width: 3,
        height: 0.3,
        step: 1,
      );
      final mesh = SplineSweeper.meshFor(
        sweep,
        _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]),
      )!;
      // Four sides of ten stretches, two triangles each, and two ends.
      expect(mesh.triangleCount, 4 * 10 * 2 + 2 * 2);
      expect(
        _volume(mesh),
        closeTo(10 * 3 * 0.3, 1e-4),
        reason: 'whole, and its faces out',
      );
      var minY = double.infinity, maxY = -double.infinity, maxZ = 0.0;
      for (var i = 0; i < mesh.positions.length; i += 3) {
        minY = math.min(minY, mesh.positions[i + 1]);
        maxY = math.max(maxY, mesh.positions[i + 1]);
        maxZ = math.max(maxZ, mesh.positions[i + 2].abs());
      }
      // +Y is down: its top at the spline, its body below.
      expect(
        [minY, maxY, maxZ],
        [closeTo(0, 1e-6), closeTo(0.3, 1e-6), closeTo(1.5, 1e-6)],
      );
    });

    test('made again only when it or its spline changes', () {
      final spline = _spline([
        [0, 0, 0],
        [10, 0, 0],
      ]);
      final sweep = SplineSweep3DComponent(profile: SweepProfile.wall);
      final first = SplineSweeper.meshFor(sweep, spline);
      expect(identical(SplineSweeper.meshFor(sweep, spline), first), isTrue);
      final key = sweep.sweepKey;
      spline.points[1].position.z = 4;
      expect(sweep.sweepKey, isNot(key));
      expect(identical(SplineSweeper.meshFor(sweep, spline), first), isFalse);
    });

    test('a pipe: smooth, its normals out from the middle', () {
      final sweep = SplineSweep3DComponent(
        profile: SweepProfile.pipe,
        radius: 0.5,
        sides: 10,
        step: 0.5,
      );
      final mesh = SplineSweeper.meshFor(
        sweep,
        _spline([
          [0, 0, 0],
          [6, 0, 0],
          [6, 0, 6],
        ], curve: SplineInterpolation.catmullRom),
      )!;
      expect(_volume(mesh), greaterThan(0));
      final path = SplinePath.of(sweep.spline!);
      for (var i = 0; i < mesh.positions.length; i += 3 * 17) {
        final p = Vector3(
          mesh.positions[i],
          mesh.positions[i + 1],
          mesh.positions[i + 2],
        );
        final n = Vector3(
          mesh.normals[i],
          mesh.normals[i + 1],
          mesh.normals[i + 2],
        );
        expect(n.length, closeTo(1, 1e-4));
        final near = path.nearest(p);
        // An end's cap faces along it.
        if (n.dot(path.at(near.distance).tangent).abs() > 0.5) continue;
        final out = p - near.position;
        if (out.length > 0.3) expect(out.normalized().dot(n), greaterThan(0.9));
      }
    });

    test('solid once tied to its spline: a mesh to collide with', () {
      final sweep = SplineSweep3DComponent(profile: SweepProfile.road, step: 1);
      expect(sweep.solidParts, isEmpty);
      sweep.spline = _spline([
        [0, 0, 0],
        [10, 0, 0],
      ]);
      final parts = sweep.solidParts;
      expect(parts.single, isA<SolidMesh>());
      expect((parts.single as SolidMesh).triangleCount, 84);
    });

    test('its solid key changes with its shape, not with how it looks', () {
      final sweep = SplineSweep3DComponent(profile: SweepProfile.road)
        ..spline = _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]);
      final key = sweep.solidKey;
      sweep.tiling = 4;
      expect(
        sweep.solidKey,
        key,
        reason: 'its collider is not made again for its texture',
      );
      sweep.width = 5;
      expect(sweep.solidKey, isNot(key));
    });
  });
}

// A spline's path: its length, frames, roll, ends and copies along it.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a spline\'s path', () {
    test('its length, straight or round a corner', () {
      expect(
        SplinePath.of(
          _spline([
            [0, 0, 0],
            [10, 0, 0],
            [10, 0, 10],
          ]),
        ).length,
        closeTo(20, 1e-9),
      );
      final straight = _spline([
        [0, 0, 0],
        [5, 0, 0],
        [10, 0, 0],
      ], curve: SplineInterpolation.catmullRom);
      expect(SplinePath.of(straight).length, closeTo(10, 1e-6));
      // A circle through 8 points, near 2πr.
      final circle = _spline(
        [
          for (var i = 0; i < 8; i++)
            [math.cos(i * math.pi / 4) * 5, 0, math.sin(i * math.pi / 4) * 5],
        ],
        closed: true,
        curve: SplineInterpolation.catmullRom,
      );
      expect(SplinePath.of(circle).length, closeTo(2 * math.pi * 5, 0.15));
    });

    test('its frames: square, unit, and level on level ground', () {
      final loop = _spline(
        [
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
          [0, 0, 10],
        ],
        closed: true,
        curve: SplineInterpolation.catmullRom,
      );
      final path = SplinePath.of(loop);
      for (var d = 0.0; d < path.length; d += path.length / 37) {
        final f = path.at(d);
        expect(f.tangent.length, closeTo(1, 1e-6));
        expect(f.up.length, closeTo(1, 1e-6));
        expect(f.right.length, closeTo(1, 1e-6));
        expect(f.tangent.dot(f.up).abs(), lessThan(1e-6));
        expect(f.right.dot(f.up).abs(), lessThan(1e-6));
        // +Y is down: up is -Y.
        expect(f.up.y, closeTo(-1, 1e-6), reason: 'at $d');
      }
    });

    test('a point\'s roll turns its up about the spline', () {
      final rolled = _spline([
        [0, 0, 0],
        [10, 0, 0],
      ])..points[1].roll = math.pi / 2;
      final path = SplinePath.of(rolled);
      expect(path.at(0).up.y, closeTo(-1, 1e-6));
      final end = path.at(path.length);
      expect(
        end.up.y.abs(),
        lessThan(1e-6),
        reason: 'a quarter turn by the end',
      );
    });

    test('where it is past its ends, and the point nearest another', () {
      final open = SplinePath.of(
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
        ]),
      );
      expect(open.at(-5).position.x, closeTo(0, 1e-9));
      expect(open.at(99).position.z, closeTo(10, 1e-9));
      final near = open.nearest(Vector3(5, -1, 3));
      expect(
        [near.position.x, near.position.z],
        [closeTo(5, 1e-9), closeTo(0, 1e-9)],
      );
      expect(near.distance, closeTo(5, 1e-9));

      final loop = SplinePath.of(
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
          [0, 0, 10],
        ], closed: true),
      );
      expect(loop.length, closeTo(40, 1e-9));
      expect(loop.at(41).position.x, closeTo(1, 1e-9), reason: 'round again');
    });

    test('copies laid along it, every so far', () {
      final path = SplinePath.of(
        _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]),
      );
      expect(
        InstancesRenderProvider.placements(
          SplineInstances3DComponent(spacing: 2),
          path,
        ),
        hasLength(6),
      );
      final loop = SplinePath.of(
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
          [0, 0, 10],
        ], closed: true),
      );
      expect(
        InstancesRenderProvider.placements(
          SplineInstances3DComponent(spacing: 4),
          loop,
        ),
        hasLength(10),
        reason: 'none twice where it meets itself',
      );
    });

    test(
      'a closed loop over hills and dips: its frames meet where it closes',
      () {
        // Not level: the frames turn on the way round, and that turn is
        // spread back along it.
        final loop = _spline(
          [
            [10, 0, 0],
            [3, -6, 8],
            [-7, 2, 5],
            [-8, -5, -6],
            [2, 4, -9],
          ],
          closed: true,
          curve: SplineInterpolation.catmullRom,
        );
        final path = SplinePath.of(loop);
        expect(
          path.ups.first.dot(path.ups.last),
          greaterThan(1 - 1e-9),
          reason: 'no twist at the seam',
        );
        final before = path.at(path.length - 1e-3), after = path.at(1e-3);
        expect(
          before.up.dot(after.up),
          greaterThan(0.999),
          reason: 'smooth across it',
        );
      },
    );

    test(
      'a point given twice is one: no fold back, the way on from the start',
      () {
        final twice = SplinePath.of(
          _spline([
            [0, 0, 0],
            [0, 0, 0],
            [10, 0, 0],
            [10, 0, 10],
          ], curve: SplineInterpolation.catmullRom),
        );
        final once = SplinePath.of(
          _spline([
            [0, 0, 0],
            [10, 0, 0],
            [10, 0, 10],
          ], curve: SplineInterpolation.catmullRom),
        );
        expect(twice.positions, hasLength(once.positions.length));
        expect(twice.length, closeTo(once.length, 1e-9));
        for (var d = 0.0; d < once.length; d += 0.5) {
          expect(
            twice.at(d).position.x,
            greaterThanOrEqualTo(-1e-9),
            reason: 'never back past its start',
          );
        }
        final straight = SplinePath.of(
          _spline([
            [0, 0, 0],
            [0, 0, 0],
            [10, 0, 0],
          ]),
        );
        expect(
          straight.at(0).tangent.x,
          closeTo(1, 1e-9),
          reason: 'facing the way it goes',
        );
        // Round a closed one, a last point back on the first is the first.
        final square = _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
          [0, 0, 10],
          [0, 0, 0],
        ], closed: true);
        expect(SplinePath.of(square).length, closeTo(40, 1e-9));
      },
    );
  });
}

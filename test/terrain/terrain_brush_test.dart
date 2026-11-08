// Terrain brushes: raise, smooth, flatten, paint and holes.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

/// A bumpy terrain of [n] samples a side.
TerrainData _bumpy(int n) {
  final data = TerrainData(n);
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      data.heights[data.index(i, j)] = math.sin(i * 0.7) + math.cos(j * 0.4);
    }
  }
  return data;
}

int data0(int n, int i, int j) => j * n + i;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('brushes', () {
    double h(TerrainData d, int i, int j) => d.heights[d.index(i, j)];

    test('raise: most in the middle, nothing past its edge', () {
      final data = TerrainData(33);
      final rect = TerrainBrush.apply(
        data,
        const TerrainDab(
          mode: TerrainBrushMode.raise,
          x: 16,
          z: 16,
          radius: 4,
          strength: 3,
          seconds: 1,
        ),
      );
      expect(rect, (12, 12, 20, 20));
      expect(h(data, 16, 16), closeTo(3, 1e-6));
      expect(h(data, 18, 16), allOf(greaterThan(0), lessThan(3)));
      expect(h(data, 21, 16), 0);
      TerrainBrush.apply(
        data,
        const TerrainDab(
          mode: TerrainBrushMode.lower,
          x: 16,
          z: 16,
          radius: 4,
          strength: 1,
          seconds: 1,
        ),
      );
      expect(h(data, 16, 16), closeTo(2, 1e-6));
    });

    test('smooth evens it; flatten brings it to one height', () {
      final data = _bumpy(33);
      double spread(TerrainData d) {
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var j = 12; j <= 20; j++) {
          for (var i = 12; i <= 20; i++) {
            lo = math.min(lo, h(d, i, j));
            hi = math.max(hi, h(d, i, j));
          }
        }
        return hi - lo;
      }

      final rough = spread(data);
      for (var k = 0; k < 10; k++) {
        TerrainBrush.apply(
          data,
          const TerrainDab(
            mode: TerrainBrushMode.smooth,
            x: 16,
            z: 16,
            radius: 8,
            strength: 2,
            seconds: 0.2,
          ),
        );
      }
      expect(spread(data), lessThan(rough * 0.7));
      for (var k = 0; k < 20; k++) {
        TerrainBrush.apply(
          data,
          const TerrainDab(
            mode: TerrainBrushMode.flatten,
            x: 16,
            z: 16,
            radius: 8,
            strength: 2,
            seconds: 0.5,
            target: 1.5,
          ),
        );
      }
      expect(h(data, 16, 16), closeTo(1.5, 1e-3));
    });

    test('paint keeps the layers adding up; holes cut and filled', () {
      final data = TerrainData(17);
      for (var k = 0; k < 10; k++) {
        TerrainBrush.apply(
          data,
          const TerrainDab(
            mode: TerrainBrushMode.paint,
            x: 8,
            z: 8,
            radius: 4,
            strength: 2,
            seconds: 0.2,
            layer: 2,
          ),
        );
      }
      final k = data.index(8, 8) * 4;
      expect(data.weights[k + 2], greaterThan(200));
      for (var i = 0; i < 17 * 17; i++) {
        expect(
          data.weights[i * 4] +
              data.weights[i * 4 + 1] +
              data.weights[i * 4 + 2] +
              data.weights[i * 4 + 3],
          255,
        );
      }
      TerrainBrush.apply(
        data,
        const TerrainDab(mode: TerrainBrushMode.hole, x: 8, z: 8, radius: 3),
      );
      expect(data.isHole(8, 8), isTrue);
      expect(data.isHole(8, 12), isFalse);
      TerrainBrush.apply(
        data,
        const TerrainDab(
          mode: TerrainBrushMode.hole,
          x: 8,
          z: 8,
          radius: 3,
          erase: true,
        ),
      );
      expect(data.hasHoles, isFalse);
    });
  });
}

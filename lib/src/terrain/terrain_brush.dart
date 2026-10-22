import 'dart:math' as math;

import 'terrain_data.dart';

/// What a terrain brush does where it touches.
enum TerrainBrushMode {
  /// Lifts the ground.
  raise('Raise'),

  /// Sinks it.
  lower('Lower'),

  /// Evens out bumps.
  smooth('Smooth'),

  /// Brings it to one height: where the stroke began.
  flatten('Flatten'),

  /// Roughens it.
  noise('Noise'),

  /// Paints a layer.
  paint('Paint'),

  /// Cuts holes (or fills them back).
  hole('Hole');

  const TerrainBrushMode(this.label);

  final String label;
}

/// A dab of a terrain brush: a circle [radius] samples across about
/// ([x], [z]) (in samples), as strong as [strength] for [seconds].
final class TerrainDab {
  const TerrainDab({
    required this.mode,
    required this.x,
    required this.z,
    required this.radius,
    this.strength = 1,
    this.seconds = 1 / 30,
    this.layer = 0,
    this.target = 0,
    this.erase = false,
  });

  final TerrainBrushMode mode;
  final double x, z, radius;

  /// Raise and lower: metres a second at the middle. Smooth, flatten,
  /// paint: how much of the way there a second (0–1 and on). Noise: metres
  /// of roughness a second.
  final double strength;

  /// How long the dab lasts.
  final double seconds;

  /// The layer [TerrainBrushMode.paint] paints (0–3).
  final int layer;

  /// The height [TerrainBrushMode.flatten] brings it to.
  final double target;

  /// For [TerrainBrushMode.hole]: fill holes back rather than cut them.
  final bool erase;
}

/// Terrain brushes: each [apply] changes the samples a dab touches, marks
/// their blocks changed, and says which samples it touched.
abstract final class TerrainBrush {
  /// How strongly a dab acts [d] samples from its middle, of [radius]: 1
  /// in the middle, easing to 0 at its edge.
  static double falloff(double d, double radius) {
    if (radius <= 0 || d >= radius) return 0;
    final t = d / radius;
    return 0.5 * (1 + math.cos(math.pi * t));
  }

  /// [dab] applied to [data]; the samples it touched, or null for none.
  static (int, int, int, int)? apply(TerrainData data, TerrainDab dab) {
    final n = data.resolution;
    final r = math.max(dab.radius, 0.5);
    final i0 = math.max(0, (dab.x - r).floor()), i1 = math.min(n - 1, (dab.x + r).ceil());
    final j0 = math.max(0, (dab.z - r).floor()), j1 = math.min(n - 1, (dab.z + r).ceil());
    if (i0 > i1 || j0 > j1) return null;
    final rate = dab.strength * dab.seconds;
    // Smoothing reads the heights as they were before this dab.
    final before = dab.mode == TerrainBrushMode.smooth ? _region(data, i0 - 1, j0 - 1, i1 + 1, j1 + 1) : null;
    var touched = false;
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        final w = falloff(math.sqrt((i - dab.x) * (i - dab.x) + (j - dab.z) * (j - dab.z)), r);
        if (w <= 0) continue;
        final k = data.index(i, j);
        touched = true;
        switch (dab.mode) {
          case TerrainBrushMode.raise:
            data.heights[k] += rate * w;
          case TerrainBrushMode.lower:
            data.heights[k] -= rate * w;
          case TerrainBrushMode.smooth:
            var sum = 0.0;
            for (var dj = -1; dj <= 1; dj++) {
              for (var di = -1; di <= 1; di++) {
                sum += before!.at(i + di, j + dj);
              }
            }
            final mean = sum / 9;
            data.heights[k] += (mean - data.heights[k]) * math.min(1.0, rate * 4 * w);
          case TerrainBrushMode.flatten:
            data.heights[k] += (dab.target - data.heights[k]) * math.min(1.0, rate * 4 * w);
          case TerrainBrushMode.noise:
            data.heights[k] += (_noise(i, j) - 0.5) * 2 * rate * w;
          case TerrainBrushMode.paint:
            _paint(data, k, dab.layer.clamp(0, 3), math.min(1.0, rate * 4 * w));
          case TerrainBrushMode.hole:
            if (w > 0.35) data.setHole(i, j, !dab.erase);
        }
      }
    }
    if (!touched) return null;
    data.touch(i0, j0, i1, j1);
    return (i0, j0, i1, j1);
  }

  /// Moves sample [k]'s weights [amount] of the way to all of [layer].
  static void _paint(TerrainData data, int k, int layer, double amount) {
    final w = data.weights;
    var total = 0;
    for (var l = 0; l < 4; l++) {
      final now = w[k * 4 + l].toDouble();
      final want = l == layer ? 255.0 : 0.0;
      final next = (now + (want - now) * amount).round().clamp(0, 255);
      w[k * 4 + l] = next;
      total += next;
    }
    // Keep them adding up to 255.
    w[k * 4 + layer] = (w[k * 4 + layer] + 255 - total).clamp(0, 255);
  }

  /// A steady value 0–1 for sample ([i], [j]): roughness that stays put
  /// from dab to dab.
  static double _noise(int i, int j) {
    var h = i * 374761393 + j * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    h ^= h >> 16;
    return (h & 0xFFFF) / 0xFFFF;
  }

  static _Region _region(TerrainData data, int i0, int j0, int i1, int j1) {
    final w = i1 - i0 + 1;
    final values = List<double>.filled(w * (j1 - j0 + 1), 0);
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        values[(j - j0) * w + (i - i0)] = data.height(i, j);
      }
    }
    return _Region(i0, j0, w, values);
  }
}

class _Region {
  _Region(this.i0, this.j0, this.width, this.values);

  final int i0, j0, width;
  final List<double> values;

  double at(int i, int j) => values[(j - j0) * width + (i - i0)];
}

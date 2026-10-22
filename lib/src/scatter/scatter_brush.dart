import 'dart:math' as math;

import 'scatter_components.dart';

/// Where a layer's pieces already stand, bucketed by its spacing: whether
/// a new one at a spot keeps its distance from them all.
final class ScatterSpacing {
  /// [instances] of layer [layer], kept [spacing] metres apart.
  ScatterSpacing(Iterable<ScatterInstance> instances, this.layer, double spacing) : spacing = math.max(spacing, 0.01) {
    for (final i in instances) {
      if (i.layer == layer) add(i.position.x, i.position.z);
    }
  }

  final int layer;
  final double spacing;
  final Map<(int, int), List<(double, double)>> _buckets = {};

  (int, int) _bucket(double x, double z) => ((x / spacing).floor(), (z / spacing).floor());

  /// Whether a piece at ([x], [z]) is at least [spacing] from every other.
  bool fits(double x, double z) {
    final (bx, bz) = _bucket(x, z);
    final s2 = spacing * spacing;
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final (px, pz) in _buckets[(bx + dx, bz + dz)] ?? const <(double, double)>[]) {
          if ((px - x) * (px - x) + (pz - z) * (pz - z) < s2) return false;
        }
      }
    }
    return true;
  }

  /// Counts a piece at ([x], [z]).
  void add(double x, double z) => (_buckets[_bucket(x, z)] ??= []).add((x, z));
}

/// The Scatter brush's arithmetic: spots to try in a dab, and what an
/// erase leaves.
abstract final class ScatterBrush {
  /// Up to [tries] spots, evenly at random over the disk of [radius] about
  /// ([x], [z]).
  static List<(double, double)> spots(math.Random random, double x, double z, double radius, int tries) => [
    for (var k = 0; k < tries; k++)
      () {
        final r = radius * math.sqrt(random.nextDouble()), a = random.nextDouble() * 2 * math.pi;
        return (x + r * math.cos(a), z + r * math.sin(a));
      }(),
  ];

  /// How many spots a dab of [radius] tries for pieces [spacing] apart:
  /// about as many as would fit, at most 64.
  static int triesFor(double radius, double spacing) =>
      (math.pi * radius * radius / math.max(spacing * spacing, 0.01) * 0.6).ceil().clamp(1, 64);

  /// [instances] less those within [radius] of ([x], [z]) — of [layer]
  /// only, when given.
  static List<ScatterInstance> erased(List<ScatterInstance> instances, double x, double z, double radius, {int? layer}) {
    final r2 = radius * radius;
    return [
      for (final i in instances)
        if ((layer != null && i.layer != layer) ||
            (i.position.x - x) * (i.position.x - x) + (i.position.z - z) * (i.position.z - z) > r2)
          i,
    ];
  }
}

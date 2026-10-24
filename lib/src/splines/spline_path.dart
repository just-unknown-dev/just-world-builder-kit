import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';

/// Where a [SplinePath] is at some distance along it: the point, the way
/// it runs ([tangent]), its [up] (with the spline's roll) and [right] —
/// unit length, square to each other.
typedef SplineFrame = ({Vector3 position, Vector3 tangent, Vector3 up, Vector3 right});

/// A [Spline3D] sampled finely along its length, in its entity's own
/// space: where it is at any distance along it, which way it runs, which
/// way is up on it — frames that turn as little as they can (rotation
/// minimising), then rolled as its points say — and the point on it
/// nearest another.
///
/// +Y is down: up is -Y.
final class SplinePath {
  SplinePath._(this.positions, this.tangents, this.ups, this.distances, this.closed);

  /// [spline] sampled [perSegment] times between each two of its points.
  factory SplinePath.of(Spline3D spline, {int perSegment = 24}) {
    final points = _distinct(spline.points, spline.closed);
    final n = points.length;
    if (n < 2) {
      return SplinePath._(
        [for (final p in points) Vector3.copy(p.position)],
        [for (final _ in points) Vector3(0, 0, 1)],
        [for (final _ in points) Vector3(0, -1, 0)],
        [for (final _ in points) 0.0],
        spline.closed,
      );
    }
    final closed = spline.closed && n >= 3;
    final segments = closed ? n : n - 1;
    final positions = <Vector3>[];
    final rolls = <double>[];
    for (var s = 0; s < segments; s++) {
      final last = s == segments - 1;
      for (var k = 0; k < perSegment + (last && !closed ? 1 : 0); k++) {
        final t = k / perSegment;
        positions.add(_point(points, closed, spline.interpolation, s, t));
        final a = points[s].roll, b = points[(s + 1) % n].roll;
        rolls.add(a + (b - a) * t);
      }
    }
    if (closed) {
      positions.add(Vector3.copy(positions.first));
      rolls.add(rolls.first);
    }
    // Tangents from the samples round each.
    final count = positions.length;
    final tangents = <Vector3>[];
    // How many samples at the start have no way of their own (they sit on
    // one spot): they take the first way there is.
    var leading = 0;
    for (var i = 0; i < count; i++) {
      final before = i == 0 ? (closed ? positions[count - 2] : positions[0]) : positions[i - 1];
      final after = i == count - 1 ? (closed ? positions[1] : positions[count - 1]) : positions[i + 1];
      final t = after - before;
      if (t.lengthSquared >= 1e-18) {
        tangents.add(t..normalize());
      } else if (leading == tangents.length) {
        leading++;
        tangents.add(Vector3(0, 0, 1));
      } else {
        tangents.add(Vector3.copy(tangents.last));
      }
    }
    if (leading > 0 && leading < count) {
      for (var i = 0; i < leading; i++) {
        tangents[i] = Vector3.copy(tangents[leading]);
      }
    }
    // Rotation-minimising frames (double reflection), from up as near the
    // world's up as the first tangent allows.
    final ups = <Vector3>[_square(Vector3(0, -1, 0), tangents.first)];
    for (var i = 0; i + 1 < count; i++) {
      final v1 = positions[i + 1] - positions[i];
      final c1 = v1.dot(v1);
      if (c1 < 1e-18) {
        ups.add(_square(Vector3.copy(ups[i]), tangents[i + 1]));
        continue;
      }
      final rL = ups[i] - v1 * (2 / c1 * v1.dot(ups[i]));
      final tL = tangents[i] - v1 * (2 / c1 * v1.dot(tangents[i]));
      final v2 = tangents[i + 1] - tL;
      final c2 = v2.dot(v2);
      final next = c2 < 1e-18 ? rL : rL - v2 * (2 / c2 * v2.dot(rL));
      ups.add(_square(next, tangents[i + 1]));
    }
    // Closed: what the frames turned on the way round, spread back along
    // it so the end meets the start. [twist] turns the last frame onto the
    // first: frame i takes its share of it.
    if (closed) {
      final twist = _angleAbout(ups.last, ups.first, tangents.first);
      for (var i = 0; i < count; i++) {
        _turnAbout(ups[i], tangents[i], twist * i / (count - 1));
      }
    }
    for (var i = 0; i < count; i++) {
      if (rolls[i] != 0) _turnAbout(ups[i], tangents[i], rolls[i]);
    }
    final distances = <double>[0];
    for (var i = 1; i < count; i++) {
      distances.add(distances.last + (positions[i] - positions[i - 1]).length);
    }
    return SplinePath._(positions, tangents, ups, distances, closed);
  }

  /// The samples, in order.
  final List<Vector3> positions;

  /// Which way it runs at each sample.
  final List<Vector3> tangents;

  /// Up at each sample.
  final List<Vector3> ups;

  /// How far along each sample is.
  final List<double> distances;

  /// Whether it runs on round from its end to its start.
  final bool closed;

  /// How long it is.
  double get length => distances.isEmpty ? 0 : distances.last;

  /// Whether it has any length to it.
  bool get isEmpty => positions.length < 2 || length <= 0;

  /// Where it is [distance] along — round again past its end when
  /// [closed], held at its ends otherwise.
  SplineFrame at(double distance) {
    if (positions.isEmpty) {
      return (position: Vector3.zero(), tangent: Vector3(0, 0, 1), up: Vector3(0, -1, 0), right: Vector3(1, 0, 0));
    }
    if (isEmpty) {
      return _frame(Vector3.copy(positions.first), Vector3.copy(tangents.first), Vector3.copy(ups.first));
    }
    var d = distance;
    if (closed) {
      d %= length;
      if (d < 0) d += length;
    } else {
      d = d.clamp(0.0, length);
    }
    // The sample at or before it.
    var lo = 0, hi = distances.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (distances[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = distances[hi] - distances[lo];
    final f = span <= 0 ? 0.0 : (d - distances[lo]) / span;
    Vector3 lerp(Vector3 a, Vector3 b) => a + (b - a) * f;
    final tangent = lerp(tangents[lo], tangents[hi])..normalize();
    return _frame(lerp(positions[lo], positions[hi]), tangent, _square(lerp(ups[lo], ups[hi]), tangent));
  }

  /// [at] as a matrix: its columns right, down (−up), along and the
  /// point — what puts something standing upright on the spline, facing
  /// along it.
  Matrix4 matrixAt(double distance, {double side = 0, double scale = 1}) {
    final f = at(distance);
    final p = f.position + f.right * side;
    final m = Matrix4.identity();
    final s = m.storage;
    s[0] = f.right.x * scale;
    s[1] = f.right.y * scale;
    s[2] = f.right.z * scale;
    s[4] = -f.up.x * scale;
    s[5] = -f.up.y * scale;
    s[6] = -f.up.z * scale;
    s[8] = f.tangent.x * scale;
    s[9] = f.tangent.y * scale;
    s[10] = f.tangent.z * scale;
    s[12] = p.x;
    s[13] = p.y;
    s[14] = p.z;
    return m;
  }

  /// The point on it nearest [point], and how far along that is.
  ({double distance, Vector3 position}) nearest(Vector3 point) {
    var best = double.infinity;
    var bestDistance = 0.0;
    var bestPoint = positions.isEmpty ? Vector3.zero() : Vector3.copy(positions.first);
    for (var i = 0; i + 1 < positions.length; i++) {
      final a = positions[i], b = positions[i + 1];
      final ab = b - a;
      final l2 = ab.lengthSquared;
      final t = l2 <= 0 ? 0.0 : ((point - a).dot(ab) / l2).clamp(0.0, 1.0);
      final q = a + ab * t;
      final d2 = (point - q).lengthSquared;
      if (d2 < best) {
        best = d2;
        bestPoint = q;
        bestDistance = distances[i] + (distances[i + 1] - distances[i]) * t;
      }
    }
    return (distance: bestDistance, position: bestPoint);
  }

  static SplineFrame _frame(Vector3 position, Vector3 tangent, Vector3 up) {
    final right = tangent.cross(up)..normalize();
    return (position: position, tangent: tangent, up: up, right: right);
  }

  /// [up] made square to [tangent] and unit length; across it when it ran
  /// along it.
  static Vector3 _square(Vector3 up, Vector3 tangent) {
    var u = up - tangent * tangent.dot(up);
    if (u.lengthSquared < 1e-12) {
      final across = tangent.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
      u = across - tangent * tangent.dot(across);
    }
    return u..normalize();
  }

  /// The angle (radians) turning [from] onto [to] about [axis].
  static double _angleAbout(Vector3 from, Vector3 to, Vector3 axis) =>
      math.atan2(axis.dot(from.cross(to)), from.dot(to));

  /// Turns [v] by [angle] about the unit [axis], in place.
  static void _turnAbout(Vector3 v, Vector3 axis, double angle) {
    Quaternion.axisAngle(axis, angle).rotate(v);
  }

  /// Two points nearer than this (squared, metres) are the same point.
  static const double _samePlace = 1e-8;

  /// [points] less each one at the same place as the one before it — and,
  /// round a [closed] spline, a last one back on the first: a repeated
  /// point makes no curve, and Catmull-Rom would loop back through it.
  static List<SplinePoint> _distinct(List<SplinePoint> points, bool closed) {
    final out = <SplinePoint>[];
    for (final p in points) {
      if (out.isEmpty || (p.position - out.last.position).lengthSquared > _samePlace) out.add(p);
    }
    if (closed && out.length > 1 && (out.last.position - out.first.position).lengthSquared <= _samePlace) {
      out.removeLast();
    }
    return out;
  }

  // The point [t] of the way along segment [s] (from point s to s + 1) of
  // [points], [closed] when they run round.
  static Vector3 _point(List<SplinePoint> points, bool closed, SplineInterpolation interpolation, int s, double t) {
    final n = points.length;
    Vector3 at(int i) {
      if (closed) return points[((i % n) + n) % n].position;
      if (i < 0) return points[0].position * 2 - points[1].position;
      if (i >= n) return points[n - 1].position * 2 - points[n - 2].position;
      return points[i].position;
    }

    final p0 = at(s - 1), p1 = at(s), p2 = at(s + 1), p3 = at(s + 2);
    switch (interpolation) {
      case SplineInterpolation.linear:
        return p1 + (p2 - p1) * t;
      case SplineInterpolation.catmullRom:
        final t2 = t * t, t3 = t2 * t;
        return (p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
            0.5;
      case SplineInterpolation.bezier:
        final a = points[s], b = points[(s + 1) % n];
        final out = a.mode == SplineTangentMode.auto || a.outTangent.lengthSquared == 0 ? (p2 - p0) / 6 : a.outTangent;
        final into = b.mode == SplineTangentMode.auto || b.inTangent.lengthSquared == 0 ? (p1 - p3) / 6 : b.inTangent;
        final c1 = p1 + out, c2 = p2 + into;
        final u = 1 - t;
        return p1 * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + p2 * (t * t * t);
    }
  }
}

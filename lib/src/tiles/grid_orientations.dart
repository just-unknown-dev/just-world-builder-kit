import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';

/// The 24 ways a tile can be turned in its cell — every quarter turn of a
/// cube — by index: `tilt * 4 + spin`, spinning it about its own up a
/// quarter turn at a time, then tilting its up onto one of the six sides
/// (up, down, +X, -X, +Z, -Z). 0 is as it was made.
///
/// +Y is down: up is -Y.
abstract final class GridOrientations {
  /// How many there are.
  static const int count = 24;

  static final List<List<int>> _matrices = _build();
  static final List<Quaternion> _turns = [for (final m in _matrices) _quaternionOf(m)];
  static final List<List<int>> _byAxis = [
    for (var axis = 0; axis < 3; axis++) [for (var i = 0; i < count; i++) _after(i, axis)],
  ];

  /// Orientation [index] as a turn.
  static Quaternion of(int index) => Quaternion.copy(_turns[index.clamp(0, count - 1)]);

  /// Orientation [index] as a matrix, row by row: whole numbers, -1, 0 or
  /// 1.
  static List<int> matrixOf(int index) => List.unmodifiable(_matrices[index.clamp(0, count - 1)]);

  /// [index] turned a further quarter turn about [axis] (0 X, 1 Y, 2 Z) of
  /// the cell, [steps] times (negative for the other way).
  static int turned(int index, int axis, [int steps = 1]) {
    var at = index.clamp(0, count - 1);
    final quarterTurns = ((steps % 4) + 4) % 4;
    for (var i = 0; i < quarterTurns; i++) {
      at = _byAxis[axis][at];
    }
    return at;
  }

  /// [v] turned by orientation [index].
  static Vector3 apply(int index, Vector3 v) {
    final m = _matrices[index.clamp(0, count - 1)];
    return Vector3(
      m[0] * v.x + m[1] * v.y + m[2] * v.z,
      m[3] * v.x + m[4] * v.y + m[5] * v.z,
      m[6] * v.x + m[7] * v.y + m[8] * v.z,
    );
  }

  static List<List<int>> _build() {
    final tilts = <Quaternion>[
      Quaternion.identity(),
      Quaternion.axisAngle(Vector3(1, 0, 0), math.pi),
      Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2),
      Quaternion.axisAngle(Vector3(0, 0, 1), -math.pi / 2),
      Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
      Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
    ];
    return [
      for (final tilt in tilts)
        for (var spin = 0; spin < 4; spin++) _matrixOf(Quaternion.copy(tilt)..multiply(Quaternion.axisAngle(Vector3(0, 1, 0), spin * math.pi / 2))),
    ];
  }

  /// [q]'s matrix, rounded to whole numbers.
  static List<int> _matrixOf(Quaternion q) {
    final columns = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)];
    for (final c in columns) {
      q.rotate(c);
    }
    int r(double v) => v.round();
    return [
      r(columns[0].x), r(columns[1].x), r(columns[2].x),
      r(columns[0].y), r(columns[1].y), r(columns[2].y),
      r(columns[0].z), r(columns[1].z), r(columns[2].z),
    ];
  }

  static int _after(int index, int axis) {
    final turn = Quaternion.axisAngle(
      Vector3(axis == 0 ? 1 : 0, axis == 1 ? 1 : 0, axis == 2 ? 1 : 0),
      math.pi / 2,
    )..multiply(_quaternionOf(_matrices[index]));
    final m = _matrixOf(turn);
    for (var i = 0; i < count; i++) {
      var same = true;
      for (var k = 0; k < 9 && same; k++) {
        same = _matrices[i][k] == m[k];
      }
      if (same) return i;
    }
    return index;
  }

  /// The turn whose matrix (row by row) is [m].
  static Quaternion _quaternionOf(List<int> m) {
    final m00 = m[0].toDouble(), m01 = m[1].toDouble(), m02 = m[2].toDouble();
    final m10 = m[3].toDouble(), m11 = m[4].toDouble(), m12 = m[5].toDouble();
    final m20 = m[6].toDouble(), m21 = m[7].toDouble(), m22 = m[8].toDouble();
    final trace = m00 + m11 + m22;
    final double x, y, z, w;
    if (trace > 0) {
      final s = math.sqrt(trace + 1) * 2;
      w = s / 4;
      x = (m21 - m12) / s;
      y = (m02 - m20) / s;
      z = (m10 - m01) / s;
    } else if (m00 > m11 && m00 > m22) {
      final s = math.sqrt(1 + m00 - m11 - m22) * 2;
      w = (m21 - m12) / s;
      x = s / 4;
      y = (m01 + m10) / s;
      z = (m02 + m20) / s;
    } else if (m11 > m22) {
      final s = math.sqrt(1 + m11 - m00 - m22) * 2;
      w = (m02 - m20) / s;
      x = (m01 + m10) / s;
      y = s / 4;
      z = (m12 + m21) / s;
    } else {
      final s = math.sqrt(1 + m22 - m00 - m11) * 2;
      w = (m10 - m01) / s;
      x = (m02 + m20) / s;
      y = (m12 + m21) / s;
      z = s / 4;
    }
    return Quaternion.identity()
      ..setValues(x, y, z, w)
      ..normalize();
  }
}

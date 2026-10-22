import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_game_engine/graphics_3d.dart' show MeshBuilder;
import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';
import 'spline_path.dart';

/// Sweeps a [SplineSweep3D]'s cross-section along its spline into
/// triangles: flat faces for a road, a wall or a rail, a smooth tube for a
/// pipe, closed at both ends of a spline that does not close on itself.
/// Texture coordinates run in metres: along the spline times the sweep's
/// tiling, and round the cross-section.
abstract final class SplineSweeper {
  /// [sweep]'s mesh along [spline] — the last one made when neither has
  /// changed — or null when the spline has no length.
  static SweptMesh? meshFor(SplineSweep3D sweep, Spline3D spline) {
    sweep.spline = spline;
    final key = sweep.sweepKey;
    if (sweep.cached != null && sweep.cachedKey == key) return sweep.cached;
    final path = SplinePath.of(spline);
    final mesh = path.isEmpty ? null : sweepAlong(sweep, path);
    sweep
      ..cached = mesh
      ..cachedKey = key;
    return mesh;
  }

  /// [sweep]'s cross-section, round its outline (x to the right of the
  /// spline, y up from it), anticlockwise as seen looking along it.
  static List<(double, double)> profileOf(SplineSweep3D sweep) {
    final w = math.max(sweep.width, 0.01) / 2;
    final h = math.max(sweep.height, 0.01);
    final List<(double, double)> outline = switch (sweep.profile) {
      // Its top on the spline.
      SweepProfile.road => [(-w, 0), (w, 0), (w, -h), (-w, -h)],
      // Standing on the spline.
      SweepProfile.wall || SweepProfile.rail => [(-w, 0), (w, 0), (w, h), (-w, h)],
      SweepProfile.pipe => [
        for (var i = 0; i < math.max(3, sweep.sides); i++)
          (
            math.cos(2 * math.pi * i / math.max(3, sweep.sides)) * math.max(sweep.radius, 0.01),
            math.sin(2 * math.pi * i / math.max(3, sweep.sides)) * math.max(sweep.radius, 0.01),
          ),
      ],
    };
    // Anticlockwise (positive area).
    var area = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final (x0, y0) = outline[i];
      final (x1, y1) = outline[(i + 1) % outline.length];
      area += x0 * y1 - x1 * y0;
    }
    return area < 0 ? outline.reversed.toList() : outline;
  }

  /// [sweep] along [path].
  static SweptMesh sweepAlong(SplineSweep3D sweep, SplinePath path) {
    final outline = profileOf(sweep);
    final smooth = sweep.profile == SweepProfile.pipe;
    final step = math.max(sweep.step, 0.05);
    final length = path.length;
    final count = math.max(1, (length / step).ceil());
    final frames = [for (var i = 0; i <= count; i++) path.at(length * i / count)];
    final b = MeshBuilder();
    final tiling = sweep.tiling <= 0 ? 1.0 : sweep.tiling;
    Vector3 place(SplineFrame f, double x, double y) => f.position + f.right * x + f.up * y;
    Vector3 across(SplineFrame f, double x, double y) => (f.right * x + f.up * y)..normalize();

    // Round the outline: how far each corner is.
    final perimeter = <double>[0];
    for (var i = 0; i < outline.length; i++) {
      final (x0, y0) = outline[i];
      final (x1, y1) = outline[(i + 1) % outline.length];
      perimeter.add(perimeter.last + math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)));
    }
    final along = [for (var i = 0; i <= count; i++) length * i / count * tiling];

    if (smooth) {
      // One ring of points per frame, each pointing out from the middle.
      final rings = <List<int>>[];
      for (var k = 0; k <= count; k++) {
        final f = frames[k];
        rings.add([
          for (var i = 0; i <= outline.length; i++)
            () {
              final (x, y) = outline[i % outline.length];
              final p = place(f, x, y), n = across(f, x, y);
              return b.vertex(p.x, p.y, p.z, n.x, n.y, n.z, perimeter[i] * tiling, along[k]);
            }(),
        ]);
      }
      for (var k = 0; k < count; k++) {
        for (var i = 0; i < outline.length; i++) {
          b.quad(rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i]);
        }
      }
    } else {
      // Each side of the outline its own flat face.
      for (var i = 0; i < outline.length; i++) {
        final (x0, y0) = outline[i];
        final (x1, y1) = outline[(i + 1) % outline.length];
        // Out of an anticlockwise outline: to the right of each side.
        final nx = y1 - y0, ny = -(x1 - x0);
        final strip = <(int, int)>[];
        for (var k = 0; k <= count; k++) {
          final f = frames[k];
          final n = across(f, nx, ny);
          final a = place(f, x0, y0), c = place(f, x1, y1);
          strip.add((
            b.vertex(a.x, a.y, a.z, n.x, n.y, n.z, perimeter[i] * tiling, along[k]),
            b.vertex(c.x, c.y, c.z, n.x, n.y, n.z, perimeter[i + 1] * tiling, along[k]),
          ));
        }
        for (var k = 0; k < count; k++) {
          b.quad(strip[k].$1, strip[k].$2, strip[k + 1].$2, strip[k + 1].$1);
        }
      }
    }
    // Ends, where it does not close on itself.
    if (!path.closed) {
      for (final (k, facing) in [(0, -1.0), (count, 1.0)]) {
        final f = frames[k];
        final n = f.tangent * facing;
        final ring = [
          for (final (x, y) in outline)
            () {
              final p = place(f, x, y);
              return b.vertex(p.x, p.y, p.z, n.x, n.y, n.z, x * tiling, y * tiling);
            }(),
        ];
        for (var i = 1; i + 1 < ring.length; i++) {
          b.triangle(ring[0], ring[i], ring[i + 1]);
        }
      }
    }
    final mesh = b.build();
    return SweptMesh(
      Float32List.fromList(mesh.positions),
      Float32List.fromList(mesh.normals),
      Float32List.fromList(mesh.uvs),
      Uint32List.fromList(mesh.indices),
    );
  }
}

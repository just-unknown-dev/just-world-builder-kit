import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_game_engine/graphics_3d.dart';

import 'terrain_data.dart';

/// One piece of a terrain's surface, ready for the renderer: interleaved
/// vertices ([kVertexFloats] each) and triangles, and its box.
final class TerrainChunkMesh {
  TerrainChunkMesh(this.vertices, this.indices, this.bounds);

  final Float32List vertices;
  final Uint32List indices;
  final Aabb3 bounds;

  int get triangleCount => indices.length ~/ 3;
}

/// Builds a terrain's surface a chunk at a time: a vertex per sample at
/// its height (+Y is down), its normal from its neighbours, texture
/// coordinates in metres, and in its colour either the four layers'
/// weights (for a layered material) or the layers' colours mixed. A
/// triangle with a hole at any of its corners is left out, as the height
/// field it is solid as leaves it out.
abstract final class TerrainMesher {
  /// Chunk ([cx], [cz]) — [chunkCells] cells a side — of [data], for a
  /// terrain [size] metres a side about its middle. [colors] mixes the
  /// layers' colours in; null puts the weights in instead.
  static TerrainChunkMesh chunk(
    TerrainData data, {
    required int cx,
    required int cz,
    required int chunkCells,
    required double size,
    List<Color>? colors,
  }) {
    final n = data.resolution;
    final cell = size / (n - 1);
    final origin = -size / 2;
    final i0 = cx * chunkCells, j0 = cz * chunkCells;
    final i1 = math.min(i0 + chunkCells, n - 1), j1 = math.min(j0 + chunkCells, n - 1);
    final w = i1 - i0 + 1, d = j1 - j0 + 1;
    final vertices = Float32List(w * d * kVertexFloats);
    final bounds = Aabb3();
    final mixed = colors == null ? null : [for (final c in colors) GraphicsShapes.linear(c)];
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        final o = ((j - j0) * w + (i - i0)) * kVertexFloats;
        final x = origin + i * cell, z = origin + j * cell, h = data.height(i, j);
        // Its slope from its neighbours: up is -Y.
        final dx = (data.height(i + 1, j) - data.height(i - 1, j)) / (2 * cell);
        final dz = (data.height(i, j + 1) - data.height(i, j - 1)) / (2 * cell);
        final len = math.sqrt(dx * dx + 1 + dz * dz);
        vertices
          ..[o] = x
          ..[o + 1] = -h
          ..[o + 2] = z
          ..[o + 3] = -dx / len
          ..[o + 4] = -1 / len
          ..[o + 5] = -dz / len
          ..[o + 10] = x
          ..[o + 11] = z;
        bounds.addXYZ(x, -h, z);
        final k = data.index(i, j) * 4;
        if (mixed == null) {
          for (var l = 0; l < 4; l++) {
            vertices[o + 12 + l] = data.weights[k + l] / 255;
          }
        } else {
          var r = 0.0, g = 0.0, b = 0.0;
          for (var l = 0; l < 4; l++) {
            final f = data.weights[k + l] / 255;
            r += mixed[l].$1 * f;
            g += mixed[l].$2 * f;
            b += mixed[l].$3 * f;
          }
          vertices
            ..[o + 12] = r
            ..[o + 13] = g
            ..[o + 14] = b
            ..[o + 15] = 1;
        }
      }
    }
    final holes = data.hasHoles;
    final indices = <int>[];
    for (var j = j0; j < j1; j++) {
      for (var i = i0; i < i1; i++) {
        final a = (j - j0) * w + (i - i0), b = a + 1, c = a + w, e = c + 1;
        // Facing up, wound anticlockwise seen from above; split corner b
        // to corner c, as the height field the terrain is solid as is.
        // A hole at any corner of a triangle leaves that triangle out —
        // the height field's rule — so the ground drawn is the ground
        // stood on.
        if (!holes) {
          indices.addAll([a, b, c, b, e, c]);
          continue;
        }
        final hb = data.isHole(i + 1, j), hc = data.isHole(i, j + 1);
        if (!hb && !hc && !data.isHole(i, j)) indices.addAll([a, b, c]);
        if (!hb && !hc && !data.isHole(i + 1, j + 1)) indices.addAll([b, e, c]);
      }
    }
    return TerrainChunkMesh(vertices, Uint32List.fromList(indices), bounds);
  }

  /// Chunks a side, for a terrain of [resolution] samples cut into
  /// [chunkCells]-cell pieces.
  static int chunksPerSide(int resolution, int chunkCells) => ((resolution - 1) + chunkCells - 1) ~/ chunkCells;
}

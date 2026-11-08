// Terrain's surface: meshed a chunk at a time, facing up, holes left out;
// solid as it is drawn.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
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

  group('its surface', () {
    test('a chunk: a vertex a sample, facing up, wound to face up', () {
      final data = TerrainData(9);
      expect(TerrainMesher.chunksPerSide(9, 4), 2);
      final mesh = TerrainMesher.chunk(
        data,
        cx: 0,
        cz: 0,
        chunkCells: 4,
        size: 8,
        colors: Terrain3DComponent.defaultColors,
      );
      expect(mesh.vertices.length, 25 * kVertexFloats);
      expect(mesh.triangleCount, 32);
      final v = mesh.vertices;
      Vector3 at(int i) => Vector3(
        v[i * kVertexFloats],
        v[i * kVertexFloats + 1],
        v[i * kVertexFloats + 2],
      );
      for (var t = 0; t < mesh.indices.length; t += 3) {
        final a = at(mesh.indices[t]),
            b = at(mesh.indices[t + 1]),
            c = at(mesh.indices[t + 2]);
        expect((b - a).cross(c - a).y, lessThan(0), reason: 'up is -Y');
      }
      expect([v[3], v[4], v[5]], [0, -1, 0]);
      expect([v[0], v[2]], [-4, -4], reason: 'about its middle');
      final (r, g, b) = LinearColor.of(Terrain3DComponent.defaultColors.first);
      expect(
        [v[12], v[13], v[14]],
        [closeTo(r, 1e-6), closeTo(g, 1e-6), closeTo(b, 1e-6)],
      );
    });

    test(
      'a hole takes the triangles round it out, as its height field does; layered keeps the weights',
      () {
        final data = TerrainData(9)..setHole(2, 2, true);
        final mesh = TerrainMesher.chunk(
          data,
          cx: 0,
          cz: 0,
          chunkCells: 4,
          size: 8,
        );
        // The six triangles that have the hole for a corner — the height
        // field (Jolt's) leaves out just those: no ground drawn missing
        // where it is solid.
        expect(mesh.triangleCount, 32 - 6);
        const hole = 2 * 5 + 2;
        expect(mesh.indices, isNot(contains(hole)));
        expect(mesh.vertices[12], 1, reason: 'layer 1 all of it');
      },
    );

    test(
      'solid as a height field, holes and all; built again once settled',
      () {
        final data = _bumpy(9)..setHole(1, 1, true);
        final terrain = Terrain3DComponent(size: 16)..loaded = data;
        final field = terrain.solidParts.single as SolidHeightField;
        expect(
          [field.sampleCount, field.cellSize, field.x, field.z],
          [9, 2, -8, -8],
        );
        // Rounded to a float: still a hole.
        expect(
          field.heights[data.index(1, 1)],
          greaterThanOrEqualTo(SolidHeightField.holeHeight),
        );
        expect(field.heights[data.index(2, 1)], data.heights[data.index(2, 1)]);
        data.heights[0] = 7;
        expect(
          identical(terrain.solidParts.single, field),
          isTrue,
          reason: 'not while a stroke goes on',
        );
        data.settle();
        expect((terrain.solidParts.single as SolidHeightField).heights[0], 7);
      },
    );
  });
}

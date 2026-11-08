// Grid tiles drawn: in batches, one per piece for each block of cells.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, Render3DView, rendererNullShaders;

const String _path = 'assets/tiles/test.meshlib.json';

/// A library of a 2 m block (solid as its cell), a ramp (solid as its
/// shape) and grass (not solid).
MeshLibrary _library(ComponentDefinitionRegistry definitions) {
  Map<String, Object?> shape(Primitive3DComponent p) =>
      Map<String, Object?>.from(definitions.encode(p)!);
  return MeshLibrary(
    cellSize: 2,
    items: [
      MeshLibraryItem(
        id: 1,
        name: 'Block',
        shape: shape(Cube3DComponent(width: 2, height: 2, depth: 2)),
      ),
      MeshLibraryItem(
        id: 2,
        name: 'Ramp',
        shape: shape(Ramp3DComponent(width: 2, height: 2, depth: 2)),
        collision: PieceCollision.shape,
      ),
      MeshLibraryItem(
        id: 3,
        name: 'Grass',
        shape: shape(Cube3DComponent(width: 2, height: 0.1, depth: 2)),
        collision: PieceCollision.none,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('drawn', () {
    late Engine engine;
    late Graphics3D service;

    setUp(() async {
      service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
      engine = Engine(
        config: EngineConfig(
          extensions: [WorldBuilderKit.extension],
          services: [service],
        ),
      );
      await engine.initialize();
    });
    tearDown(() => engine.dispose());

    test('in batches, one per piece for each block of cells', () async {
      final library = _library(engine.world.context.definitions);
      engine.world.context.tiles.readText = (path) async => library.encode();
      await MeshLibraries.of(engine.world.context).load(_path);
      final tiles = GridTiles3DComponent(library: _path);
      for (var x = 0; x < 20; x++) {
        tiles.setTile(x, -1, 0, 1);
      }
      tiles.setTile(0, -2, 0, 2);
      engine.world.createEntityWithComponents([TransformComponent(), tiles]);
      final camera = Render3DView()
        ..lookAt(Vector3(20, -20, -30), Vector3(20, 0, 0));
      final view = FrameView()
        ..viewportSize = const Size(64, 64)
        ..isPlanar = false;
      view.view.setFrom(camera.view);
      view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 300);
      view.viewProjection.setProduct(view.projection, view.view);
      view.cameraPosition.setFrom(Vector3(20, -20, -30));
      final renderer = service.sceneRenderer..update(view);
      final counts = [for (final b in renderer.scene.batches) b.count]..sort();
      expect(counts, [
        1,
        4,
        8,
        8,
      ], reason: 'blocks of 8: 8, 8 and 4 blocks, and a ramp');
      tiles.clearTile(19, -1, 0);
      renderer.update(view);
      expect([for (final b in renderer.scene.batches) b.count]..sort(), [
        1,
        3,
        8,
        8,
      ]);
    });
  });
}

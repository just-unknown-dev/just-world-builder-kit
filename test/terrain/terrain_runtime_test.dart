// Terrain at run time: saved and read back, drawn a chunk at a time, one
// solid per file and size, and ready.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, Render3DView, rendererNullShaders;

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

  group('the runtime', () {
    test('saved and read back; its file loaded through its reader', () async {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
      final definitions = world.context.definitions;
      final t =
          Terrain3DComponent(
              data: 'assets/terrain/a.jterrain',
              size: 100,
              material: 'assets/materials/ground.material.json',
            )
            ..colors = [...Terrain3DComponent.defaultColors]
            ..colors[2] = const Color(0xFF123456);
      final back =
          definitions.decode(definitions.encode(t)!)! as Terrain3DComponent;
      expect(
        [back.data, back.size, back.material, back.colors[2]],
        [t.data, 100, t.material, const Color(0xFF123456)],
      );

      final files = TerrainFiles.of(world.context)
        ..read = (path) async => _bumpy(17).encode();
      expect(files.get('assets/terrain/a.jterrain'), isNull, reason: 'loading');
      await files.load('assets/terrain/a.jterrain');
      expect(files.get('assets/terrain/a.jterrain')!.resolution, 17);
      files.read = (path) async => Uint8List(3);
      await files.load('assets/terrain/b.jterrain');
      expect(
        files.errorOf('assets/terrain/b.jterrain'),
        isA<FormatException>(),
      );
    });

    test('drawn a chunk at a time, again only where it changed', () async {
      final service = Graphics3D(
        device: NullGpuDevice(shaders: rendererNullShaders),
      );
      final engine = Engine(
        config: EngineConfig(
          extensions: [WorldBuilderKit.extension],
          services: [service],
        ),
      );
      await engine.initialize();
      addTearDown(engine.dispose);
      final data = TerrainData(65);
      TerrainFiles.of(
        engine.world.context,
      ).put('assets/terrain/t.jterrain', data);
      engine.world.createEntityWithComponents([
        TransformComponent(),
        Terrain3DComponent(data: 'assets/terrain/t.jterrain', size: 64),
      ]);
      final camera = Render3DView()
        ..lookAt(Vector3(0, -40, -60), Vector3.zero());
      final view = FrameView()
        ..viewportSize = const Size(64, 64)
        ..isPlanar = false;
      view.view.setFrom(camera.view);
      view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 300);
      view.viewProjection.setProduct(view.projection, view.view);
      view.cameraPosition.setFrom(Vector3(0, -40, -60));
      final renderer = service.sceneRenderer..update(view);
      final first = [for (final m in renderer.scene.instances) m.primitive];
      expect(first, hasLength(4));
      // A dab in the far corner: one chunk changes.
      TerrainBrush.apply(
        data,
        const TerrainDab(
          mode: TerrainBrushMode.raise,
          x: 60,
          z: 60,
          radius: 2,
          strength: 2,
          seconds: 1,
        ),
      );
      renderer.update(view);
      final second = [for (final m in renderer.scene.instances) m.primitive];
      expect(second, hasLength(4));
      expect(
        [
          for (var k = 0; k < 4; k++) identical(first[k], second[k]),
        ].where((same) => same),
        hasLength(3),
      );
      // Smaller chunks, then bigger: what it keeps is what it draws.
      final provider =
          engine.world.context.renderProviders.forType(Terrain3DComponent)!
              as TerrainRenderProvider;
      final t = engine.world
          .query([Terrain3DComponent])
          .single
          .getComponent<Terrain3DComponent>()!;
      t.chunkCells = 8;
      renderer.update(view);
      expect(provider.chunksKept(data), 64);
      t.chunkCells = 32;
      renderer.update(view);
      expect(provider.chunksKept(data), 4);
    });

    test(
      'terrains on one file and of one size are one solid; any other is its own',
      () {
        final shared = TerrainData(9);
        final a = Terrain3DComponent(size: 16)..loaded = shared;
        final b = Terrain3DComponent(size: 16)..loaded = shared;
        final c = Terrain3DComponent(size: 16)..loaded = TerrainData(9);
        expect(a.solidKey, b.solidKey);
        expect(a.solidKey, isNot(c.solidKey));
        shared.settle();
        expect(a.solidKey, b.solidKey);
        expect(
          a.solidKey,
          isNot((Terrain3DComponent(size: 32)..loaded = shared).solidKey),
        );
      },
    );

    test(
      'ready: a level\'s files read before it runs — solid at once — and the last one\'s let go',
      () async {
        final world = World()..initialize();
        Graphics3D.registerDefinitions(world.context);
        WorldBuilderKit.install(world.context);
        final files = TerrainFiles.of(world.context)
          ..read = (path) async => _bumpy(17).encode();
        await files.load('assets/terrain/old.jterrain');
        final library = MeshLibrary.starter(world.context.definitions).encode();
        world.context.tiles.readText = (path) async => library;
        final terrain = Terrain3DComponent(
          data: 'assets/terrain/new.jterrain',
          size: 32,
        );
        final tiles = GridTiles3DComponent(
          library: 'assets/tiles/blocks.meshlib.json',
        )..setTile(0, -1, 0, 2);
        world
          ..createEntityWithComponents([TransformComponent(), terrain])
          ..createEntityWithComponents([TransformComponent(), tiles]);
        await WorldBuilderKit.ready(world);
        expect(terrain.loaded, isNotNull);
        expect(
          terrain.solidParts.single,
          isA<SolidHeightField>(),
          reason: 'before any step',
        );
        expect(tiles.loaded, isNotNull);
        expect(tiles.solidParts, isNotEmpty);
        expect(
          files.knows('assets/terrain/old.jterrain'),
          isFalse,
          reason: 'no terrain uses it now',
        );
        // Changes not written are never let go.
        files.put('assets/terrain/draft.jterrain', TerrainData(9));
        files.releaseUnused(const []);
        expect(files.get('assets/terrain/draft.jterrain'), isNotNull);
      },
    );

    test('the link system lets go of the files no terrain uses any more', () {
      final world = World(
        context: EngineContext(extensions: [WorldBuilderKit.extension]),
      )..initialize();
      final files = TerrainFiles.of(world.context)
        ..read = (path) async => TerrainData(9).encode();
      world.addSystem(Terrain3DLinkSystem());
      files
        ..put('a.jterrain', TerrainData(9))
        ..saved('a.jterrain')
        ..put('b.jterrain', TerrainData(9))
        ..saved('b.jterrain');
      final a = world.createEntityWithComponents([
        TransformComponent(),
        Terrain3DComponent(data: 'a.jterrain', size: 8),
      ]);
      world.createEntityWithComponents([
        TransformComponent(),
        Terrain3DComponent(data: 'b.jterrain', size: 8),
      ]);
      world.update(1 / 60);
      expect(files.knows('a.jterrain'), isTrue);
      // A level unloaded: what it used is let go; what is still used stays.
      world.destroyEntity(a);
      world.update(1 / 60);
      expect(files.knows('a.jterrain'), isFalse);
      expect(files.knows('b.jterrain'), isTrue);
      world.dispose();
    });
  });
}

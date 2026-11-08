// Mesh libraries: their files, loading through the text seam, the solids
// their pieces make, letting go of those no level uses, and an older
// library's shapes read under their new names.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

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

  group('a mesh library', () {
    late World world;

    setUp(() {
      world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
    });

    test('its file, written and read back', () {
      final library = MeshLibrary.starter(world.context.definitions);
      expect(library.items.map((i) => i.name), [
        'Floor',
        'Block',
        'Wall',
        'Ramp',
        'Stairs',
        'Pillar',
      ]);
      final back = MeshLibrary.parse(library.encode());
      expect(back.encode(), library.encode());
      expect(back.nextId, 7);
      expect(
        () => MeshLibrary.parse('{"format": "other"}'),
        throwsFormatException,
      );
      expect(
        () => MeshLibrary.parse('{"format": "just.meshlib", "version": 99}'),
        throwsFormatException,
      );
    });

    test('loaded through the text seam, its shapes made', () async {
      final text = _library(world.context.definitions).encode();
      world.context.tiles.readText = (path) async =>
          path == _path ? text : throw StateError('no $path');
      final libraries = MeshLibraries.of(world.context);
      expect(libraries.get(_path), isNull, reason: 'loading');
      final before = libraries.revision;
      await libraries.load(_path);
      final library = libraries.get(_path)!;
      expect(libraries.revision, greaterThan(before));
      expect(
        libraries.shapeOf(_path, library.item(2)!),
        isA<Ramp3DComponent>(),
      );
      await libraries.load('assets/tiles/missing.meshlib.json');
      expect(libraries.errorOf('assets/tiles/missing.meshlib.json'), isNotNull);
    });

    test(
      'tiles solid in runs along X, as their shapes, or not at all',
      () async {
        final library = _library(world.context.definitions);
        world.context.tiles.readText = (path) async => library.encode();
        await MeshLibraries.of(world.context).load(_path);
        final tiles = GridTiles3DComponent(library: _path);
        for (var x = 0; x < 3; x++) {
          tiles.setTile(x, -1, 0, 1);
        }
        tiles
          ..setTile(5, -1, 0, 1)
          ..setTile(0, -1, 4, 2, 1)
          ..setTile(0, -1, 8, 3);
        world.createEntityWithComponents([TransformComponent(), tiles]);
        world.addSystem(GridTiles3DLinkSystem());
        world.update(0);
        final parts = tiles.solidParts;
        final boxes = parts.whereType<SolidBox>().toList();
        expect(boxes, hasLength(2), reason: 'a run of three, and one alone');
        final run = boxes.firstWhere((b) => b.halfX > 1.5);
        expect([run.halfX, run.halfY, run.x, run.y], [3, 1, 3, -1]);
        expect(
          parts.where((p) => p is! SolidBox),
          isNotEmpty,
          reason: 'the ramp as its own shape',
        );
        expect(
          identical(tiles.solidParts, parts),
          isTrue,
          reason: 'kept while nothing changes',
        );
        tiles.clearTile(5, -1, 0);
        expect(tiles.solidParts.whereType<SolidBox>(), hasLength(1));
      },
    );

    test(
      'the starter floors and walls are solid as their slabs, not their cells',
      () async {
        final text = MeshLibrary.starter(world.context.definitions).encode();
        world.context.tiles.readText = (path) async => text;
        final libraries = MeshLibraries.of(world.context);
        await libraries.load(_path);
        final tiles = GridTiles3DComponent(library: _path)
          ..setTile(0, -1, 0, 1) // a floor, on the ground
          ..setTile(3, -1, 0, 3) // a wall
          ..link(libraries);
        final boxes = tiles.solidParts.whereType<SolidBox>().toList();
        expect(boxes, hasLength(2));
        final floor = boxes.firstWhere((b) => b.halfY < 0.5);
        // +Y is down: its top 0.2 m up, its bottom on the ground — as drawn.
        expect(
          [floor.y - floor.halfY, floor.y + floor.halfY],
          [closeTo(-0.2, 1e-6), closeTo(0, 1e-6)],
        );
        expect([floor.halfX, floor.halfZ], [1, 1]);
        final wall = boxes.firstWhere((b) => b.halfY > 0.5);
        expect(
          [wall.halfZ, wall.z],
          [closeTo(0.1, 1e-6), closeTo(0.1, 1e-6)],
          reason: '0.2 m thick, at its cell\'s side',
        );
      },
    );

    test('a piece taken out leaves its number behind', () {
      final library = MeshLibrary.starter(world.context.definitions)..remove(6);
      expect(
        library.takeId(),
        7,
        reason: 'not 6: tiles of the pillar stay empty',
      );
      final back = MeshLibrary.parse(library.encode());
      expect(back.nextId, 8);
      // A file from before the number was kept: its highest piece taken out.
      final old = MeshLibrary.parse(
        '{"format": "just.meshlib", "version": 1, "items": [{"id": 1}, {"id": 2}]}',
      )..remove(2);
      expect(old.takeId(), 3);
    });

    test(
      'a piece whose shape cannot be made: solid as its cell and said, never a throw',
      () async {
        final bad = MeshLibrary(
          items: [
            MeshLibraryItem(
              id: 1,
              name: 'Broken',
              shape: {
                'type': 'Ramp3DComponent',
                'fields': {'height': 'tall'},
              },
              collision: PieceCollision.shape,
            ),
          ],
        );
        world.context.tiles.readText = (path) async => bad.encode();
        final libraries = MeshLibraries.of(world.context);
        await libraries.load(_path);
        final tiles = GridTiles3DComponent(library: _path)
          ..setTile(0, -1, 0, 1)
          ..link(libraries);
        final box = tiles.solidParts.single as SolidBox;
        expect(box.halfX, 1, reason: 'as its cell');
        expect(libraries.errorOf(_path), isA<FormatException>());
        expect(
          libraries.get(_path),
          isNotNull,
          reason: 'the rest of it still read',
        );
      },
    );

    test(
      'two grids on one library, read from a scene, are each solid as itself',
      () async {
        final library = _library(world.context.definitions);
        world.context.tiles.readText = (path) async => library.encode();
        final libraries = MeshLibraries.of(world.context);
        await libraries.load(_path);
        final definitions = world.context.definitions;
        GridTiles3DComponent read(GridTiles3DComponent tiles) =>
            (definitions.decode(definitions.encode(tiles)!)!
                  as GridTiles3DComponent)
              ..link(libraries);
        final a = read(
          GridTiles3DComponent(library: _path)..setTile(0, -1, 0, 1),
        );
        final b = read(
          GridTiles3DComponent(library: _path)
            ..setTile(5, -1, 5, 1)
            ..setTile(6, -1, 5, 1),
        );
        expect(a.revision, b.revision, reason: 'what made their keys the same');
        expect(a.solidKey, isNot(b.solidKey));
        // The engine keeps shapes by key: each its own.
        final shapes = Collider3DShapes();
        final collider = Collider3DComponent(shape: Collider3DShape.matchShape);
        final one = Vector3(1, 1, 1);
        expect(
          identical(
            shapes.build(collider, one, source: a),
            shapes.build(collider, one, source: b),
          ),
          isFalse,
        );
        expect(
          identical(
            shapes.build(collider, one, source: a),
            shapes.build(collider, one, source: a),
          ),
          isTrue,
        );
      },
    );

    test('libraries no level uses are let go', () async {
      final library = _library(world.context.definitions);
      world.context.tiles.readText = (path) async => library.encode();
      final libraries = MeshLibraries.of(world.context);
      const other = 'assets/tiles/other.meshlib.json';
      await libraries.load(_path);
      await libraries.load(other);
      libraries.releaseUnused([_path]);
      expect(libraries.get(_path), isNotNull);
      expect(
        libraries.get(other),
        isNull,
        reason: 'read again, when next asked for',
      );
    });
  });

  test(
    'a library read, read again or let go: whoever listens is told',
    () async {
      final context = EngineContext(extensions: [WorldBuilderKit.extension]);
      context.tiles.readText = (path) async =>
          MeshLibrary(cellSize: 2).encode();
      final libraries = MeshLibraries.of(context);
      var told = 0;
      void listener() => told++;
      libraries.changes.addListener(listener);
      await libraries.ready(_path);
      expect(told, 1, reason: 'loaded');
      await libraries.ready(_path);
      expect(told, 1, reason: 'ready reads it only once');
      libraries.forget(_path);
      expect(told, 2, reason: 'forgotten: to be read again');
      await libraries.ready(_path);
      libraries.releaseUnused(const []);
      expect(told, 4, reason: 'read again, then let go');
      libraries.changes.removeListener(listener);
    },
  );

  test(
    'the link system lets go of the libraries no grid uses any more',
    () async {
      final world = World(
        context: EngineContext(extensions: [WorldBuilderKit.extension]),
      )..initialize();
      world.context.tiles.readText = (path) async =>
          MeshLibrary(cellSize: 2).encode();
      final libraries = MeshLibraries.of(world.context);
      world.addSystem(GridTiles3DLinkSystem());
      final a = world.createEntityWithComponents([
        TransformComponent(),
        GridTiles3DComponent(library: 'a$_path'),
      ]);
      world.createEntityWithComponents([
        TransformComponent(),
        GridTiles3DComponent(library: 'b$_path'),
      ]);
      await libraries.ready('a$_path');
      await libraries.ready('b$_path');
      world.update(1 / 60);
      expect(libraries.get('a$_path'), isNotNull);
      // A level unloaded: what it used is let go.
      world.destroyEntity(a);
      world.update(1 / 60);
      world.update(1 / 60);
      expect(libraries.errorOf('a$_path'), isNull);
      var loading = false;
      world.context.tiles.readText = (path) async {
        loading = true;
        return MeshLibrary(cellSize: 2).encode();
      };
      expect(
        libraries.get('a$_path'),
        isNull,
        reason: 'let go: asked for, it is read again',
      );
      expect(loading, isTrue);
      expect(libraries.get('b$_path'), isNotNull, reason: 'still used');
      world.dispose();
    },
  );

  test('a version 1 mesh library reads its shapes under their new names', () {
    final library = MeshLibrary.parse(
      jsonEncode({
        'format': MeshLibrary.format,
        'version': 1,
        'cellSize': 2,
        'items': [
          {
            'id': 1,
            'name': 'Block',
            'shape': {
              'type': 'Cube3D',
              'fields': {'material': ''},
            },
          },
          {'id': 2, 'name': 'Rock', 'model': 'assets/models/rock.glb'},
        ],
      }),
    );
    expect(library.item(1)!.shape, {
      'type': 'Cube3DComponent',
      'fields': {'material': ''},
    });
    expect(library.item(2)!.shape, isNull);
    expect(jsonDecode(library.encode())['version'], MeshLibrary.version);
  });
}

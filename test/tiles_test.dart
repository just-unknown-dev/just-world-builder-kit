// Grid tiles: the 24 turns of a cell; cells packed small and read back; a
// mesh library's file; tiles solid in runs, and as their shapes; drawn in
// batches by block; and the Tiles tool — paint, a run, erase, fill, turn,
// pick — each stroke one undo step.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

const String _path = 'assets/tiles/test.meshlib.json';

/// A library of a 2 m block (solid as its cell), a ramp (solid as its
/// shape) and grass (not solid).
MeshLibrary _library(ComponentDefinitionRegistry definitions) {
  Map<String, Object?> shape(Primitive3D p) => Map<String, Object?>.from(definitions.encode(p)!);
  return MeshLibrary(
    cellSize: 2,
    items: [
      MeshLibraryItem(id: 1, name: 'Block', shape: shape(Cube3D(width: 2, height: 2, depth: 2))),
      MeshLibraryItem(id: 2, name: 'Ramp', shape: shape(Ramp3D(width: 2, height: 2, depth: 2)), collision: PieceCollision.shape),
      MeshLibraryItem(id: 3, name: 'Grass', shape: shape(Cube3D(width: 2, height: 0.1, depth: 2)), collision: PieceCollision.none),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('turns', () {
    test('24 different ones, the first as made', () {
      final seen = {for (var i = 0; i < GridOrientations.count; i++) GridOrientations.matrixOf(i).join(',')};
      expect(seen, hasLength(24));
      expect(GridOrientations.matrixOf(0), [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    });

    test('the first four only spin: up stays up', () {
      for (var i = 0; i < 4; i++) {
        final up = GridOrientations.apply(i, Vector3(0, -1, 0));
        expect([up.x, up.y, up.z], [0, -1, 0]);
      }
      expect(GridOrientations.apply(4, Vector3(0, -1, 0)).y, 1, reason: 'then upside down');
    });

    test('turned about an axis and back; four turns come round', () {
      for (var i = 0; i < 24; i++) {
        for (var axis = 0; axis < 3; axis++) {
          expect(GridOrientations.turned(GridOrientations.turned(i, axis), axis, -1), i);
          expect(GridOrientations.turned(i, axis, 4), i);
        }
      }
      // A quarter turn about up from as made: the first spin.
      expect(GridOrientations.turned(0, 1), 1);
    });

    test('its turn matches its matrix', () {
      for (var i = 0; i < 24; i++) {
        final v = Vector3(1, 2, 3);
        GridOrientations.of(i).rotate(v);
        final m = GridOrientations.apply(i, Vector3(1, 2, 3));
        expect([v.x, v.y, v.z], [closeTo(m.x, 1e-9), closeTo(m.y, 1e-9), closeTo(m.z, 1e-9)]);
      }
    });
  });

  group('cells', () {
    test('a cell\'s key and back, below zero too', () {
      for (final (x, y, z) in [(0, 0, 0), (-1, -5, 7), (32767, -32768, 12), (-300, 2, -9)]) {
        final c = GridTiles3D.cellOf(GridTiles3D.keyOf(x, y, z));
        expect([c.x, c.y, c.z], [x, y, z]);
      }
      final t = GridTiles3D.unpack(GridTiles3D.pack(1234, 23));
      expect([t.item, t.orientation], [1234, 23]);
    });

    test('packed small and read back', () {
      final random = math.Random(7);
      final cells = <int, int>{
        for (var i = 0; i < 1000; i++)
          GridTiles3D.keyOf(random.nextInt(200) - 100, -random.nextInt(20), random.nextInt(200) - 100): GridTiles3D.pack(1 + random.nextInt(5), random.nextInt(24)),
      };
      final text = GridCellsFieldType.encodeCells(cells);
      expect(GridCellsFieldType.decodeCells(text), cells);
      expect(text.length, lessThan(cells.length * 10 * 4 ~/ 3), reason: 'packed');
      expect(GridCellsFieldType.decodeCells(GridCellsFieldType.encodeCells({})), isEmpty);
      expect(() => GridCellsFieldType.decodeCells('bm90IHRpbGVz'), throwsA(anything));
    });
  });

  group('a mesh library', () {
    late World world;

    setUp(() {
      world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
    });

    test('its file, written and read back', () {
      final library = MeshLibrary.starter(world.context.definitions);
      expect(library.items.map((i) => i.name), ['Floor', 'Block', 'Wall', 'Ramp', 'Stairs', 'Pillar']);
      final back = MeshLibrary.parse(library.encode());
      expect(back.encode(), library.encode());
      expect(back.nextId, 7);
      expect(() => MeshLibrary.parse('{"format": "other"}'), throwsFormatException);
      expect(() => MeshLibrary.parse('{"format": "just.meshlib", "version": 99}'), throwsFormatException);
    });

    test('loaded through the text seam, its shapes made', () async {
      final text = _library(world.context.definitions).encode();
      world.context.tiles.readText = (path) async => path == _path ? text : throw StateError('no $path');
      final libraries = MeshLibraries.of(world.context);
      expect(libraries.get(_path), isNull, reason: 'loading');
      final before = libraries.revision;
      await libraries.load(_path);
      final library = libraries.get(_path)!;
      expect(libraries.revision, greaterThan(before));
      expect(libraries.shapeOf(_path, library.item(2)!), isA<Ramp3D>());
      await libraries.load('assets/tiles/missing.meshlib.json');
      expect(libraries.errorOf('assets/tiles/missing.meshlib.json'), isNotNull);
    });

    test('tiles solid in runs along X, as their shapes, or not at all', () async {
      final library = _library(world.context.definitions);
      world.context.tiles.readText = (path) async => library.encode();
      await MeshLibraries.of(world.context).load(_path);
      final tiles = GridTiles3D(library: _path);
      for (var x = 0; x < 3; x++) {
        tiles.setTile(x, -1, 0, 1);
      }
      tiles
        ..setTile(5, -1, 0, 1)
        ..setTile(0, -1, 4, 2, 1)
        ..setTile(0, -1, 8, 3);
      world.createEntityWithComponents([TransformComponent(), tiles]);
      world.addSystem(GridTilesLinkSystem());
      world.update(0);
      final parts = tiles.solidParts;
      final boxes = parts.whereType<SolidBox>().toList();
      expect(boxes, hasLength(2), reason: 'a run of three, and one alone');
      final run = boxes.firstWhere((b) => b.halfX > 1.5);
      expect([run.halfX, run.halfY, run.x, run.y], [3, 1, 3, -1]);
      expect(parts.where((p) => p is! SolidBox), isNotEmpty, reason: 'the ramp as its own shape');
      expect(identical(tiles.solidParts, parts), isTrue, reason: 'kept while nothing changes');
      tiles.clearTile(5, -1, 0);
      expect(tiles.solidParts.whereType<SolidBox>(), hasLength(1));
    });
  });

  group('drawn', () {
    late Engine engine;
    late Graphics3D service;

    setUp(() async {
      service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
      engine = Engine(config: EngineConfig(extensions: [WorldBuilderKit.extension], graphics3D: service));
      await engine.initialize();
    });
    tearDown(() => engine.dispose());

    test('in batches, one per piece for each block of cells', () async {
      final library = _library(engine.world.context.definitions);
      engine.world.context.tiles.readText = (path) async => library.encode();
      await MeshLibraries.of(engine.world.context).load(_path);
      final tiles = GridTiles3D(library: _path);
      for (var x = 0; x < 20; x++) {
        tiles.setTile(x, -1, 0, 1);
      }
      tiles.setTile(0, -2, 0, 2);
      engine.world.createEntityWithComponents([TransformComponent(), tiles]);
      final camera = RenderView()..lookAt(Vector3(20, -20, -30), Vector3(20, 0, 0));
      final view = FrameView()
        ..viewportSize = const Size(64, 64)
        ..isPlanar = false;
      view.view.setFrom(camera.view);
      view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 300);
      view.viewProjection.setProduct(view.projection, view.view);
      view.cameraPosition.setFrom(Vector3(20, -20, -30));
      final renderer = service.sceneRenderer..update(view);
      final counts = [for (final b in renderer.scene.batches) b.count]..sort();
      expect(counts, [1, 4, 8, 8], reason: 'blocks of 8: 8, 8 and 4 blocks, and a ramp');
      tiles.clearTile(19, -1, 0);
      renderer.update(view);
      expect([for (final b in renderer.scene.batches) b.count]..sort(), [1, 3, 8, 8]);
    });
  });

  group('the Tiles tool', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() async {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      final text = _library(world.context.definitions).encode();
      world.context.tiles.readText = (path) async => text;
      await MeshLibraries.of(world.context).load(_path);
      scope = EditorScope(world: world, modules: [WorldBuilderModule()], builtIns: const [BuiltInEditorModule.new]);
      addTearDown(scope.dispose);
      scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
      scope.selectDesigner('world_builder');
      view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
        ..viewportSize = const Size(400, 400)
        ..pivot.setValues(4, 0, 4)
        ..distance = 30
        ..yaw = 0.3
        ..pitch = -0.9;
      view.sync();
      modifiers = const ModifierKeys();
      session = LevelDesignerSession(
        scope: scope,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => modifiers,
        camera: () => view,
      );
      addTearDown(session.dispose);
      session.controller.snapEnabled.value = false;
      session.setTool(GridTileTool.toolId);
      (session.tools.byId(GridTileTool.toolId)! as GridTileTool).library.value = _path;
    });

    GridTileTool tool() => session.tools.byId(GridTileTool.toolId)! as GridTileTool;
    Offset at(Vector3 p) => view.projectToScreen(p)!;
    void press(Vector3 p) => session.onPointerDown(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void move(Vector3 p) => session.onPointerMove(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void release(Vector3 p) => session.onPointerUp(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void click(Vector3 p) {
      press(p);
      release(p);
    }

    GridTiles3D tiles() => scope.world.query([GridTiles3D]).single.getComponent<GridTiles3D>()!;

    test('a click on the floor: a tile there, in new tiles, one undo step', () {
      tool().onSurfaces.value = false;
      click(Vector3(1, 0, 1));
      final t = tiles();
      expect(t.tileAt(0, -1, 0), (item: 1, orientation: 0), reason: 'on the ground, a cell up');
      final entity = scope.world.query([GridTiles3D]).single;
      expect(entity.getComponent<Collider3D>()!.shape, ColliderShape3D.matchShape);
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(scope.world.query([GridTiles3D]), isEmpty);
    });

    test('a drag paints a run; another stroke is its own undo step', () {
      tool().onSurfaces.value = false;
      click(Vector3(1, 0, 1));
      press(Vector3(3, 0, 1));
      move(Vector3(5, 0, 1));
      move(Vector3(7, 0, 1));
      release(Vector3(7, 0, 1));
      expect(tiles().cells, hasLength(4));
      expect(scope.history.undoEntries, hasLength(2));
      scope.history.undo();
      expect(tiles().cells, hasLength(1));
      scope.history.redo();
      expect(tiles().cells, hasLength(4));
    });

    test('stacked on what is under the pointer', () {
      tool().onSurfaces.value = false;
      click(Vector3(1, 0, 1));
      tool().onSurfaces.value = true;
      // The top of the first tile, 2 m up.
      click(Vector3(1, -2, 1));
      expect(tiles().tileAt(0, -2, 0), isNotNull, reason: 'one on top');
    });

    test('erase and fill', () {
      tool()
        ..onSurfaces.value = false
        ..mode.value = GridTileMode.fill;
      press(Vector3(1, 0, 1));
      move(Vector3(5, 0, 5));
      release(Vector3(5, 0, 5));
      expect(tiles().cells, hasLength(9), reason: 'three by three');
      tool().mode.value = GridTileMode.erase;
      click(Vector3(3, -2, 3));
      expect(tiles().cells, hasLength(8));
      expect(tiles().tileAt(1, -1, 1), isNull);
    });

    test('turned with Z and X, the floor with Page Up; Alt-click picks one up', () {
      expect(session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32), isTrue);
      expect(tool().orientation.value, 1);
      modifiers = const ModifierKeys(shift: true);
      session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32);
      expect(tool().orientation.value, 0);
      modifiers = const ModifierKeys();
      session.handleKey(LogicalKeyboardKey.keyX, gridSize: 32);
      expect(tool().orientation.value, isNot(0));
      session.handleKey(LogicalKeyboardKey.pageUp, gridSize: 32);
      expect(tool().floor.value, 1);
      tool()
        ..floor.value = 0
        ..onSurfaces.value = false
        ..item.value = 2;
      final turn = tool().orientation.value;
      click(Vector3(1, 0, 1));
      tool()
        ..item.value = 1
        ..orientation.value = 0;
      modifiers = const ModifierKeys(alt: true);
      click(Vector3(1, -2, 1));
      expect([tool().item.value, tool().orientation.value], [2, turn]);
    });
  });

  group('the mesh library workspace', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('meshlib_');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    testWidgets('a new library; pieces added, undone, saved', (tester) async {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      final files = MeshLibraryFiles(dir.path);
      final path = (await tester.runAsync(() => files.create(world.context.definitions)))!;
      expect(path, 'assets/tiles/tiles${MeshLibrary.ending}');
      expect(files.list(), [path]);
      final scope = EditorScope(world: world, modules: const []);
      addTearDown(scope.dispose);
      final reloaded = <String>[];
      final key = GlobalKey<MeshLibraryWorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeshLibraryWorkspace(
              key: key,
              path: path,
              root: dir.path,
              definitions: world.context.definitions,
              workspace: WorkspaceContext(scope: scope, onClose: () {}, path: path, reloadAssets: reloaded.add),
              loadOnStart: false,
            ),
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      expect(state.library.items, hasLength(6));
      expect(state.dirty, isFalse);

      state.addShape('Arch', meshLibraryShapes.last.$2);
      state.edit((l) => l.cellSize = 3);
      state.undo();
      expect(state.library.cellSize, 2);
      expect(state.library.items.last.id, 7);
      expect(state.dirty, isTrue);
      await tester.pump();

      await tester.runAsync(state.save);
      expect(state.dirty, isFalse);
      expect(reloaded, [path]);
      final saved = MeshLibrary.parse(File('${dir.path}/$path').readAsStringSync());
      expect(saved.items.last.name, 'Arch');
      expect(world.context.definitions.decode(Map<String, dynamic>.from(saved.items.last.shape!)), isA<Arch3D>());
      expect(tester.takeException(), isNull);
    });
  });
}

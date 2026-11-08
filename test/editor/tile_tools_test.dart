// The Tiles tool: paint, erase, fill, pick, floors and turns; a stroke
// one undo step.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
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

  group('the Tiles tool', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() async {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
      final text = _library(world.context.definitions).encode();
      world.context.tiles.readText = (path) async => text;
      await MeshLibraries.of(world.context).load(_path);
      scope = EditorScope(
        world: world,
        modules: [WorldBuilderModule()],
        builtIns: const [BuiltInEditorModule.new],
      );
      addTearDown(scope.dispose);
      scope.sceneState.openScene(
        EditorScene(name: 'level', mode: SceneMode.threeD),
      );
      scope.selectDesigner('world_builder');
      view =
          OrbitFlyEditorView.of(
              OutputCamera(viewportSize: const Size(400, 400)),
            )
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
      (session.tools.byId(GridTileTool.toolId)! as GridTileTool).library.value =
          _path;
    });

    GridTileTool tool() =>
        session.tools.byId(GridTileTool.toolId)! as GridTileTool;
    Offset at(Vector3 p) => view.projectToScreen(p)!;
    void press(Vector3 p) => session.onPointerDown(
      Offset.zero,
      32,
      screen: at(p),
      canvasSize: const Size(400, 400),
    );
    void move(Vector3 p) => session.onPointerMove(
      Offset.zero,
      32,
      screen: at(p),
      canvasSize: const Size(400, 400),
    );
    void release(Vector3 p) => session.onPointerUp(
      Offset.zero,
      32,
      screen: at(p),
      canvasSize: const Size(400, 400),
    );
    void click(Vector3 p) {
      press(p);
      release(p);
    }

    GridTiles3DComponent tiles() => scope.world
        .query([GridTiles3DComponent])
        .single
        .getComponent<GridTiles3DComponent>()!;

    test('a click on the floor: a tile there, in new tiles, one undo step', () {
      tool().onSurfaces.value = false;
      click(Vector3(1, 0, 1));
      final t = tiles();
      expect(t.tileAt(0, -1, 0), (
        item: 1,
        orientation: 0,
      ), reason: 'on the ground, a cell up');
      final entity = scope.world.query([GridTiles3DComponent]).single;
      expect(
        entity.getComponent<Collider3DComponent>()!.shape,
        Collider3DShape.matchShape,
      );
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(scope.world.query([GridTiles3DComponent]), isEmpty);
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

    test(
      'a drag on surfaces paints along the level it began on, not up the tiles it paints',
      () {
        click(Vector3(1, 0, 1));
        tiles().link(MeshLibraries.of(scope.world.context));
        expect(tool().onSurfaces.value, isTrue);
        press(Vector3(3, 0, 1));
        move(Vector3(3.3, 0, 1.2)); // over the tile just painted
        move(Vector3(3.6, 0, 1.4));
        move(Vector3(5, 0, 1));
        release(Vector3(5, 0, 1));
        final cells = [
          for (final key in tiles().cells.keys)
            GridTiles3DComponent.cellOf(key),
        ];
        expect(cells.map((c) => c.y).toSet(), {
          -1,
        }, reason: 'one level: $cells');
        expect(cells, hasLength(3));
      },
    );

    test(
      'a selected grid on another library is painted from that library',
      () async {
        const other = 'assets/tiles/small.meshlib.json';
        final small = MeshLibrary(
          cellSize: 1,
          items: [
            MeshLibraryItem(
              id: 10,
              name: 'Brick',
              shape: Map<String, Object?>.from(
                scope.context.definitions.encode(Cube3DComponent())!,
              ),
            ),
          ],
        );
        final text = _library(scope.context.definitions).encode();
        scope.context.tiles.readText = (path) async =>
            path == other ? small.encode() : text;
        await MeshLibraries.of(scope.context).load(other);
        final grid = scope.world.createEntityWithComponents([
          TransformComponent(),
          GridTiles3DComponent(library: other),
        ], name: 'Small');
        scope.sceneState
          ..registerEntity(grid)
          ..selectEntity(grid);
        tool().onSurfaces.value = false;
        click(Vector3(1.5, 0, 0.5));
        expect(tool().library.value, other);
        final cells = grid.getComponent<GridTiles3DComponent>()!;
        expect(cells.tileAt(1, -1, 0), (
          item: 10,
          orientation: 0,
        ), reason: 'its piece, on its 1 m cells');
        expect(
          scope.world.query([GridTiles3DComponent]),
          hasLength(1),
          reason: 'no grid of another library made',
        );
      },
    );

    test('a stroke into an unnamed grid is undone like any other', () {
      final grid = scope.world.createEntityWithComponents([
        TransformComponent(),
        GridTiles3DComponent(library: _path),
      ]);
      scope.sceneState
        ..registerEntity(grid)
        ..selectEntity(grid);
      tool().onSurfaces.value = false;
      click(Vector3(1, 0, 1));
      final cells = grid.getComponent<GridTiles3DComponent>()!;
      expect(cells.cells, hasLength(1));
      scope.history.undo();
      expect(cells.cells, isEmpty);
      scope.history.redo();
      expect(cells.cells, hasLength(1));
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

    test('an erase over a surface with no tiles to erase from makes none', () {
      // A slab, its top at y = 0: a surface, but no tiles.
      final slab = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(4, 0.5, 4)),
        Cube3DComponent(width: 20, height: 1, depth: 20),
      ], name: 'Slab');
      scope.sceneState.registerEntity(slab);
      tool().mode.value = GridTileMode.erase;
      press(Vector3(1, 0, 1));
      move(Vector3(5, 0, 1));
      release(Vector3(5, 0, 1));
      expect(scope.world.query([GridTiles3DComponent]), isEmpty);
      expect(scope.history.undoEntries, isEmpty);
    });

    test('a fast drag paints every cell it passes over', () {
      tool().onSurfaces.value = false;
      press(Vector3(1, 0, 1));
      // One move, four cells on.
      move(Vector3(9, 0, 1));
      release(Vector3(9, 0, 1));
      expect(tiles().cells, hasLength(5));
      for (var x = 0; x <= 4; x++) {
        expect(tiles().tileAt(x, -1, 0), isNotNull, reason: 'cell $x');
      }
      expect(scope.history.undoEntries, hasLength(1));
    });

    test(
      'a fill keeps its box when the floor changes under it, and reaches so far at most',
      () {
        tool()
          ..onSurfaces.value = false
          ..mode.value = GridTileMode.fill;
        press(Vector3(1, 0, 1));
        move(Vector3(5, 0, 5));
        // Page Up mid-fill shows the floor above, not this box.
        expect(
          session.handleKey(LogicalKeyboardKey.pageUp, gridSize: 32),
          isTrue,
        );
        final box = tool().preview.value!;
        expect((box.from, box.to), ((x: 0, y: -1, z: 0), (x: 2, y: -1, z: 2)));
        release(Vector3(5, 0, 5));
        expect(
          tiles().cells,
          hasLength(9),
          reason: 'three by three, on the floor it began on',
        );

        // Dragged toward the horizon: no more than the most a fill spans.
        tool().floor.value = 0;
        press(Vector3(1, 0, 1));
        // Far off on the floor, some way the camera looks.
        final ahead = [
          for (final (x, z) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)])
            Vector3(1 + x * 1200.0, 0, 1 + z * 1200.0),
        ].firstWhere((p) => view.projectToScreen(p) != null);
        move(ahead);
        final far = tool().preview.value!;
        expect(
          (far.to.x - far.from.x).abs(),
          lessThan(GridTileTool.maxFillCells),
        );
        expect(
          (far.to.z - far.from.z).abs(),
          lessThan(GridTileTool.maxFillCells),
        );
        expect(
          session.handleKey(LogicalKeyboardKey.escape, gridSize: 32),
          isTrue,
        );
        expect(tiles().cells, hasLength(9), reason: 'called off');
      },
    );

    test('the preview goes when the pointer leaves the viewport', () {
      tool().onSurfaces.value = false;
      session.onPointerHover(
        Offset.zero,
        32,
        screen: at(Vector3(1, 0, 1)),
        canvasSize: const Size(400, 400),
      );
      expect(tool().preview.value, isNotNull);
      session.onPointerExit();
      expect(tool().preview.value, isNull);
    });

    test(
      'turned with Z and X, the floor with Page Up; Alt-click picks one up',
      () {
        expect(
          session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32),
          isTrue,
        );
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
      },
    );
  });
}

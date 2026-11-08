// The Terrain tool and panel: a new terrain, strokes one undo step each,
// files written as the scene is saved, a shared file made unique.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

int data0(int n, int i, int j) => j * n + i;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the editor', () {
    late Directory root;
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() {
      root = Directory.systemTemp.createTempSync('terrain_');
      addTearDown(() => root.deleteSync(recursive: true));
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
      scope = EditorScope(
        world: world,
        modules: [WorldBuilderModule(root: root.path)],
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
            ..pivot.setValues(0, 0, 0)
            ..distance = 40
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
      session.setTool(TerrainSculptTool.toolId);
    });

    TerrainSculptTool tool() =>
        session.tools.byId(TerrainSculptTool.toolId)! as TerrainSculptTool;
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

    Entity terrain() => makeTerrain(
      tool().designer,
      sceneName: 'level',
      size: 32,
      resolution: 33,
    );

    test('a new terrain: its file beside the scene, one undo step', () {
      final e = terrain();
      final t = e.getComponent<Terrain3DComponent>()!;
      expect(t.data, 'assets/terrain/level/${e.name}.jterrain');
      expect(TerrainFiles.of(scope.context).unsaved, {t.data});
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a stroke raises the ground; undone exactly, redone', () {
      final t = terrain().getComponent<Terrain3DComponent>()!;
      final data = t.loaded ?? TerrainFiles.of(scope.context).get(t.data)!;
      final flat = Float32List.fromList(data.heights);
      final solid = data.solidRevision;
      press(Vector3(0, 0, 0));
      move(Vector3(3, 0, 0));
      release(Vector3(3, 0, 0));
      expect(data.heights.reduce(math.max), greaterThan(0.05));
      expect(
        data.solidRevision,
        greaterThan(solid),
        reason: 'solid again once the stroke is done',
      );
      expect(scope.history.undoEntries, hasLength(2));
      final raised = Float32List.fromList(data.heights);
      scope.history.undo();
      expect(data.heights, flat);
      scope.history.redo();
      expect(data.heights, raised);
    });

    test('Shift lowers; [ and ] size the brush', () {
      final t = terrain().getComponent<Terrain3DComponent>()!;
      final data = TerrainFiles.of(scope.context).get(t.data)!;
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      expect(data.heights.reduce(math.min), lessThan(0));
      modifiers = const ModifierKeys();
      session.handleKey(LogicalKeyboardKey.bracketRight, gridSize: 32);
      expect(tool().radius.value, 8);
    });

    test('its file written as the scene is saved', () async {
      final t = terrain().getComponent<Terrain3DComponent>()!;
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      final failed = await scope.modules.notifySceneSaving('level');
      expect(failed, isEmpty);
      final file = File('${root.path}/${t.data}');
      expect(file.existsSync(), isTrue);
      expect(
        TerrainData.decode(file.readAsBytesSync()).heights,
        TerrainFiles.of(scope.context).get(t.data)!.heights,
      );
      expect(TerrainFiles.of(scope.context).unsaved, isEmpty);
    });

    test('a shared file made unique: a copy of its own, one undo step', () {
      final first = terrain();
      final t = first.getComponent<Terrain3DComponent>()!;
      final twin = scope.world.createEntityWithComponents([
        TransformComponent(),
        Terrain3DComponent(data: t.data, size: 32),
      ], name: 'Twin');
      scope.sceneState.registerEntity(twin);
      final files = TerrainFiles.of(scope.context);
      twin.getComponent<Terrain3DComponent>()!.link(files);
      makeTerrainUnique(scope, twin, sceneName: 'level');
      final own = twin.getComponent<Terrain3DComponent>()!.data;
      expect(own, isNot(t.data));
      expect(identical(files.get(own), files.get(t.data)), isFalse);
      scope.history.undo();
      expect(twin.getComponent<Terrain3DComponent>()!.data, t.data);
    });

    test(
      'a terrain made unique keeps its copy once the disk has been looked at',
      () async {
        final first = terrain();
        final t = first.getComponent<Terrain3DComponent>()!;
        final twin = scope.world.createEntityWithComponents([
          TransformComponent(),
          Terrain3DComponent(data: t.data, size: 32),
        ], name: 'Twin');
        scope.sceneState.registerEntity(twin);
        final files = TerrainFiles.of(scope.context);
        twin.getComponent<Terrain3DComponent>()!.link(files);
        // A file of the first free name on disk already: passed over.
        File('${root.path}/assets/terrain/level/Twin_2.jterrain')
          ..createSync(recursive: true)
          ..writeAsBytesSync(TerrainData(9).encode());
        makeTerrainUnique(scope, twin, sceneName: 'level', root: root.path);
        final own = twin.getComponent<Terrain3DComponent>()!.data;
        expect(own, 'assets/terrain/level/Twin_3.jterrain');
        final copy = files.get(own);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(files.get(own), isNotNull);
        expect(
          identical(files.get(own), copy),
          isTrue,
          reason: 'no read came back over it',
        );
        final failed = await scope.modules.notifySceneSaving('level');
        expect(failed, isEmpty);
        expect(
          File('${root.path}/$own').existsSync(),
          isTrue,
          reason: 'written with the scene',
        );
      },
    );

    test('ground put while its file is read is kept', () async {
      final files = TerrainFiles.of(scope.context)
        ..read = (path) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw const FileSystemException('not there');
        };
      const path = 'assets/terrain/level/late.jterrain';
      expect(files.get(path), isNull, reason: 'reading');
      final put = TerrainData(9);
      files.put(path, put);
      await files.load(path);
      expect(identical(files.get(path), put), isTrue);
      expect(files.errorOf(path), isNull);
    });

    test(
      "another terrain never takes over a terrain's file: one renamed since it was made",
      () {
        final files = TerrainFiles.of(scope.context);
        // A level saved with its terrain renamed: Island, its file still the
        // one it was made with, under the name the next terrain is given.
        const path = 'assets/terrain/level/Terrain_0.jterrain';
        final ground = TerrainData(33)..heights[40] = 2;
        files
          ..put(path, ground)
          ..saved(path);
        final island = scope.world.createEntityWithComponents([
          TransformComponent(),
          Terrain3DComponent(data: path, size: 32, resolution: 33),
        ], name: 'Island');
        scope.sceneState.registerEntity(island);

        final made = terrain();
        expect(
          made.name,
          'Terrain_0',
          reason: 'the name is free among the entities',
        );
        final own = made.getComponent<Terrain3DComponent>()!.data;
        expect(own, isNot(path), reason: 'the file is not');
        expect(
          identical(files.get(path), ground),
          isTrue,
          reason: "Island's ground is its own still",
        );
        expect(ground.heights[40], 2, reason: 'and not flattened');
        expect(files.unsaved, {
          own,
        }, reason: "nothing to write over Island's file");

        // Made, then undone: its file goes with it; redone, back.
        scope.history.undo();
        expect(files.knows(own), isFalse);
        expect(identical(files.get(path), ground), isTrue);
        scope.history.redo();
        expect(files.knows(own), isTrue);
      },
    );

    test('another terrain passes over a file of its name on disk', () {
      // The first terrain this editor makes is Terrain_0.
      File('${root.path}/assets/terrain/level/Terrain_0.jterrain')
        ..createSync(recursive: true)
        ..writeAsBytesSync(TerrainData(9).encode());
      final e = makeTerrain(
        tool().designer,
        sceneName: 'level',
        size: 32,
        resolution: 33,
        root: root.path,
      );
      expect(e.name, 'Terrain_0');
      expect(
        e.getComponent<Terrain3DComponent>()!.data,
        'assets/terrain/level/Terrain_0_2.jterrain',
      );
    });

    test(
      'a stroke shapes as much a metre whether the pointer reports often or seldom',
      () {
        final data = TerrainFiles.of(
          scope.context,
        ).get(terrain().getComponent<Terrain3DComponent>()!.data)!;
        double raised() => data.heights.fold(0.0, (a, h) => a + h);

        // Fast: one move along 8 m.
        press(Vector3(-4, 0, -6));
        move(Vector3(4, 0, -6));
        release(Vector3(4, 0, -6));
        final fast = raised();

        // Slow: the same 8 m in moves of 5 cm, further along the terrain.
        press(Vector3(-4, 0, 6));
        for (var k = 1; k <= 160; k++) {
          move(Vector3(-4 + k * 0.05, 0, 6));
        }
        release(Vector3(4, 0, 6));
        final slow = raised() - fast;
        expect(slow / fast, closeTo(1, 0.35), reason: 'fast $fast, slow $slow');
      },
    );

    test('the brush goes when the pointer leaves the viewport', () {
      terrain();
      session.onPointerHover(
        Offset.zero,
        32,
        screen: at(Vector3(0, 0, 0)),
        canvasSize: const Size(400, 400),
      );
      expect(tool().spot.value, isNotNull);
      session.onPointerExit();
      expect(tool().spot.value, isNull);
    });
  });
}

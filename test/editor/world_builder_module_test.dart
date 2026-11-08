// The World Builder module: a Level Designer kit for 3-D scenes; and what
// it does as a scene is saved — every terrain file it can write is
// written, one it cannot fails the save, and a file changed while it was
// written stays unsaved.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a kit for 3-D scenes: World Builder', () {
    final module = WorldBuilderModule();
    expect(module.name, 'World Builder');
    expect(module.designerModes, {SceneMode.threeD});
    expect(WorldBuilderKit.extension.id, 'just_world_builder_kit');
  });

  group('saving terrain files', () {
    late Directory root;
    late EditorScope scope;
    late WorldBuilderModule module;
    late TerrainFiles files;

    setUp(() {
      root = Directory.systemTemp.createTempSync('wb_save_');
      addTearDown(() => root.deleteSync(recursive: true));
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
      module = WorldBuilderModule(root: root.path);
      scope = EditorScope(
        world: world,
        modules: [module],
        builtIns: const [BuiltInEditorModule.new],
      );
      addTearDown(scope.dispose);
      scope.sceneState.openScene(
        EditorScene(name: 'level', mode: SceneMode.threeD),
      );
      files = TerrainFiles.of(scope.context);
    });

    /// A terrain using [path], its ground put and not yet written.
    TerrainData terrainAt(String path) {
      final data = TerrainData(9);
      files.put(path, data);
      scope.world.createEntityWithComponents([
        TransformComponent(),
        Terrain3DComponent(data: path, size: 8),
      ]);
      return data;
    }

    test(
      'one file that cannot be written: the others are, and the save fails',
      () async {
        // A folder where the file should be: it cannot be written.
        const blocked = 'assets/terrain/level/a.jterrain';
        Directory('${root.path}/$blocked').createSync(recursive: true);
        terrainAt(blocked);
        const fine = 'assets/terrain/level/b.jterrain';
        terrainAt(fine);
        final failed = await scope.modules.notifySceneSaving('level');
        expect(failed['world_builder'], isA<TerrainSaveException>());
        expect((failed['world_builder']! as TerrainSaveException).failed.keys, [
          blocked,
        ]);
        expect(
          File('${root.path}/$fine').existsSync(),
          isTrue,
          reason: 'written all the same',
        );
        expect(files.unsaved, {
          blocked,
        }, reason: 'the one not written is still to be written');
      },
    );

    test('a file changed while it is written stays unsaved', () async {
      const path = 'assets/terrain/level/c.jterrain';
      final data = terrainAt(path);
      // The write is under way: the ground changes before it is done.
      final saving = module.onSceneSaving('level');
      data
        ..heights[0] = 3
        ..touch(0, 0, 0, 0);
      files.changed(path);
      await saving;
      expect(
        File('${root.path}/$path').existsSync(),
        isTrue,
        reason: 'written as it was',
      );
      expect(files.unsaved, {
        path,
      }, reason: 'what was written is not what it is now');
    });
  });
}

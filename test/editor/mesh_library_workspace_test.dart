// The mesh library workspace: pieces added, undone and saved.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the mesh library workspace', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('meshlib_');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    testWidgets('a new library; pieces added, undone, saved', (tester) async {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      final files = WorldBuilderFiles(dir.path);
      final path = (await tester.runAsync(
        () => files.create(world.context.definitions),
      ))!;
      expect(path, 'assets/tiles/tiles${MeshLibrary.ending}');
      expect(await tester.runAsync(files.libraries), [path]);
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
              files: files,
              definitions: world.context.definitions,
              workspace: WorkspaceContext(
                scope: scope,
                onClose: () {},
                path: path,
                reloadAssets: reloaded.add,
              ),
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
      final saved = MeshLibrary.parse(
        File('${dir.path}/$path').readAsStringSync(),
      );
      expect(saved.items.last.name, 'Arch');
      expect(
        world.context.definitions.decode(
          Map<String, dynamic>.from(saved.items.last.shape!),
        ),
        isA<Arch3DComponent>(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a name typed is kept when its field is left, as on Enter', (
      tester,
    ) async {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      final files = WorldBuilderFiles(dir.path);
      final path = (await tester.runAsync(
        () => files.create(world.context.definitions),
      ))!;
      final scope = EditorScope(world: world, modules: const []);
      addTearDown(scope.dispose);
      final key = GlobalKey<MeshLibraryWorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeshLibraryWorkspace(
              key: key,
              path: path,
              files: files,
              definitions: world.context.definitions,
              workspace: WorkspaceContext(
                scope: scope,
                onClose: () {},
                path: path,
              ),
              loadOnStart: false,
            ),
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      final first = state.library.items.first;
      final field = find.byKey(ValueKey('name${first.id}0'));
      await tester.tap(field);
      await tester.enterText(field, 'Slab');
      // Left, not submitted.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(state.library.item(first.id)!.name, 'Slab');
      expect(state.dirty, isTrue);
    });

    testWidgets(
      'a file that cannot be read: nothing to save, nothing written over it',
      (tester) async {
        final world = World()..initialize();
        Graphics3D.registerDefinitions(world.context);
        final files = WorldBuilderFiles(dir.path);
        const path = 'assets/tiles/broken${MeshLibrary.ending}';
        const text = '<<<<<<< merge markers, not a library';
        File('${dir.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
        final scope = EditorScope(world: world, modules: const []);
        addTearDown(scope.dispose);
        final key = GlobalKey<MeshLibraryWorkspaceState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeshLibraryWorkspace(
                key: key,
                path: path,
                files: files,
                definitions: world.context.definitions,
                workspace: WorkspaceContext(
                  scope: scope,
                  onClose: () {},
                  path: path,
                ),
                loadOnStart: false,
              ),
            ),
          ),
        );
        final state = key.currentState!;
        // Before it is read, and once it could not be.
        expect(state.dirty, isFalse);
        await tester.runAsync(state.load);
        await tester.pump();
        expect(state.loaded, isFalse);
        expect(
          state.dirty,
          isFalse,
          reason: 'no changes to save: it was never read',
        );
        state.addShape('Block', meshLibraryShapes.first.$2);
        expect(
          state.library.items,
          isEmpty,
          reason: 'nothing changes before the file is read',
        );
        expect(await tester.runAsync(state.save), isFalse);
        expect(
          File('${dir.path}/$path').readAsStringSync(),
          text,
          reason: 'never written over',
        );
      },
    );
  });
}

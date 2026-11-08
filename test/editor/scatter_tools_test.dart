// The Scatter brush: strokes, each one undo step; Shift erases; its
// options bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

ScatterInstance _piece(double x, double z, {int layer = 0, double scale = 1}) =>
    ScatterInstance(layer: layer, position: Vector3(x, 0, z), scale: scale);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Scatter brush', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
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
      // A floor to scatter on: its top at y = 0.
      final floor = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0.5, 0)),
        Cube3DComponent(width: 40, height: 1, depth: 40),
      ], name: 'Floor');
      scope.sceneState.registerEntity(floor);
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
      session.setTool(ScatterTool.toolId);
    });

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
    ScatterTool tool() =>
        session.tools.byId(ScatterTool.toolId)! as ScatterTool;
    Scatter3DComponent scatter() => scope.world
        .query([Scatter3DComponent])
        .single
        .getComponent<Scatter3DComponent>()!;

    test('a stroke scatters grass on the floor, apart; one undo step', () {
      press(Vector3(0, 0, 0));
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      final s = scatter();
      expect(s.instances, isNotEmpty);
      for (final p in s.instances) {
        expect(p.position.y, closeTo(0, 1e-3), reason: 'set down on the floor');
        expect(p.layer, 0);
      }
      for (final a in s.instances) {
        for (final b in s.instances) {
          if (identical(a, b)) continue;
          expect(
            (a.position - b.position).length,
            greaterThanOrEqualTo(s.layers[0].spacing - 1e-9),
          );
        }
      }
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(scope.world.query([Scatter3DComponent]), isEmpty);
    });

    test('a second stroke is its own step; Shift erases', () {
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      final first = scatter().instances.length;
      press(Vector3(8, 0, 8));
      release(Vector3(8, 0, 8));
      expect(scatter().instances.length, greaterThan(first));
      expect(scope.history.undoEntries, hasLength(2));
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(8, 0, 8));
      release(Vector3(8, 0, 8));
      expect(scatter().instances.length, first);
      scope.history.undo();
      expect(scatter().instances.length, greaterThan(first));
    });

    Entity scatterOf(
      List<ScatterLayer> layers,
      List<ScatterInstance> pieces, {
      String? name,
    }) {
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
        Scatter3DComponent(layers: layers, instances: pieces),
      ], name: name);
      scope.sceneState
        ..registerEntity(e)
        ..selectEntity(e);
      return e;
    }

    test('a stroke that erases as many as it scatters is still a step', () {
      // So far apart that one piece fills the floor.
      final e = scatterOf(
        [ScatterLayer(name: 'Big', spacing: 100)],
        [_piece(0, 0)],
        name: 'Big',
      );
      final s = e.getComponent<Scatter3DComponent>()!;
      final original = s.instances.single;
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(0, 0, 0));
      modifiers = const ModifierKeys();
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      expect(s.instances, hasLength(1));
      expect(
        identical(s.instances.single, original),
        isFalse,
        reason: 'another piece',
      );
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(identical(s.instances.single, original), isTrue);
    });

    test('a stroke where nothing lands makes no scatter', () {
      // Off the floor's edge: nothing under the brush to set a piece on.
      press(Vector3(30, 0, 30));
      move(Vector3(34, 0, 30));
      release(Vector3(34, 0, 30));
      expect(scope.world.query([Scatter3DComponent]), isEmpty);
      expect(scope.history.undoEntries, isEmpty);
    });

    test("a stroke's undo step keeps what it changed, not every piece", () {
      press(Vector3(0, 0, 0));
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      final first = List.of(scatter().instances);
      press(Vector3(-8, 0, -8));
      move(Vector3(-4, 0, -8));
      release(Vector3(-4, 0, -8));
      final both = List.of(scatter().instances);
      final step = scope.history.undoEntries.last as ScatterStrokeCommand;
      expect(step.addedCount, both.length - first.length);
      expect(step.removedCount, 0);
      scope.history.undo();
      expect(scatter().instances, orderedEquals(first));
      scope.history.redo();
      expect(scatter().instances, orderedEquals(both));
      // Erasing some of each stroke's: put back in their places.
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(-2, 0, -4));
      release(Vector3(-2, 0, -4));
      modifiers = const ModifierKeys();
      final erased = List.of(scatter().instances);
      expect(erased.length, lessThan(both.length));
      scope.history.undo();
      expect(scatter().instances, orderedEquals(both));
      scope.history.redo();
      expect(scatter().instances, orderedEquals(erased));
    });

    test('the brush goes when the pointer leaves the viewport', () {
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

    test('a scatter of no layers takes no pieces, and nothing throws', () {
      final e = scatterOf([], []);
      press(Vector3(0, 0, 0));
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      expect(e.getComponent<Scatter3DComponent>()!.instances, isEmpty);
    });

    test('a stroke into an unnamed scatter is undone like any other', () {
      final e = scatterOf(starterScatterLayers(), []);
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      final s = e.getComponent<Scatter3DComponent>()!;
      expect(s.instances, isNotEmpty);
      scope.history.undo();
      expect(s.instances, isEmpty);
    });

    test('a layer taken out takes its pieces; those after it keep theirs', () {
      final e = scatterOf(starterScatterLayers(), [
        _piece(0, 0),
        _piece(5, 0, layer: 1),
        _piece(9, 0, layer: 2),
      ]);
      final s = e.getComponent<Scatter3DComponent>()!;
      removeScatterLayer(scope, s, 1);
      expect(s.layers.map((l) => l.name), ['Grass', 'Trees']);
      expect(
        [for (final p in s.instances) (p.position.x, s.layers[p.layer].name)],
        [(0.0, 'Grass'), (9.0, 'Trees')],
      );
      scope.history.undo();
      expect(s.layers, hasLength(3));
      expect(s.instances.map((p) => p.layer), [0, 1, 2]);
    });

    testWidgets(
      "the options bar shows the scatter's layers as they are now, not as "
      'they were when it was built',
      (tester) async {
        final e = scatterOf(starterScatterLayers(), []);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              // Built once, as the designer's status bar builds it while
              // the tool stays in hand.
              body: Builder(
                builder: (context) => tool().buildOptions(
                  context,
                  ToolOptionsContext(
                    scope: scope,
                    controller: session.controller,
                    world: scope.world,
                    setTool: session.setTool,
                  ),
                )!,
              ),
            ),
          ),
        );
        expect(find.text('Grass'), findsOneWidget);

        // A layer added (from the panel or the inspector), then chosen.
        final s = e.getComponent<Scatter3DComponent>()!;
        s.layers = [...s.layers, ScatterLayer(name: 'Ferns')];
        tool().layer.value = 3;
        await tester.pump();
        expect(find.text('Ferns'), findsOneWidget, reason: 'not "Layer 4"');

        await tester.tap(find.text('Ferns'));
        await tester.pumpAndSettle();
        expect(
          find.text('Ferns'),
          findsNWidgets(2),
          reason: 'its menu lists it too',
        );
        await tester.tap(find.text('Grass').last);
        await tester.pumpAndSettle();
        expect(tool().layer.value, 0);
        expect(find.text('Grass'), findsOneWidget);
      },
    );
  });
}

// The designer's side panels: each section opens with its own tools, shows
// what it works on, and the scatter inspector's layers and pieces.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorScope scope;
  late LevelDesignerSession session;
  late WorldBuilderModule module;

  setUp(() {
    final world = World()..initialize();
    Graphics3D.registerDefinitions(world.context);
    WorldBuilderKit.install(world.context);
    module = WorldBuilderModule();
    scope = EditorScope(
      world: world,
      modules: [module],
      builtIns: const [BuiltInEditorModule.new],
    );
    addTearDown(scope.dispose);
    scope.sceneState.openScene(
      EditorScene(name: 'level', mode: SceneMode.threeD),
    );
    scope.selectDesigner('world_builder');
    final view = OrbitFlyEditorView.of(
      OutputCamera(viewportSize: const Size(400, 400)),
    )..viewportSize = const Size(400, 400);
    session = LevelDesignerSession(
      scope: scope,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
      camera: () => view,
    );
    addTearDown(session.dispose);
  });

  test('each section opens with its own tools', () {
    final groups = {for (final s in module.designerPanels) s.title: s.groups};
    expect(groups, {
      'TILES': {tilesGroup},
      'TERRAIN': {terrainGroup},
      'SCATTER': {scatterGroup},
    });
  });

  Future<void> pumpSections(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 330,
              child: Builder(
                builder: (context) => Column(
                  children: [
                    for (final s in module.designerPanels)
                      s.build(context, session),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the sections, with nothing made yet', (tester) async {
    await pumpSections(tester);
    expect(find.textContaining('No terrain in this scene yet'), findsOneWidget);
    expect(find.textContaining('No scatter in this scene yet'), findsOneWidget);
    expect(
      find.text('Medium'),
      findsOneWidget,
      reason: 'detail in words, not sample counts',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sections, shaping a terrain and painting a scatter', (
    tester,
  ) async {
    final terrainTool =
        session.tools.byId(TerrainSculptTool.toolId)! as TerrainSculptTool;
    final terrain = makeTerrain(
      terrainTool.designer,
      sceneName: 'level',
      size: 32,
      resolution: 33,
    );
    scope.world.createEntityWithComponents([
      TransformComponent(),
      Scatter3DComponent(
        layers: starterScatterLayers(),
        instances: [ScatterInstance(layer: 2, position: Vector3.zero())],
      ),
    ], name: 'Scatter_0');
    scope.sceneState.selectEntity(terrain);
    await pumpSections(tester);
    expect(
      find.textContaining(terrain.name!, findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('33 × 33 samples, 1 m apart'), findsOneWidget);
    expect(
      find.textContaining('Scatter_0', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('GRASS SETTINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // What a layer is: the shapes in its colour, then the project's models.
    await tester.ensureVisible(find.text('Cone'));
    await tester.tap(find.text('Cone'));
    await tester.pumpAndSettle();
    for (final shape in ['Cube', 'Sphere', 'Cylinder', 'Capsule']) {
      expect(find.text(shape), findsWidgets, reason: 'listed: $shape');
    }
    await tester.tap(find.text('Cube'));
    await tester.pumpAndSettle();
    final scatter = scope.world
        .query([Scatter3DComponent])
        .single
        .getComponent<Scatter3DComponent>()!;
    expect(
      [scatter.layers[0].shape, scatter.layers[0].model],
      [ScatterShape.cube, ''],
    );
    expect(scope.history.undoEntries.last.label, 'Change Grass: look');

    // Live: a layer added from the panel shows at once.
    await tester.ensureVisible(find.text('Add a layer'));
    await tester.tap(find.text('Add a layer'));
    await tester.pump();
    expect(find.text('Layer 4'), findsOneWidget);
    expect(scope.history.undoEntries.last.label, 'Add a scatter layer');
  });

  testWidgets('a slider dragged as the panel closes is still one undo step', (
    tester,
  ) async {
    final e = scope.world.createEntityWithComponents([
      TransformComponent(),
      Scatter3DComponent(layers: starterScatterLayers()),
    ], name: 'Scatter_0');
    Scatter3DComponent scatter() => e.getComponent<Scatter3DComponent>()!;
    final before = scatter().layers[0].spacing;
    await pumpSections(tester);
    final steps = scope.history.undoEntries.length;
    final spacing = find.descendant(
      of: find.ancestor(of: find.text('Spacing'), matching: find.byType(Row)),
      matching: find.byType(Slider),
    );
    expect(spacing, findsOneWidget);
    await tester.ensureVisible(spacing);
    final gesture = await tester.startGesture(tester.getCenter(spacing));
    addTearDown(gesture.removePointer);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final dragged = scatter().layers[0].spacing;
    expect(dragged, isNot(before), reason: 'shown as it is dragged');
    expect(scope.history.undoEntries, hasLength(steps), reason: 'not yet');

    // The panel goes in the middle of the drag (another tool's section,
    // the designer closed): the slider never says the drag ended.
    await tester.pumpWidget(const SizedBox());
    expect(scope.history.undoEntries, hasLength(steps + 1));
    expect(scope.history.undoEntries.last.label, 'Change Grass: spacing');
    scope.history.undo();
    expect(scatter().layers[0].spacing, before);
    scope.history.redo();
    expect(scatter().layers[0].spacing, dragged);
    await gesture.up();
  });

  testWidgets(
    'the Tiles panel shows a library when it is read, read again or let go',
    (tester) async {
      const path = 'assets/tiles/panel.meshlib.json';
      final definitions = scope.context.definitions;
      String library(String piece) => MeshLibrary(
        cellSize: 2,
        items: [
          MeshLibraryItem(
            id: 1,
            name: piece,
            shape: Map<String, Object?>.from(
              definitions.encode(
                Cube3DComponent(width: 2, height: 2, depth: 2),
              )!,
            ),
          ),
        ],
      ).encode();
      // Each read waits for [gate]: what the panel shows while it loads.
      var text = library('Block');
      var gate = Completer<void>();
      scope.context.tiles.readText = (_) async {
        await gate.future;
        return text;
      };
      final libraries = MeshLibraries.of(scope.context);
      (session.tools.byId(GridTileTool.toolId)! as GridTileTool).library.value =
          path;
      await pumpSections(tester);
      expect(find.text('Block'), findsNothing, reason: 'still being read');

      Future<void> read() async {
        gate.complete();
        await tester.pump();
        await tester.pump();
      }

      await read();
      expect(find.text('Block'), findsOneWidget, reason: 'read');

      // Saved in its workspace: the module forgets it, the panel reads it
      // again.
      text = library('Arch');
      gate = Completer<void>();
      libraries.forget(path);
      await tester.pump();
      expect(find.text('Block'), findsNothing, reason: 'forgotten');
      await read();
      expect(find.text('Arch'), findsOneWidget, reason: 'read again');

      // Let go (no piece uses it): the open panel asks for it again.
      text = library('Pillar');
      gate = Completer<void>();
      libraries.releaseUnused(const []);
      await tester.pump();
      expect(find.text('Arch'), findsNothing, reason: 'let go');
      await read();
      expect(find.text('Pillar'), findsOneWidget, reason: 'and read again');
      expect(tester.takeException(), isNull);
    },
  );

  FieldEditorContext fieldOf(
    Scatter3DComponent scatter,
    String name,
    List<Object?> written,
  ) {
    final schema = scope.definitions.definitionFor(scatter)!;
    final field = schema.fields.firstWhere((f) => f.name == name);
    return FieldEditorContext(
      field: field,
      hint: FieldHint(label: name == 'layers' ? 'Layers' : 'Pieces'),
      value: field.read(scatter),
      component: scatter,
      onChanged: written.add,
      editors: scope.fieldEditors,
      scope: scope,
      world: scope.world,
      sceneState: scope.sceneState,
    );
  }

  testWidgets('the inspector: layers in cards, pieces counted', (tester) async {
    final scatter = Scatter3DComponent(
      layers: starterScatterLayers(),
      instances: [
        for (var k = 0; k < 5; k++)
          ScatterInstance(layer: k % 2, position: Vector3(k * 2.0, 0, 0)),
      ],
    );
    scope.world.createEntityWithComponents([TransformComponent(), scatter]);
    final written = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 330,
              child: Column(
                children: [
                  scope.fieldEditors.build(fieldOf(scatter, 'layers', written)),
                  scope.fieldEditors.build(
                    fieldOf(scatter, 'instances', written),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('no editor for'), findsNothing);
    expect(find.text('Grass'), findsWidgets);
    expect(
      find.textContaining('3 pieces'),
      findsOneWidget,
      reason: 'the grass card',
    );
    expect(
      find.text('Shape'),
      findsOneWidget,
      reason: 'no model: what shape instead',
    );
    expect(find.textContaining('5: 3 grass, 2 rocks'), findsOneWidget);

    await tester.ensureVisible(find.text('Add a layer'));
    await tester.tap(find.text('Add a layer'));
    expect((written.last! as List).length, 4);
    await tester.ensureVisible(find.text('Clear them all'));
    await tester.tap(find.text('Clear them all'));
    expect(written.last, isEmpty);
  });

  test('a stroke over a terrain scatters on its ground', () {
    final terrainTool =
        session.tools.byId(TerrainSculptTool.toolId)! as TerrainSculptTool;
    final terrain = makeTerrain(
      terrainTool.designer,
      sceneName: 'level',
      size: 32,
      resolution: 33,
    ).getComponent<Terrain3DComponent>()!;
    final data = TerrainFiles.of(scope.context).get(terrain.data)!;
    for (var j = 0; j < 33; j++) {
      for (var i = 0; i < 33; i++) {
        data.heights[data.index(i, j)] = 2 + math.sin(i * 0.4);
      }
    }
    data.touch(0, 0, 32, 32);
    terrain.link(TerrainFiles.of(scope.context));
    final view = session.camera as OrbitFlyEditorView
      ..pivot.setValues(0, -2, 0)
      ..distance = 30
      ..yaw = 0.3
      ..pitch = -0.9;
    view.sync();
    session.setTool(ScatterTool.toolId);
    final at = view.projectToScreen(Vector3(0, -2, 0))!;
    session.onPointerDown(
      Offset.zero,
      32,
      screen: at,
      canvasSize: const Size(400, 400),
    );
    session.onPointerUp(
      Offset.zero,
      32,
      screen: at,
      canvasSize: const Size(400, 400),
    );
    final scatter = scope.world
        .query([Scatter3DComponent])
        .single
        .getComponent<Scatter3DComponent>()!;
    expect(
      scatter.instances,
      isNotEmpty,
      reason: 'each piece dropped straight down onto the terrain',
    );
    for (final p in scatter.instances) {
      final h = data.heightAt(
        (p.position.x - terrain.origin) / terrain.cellSize,
        (p.position.z - terrain.origin) / terrain.cellSize,
      );
      expect(
        p.position.y,
        closeTo(-h, 0.05),
        reason: 'on the ground (+Y is down)',
      );
    }
  });
}

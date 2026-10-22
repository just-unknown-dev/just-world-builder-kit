// The world builder kit: a Level Designer kit for 3-D scenes, its runtime
// library never reaching the editor; and blockout — a box drawn on a
// surface and pulled up, a floor outlined, a ramp or stairs dragged from
// foot to top — each one undo step of the engine's own shapes.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the package', () {
    test('its runtime library never reaches the editor', () {
      final runtime = [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !f.path.replaceAll(r'\', '/').contains('lib/src/editor/') &&
              !f.path.replaceAll(r'\', '/').endsWith('lib/editor.dart'))
            f,
      ];
      expect(runtime, isNotEmpty);
      for (final f in runtime) {
        final text = f.readAsStringSync();
        expect(text, isNot(contains('just_editor_core')), reason: f.path);
        expect(text, isNot(contains('just_game_engine_editor')), reason: f.path);
        expect(text, isNot(contains("src/editor/")), reason: f.path);
      }
    });

    test('its editor part builds on the editor\'s contract alone', () {
      for (final f in Directory('lib/src/editor').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains('just_game_engine_editor')), reason: f.path);
      }
    });

    test('a kit for 3-D scenes: World Builder', () {
      final module = WorldBuilderModule();
      expect(module.name, 'World Builder');
      expect(module.designerModes, {SceneMode.threeD});
      expect(WorldBuilderKit.extension.id, 'just_world_builder_kit');
    });
  });

  group('blockout', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      scope = EditorScope(
        world: world,
        modules: [WorldBuilderModule()],
        builtIns: const [BuiltInEditorModule.new],
      );
      addTearDown(scope.dispose);
      scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
      // World Builder chosen in the designer's switch.
      scope.selectDesigner('world_builder');
      view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
        ..viewportSize = const Size(400, 400)
        ..pivot.setValues(0, 0, 0)
        ..distance = 20
        ..yaw = 0.3
        ..pitch = -0.9;
      view.sync();
      session = LevelDesignerSession(
        scope: scope,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
        camera: () => view,
      );
      addTearDown(session.dispose);
      // Off: the tests place exactly.
      session.controller.snapEnabled.value = false;
    });

    Offset at(Vector3 p) => view.projectToScreen(p)!;
    void press(Vector3 p) => session.onPointerDown(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void move(Vector3 p) => session.onPointerMove(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void release(Vector3 p) => session.onPointerUp(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void hover(Vector3 p) => session.onPointerHover(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));

    Entity only<T extends Primitive3D>() => scope.world.entities.singleWhere((e) => e.getComponent<Primitive3D>() is T);
    Vector3 position(Entity e) => e.getComponent<TransformComponent>()!.position;

    test('the tools are the kit\'s, in 3-D', () {
      expect(session.tools.byId(BlockTool.toolId), isA<BlockTool>());
      expect(session.tools.byId(FloorTool.toolId), isA<FloorTool>());
      expect(session.tools.byId(RampTool.toolId), isA<RampTool>());
    });

    test('a click makes a metre block standing on the surface', () {
      session.setTool(BlockTool.toolId);
      press(Vector3(3, 0, 2));
      release(Vector3(3, 0, 2));
      final block = only<Cube3D>();
      final p = position(block);
      expect([p.x, p.y, p.z], [closeTo(3, 1e-6), closeTo(-0.5, 1e-6), closeTo(2, 1e-6)]);
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a footprint dragged, pulled up, clicked: a box that size', () {
      session.setTool(BlockTool.toolId);
      press(Vector3(0, 0, 0));
      move(Vector3(2, 0, 3));
      release(Vector3(2, 0, 3));
      expect(scope.world.entities.where((e) => e.hasComponent<Primitive3D>()), isEmpty, reason: 'its height next');
      hover(Vector3(2, -1.5, 3));
      final preview = (session.tools.byId(BlockTool.toolId)! as BlockTool).preview.value!;
      expect(preview.box!.min.y, closeTo(-1.5, 1e-3));
      press(Vector3(2, -1.5, 3));
      final box = only<Cube3D>().getComponent<Primitive3D>()! as Cube3D;
      expect([box.width, box.height, box.depth], [closeTo(2, 1e-3), closeTo(1.5, 1e-3), closeTo(3, 1e-3)]);
      final p = position(only<Cube3D>());
      expect([p.x, p.y, p.z], [closeTo(1, 1e-3), closeTo(-0.75, 1e-3), closeTo(1.5, 1e-3)]);
    });

    test('an outline closed with Enter: a floor, its top on the surface', () {
      session.setTool(FloorTool.toolId);
      for (final p in [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 2), Vector3(0, 0, 2)]) {
        press(p);
        release(p);
      }
      expect(session.handleKey(LogicalKeyboardKey.enter, gridSize: 32), isTrue);
      final floor = only<Polygon3D>();
      final polygon = floor.getComponent<Primitive3D>()! as Polygon3D;
      expect(polygon.points, hasLength(4));
      final p = position(floor);
      expect([p.x, p.z], [closeTo(2, 1e-6), closeTo(1, 1e-6)]);
      expect(p.y - polygon.height / 2, closeTo(0, 1e-6), reason: 'its top on the ground');
    });

    test('a ramp dragged from its foot to a ledge: risen that far, facing it', () {
      final ledge = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, -1, 6)),
        Cube3D(width: 4, height: 2, depth: 4),
      ], name: 'Ledge');
      scope.sceneState.registerEntity(ledge);
      session.setTool(RampTool.toolId);
      press(Vector3(0, 0, 0));
      move(Vector3(0, -2, 4.5));
      release(Vector3(0, -2, 4.5));
      final ramp = only<Ramp3D>();
      final shape = ramp.getComponent<Primitive3D>()! as Ramp3D;
      expect([shape.height, shape.depth], [closeTo(2, 1e-3), closeTo(4.5, 1e-3)]);
      final q = Quaternion.identity();
      ramp.getComponent<TransformComponent>()!.rotationInto(q);
      final forward = Vector3(0, 0, 1);
      q.rotate(forward);
      expect(forward.z, closeTo(1, 1e-6), reason: 'rising towards the ledge');
      expect(position(ramp).y, closeTo(-1, 1e-3));

      // Stairs, the other way round: dragged down from the ledge.
      (session.tools.byId(RampTool.toolId)! as RampTool).kind.value = SlopeKind.stairs;
      press(Vector3(1, -2, 4.5));
      move(Vector3(math.sqrt(2) * 3 + 1, 0, 4.5));
      release(Vector3(math.sqrt(2) * 3 + 1, 0, 4.5));
      final stairs = only<Stairs3D>().getComponent<Primitive3D>()! as Stairs3D;
      expect(stairs.steps, 10, reason: '2 m of 20 cm steps');
    });
  });
}

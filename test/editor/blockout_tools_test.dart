// Blockout: a box drawn on a surface and pulled up, a floor outlined, a
// ramp or stairs dragged from foot to top — each one undo step of the
// engine's own shapes.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('blockout', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      // As a 3-D game's editor has them: bodies and colliders saved.
      Physics3D.registerDefinitions(world.context);
      scope = EditorScope(
        world: world,
        modules: [WorldBuilderModule()],
        builtIns: const [BuiltInEditorModule.new],
      );
      addTearDown(scope.dispose);
      scope.sceneState.openScene(
        EditorScene(name: 'level', mode: SceneMode.threeD),
      );
      // World Builder chosen in the designer's switch.
      scope.selectDesigner('world_builder');
      view =
          OrbitFlyEditorView.of(
              OutputCamera(viewportSize: const Size(400, 400)),
            )
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
    void hover(Vector3 p) => session.onPointerHover(
      Offset.zero,
      32,
      screen: at(p),
      canvasSize: const Size(400, 400),
    );

    Entity only<T extends Primitive3DComponent>() => scope.world.entities
        .singleWhere((e) => e.getComponent<Primitive3DComponent>() is T);
    Vector3 position(Entity e) =>
        e.getComponent<TransformComponent>()!.position;

    test('the tools are the kit\'s, in 3-D', () {
      expect(session.tools.byId(BlockTool.toolId), isA<BlockTool>());
      expect(session.tools.byId(FloorTool.toolId), isA<FloorTool>());
      expect(session.tools.byId(RampTool.toolId), isA<RampTool>());
    });

    test('a click makes a metre block standing on the surface', () {
      session.setTool(BlockTool.toolId);
      press(Vector3(3, 0, 2));
      release(Vector3(3, 0, 2));
      final block = only<Cube3DComponent>();
      final p = position(block);
      expect(
        [p.x, p.y, p.z],
        [closeTo(3, 1e-6), closeTo(-0.5, 1e-6), closeTo(2, 1e-6)],
      );
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a footprint dragged, pulled up, clicked: a box that size', () {
      session.setTool(BlockTool.toolId);
      press(Vector3(0, 0, 0));
      move(Vector3(2, 0, 3));
      release(Vector3(2, 0, 3));
      expect(
        scope.world.entities.where(
          (e) => e.hasComponent<Primitive3DComponent>(),
        ),
        isEmpty,
        reason: 'its height next',
      );
      hover(Vector3(2, -1.5, 3));
      final preview =
          (session.tools.byId(BlockTool.toolId)! as BlockTool).preview.value!;
      expect(preview.box!.min.y, closeTo(-1.5, 1e-3));
      press(Vector3(2, -1.5, 3));
      final box =
          only<Cube3DComponent>().getComponent<Primitive3DComponent>()!
              as Cube3DComponent;
      expect(
        [box.width, box.height, box.depth],
        [closeTo(2, 1e-3), closeTo(1.5, 1e-3), closeTo(3, 1e-3)],
      );
      final p = position(only<Cube3DComponent>());
      expect(
        [p.x, p.y, p.z],
        [closeTo(1, 1e-3), closeTo(-0.75, 1e-3), closeTo(1.5, 1e-3)],
      );
    });

    test('an outline closed with Enter: a floor, its top on the surface', () {
      session.setTool(FloorTool.toolId);
      for (final p in [
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(4, 0, 2),
        Vector3(0, 0, 2),
      ]) {
        press(p);
        release(p);
      }
      expect(session.handleKey(LogicalKeyboardKey.enter, gridSize: 32), isTrue);
      final floor = only<Polygon3DComponent>();
      final polygon =
          floor.getComponent<Primitive3DComponent>()! as Polygon3DComponent;
      expect(polygon.points, hasLength(4));
      final p = position(floor);
      expect([p.x, p.z], [closeTo(2, 1e-6), closeTo(1, 1e-6)]);
      expect(
        p.y - polygon.height / 2,
        closeTo(0, 1e-6),
        reason: 'its top on the ground',
      );
    });

    test(
      'a double-click with too few corners to close puts no corner in twice',
      () {
        session.setTool(FloorTool.toolId);
        var ms = 0;
        void clickAt(Vector3 p, {int after = 1000}) {
          ms += after;
          session.onPointerDown(
            Offset.zero,
            32,
            screen: at(p),
            canvasSize: const Size(400, 400),
            time: Duration(milliseconds: ms),
          );
          session.onPointerUp(
            Offset.zero,
            32,
            screen: at(p),
            canvasSize: const Size(400, 400),
          );
        }

        clickAt(Vector3(0, 0, 0));
        // A double-click for the second corner: with two corners it cannot
        // close, and its second click adds nothing.
        clickAt(Vector3(4, 0, 0));
        clickAt(Vector3(4, 0, 0), after: 100);
        clickAt(Vector3(4, 0, 2));
        expect(
          session.handleKey(LogicalKeyboardKey.enter, gridSize: 32),
          isTrue,
        );
        final polygon =
            only<Polygon3DComponent>().getComponent<Primitive3DComponent>()!
                as Polygon3DComponent;
        expect(polygon.points, hasLength(3), reason: '${polygon.points}');
        expect(polygon.points.toSet(), hasLength(3), reason: 'no corner twice');
      },
    );

    test(
      'a ramp dragged from its foot to a ledge: risen that far, facing it',
      () {
        final ledge = scope.world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, -1, 6)),
          Cube3DComponent(width: 4, height: 2, depth: 4),
        ], name: 'Ledge');
        scope.sceneState.registerEntity(ledge);
        session.setTool(RampTool.toolId);
        press(Vector3(0, 0, 0));
        move(Vector3(0, -2, 4.5));
        release(Vector3(0, -2, 4.5));
        final ramp = only<Ramp3DComponent>();
        final shape =
            ramp.getComponent<Primitive3DComponent>()! as Ramp3DComponent;
        expect(
          [shape.height, shape.depth],
          [closeTo(2, 1e-3), closeTo(4.5, 1e-3)],
        );
        final q = Quaternion.identity();
        ramp.getComponent<TransformComponent>()!.rotationInto(q);
        final forward = Vector3(0, 0, 1);
        q.rotate(forward);
        expect(forward.z, closeTo(1, 1e-6), reason: 'rising towards the ledge');
        expect(position(ramp).y, closeTo(-1, 1e-3));

        // Stairs, the other way round: dragged down from the ledge.
        (session.tools.byId(RampTool.toolId)! as RampTool).kind.value =
            SlopeKind.stairs;
        press(Vector3(1, -2, 4.5));
        move(Vector3(math.sqrt(2) * 3 + 1, 0, 4.5));
        release(Vector3(math.sqrt(2) * 3 + 1, 0, 4.5));
        final stairs =
            only<Stairs3DComponent>().getComponent<Primitive3DComponent>()!
                as Stairs3DComponent;
        expect(stairs.steps, 10, reason: '2 m of 20 cm steps');
      },
    );

    test(
      'every piece is solid, as the engine\'s Solid shapes are: a static body matching its shape',
      () {
        final ledge = scope.world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, -1, 6)),
          Cube3DComponent(width: 4, height: 2, depth: 4),
        ], name: 'Ledge');
        scope.sceneState.registerEntity(ledge);
        session.setTool(BlockTool.toolId);
        press(Vector3(5, 0, 0));
        release(Vector3(5, 0, 0));
        session.setTool(FloorTool.toolId);
        for (final p in [
          Vector3(-8, 0, -4),
          Vector3(-4, 0, -4),
          Vector3(-4, 0, -1),
        ]) {
          press(p);
          release(p);
        }
        session.handleKey(LogicalKeyboardKey.enter, gridSize: 32);
        session.setTool(RampTool.toolId);
        press(Vector3(0, 0, 0));
        move(Vector3(0, -2, 4.5));
        release(Vector3(0, -2, 4.5));
        final made = [
          for (final e in scope.world.entities)
            if (e.hasComponent<Primitive3DComponent>() && !identical(e, ledge))
              e,
        ];
        expect(
          made
              .map((e) => e.getComponent<Primitive3DComponent>().runtimeType)
              .toSet(),
          {Cube3DComponent, Polygon3DComponent, Ramp3DComponent},
        );
        for (final e in made) {
          expect(
            e.getComponent<RigidBody3DComponent>()?.bodyType,
            Body3DType.static,
            reason: e.name,
          );
          expect(
            e.getComponent<Collider3DComponent>()?.shape,
            Collider3DShape.matchShape,
            reason: e.name,
          );
        }
        // Undone and redone with them.
        expect(scope.history.undoEntries, hasLength(3));
        scope.history.undo();
        scope.history.redo();
        expect(
          only<Ramp3DComponent>().getComponent<Collider3DComponent>(),
          isNotNull,
        );
      },
    );
  });
}

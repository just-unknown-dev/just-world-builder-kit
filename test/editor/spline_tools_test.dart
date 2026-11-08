// The Spline tool, its handles and the spline inspector.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

Spline3DComponent _spline(
  List<List<double>> points, {
  bool closed = false,
  SplineInterpolation curve = SplineInterpolation.linear,
}) => Spline3DComponent(
  points: [
    for (final p in points) SplinePoint(position: Vector3(p[0], p[1], p[2])),
  ],
  closed: closed,
  interpolation: curve,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the editor', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;

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
      view =
          OrbitFlyEditorView.of(
              OutputCamera(viewportSize: const Size(400, 400)),
            )
            ..viewportSize = const Size(400, 400)
            ..pivot.setValues(0, 0, 0)
            ..distance = 30
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
      session.controller.snapEnabled.value = false;
    });

    Offset at(Vector3 p) => view.projectToScreen(p)!;
    void click(Vector3 p) {
      session.onPointerDown(
        Offset.zero,
        32,
        screen: at(p),
        canvasSize: const Size(400, 400),
      );
      session.onPointerUp(
        Offset.zero,
        32,
        screen: at(p),
        canvasSize: const Size(400, 400),
      );
    }

    SplineTool tool() => session.tools.byId(SplineTool.toolId)! as SplineTool;
    Entity withSpline() => scope.world.entities.singleWhere(
      (e) => e.hasComponent<Spline3DComponent>(),
    );

    test('points clicked, Enter: a solid road, one undo step', () {
      session.setTool(SplineTool.toolId);
      for (final p in [Vector3(2, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 6)]) {
        click(p);
      }
      expect(tool().preview.value!.markers, hasLength(3));
      session.handleKey(LogicalKeyboardKey.backspace, gridSize: 32);
      expect(tool().points, hasLength(2));
      click(Vector3(8, 0, 6));
      expect(session.handleKey(LogicalKeyboardKey.enter, gridSize: 32), isTrue);
      final road = withSpline();
      final spline = road.getComponent<Spline3DComponent>()!;
      expect(spline.points, hasLength(3));
      expect(
        spline.points.first.position.length,
        closeTo(0, 1e-9),
        reason: 'standing at its first point',
      );
      final t = road.getComponent<TransformComponent>()!.position;
      expect(
        [t.x, t.y, t.z],
        [closeTo(2, 1e-6), closeTo(-0.02, 1e-6), closeTo(0, 1e-6)],
        reason: 'lifted off the ground',
      );
      expect(
        road.getComponent<SplineSweep3DComponent>()!.profile,
        SweepProfile.road,
      );
      expect(
        road.getComponent<RigidBody3DComponent>()!.bodyType,
        Body3DType.static,
      );
      expect(
        road.getComponent<Collider3DComponent>()!.shape,
        Collider3DShape.matchShape,
      );
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(
        scope.world.entities.where((e) => e.hasComponent<Spline3DComponent>()),
        isEmpty,
      );
    });

    test(
      'closed by a click on its first point, that once; a spot clicked twice is one point',
      () {
        session.setTool(SplineTool.toolId);
        for (final p in [
          Vector3(0, 0, 0),
          Vector3(8, 0, 0),
          Vector3(8, 0, 8),
        ]) {
          click(p);
        }
        click(Vector3(0, 0, 0));
        final first = withSpline().getComponent<Spline3DComponent>()!;
        expect(first.closed, isTrue);
        expect(tool().closed.value, isFalse, reason: 'the option as it was');

        click(Vector3(0, 0, 12));
        click(Vector3(0, 0, 12));
        expect(
          tool().points,
          hasLength(1),
          reason: 'the same spot again adds nothing',
        );
        click(Vector3(8, 0, 12));
        click(Vector3(8, 0, 18));
        session.handleKey(LogicalKeyboardKey.enter, gridSize: 32);
        final second = scope.world.entities
            .where((e) => e.hasComponent<Spline3DComponent>())
            .last
            .getComponent<Spline3DComponent>()!;
        expect(identical(second, first), isFalse);
        expect([second.points.length, second.closed], [3, false]);
      },
    );

    test('a platform route: a path and the platform that rides it', () {
      session.setTool(SplineTool.toolId);
      tool().make.value = SplineMake.route;
      click(Vector3(0, 0, 0));
      click(Vector3(10, 0, 0));
      session.handleKey(LogicalKeyboardKey.enter, gridSize: 32);
      final path = withSpline();
      final platform = scope.world.entities.singleWhere(
        (e) => e.hasComponent<PathFollower3DComponent>(),
      );
      expect(
        platform.getComponent<PathFollower3DComponent>()!.path.value,
        path.name,
      );
      expect(
        platform.getComponent<RigidBody3DComponent>()!.bodyType,
        Body3DType.kinematic,
      );
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('handles: drag a point, raise it, add one, remove one', () {
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 5)),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
        ], curve: SplineInterpolation.catmullRom),
      ], name: 'Path_0');
      scope.sceneState.registerEntity(entity);
      final spline = entity.getComponent<Spline3DComponent>()!;
      List<ViewportHandle> handles() =>
          SplineHandles().handlesOf(entity, scope);
      // Three points, their heights, two "+" between and one past the end.
      expect(handles(), hasLength(3 + 3 + 2 + 1));
      expect(
        handles().first.position.z,
        closeTo(5, 1e-9),
        reason: 'in the world',
      );

      Ray3D down(double x, double z) =>
          Ray3D.originDirection(Vector3(x, -10, z), Vector3(0, 1, 0));
      handles()[0].onDrag(
        HandleDrag(
          ray: down(1, 7),
          start: Vector3(0, 0, 5),
          snap: false,
          grid: 1,
        ),
      );
      expect(
        [spline.points[0].position.x, spline.points[0].position.z],
        [closeTo(1, 1e-9), closeTo(2, 1e-9)],
      );

      // The diamond a metre above point 1, pulled up 2 m: a sideways ray.
      final height = handles()
          .where((h) => h.style == ViewportHandleStyle.size)
          .toList()[1];
      height.onDrag(
        HandleDrag(
          ray: Ray3D.originDirection(Vector3(-20, -3, 5), Vector3(1, 0, 0)),
          start: height.position,
          snap: false,
          grid: 1,
        ),
      );
      expect(spline.points[1].position.y, closeTo(-2, 1e-9));

      final add = handles()
          .where((h) => h.style == ViewportHandleStyle.add)
          .first;
      add.onClick!(const HandleClick(alt: false));
      expect(spline.points, hasLength(4));
      handles().first.onClick!(const HandleClick(alt: true));
      expect(spline.points, hasLength(3));
    });

    test('Bézier points have handles; one dragged turns the other', () {
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [20, 0, 0],
        ], curve: SplineInterpolation.bezier),
      ]);
      final spline = entity.getComponent<Spline3DComponent>()!;
      final handles = SplineHandles().handlesOf(entity, scope);
      // Middle point: in and out.
      final out = handles
          .where((h) => h.tooltip!.contains('leaving'))
          .toList()[1];
      out.onDrag(
        HandleDrag(
          ray: Ray3D.originDirection(Vector3(12, -10, 2), Vector3(0, 1, 0)),
          start: out.position,
          snap: false,
          grid: 1,
        ),
      );
      final p = spline.points[1];
      expect(p.mode, SplineTangentMode.aligned);
      expect(
        [p.outTangent.x, p.outTangent.z],
        [closeTo(2, 1e-9), closeTo(2, 1e-9)],
      );
      expect(
        p.inTangent.normalized().dot(p.outTangent.normalized()),
        closeTo(-1, 1e-9),
      );
    });

    test('the points row: Reverse and Flatten', () {
      final points = _spline([
        [0, -1, 0],
        [5, -3, 0],
      ]).points..first.outTangent = Vector3(1, -1, 0);
      final reversed = SplineEdits.reversed(points);
      expect(reversed.first.position.x, 5);
      expect(reversed.last.inTangent.x, 1);
      final flat = SplineEdits.flattened(points);
      expect(flat.every((p) => p.position.y == -1), isTrue);
      expect(flat.first.outTangent.y, 0);
      expect(points.last.position.y, -3, reason: 'the originals left alone');
    });

    test('the selection laid along a spline, facing along it', () {
      final route = scope.world.createEntityWithComponents([
        TransformComponent(),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]),
      ], name: 'Path_0');
      final lamp = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(50, 0, 50)),
        Cube3DComponent(width: 0.2, height: 3, depth: 0.2),
      ], name: 'Lamp_0');
      for (final e in [route, lamp]) {
        scope.sceneState.registerEntity(e);
      }
      expect(SplineEdits.layAlong(scope, route, [route, lamp], 5), 3);
      final lamps = scope.world.entities
          .where(
            (e) =>
                e.getComponent<Primitive3DComponent>() is Cube3DComponent &&
                e != lamp,
          )
          .toList();
      expect(
        [
          for (final l in lamps)
            l.getComponent<TransformComponent>()!.position.x,
        ]..sort(),
        [closeTo(0, 1e-6), closeTo(5, 1e-6), closeTo(10, 1e-6)],
      );
      final q = Quaternion.identity();
      lamps.first.getComponent<TransformComponent>()!.rotationInto(q);
      final forward = Vector3(0, 0, 1);
      q.rotate(forward);
      expect(forward.x, closeTo(1, 1e-6));
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('copies along a spline baked into entities, the component off', () {
      final fence = scope.world.createEntityWithComponents([
        TransformComponent(),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]),
        SplineInstances3DComponent(spacing: 2),
      ], name: 'Posts_0');
      scope.sceneState.registerEntity(fence);
      expect(SplineEdits.bake(scope, fence), 6);
      expect(fence.hasComponent<SplineInstances3DComponent>(), isFalse);
      final posts = scope.world.entities
          .where(
            (e) => e.getComponent<Primitive3DComponent>() is Cube3DComponent,
          )
          .toList();
      expect(posts, hasLength(6));
      // A metre cube standing on the spline: its middle half a metre up.
      expect(
        posts.first.getComponent<TransformComponent>()!.position.y,
        closeTo(-0.5, 1e-6),
      );
      expect(
        posts.every((p) => p.getComponent<ParentComponent>() != null),
        isTrue,
        reason: 'in one group',
      );
      scope.history.undo();
      expect(fence.hasComponent<SplineInstances3DComponent>(), isTrue);
      expect(
        scope.world.entities.where(
          (e) => e.getComponent<Primitive3DComponent>() is Cube3DComponent,
        ),
        isEmpty,
      );
    });
  });
}

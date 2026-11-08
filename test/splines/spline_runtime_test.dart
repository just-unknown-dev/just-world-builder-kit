// Splines at run time: saved and read back, a follower carried along its
// route, a sweep tied to its spline before physics.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
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

  group('the runtime', () {
    late World world;

    setUp(() {
      world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
    });

    test('its components saved and read back', () {
      final definitions = world.context.definitions;
      final spline =
          _spline(
              [
                [0, 0, 0],
                [4, -1, 2],
              ],
              closed: true,
              curve: SplineInterpolation.bezier,
            )
            ..points[0].outTangent = Vector3(1, 0, 0)
            ..points[0].mode = SplineTangentMode.free
            ..points[1].roll = 0.5;
      final json = definitions.encode(spline)!;
      final back = definitions.decode(json)! as Spline3DComponent;
      expect(back.shapeKey, spline.shapeKey);

      final follower = PathFollower3DComponent(
        path: const EntityTarget.name('Route'),
        speed: 3,
        mode: FollowMode.loop,
        faceAlong: true,
      );
      final again =
          definitions.decode(definitions.encode(follower)!)!
              as PathFollower3DComponent;
      expect(
        [again.path.value, again.speed, again.mode, again.faceAlong],
        ['Route', 3, FollowMode.loop, true],
      );

      final sweep = SplineSweep3DComponent(
        profile: SweepProfile.pipe,
        radius: 0.7,
        material: 'assets/materials/rock.material.json',
      );
      final copy =
          definitions.decode(definitions.encode(sweep)!)!
              as SplineSweep3DComponent;
      expect(
        [copy.profile, copy.radius, copy.material],
        [SweepProfile.pipe, 0.7, 'assets/materials/rock.material.json'],
      );
      expect(
        world.context.fieldTypes.byId(SplinePointsFieldType.typeId),
        isA<SplinePointsFieldType>(),
      );
    });

    test('a platform carried along its route, resting at each end', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 10)),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
        ]),
      ], name: 'Route');
      final platform = world.createEntityWithComponents([
        TransformComponent(),
        RigidBody3DComponent(bodyType: Body3DType.kinematic),
        PathFollower3DComponent(
          path: const EntityTarget.name('Route'),
          speed: 2,
          wait: 0.5,
          faceAlong: true,
        ),
      ], name: 'Platform');
      WorldBuilderKit.registerSystems(world);
      final at = platform.getComponent<TransformComponent>()!.position;
      world.update(0.0);
      expect(
        [at.x, at.z],
        [closeTo(0, 1e-9), closeTo(10, 1e-9)],
        reason: 'laid out by the route\'s entity',
      );
      world.update(1);
      expect(at.x, closeTo(2, 1e-6));
      final q = Quaternion.identity();
      platform.getComponent<TransformComponent>()!.rotationInto(q);
      final facing = Vector3(0, 0, 1);
      q.rotate(facing);
      expect(facing.x, closeTo(1, 1e-6), reason: 'facing the way it goes');
      for (var i = 0; i < 4; i++) {
        world.update(1);
      }
      expect(at.x, closeTo(10, 1e-6));
      world.update(0.25);
      expect(at.x, closeTo(10, 1e-6), reason: 'resting');
      world.update(0.75);
      expect(at.x, closeTo(9, 1e-6), reason: 'and back');
      expect(
        platform.getComponent<PathFollower3DComponent>()!.speed,
        2,
        reason: 'its saved fields untouched',
      );
    });

    test(
      'while time stands still, a follower goes where its start now is; paused, it stays',
      () {
        world.createEntityWithComponents([
          TransformComponent(),
          _spline([
            [0, 0, 0],
            [10, 0, 0],
          ]),
        ], name: 'Route');
        final follower = PathFollower3DComponent(
          path: const EntityTarget.name('Route'),
          speed: 2,
        );
        final entity = world.createEntityWithComponents([
          TransformComponent(),
          follower,
        ]);
        world.addSystem(PathFollower3DSystem());
        final at = entity.getComponent<TransformComponent>()!.position;
        world.update(0);
        expect(at.x, closeTo(0, 1e-9));
        // Authored in an editor: its start moved, with time standing still.
        follower.startAt = 6;
        world.update(0);
        expect(at.x, closeTo(6, 1e-9), reason: 'where it now starts');
        // Played a while, then paused: it stays where it got to.
        world.update(1);
        expect(at.x, closeTo(8, 1e-9));
        world.update(0);
        world.update(0);
        expect(at.x, closeTo(8, 1e-9), reason: 'a pause is no edit');
        expect(follower.startAt, 6, reason: 'its saved fields untouched');
      },
    );

    test('once: to the end, and stops; a loop round a closed route', () {
      world.createEntityWithComponents([
        TransformComponent(),
        _spline([
          [0, 0, 0],
          [10, 0, 0],
          [10, 0, 10],
          [0, 0, 10],
        ], closed: true),
      ], name: 'Ring');
      final once = PathFollower3DComponent(
        path: const EntityTarget.name('Ring'),
        speed: 10,
        mode: FollowMode.once,
      );
      final loop = PathFollower3DComponent(
        path: const EntityTarget.name('Ring'),
        speed: 10,
        mode: FollowMode.loop,
        wait: 9,
      );
      world.createEntityWithComponents([TransformComponent(), once]);
      world.createEntityWithComponents([TransformComponent(), loop]);
      world.addSystem(PathFollower3DSystem());
      world.update(0);
      for (var i = 0; i < 5; i++) {
        world.update(1);
      }
      expect(once.travelled, closeTo(40, 1e-9));
      expect(
        loop.travelled,
        closeTo(10, 1e-9),
        reason: 'round again, with no ends to rest at',
      );
    });

    test('a sweep tied to its spline before physics, drawn or not', () {
      final sweep = SplineSweep3DComponent();
      final spline = _spline([
        [0, 0, 0],
        [3, 0, 0],
      ]);
      world.createEntityWithComponents([TransformComponent(), spline, sweep]);
      world.addSystem(Spline3DLinkSystem());
      world.update(0);
      expect(identical(sweep.spline, spline), isTrue);
      expect(sweep.solidParts, isNotEmpty);
    });
  });
}

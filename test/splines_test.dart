// Splines: a path's length, frames and nearest point; a road swept along
// one, closed and facing out; the kit's components saved and read back; a
// platform carried along a route; and the editor's Spline tool, handles,
// lay-along and bake, each one undo step.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

Spline3D _spline(List<List<double>> points, {bool closed = false, SplineInterpolation curve = SplineInterpolation.linear}) =>
    Spline3D(
      points: [for (final p in points) SplinePoint(position: Vector3(p[0], p[1], p[2]))],
      closed: closed,
      interpolation: curve,
    );

/// The volume [mesh] holds: positive when its faces wind anticlockwise
/// seen from outside.
double _volume(SweptMesh mesh) {
  final p = mesh.positions, idx = mesh.indices;
  Vector3 at(int i) => Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]);
  var v = 0.0;
  for (var i = 0; i < idx.length; i += 3) {
    v += at(idx[i]).dot(at(idx[i + 1]).cross(at(idx[i + 2])));
  }
  return v / 6;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a spline\'s path', () {
    test('its length, straight or round a corner', () {
      expect(SplinePath.of(_spline([[0, 0, 0], [10, 0, 0], [10, 0, 10]])).length, closeTo(20, 1e-9));
      final straight = _spline([[0, 0, 0], [5, 0, 0], [10, 0, 0]], curve: SplineInterpolation.catmullRom);
      expect(SplinePath.of(straight).length, closeTo(10, 1e-6));
      // A circle through 8 points, near 2πr.
      final circle = _spline([
        for (var i = 0; i < 8; i++) [math.cos(i * math.pi / 4) * 5, 0, math.sin(i * math.pi / 4) * 5],
      ], closed: true, curve: SplineInterpolation.catmullRom);
      expect(SplinePath.of(circle).length, closeTo(2 * math.pi * 5, 0.15));
    });

    test('its frames: square, unit, and level on level ground', () {
      final loop = _spline([[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 10]], closed: true, curve: SplineInterpolation.catmullRom);
      final path = SplinePath.of(loop);
      for (var d = 0.0; d < path.length; d += path.length / 37) {
        final f = path.at(d);
        expect(f.tangent.length, closeTo(1, 1e-6));
        expect(f.up.length, closeTo(1, 1e-6));
        expect(f.right.length, closeTo(1, 1e-6));
        expect(f.tangent.dot(f.up).abs(), lessThan(1e-6));
        expect(f.right.dot(f.up).abs(), lessThan(1e-6));
        // +Y is down: up is -Y.
        expect(f.up.y, closeTo(-1, 1e-6), reason: 'at $d');
      }
    });

    test('a point\'s roll turns its up about the spline', () {
      final rolled = _spline([[0, 0, 0], [10, 0, 0]])..points[1].roll = math.pi / 2;
      final path = SplinePath.of(rolled);
      expect(path.at(0).up.y, closeTo(-1, 1e-6));
      final end = path.at(path.length);
      expect(end.up.y.abs(), lessThan(1e-6), reason: 'a quarter turn by the end');
    });

    test('where it is past its ends, and the point nearest another', () {
      final open = SplinePath.of(_spline([[0, 0, 0], [10, 0, 0], [10, 0, 10]]));
      expect(open.at(-5).position.x, closeTo(0, 1e-9));
      expect(open.at(99).position.z, closeTo(10, 1e-9));
      final near = open.nearest(Vector3(5, -1, 3));
      expect([near.position.x, near.position.z], [closeTo(5, 1e-9), closeTo(0, 1e-9)]);
      expect(near.distance, closeTo(5, 1e-9));

      final loop = SplinePath.of(_spline([[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 10]], closed: true));
      expect(loop.length, closeTo(40, 1e-9));
      expect(loop.at(41).position.x, closeTo(1, 1e-9), reason: 'round again');
    });

    test('copies laid along it, every so far', () {
      final path = SplinePath.of(_spline([[0, 0, 0], [10, 0, 0]]));
      expect(InstancesRenderProvider.placements(SplineInstances3D(spacing: 2), path), hasLength(6));
      final loop = SplinePath.of(_spline([[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 10]], closed: true));
      expect(InstancesRenderProvider.placements(SplineInstances3D(spacing: 4), loop), hasLength(10), reason: 'none twice where it meets itself');
    });

    test('a closed loop over hills and dips: its frames meet where it closes', () {
      // Not level: the frames turn on the way round, and that turn is
      // spread back along it.
      final loop = _spline([
        [10, 0, 0],
        [3, -6, 8],
        [-7, 2, 5],
        [-8, -5, -6],
        [2, 4, -9],
      ], closed: true, curve: SplineInterpolation.catmullRom);
      final path = SplinePath.of(loop);
      expect(path.ups.first.dot(path.ups.last), greaterThan(1 - 1e-9), reason: 'no twist at the seam');
      final before = path.at(path.length - 1e-3), after = path.at(1e-3);
      expect(before.up.dot(after.up), greaterThan(0.999), reason: 'smooth across it');
    });

    test('a point given twice is one: no fold back, the way on from the start', () {
      final twice = SplinePath.of(_spline([[0, 0, 0], [0, 0, 0], [10, 0, 0], [10, 0, 10]], curve: SplineInterpolation.catmullRom));
      final once = SplinePath.of(_spline([[0, 0, 0], [10, 0, 0], [10, 0, 10]], curve: SplineInterpolation.catmullRom));
      expect(twice.positions, hasLength(once.positions.length));
      expect(twice.length, closeTo(once.length, 1e-9));
      for (var d = 0.0; d < once.length; d += 0.5) {
        expect(twice.at(d).position.x, greaterThanOrEqualTo(-1e-9), reason: 'never back past its start');
      }
      final straight = SplinePath.of(_spline([[0, 0, 0], [0, 0, 0], [10, 0, 0]]));
      expect(straight.at(0).tangent.x, closeTo(1, 1e-9), reason: 'facing the way it goes');
      // Round a closed one, a last point back on the first is the first.
      final square = _spline([[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 10], [0, 0, 0]], closed: true);
      expect(SplinePath.of(square).length, closeTo(40, 1e-9));
    });
  });

  group('a sweep', () {
    test('a road: closed, facing out, its top on the spline', () {
      final sweep = SplineSweep3D(profile: SweepProfile.road, width: 3, height: 0.3, step: 1);
      final mesh = SplineSweeper.meshFor(sweep, _spline([[0, 0, 0], [10, 0, 0]]))!;
      // Four sides of ten stretches, two triangles each, and two ends.
      expect(mesh.triangleCount, 4 * 10 * 2 + 2 * 2);
      expect(_volume(mesh), closeTo(10 * 3 * 0.3, 1e-4), reason: 'whole, and its faces out');
      var minY = double.infinity, maxY = -double.infinity, maxZ = 0.0;
      for (var i = 0; i < mesh.positions.length; i += 3) {
        minY = math.min(minY, mesh.positions[i + 1]);
        maxY = math.max(maxY, mesh.positions[i + 1]);
        maxZ = math.max(maxZ, mesh.positions[i + 2].abs());
      }
      // +Y is down: its top at the spline, its body below.
      expect([minY, maxY, maxZ], [closeTo(0, 1e-6), closeTo(0.3, 1e-6), closeTo(1.5, 1e-6)]);
    });

    test('made again only when it or its spline changes', () {
      final spline = _spline([[0, 0, 0], [10, 0, 0]]);
      final sweep = SplineSweep3D(profile: SweepProfile.wall);
      final first = SplineSweeper.meshFor(sweep, spline);
      expect(identical(SplineSweeper.meshFor(sweep, spline), first), isTrue);
      final key = sweep.sweepKey;
      spline.points[1].position.z = 4;
      expect(sweep.sweepKey, isNot(key));
      expect(identical(SplineSweeper.meshFor(sweep, spline), first), isFalse);
    });

    test('a pipe: smooth, its normals out from the middle', () {
      final sweep = SplineSweep3D(profile: SweepProfile.pipe, radius: 0.5, sides: 10, step: 0.5);
      final mesh = SplineSweeper.meshFor(sweep, _spline([[0, 0, 0], [6, 0, 0], [6, 0, 6]], curve: SplineInterpolation.catmullRom))!;
      expect(_volume(mesh), greaterThan(0));
      final path = SplinePath.of(sweep.spline!);
      for (var i = 0; i < mesh.positions.length; i += 3 * 17) {
        final p = Vector3(mesh.positions[i], mesh.positions[i + 1], mesh.positions[i + 2]);
        final n = Vector3(mesh.normals[i], mesh.normals[i + 1], mesh.normals[i + 2]);
        expect(n.length, closeTo(1, 1e-4));
        final near = path.nearest(p);
        // An end's cap faces along it.
        if (n.dot(path.at(near.distance).tangent).abs() > 0.5) continue;
        final out = p - near.position;
        if (out.length > 0.3) expect(out.normalized().dot(n), greaterThan(0.9));
      }
    });

    test('solid once tied to its spline: a mesh to collide with', () {
      final sweep = SplineSweep3D(profile: SweepProfile.road, step: 1);
      expect(sweep.solidParts, isEmpty);
      sweep.spline = _spline([[0, 0, 0], [10, 0, 0]]);
      final parts = sweep.solidParts;
      expect(parts.single, isA<SolidMesh>());
      expect((parts.single as SolidMesh).triangleCount, 84);
    });

    test('its solid key changes with its shape, not with how it looks', () {
      final sweep = SplineSweep3D(profile: SweepProfile.road)..spline = _spline([[0, 0, 0], [10, 0, 0]]);
      final key = sweep.solidKey;
      sweep.tiling = 4;
      expect(sweep.solidKey, key, reason: 'its collider is not made again for its texture');
      sweep.width = 5;
      expect(sweep.solidKey, isNot(key));
    });
  });

  group('the runtime', () {
    late World world;

    setUp(() {
      world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
    });

    test('its components saved and read back', () {
      final definitions = world.context.definitions;
      final spline = _spline([[0, 0, 0], [4, -1, 2]], closed: true, curve: SplineInterpolation.bezier)
        ..points[0].outTangent = Vector3(1, 0, 0)
        ..points[0].mode = SplineTangentMode.free
        ..points[1].roll = 0.5;
      final json = definitions.encode(spline)!;
      final back = definitions.decode(json)! as Spline3D;
      expect(back.shapeKey, spline.shapeKey);

      final follower = PathFollower3D(path: const EntityTarget.name('Route'), speed: 3, mode: FollowMode.loop, faceAlong: true);
      final again = definitions.decode(definitions.encode(follower)!)! as PathFollower3D;
      expect([again.path.value, again.speed, again.mode, again.faceAlong], ['Route', 3, FollowMode.loop, true]);

      final sweep = SplineSweep3D(profile: SweepProfile.pipe, radius: 0.7, material: 'assets/materials/rock.material.json');
      final copy = definitions.decode(definitions.encode(sweep)!)! as SplineSweep3D;
      expect([copy.profile, copy.radius, copy.material], [SweepProfile.pipe, 0.7, 'assets/materials/rock.material.json']);
      expect(world.context.fieldTypes.byId(SplinePointsFieldType.typeId), isA<SplinePointsFieldType>());
    });

    test('a platform carried along its route, resting at each end', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 10)),
        _spline([[0, 0, 0], [10, 0, 0]]),
      ], name: 'Route');
      final platform = world.createEntityWithComponents([
        TransformComponent(),
        RigidBody3D(bodyType: BodyType3D.kinematic),
        PathFollower3D(path: const EntityTarget.name('Route'), speed: 2, wait: 0.5, faceAlong: true),
      ], name: 'Platform');
      WorldBuilderKit.registerSystems(world);
      final at = platform.getComponent<TransformComponent>()!.position;
      world.update(0.0);
      expect([at.x, at.z], [closeTo(0, 1e-9), closeTo(10, 1e-9)], reason: 'laid out by the route\'s entity');
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
      expect(platform.getComponent<PathFollower3D>()!.speed, 2, reason: 'its saved fields untouched');
    });

    test('once: to the end, and stops; a loop round a closed route', () {
      world.createEntityWithComponents([
        TransformComponent(),
        _spline([[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 10]], closed: true),
      ], name: 'Ring');
      final once = PathFollower3D(path: const EntityTarget.name('Ring'), speed: 10, mode: FollowMode.once);
      final loop = PathFollower3D(path: const EntityTarget.name('Ring'), speed: 10, mode: FollowMode.loop, wait: 9);
      world.createEntityWithComponents([TransformComponent(), once]);
      world.createEntityWithComponents([TransformComponent(), loop]);
      world.addSystem(PathFollower3DSystem());
      world.update(0);
      for (var i = 0; i < 5; i++) {
        world.update(1);
      }
      expect(once.travelled, closeTo(40, 1e-9));
      expect(loop.travelled, closeTo(10, 1e-9), reason: 'round again, with no ends to rest at');
    });

    test('a sweep tied to its spline before physics, drawn or not', () {
      final sweep = SplineSweep3D();
      final spline = _spline([[0, 0, 0], [3, 0, 0]]);
      world.createEntityWithComponents([TransformComponent(), spline, sweep]);
      world.addSystem(SplineLinkSystem());
      world.update(0);
      expect(identical(sweep.spline, spline), isTrue);
      expect(sweep.solidParts, isNotEmpty);
    });
  });

  group('the editor', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      scope = EditorScope(
        world: world,
        modules: [WorldBuilderModule()],
        builtIns: const [BuiltInEditorModule.new],
      );
      addTearDown(scope.dispose);
      scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
      scope.selectDesigner('world_builder');
      view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
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
      session.onPointerDown(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
      session.onPointerUp(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    }

    SplineTool tool() => session.tools.byId(SplineTool.toolId)! as SplineTool;
    Entity withSpline() => scope.world.entities.singleWhere((e) => e.hasComponent<Spline3D>());

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
      final spline = road.getComponent<Spline3D>()!;
      expect(spline.points, hasLength(3));
      expect(spline.points.first.position.length, closeTo(0, 1e-9), reason: 'standing at its first point');
      final t = road.getComponent<TransformComponent>()!.position;
      expect([t.x, t.y, t.z], [closeTo(2, 1e-6), closeTo(-0.02, 1e-6), closeTo(0, 1e-6)], reason: 'lifted off the ground');
      expect(road.getComponent<SplineSweep3D>()!.profile, SweepProfile.road);
      expect(road.getComponent<RigidBody3D>()!.bodyType, BodyType3D.static);
      expect(road.getComponent<Collider3D>()!.shape, ColliderShape3D.matchShape);
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(scope.world.entities.where((e) => e.hasComponent<Spline3D>()), isEmpty);
    });

    test('closed by a click on its first point, that once; a spot clicked twice is one point', () {
      session.setTool(SplineTool.toolId);
      for (final p in [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8)]) {
        click(p);
      }
      click(Vector3(0, 0, 0));
      final first = withSpline().getComponent<Spline3D>()!;
      expect(first.closed, isTrue);
      expect(tool().closed.value, isFalse, reason: 'the option as it was');

      click(Vector3(0, 0, 12));
      click(Vector3(0, 0, 12));
      expect(tool().points, hasLength(1), reason: 'the same spot again adds nothing');
      click(Vector3(8, 0, 12));
      click(Vector3(8, 0, 18));
      session.handleKey(LogicalKeyboardKey.enter, gridSize: 32);
      final second = scope.world.entities.where((e) => e.hasComponent<Spline3D>()).last.getComponent<Spline3D>()!;
      expect(identical(second, first), isFalse);
      expect([second.points.length, second.closed], [3, false]);
    });

    test('a platform route: a path and the platform that rides it', () {
      session.setTool(SplineTool.toolId);
      tool().make.value = SplineMake.route;
      click(Vector3(0, 0, 0));
      click(Vector3(10, 0, 0));
      session.handleKey(LogicalKeyboardKey.enter, gridSize: 32);
      final path = withSpline();
      final platform = scope.world.entities.singleWhere((e) => e.hasComponent<PathFollower3D>());
      expect(platform.getComponent<PathFollower3D>()!.path.value, path.name);
      expect(platform.getComponent<RigidBody3D>()!.bodyType, BodyType3D.kinematic);
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('handles: drag a point, raise it, add one, remove one', () {
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 5)),
        _spline([[0, 0, 0], [10, 0, 0], [10, 0, 10]], curve: SplineInterpolation.catmullRom),
      ], name: 'Path_0');
      scope.sceneState.registerEntity(entity);
      final spline = entity.getComponent<Spline3D>()!;
      List<ViewportHandle> handles() => SplineHandles().handlesOf(entity, scope);
      // Three points, their heights, two "+" between and one past the end.
      expect(handles(), hasLength(3 + 3 + 2 + 1));
      expect(handles().first.position.z, closeTo(5, 1e-9), reason: 'in the world');

      Ray3 down(double x, double z) => Ray3.originDirection(Vector3(x, -10, z), Vector3(0, 1, 0));
      handles()[0].onDrag(HandleDrag(ray: down(1, 7), start: Vector3(0, 0, 5), snap: false, grid: 1));
      expect([spline.points[0].position.x, spline.points[0].position.z], [closeTo(1, 1e-9), closeTo(2, 1e-9)]);

      // The diamond a metre above point 1, pulled up 2 m: a sideways ray.
      final height = handles().where((h) => h.style == ViewportHandleStyle.size).toList()[1];
      height.onDrag(HandleDrag(ray: Ray3.originDirection(Vector3(-20, -3, 5), Vector3(1, 0, 0)), start: height.position, snap: false, grid: 1));
      expect(spline.points[1].position.y, closeTo(-2, 1e-9));

      final add = handles().where((h) => h.style == ViewportHandleStyle.add).first;
      add.onClick!(const HandleClick(alt: false));
      expect(spline.points, hasLength(4));
      handles().first.onClick!(const HandleClick(alt: true));
      expect(spline.points, hasLength(3));
    });

    test('Bézier points have handles; one dragged turns the other', () {
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(),
        _spline([[0, 0, 0], [10, 0, 0], [20, 0, 0]], curve: SplineInterpolation.bezier),
      ]);
      final spline = entity.getComponent<Spline3D>()!;
      final handles = SplineHandles().handlesOf(entity, scope);
      // Middle point: in and out.
      final out = handles.where((h) => h.tooltip!.contains('leaving')).toList()[1];
      out.onDrag(HandleDrag(ray: Ray3.originDirection(Vector3(12, -10, 2), Vector3(0, 1, 0)), start: out.position, snap: false, grid: 1));
      final p = spline.points[1];
      expect(p.mode, SplineTangentMode.aligned);
      expect([p.outTangent.x, p.outTangent.z], [closeTo(2, 1e-9), closeTo(2, 1e-9)]);
      expect(p.inTangent.normalized().dot(p.outTangent.normalized()), closeTo(-1, 1e-9));
    });

    test('the points row: Reverse and Flatten', () {
      final points = _spline([[0, -1, 0], [5, -3, 0]]).points..first.outTangent = Vector3(1, -1, 0);
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
        _spline([[0, 0, 0], [10, 0, 0]]),
      ], name: 'Path_0');
      final lamp = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(50, 0, 50)),
        Cube3D(width: 0.2, height: 3, depth: 0.2),
      ], name: 'Lamp_0');
      for (final e in [route, lamp]) {
        scope.sceneState.registerEntity(e);
      }
      expect(SplineEdits.layAlong(scope, route, [route, lamp], 5), 3);
      final lamps = scope.world.entities.where((e) => e.getComponent<Primitive3D>() is Cube3D && e != lamp).toList();
      expect([for (final l in lamps) l.getComponent<TransformComponent>()!.position.x]..sort(), [
        closeTo(0, 1e-6),
        closeTo(5, 1e-6),
        closeTo(10, 1e-6),
      ]);
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
        _spline([[0, 0, 0], [10, 0, 0]]),
        SplineInstances3D(spacing: 2),
      ], name: 'Posts_0');
      scope.sceneState.registerEntity(fence);
      expect(SplineEdits.bake(scope, fence), 6);
      expect(fence.hasComponent<SplineInstances3D>(), isFalse);
      final posts = scope.world.entities.where((e) => e.getComponent<Primitive3D>() is Cube3D).toList();
      expect(posts, hasLength(6));
      // A metre cube standing on the spline: its middle half a metre up.
      expect(posts.first.getComponent<TransformComponent>()!.position.y, closeTo(-0.5, 1e-6));
      expect(posts.every((p) => p.getComponent<ParentComponent>() != null), isTrue, reason: 'in one group');
      scope.history.undo();
      expect(fence.hasComponent<SplineInstances3D>(), isTrue);
      expect(scope.world.entities.where((e) => e.getComponent<Primitive3D>() is Cube3D), isEmpty);
    });
  });
}

// What draws the kit's splines, on the null device: a sweep's mesh and a
// row of copies, where their entity is, built again when the spline
// changes.
import 'dart:math' as math;
import 'dart:ui' show Color, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

FrameView _view(Vector3 eye) {
  const size = Size(64, 64);
  final camera = RenderView()..lookAt(eye, Vector3(10, 0, 0));
  final view = FrameView()
    ..viewportSize = size
    ..isPlanar = false;
  view.view.setFrom(camera.view);
  view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 200);
  view.viewProjection.setProduct(view.projection, view.view);
  view.cameraPosition.setFrom(eye);
  return view;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  final view = _view(Vector3(10, -10, -20));

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(config: EngineConfig(extensions: [WorldBuilderKit.extension], graphics3D: service));
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  Entity road({SplineInstances3D? copies}) => engine.world.createEntityWithComponents([
    TransformComponent(position: Vector3(5, 0, 0)),
    Spline3D(points: [SplinePoint(position: Vector3.zero()), SplinePoint(position: Vector3(10, 0, 0))]),
    SplineSweep3D(step: 1),
    ?copies,
  ], name: 'Road');

  test('a sweep\'s mesh, where its entity is', () {
    road();
    final renderer = service.sceneRenderer..update(view);
    final mesh = renderer.scene.instances.single;
    expect(mesh.world.storage[12], 5);
    expect(mesh.primitive.bounds.max.x - mesh.primitive.bounds.min.x, closeTo(10, 1e-4));
  });

  test('a row of copies in one batch, built again when the spline changes', () {
    final e = road(copies: SplineInstances3D(spacing: 2));
    final renderer = service.sceneRenderer..update(view);
    final batch = renderer.scene.batches.single;
    expect(batch.count, 6);
    expect(batch.bounds.min.x, closeTo(4.5, 1e-4), reason: 'a metre cube each, from x = 5');
    final spline = e.getComponent<Spline3D>()!;
    spline.points = [spline.points.first, SplinePoint(position: Vector3(20, 0, 0))];
    renderer.update(view);
    expect(renderer.scene.batches.single.count, 11);
    final sweep = renderer.scene.instances.single;
    expect(sweep.primitive.bounds.max.x - sweep.primitive.bounds.min.x, closeTo(20, 1e-4), reason: 'swept again');
  });

  test('a spline put in another\'s place is followed, though no system runs', () {
    final e = road(copies: SplineInstances3D(spacing: 2));
    final renderer = service.sceneRenderer..update(view);
    expect(renderer.scene.batches.single.count, 6);
    // Taken off and another put on — as an undone removal does.
    e.removeComponent<Spline3D>();
    e.addComponent(Spline3D(points: [SplinePoint(position: Vector3.zero()), SplinePoint(position: Vector3(30, 0, 0))]));
    renderer.update(view);
    final sweep = renderer.scene.instances.single;
    expect(sweep.primitive.bounds.max.x - sweep.primitive.bounds.min.x, closeTo(30, 1e-4), reason: 'swept along the new one');
    expect(renderer.scene.batches.single.count, 16);
  });

  test('plain colours\' materials: only the last ones drawn are kept', () {
    final e = road();
    final renderer = service.sceneRenderer..update(view);
    final sweep = e.getComponent<SplineSweep3D>()!;
    final provider = RenderProviders.of(engine.world.context).forType(SplineSweep3D)! as SweepRenderProvider;
    for (var k = 0; k < SweepRenderProvider.colourLimit + 30; k++) {
      sweep.color = Color(0xFF000000 | (k * 997));
      renderer.update(view);
    }
    expect(provider.colourCount, SweepRenderProvider.colourLimit);
  });
}

// Scatter: pieces packed small, kept apart, solid as their layer says;
// saved and read back; drawn in batches by layer and square.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, Render3DView, rendererNullShaders;

ScatterInstance _piece(double x, double z, {int layer = 0, double scale = 1}) =>
    ScatterInstance(layer: layer, position: Vector3(x, 0, z), scale: scale);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pieces', () {
    test('packed small and read back', () {
      final random = math.Random(3);
      final pieces = [
        for (var k = 0; k < 500; k++)
          ScatterInstance(
            layer: random.nextInt(3),
            position: Vector3(
              random.nextDouble() * 100,
              -random.nextDouble(),
              random.nextDouble() * 100,
            ),
            yaw: random.nextDouble() * 6,
            scale: 0.5 + random.nextDouble(),
            normal: Vector3(0.2, -0.9, 0.1)..normalize(),
          ),
      ];
      final back = ScatterInstancesFieldType.decodeInstances(
        ScatterInstancesFieldType.encodeInstances(pieces),
      );
      expect(back, hasLength(500));
      for (var k = 0; k < 500; k++) {
        expect(back[k].layer, pieces[k].layer);
        expect(back[k].position.x, closeTo(pieces[k].position.x, 1e-4));
        expect(back[k].yaw, closeTo(pieces[k].yaw, 1e-5));
        expect(
          back[k].normal.y,
          closeTo(pieces[k].normal.y, 1e-5),
          reason: 'its lean made whole again',
        );
      }
      expect(ScatterInstancesFieldType.decodeInstances(''), isEmpty);
    });

    test('kept their spacing apart; erased by area', () {
      final spacing = ScatterSpacing(
        [_piece(0, 0), _piece(10, 0, layer: 1)],
        0,
        2,
      );
      expect(spacing.fits(1, 1), isFalse);
      expect(spacing.fits(2.5, 0), isTrue);
      expect(spacing.fits(10, 0.5), isTrue, reason: 'another layer');
      expect(ScatterBrush.triesFor(5, 1), greaterThan(10));
      final random = math.Random(1);
      for (final (x, z) in ScatterBrush.spots(random, 5, 5, 3, 50)) {
        expect(
          math.sqrt((x - 5) * (x - 5) + (z - 5) * (z - 5)),
          lessThanOrEqualTo(3),
        );
      }
      final left = ScatterBrush.erased(
        [_piece(0, 0), _piece(1, 0), _piece(5, 0), _piece(0, 0, layer: 1)],
        0,
        0,
        2,
        layer: 0,
      );
      expect(left.map((p) => (p.position.x, p.layer)), [(5.0, 0), (0.0, 1)]);
    });

    test('solid only where their layer says, standing on their spot', () {
      final scatter = Scatter3DComponent(
        layers: [
          ScatterLayer(name: 'Grass'),
          ScatterLayer(
            name: 'Trees',
            collision: ScatterCollision.capsule,
            colliderRadius: 0.2,
            colliderHeight: 2,
          ),
        ],
        instances: [_piece(0, 0), _piece(4, 4, layer: 1, scale: 2)],
      );
      final capsule = scatter.solidParts.single as SolidCapsule;
      expect(
        [capsule.radius, capsule.halfHeight, capsule.x, capsule.y],
        [0.4, 1.6, 4, -2],
      );
      expect(identical(scatter.solidParts, scatter.solidParts), isTrue);
    });

    test(
      'a box piece turned or leant is solid as it is drawn; a new layer is as solid as its cone',
      () {
        final scatter = Scatter3DComponent(
          layers: [
            ScatterLayer(
              name: 'Rocks',
              collision: ScatterCollision.box,
              colliderRadius: 1,
              colliderHeight: 2,
            ),
          ],
          instances: [
            ScatterInstance(
              layer: 0,
              position: Vector3(10, 0, 0),
              yaw: math.pi / 4,
            ),
          ],
        );
        final hull = scatter.solidParts.single as SolidHull;
        var far = 0.0, top = 0.0;
        for (var i = 0; i < hull.points.length; i += 3) {
          far = math.max(far, (hull.points[i] - 10).abs());
          top = math.min(top, hull.points[i + 1]);
        }
        // An eighth of a turn: its corners reach out a metre's diagonal.
        expect(far, closeTo(math.sqrt2, 1e-5));
        expect(
          top,
          closeTo(-2, 1e-5),
          reason: 'standing on its spot, 2 m tall',
        );
        final upright = Scatter3DComponent(
          layers: [ScatterLayer(collision: ScatterCollision.box)],
          instances: [_piece(0, 0)],
        );
        expect(
          upright.solidParts.single,
          isA<SolidBox>(),
          reason: 'not turned: a plain box',
        );
        final layer = ScatterLayer();
        final (_, height) = ScatterRenderProvider.shapeOf(layer);
        expect(
          [layer.colliderHeight, layer.colliderRadius],
          [height, 0.4],
          reason: 'the cone it shows: 1.2 m, 0.4 m across its base',
        );
      },
    );

    test('two scatters read from a scene are each solid as itself', () {
      final world = World()..initialize();
      Graphics3D.registerDefinitions(world.context);
      WorldBuilderKit.install(world.context);
      final definitions = world.context.definitions;
      Scatter3DComponent read(Scatter3DComponent s) =>
          definitions.decode(definitions.encode(s)!)! as Scatter3DComponent;
      List<ScatterLayer> trees() => [
        ScatterLayer(name: 'Trees', collision: ScatterCollision.capsule),
      ];
      final a = read(
        Scatter3DComponent(layers: trees(), instances: [_piece(0, 0)]),
      );
      final b = read(
        Scatter3DComponent(
          layers: trees(),
          instances: [_piece(20, 20), _piece(30, 30)],
        ),
      );
      expect(a.revision, b.revision, reason: 'what made their keys the same');
      expect(a.solidKey, isNot(b.solidKey));
      final shapes = Collider3DShapes();
      final collider = Collider3DComponent(shape: Collider3DShape.matchShape);
      final one = Vector3(1, 1, 1);
      expect(
        identical(
          shapes.build(collider, one, source: a),
          shapes.build(collider, one, source: b),
        ),
        isFalse,
      );
    });

    test('a leaning piece leans with its ground', () {
      final lean = ScatterInstance(
        layer: 0,
        position: Vector3.zero(),
        normal: Vector3(1, -1, 0)..normalize(),
      );
      final m = lean.matrix(lean: true);
      final up = Vector3.zero();
      m.transformDirectionInto(Vector3(0, -1, 0), up);
      expect(
        [up.x, up.y],
        [closeTo(math.sqrt(0.5), 1e-6), closeTo(-math.sqrt(0.5), 1e-6)],
      );
    });
  });

  test('saved and read back', () {
    final world = World()..initialize();
    Graphics3D.registerDefinitions(world.context);
    WorldBuilderKit.install(world.context);
    final scatter = Scatter3DComponent(
      layers: starterScatterLayers(),
      instances: [_piece(1, 2, layer: 2)],
    );
    final definitions = world.context.definitions;
    final back =
        definitions.decode(definitions.encode(scatter)!)! as Scatter3DComponent;
    expect(back.layers.map((l) => l.name), ['Grass', 'Rocks', 'Trees']);
    expect(back.layers[2].collision, ScatterCollision.capsule);
    expect(back.instances.single.layer, 2);
    // What a layer is without a model: saved when not the cone, older files
    // read as cones.
    expect(
      ScatterLayer.fromJson(
        ScatterLayer(shape: ScatterShape.sphere).toJson(),
      ).shape,
      ScatterShape.sphere,
    );
    expect(ScatterLayer().toJson().containsKey('shape'), isFalse);
    expect(ScatterLayer.fromJson({'name': 'Old'}).shape, ScatterShape.cone);
  });

  test('drawn in batches by layer and square, not far off', () async {
    final service = Graphics3D(
      device: NullGpuDevice(shaders: rendererNullShaders),
    );
    final engine = Engine(
      config: EngineConfig(
        extensions: [WorldBuilderKit.extension],
        services: [service],
      ),
    );
    await engine.initialize();
    addTearDown(engine.dispose);
    engine.world.createEntityWithComponents([
      TransformComponent(),
      Scatter3DComponent(
        layers: [
          ScatterLayer(name: 'Grass', maxDistance: 50),
          ScatterLayer(name: 'Rocks'),
        ],
        instances: [
          _piece(1, 1),
          _piece(2, 2),
          _piece(40, 1),
          _piece(3, 3, layer: 1),
        ],
      ),
    ]);
    final camera = Render3DView()
      ..lookAt(Vector3(10, -20, -30), Vector3(10, 0, 0));
    final view = FrameView()
      ..viewportSize = const Size(64, 64)
      ..isPlanar = false;
    view.view.setFrom(camera.view);
    view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 300);
    view.viewProjection.setProduct(view.projection, view.view);
    view.cameraPosition.setFrom(Vector3(10, -20, -30));
    final batches = (service.sceneRenderer..update(view)).scene.batches;
    expect([for (final b in batches) b.count]..sort(), [1, 1, 2]);
    expect(batches.where((b) => b.maxDistance == 50), hasLength(2));
  });
}

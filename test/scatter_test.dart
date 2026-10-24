// Scatter: pieces packed small and read back; kept their spacing apart;
// erased by area; solid only where a layer says so; drawn in batches by
// square and layer, not at all far off; and the Scatter brush — pieces set
// down on the ground under them, one undo step a stroke, Shift erasing.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

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
            position: Vector3(random.nextDouble() * 100, -random.nextDouble(), random.nextDouble() * 100),
            yaw: random.nextDouble() * 6,
            scale: 0.5 + random.nextDouble(),
            normal: Vector3(0.2, -0.9, 0.1)..normalize(),
          ),
      ];
      final back = ScatterInstancesFieldType.decodeInstances(ScatterInstancesFieldType.encodeInstances(pieces));
      expect(back, hasLength(500));
      for (var k = 0; k < 500; k++) {
        expect(back[k].layer, pieces[k].layer);
        expect(back[k].position.x, closeTo(pieces[k].position.x, 1e-4));
        expect(back[k].yaw, closeTo(pieces[k].yaw, 1e-5));
        expect(back[k].normal.y, closeTo(pieces[k].normal.y, 1e-5), reason: 'its lean made whole again');
      }
      expect(ScatterInstancesFieldType.decodeInstances(''), isEmpty);
    });

    test('kept their spacing apart; erased by area', () {
      final spacing = ScatterSpacing([_piece(0, 0), _piece(10, 0, layer: 1)], 0, 2);
      expect(spacing.fits(1, 1), isFalse);
      expect(spacing.fits(2.5, 0), isTrue);
      expect(spacing.fits(10, 0.5), isTrue, reason: 'another layer');
      expect(ScatterBrush.triesFor(5, 1), greaterThan(10));
      final random = math.Random(1);
      for (final (x, z) in ScatterBrush.spots(random, 5, 5, 3, 50)) {
        expect(math.sqrt((x - 5) * (x - 5) + (z - 5) * (z - 5)), lessThanOrEqualTo(3));
      }
      final left = ScatterBrush.erased([_piece(0, 0), _piece(1, 0), _piece(5, 0), _piece(0, 0, layer: 1)], 0, 0, 2, layer: 0);
      expect(left.map((p) => (p.position.x, p.layer)), [(5.0, 0), (0.0, 1)]);
    });

    test('solid only where their layer says, standing on their spot', () {
      final scatter = Scatter3D(
        layers: [
          ScatterLayer(name: 'Grass'),
          ScatterLayer(name: 'Trees', collision: ScatterCollision.capsule, colliderRadius: 0.2, colliderHeight: 2),
        ],
        instances: [_piece(0, 0), _piece(4, 4, layer: 1, scale: 2)],
      );
      final capsule = scatter.solidParts.single as SolidCapsule;
      expect([capsule.radius, capsule.halfHeight, capsule.x, capsule.y], [0.4, 1.6, 4, -2]);
      expect(identical(scatter.solidParts, scatter.solidParts), isTrue);
    });

    test('a box piece turned or leant is solid as it is drawn; a new layer is as solid as its cone', () {
      final scatter = Scatter3D(
        layers: [ScatterLayer(name: 'Rocks', collision: ScatterCollision.box, colliderRadius: 1, colliderHeight: 2)],
        instances: [ScatterInstance(layer: 0, position: Vector3(10, 0, 0), yaw: math.pi / 4)],
      );
      final hull = scatter.solidParts.single as SolidHull;
      var far = 0.0, top = 0.0;
      for (var i = 0; i < hull.points.length; i += 3) {
        far = math.max(far, (hull.points[i] - 10).abs());
        top = math.min(top, hull.points[i + 1]);
      }
      // An eighth of a turn: its corners reach out a metre's diagonal.
      expect(far, closeTo(math.sqrt2, 1e-5));
      expect(top, closeTo(-2, 1e-5), reason: 'standing on its spot, 2 m tall');
      final upright = Scatter3D(
        layers: [ScatterLayer(collision: ScatterCollision.box)],
        instances: [_piece(0, 0)],
      );
      expect(upright.solidParts.single, isA<SolidBox>(), reason: 'not turned: a plain box');
      final layer = ScatterLayer();
      final (_, height) = ScatterRenderProvider.shapeOf(layer);
      expect([layer.colliderHeight, layer.colliderRadius], [height, 0.4], reason: 'the cone it shows: 1.2 m, 0.4 m across its base');
    });

    test('two scatters read from a scene are each solid as itself', () {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      final definitions = world.context.definitions;
      Scatter3D read(Scatter3D s) => definitions.decode(definitions.encode(s)!)! as Scatter3D;
      List<ScatterLayer> trees() => [ScatterLayer(name: 'Trees', collision: ScatterCollision.capsule)];
      final a = read(Scatter3D(layers: trees(), instances: [_piece(0, 0)]));
      final b = read(Scatter3D(layers: trees(), instances: [_piece(20, 20), _piece(30, 30)]));
      expect(a.revision, b.revision, reason: 'what made their keys the same');
      expect(a.solidKey, isNot(b.solidKey));
      final shapes = ColliderShapes3D();
      final collider = Collider3D(shape: ColliderShape3D.matchShape);
      final one = Vector3(1, 1, 1);
      expect(identical(shapes.build(collider, one, source: a), shapes.build(collider, one, source: b)), isFalse);
    });

    test('a leaning piece leans with its ground', () {
      final lean = ScatterInstance(layer: 0, position: Vector3.zero(), normal: Vector3(1, -1, 0)..normalize());
      final m = lean.matrix(lean: true);
      final up = Vector3.zero();
      m.transformDirectionInto(Vector3(0, -1, 0), up);
      expect([up.x, up.y], [closeTo(math.sqrt(0.5), 1e-6), closeTo(-math.sqrt(0.5), 1e-6)]);
    });
  });

  test('saved and read back', () {
    final world = World()..initialize();
    Graphics3D.registerSchemas(world.context);
    WorldBuilderKit.install(world.context);
    final scatter = Scatter3D(layers: starterScatterLayers(), instances: [_piece(1, 2, layer: 2)]);
    final definitions = world.context.definitions;
    final back = definitions.decode(definitions.encode(scatter)!)! as Scatter3D;
    expect(back.layers.map((l) => l.name), ['Grass', 'Rocks', 'Trees']);
    expect(back.layers[2].collision, ScatterCollision.capsule);
    expect(back.instances.single.layer, 2);
    // What a layer is without a model: saved when not the cone, older files
    // read as cones.
    expect(ScatterLayer.fromJson(ScatterLayer(shape: ScatterShape.sphere).toJson()).shape, ScatterShape.sphere);
    expect(ScatterLayer().toJson().containsKey('shape'), isFalse);
    expect(ScatterLayer.fromJson({'name': 'Old'}).shape, ScatterShape.cone);
  });

  test('drawn in batches by layer and square, not far off', () async {
    final service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    final engine = Engine(config: EngineConfig(extensions: [WorldBuilderKit.extension], graphics3D: service));
    await engine.initialize();
    addTearDown(engine.dispose);
    engine.world.createEntityWithComponents([
      TransformComponent(),
      Scatter3D(
        layers: [ScatterLayer(name: 'Grass', maxDistance: 50), ScatterLayer(name: 'Rocks')],
        instances: [_piece(1, 1), _piece(2, 2), _piece(40, 1), _piece(3, 3, layer: 1)],
      ),
    ]);
    final camera = RenderView()..lookAt(Vector3(10, -20, -30), Vector3(10, 0, 0));
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

  group('the Scatter brush', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      scope = EditorScope(world: world, modules: [WorldBuilderModule()], builtIns: const [BuiltInEditorModule.new]);
      addTearDown(scope.dispose);
      scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
      scope.selectDesigner('world_builder');
      // A floor to scatter on: its top at y = 0.
      final floor = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0.5, 0)),
        Cube3D(width: 40, height: 1, depth: 40),
      ], name: 'Floor');
      scope.sceneState.registerEntity(floor);
      view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
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
    void press(Vector3 p) => session.onPointerDown(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void move(Vector3 p) => session.onPointerMove(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void release(Vector3 p) => session.onPointerUp(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    Scatter3D scatter() => scope.world.query([Scatter3D]).single.getComponent<Scatter3D>()!;

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
          expect((a.position - b.position).length, greaterThanOrEqualTo(s.layers[0].spacing - 1e-9));
        }
      }
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(scope.world.query([Scatter3D]), isEmpty);
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

    Entity scatterOf(List<ScatterLayer> layers, List<ScatterInstance> pieces, {String? name}) {
      final e = scope.world.createEntityWithComponents([TransformComponent(), Scatter3D(layers: layers, instances: pieces)], name: name);
      scope.sceneState
        ..registerEntity(e)
        ..selectEntity(e);
      return e;
    }

    test('a stroke that erases as many as it scatters is still a step', () {
      // So far apart that one piece fills the floor.
      final e = scatterOf([ScatterLayer(name: 'Big', spacing: 100)], [_piece(0, 0)], name: 'Big');
      final s = e.getComponent<Scatter3D>()!;
      final original = s.instances.single;
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(0, 0, 0));
      modifiers = const ModifierKeys();
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      expect(s.instances, hasLength(1));
      expect(identical(s.instances.single, original), isFalse, reason: 'another piece');
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(identical(s.instances.single, original), isTrue);
    });

    test('a scatter of no layers takes no pieces, and nothing throws', () {
      final e = scatterOf([], []);
      press(Vector3(0, 0, 0));
      move(Vector3(4, 0, 0));
      release(Vector3(4, 0, 0));
      expect(e.getComponent<Scatter3D>()!.instances, isEmpty);
    });

    test('a stroke into an unnamed scatter is undone like any other', () {
      final e = scatterOf(starterScatterLayers(), []);
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      final s = e.getComponent<Scatter3D>()!;
      expect(s.instances, isNotEmpty);
      scope.history.undo();
      expect(s.instances, isEmpty);
    });

    test('a layer taken out takes its pieces; those after it keep theirs', () {
      final e = scatterOf(starterScatterLayers(), [_piece(0, 0), _piece(5, 0, layer: 1), _piece(9, 0, layer: 2)]);
      final s = e.getComponent<Scatter3D>()!;
      removeScatterLayer(scope, s, 1);
      expect(s.layers.map((l) => l.name), ['Grass', 'Trees']);
      expect([for (final p in s.instances) (p.position.x, s.layers[p.layer].name)], [(0.0, 'Grass'), (9.0, 'Trees')]);
      scope.history.undo();
      expect(s.layers, hasLength(3));
      expect(s.instances.map((p) => p.layer), [0, 1, 2]);
    });
  });
}

// Terrain: its file written and read back; blocks kept for undo; brushes
// that raise, smooth, flatten, paint and cut holes; its surface meshed a
// chunk at a time, facing up, holes left out; solid as a height field; drawn
// again only where it changed; and the Terrain tool — a stroke one undo
// step, files written as the scene is saved, a shared file made unique.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_world_builder_kit/editor.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

/// A bumpy terrain of [n] samples a side.
TerrainData _bumpy(int n) {
  final data = TerrainData(n);
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      data.heights[data.index(i, j)] = math.sin(i * 0.7) + math.cos(j * 0.4);
    }
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the ground', () {
    test('a new one: flat, all of the first layer', () {
      final data = TerrainData(9);
      expect(data.heights.every((h) => h == 0), isTrue);
      expect([data.weights[0], data.weights[1], data.weights[2], data.weights[3]], [255, 0, 0, 0]);
      expect(data.hasHoles, isFalse);
    });

    test('its file, written and read back', () {
      final data = _bumpy(33)
        ..setHole(4, 5, true)
        ..weights[data0(33, 3, 3) * 4 + 2] = 99;
      final back = TerrainData.decode(data.encode());
      expect(back.resolution, 33);
      expect(back.heights, data.heights);
      expect(back.weights, data.weights);
      expect(back.isHole(4, 5), isTrue);
      expect(back.isHole(5, 4), isFalse);
      expect(() => TerrainData.decode(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])), throwsFormatException);
      final newer = data.encode()..[4] = 9;
      expect(() => TerrainData.decode(newer), throwsFormatException);
    });

    test('heights between samples', () {
      final data = TerrainData(3)
        ..heights[0] = 0
        ..heights[1] = 2;
      expect(data.heightAt(0.5, 0), closeTo(1, 1e-9));
      expect(data.heightAt(0.5, 0.5), closeTo(0.5, 1e-9));
      expect(data.heightAt(-4, 0), 0, reason: 'held at its edge');
    });

    test('a block kept and put back; changes counted by block', () {
      final data = _bumpy(40);
      final before = data.blockRevision(1, 1);
      final kept = data.capture(1, 1);
      data.heights[data.index(20, 20)] = 50;
      data.touch(20, 20, 20, 20);
      expect(data.blockRevision(1, 1), greaterThan(before));
      expect(data.blockRevision(0, 0), 0, reason: 'nothing near it changed');
      data.touch(16, 16, 16, 16);
      expect(data.blockRevision(0, 0), greaterThan(0), reason: 'a slope next to it did');
      data.restore(kept);
      expect(data.heights[data.index(20, 20)], closeTo(math.sin(14) + math.cos(8), 1e-6));
    });
  });

  group('brushes', () {
    double h(TerrainData d, int i, int j) => d.heights[d.index(i, j)];

    test('raise: most in the middle, nothing past its edge', () {
      final data = TerrainData(33);
      final rect = TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.raise, x: 16, z: 16, radius: 4, strength: 3, seconds: 1));
      expect(rect, (12, 12, 20, 20));
      expect(h(data, 16, 16), closeTo(3, 1e-6));
      expect(h(data, 18, 16), allOf(greaterThan(0), lessThan(3)));
      expect(h(data, 21, 16), 0);
      TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.lower, x: 16, z: 16, radius: 4, strength: 1, seconds: 1));
      expect(h(data, 16, 16), closeTo(2, 1e-6));
    });

    test('smooth evens it; flatten brings it to one height', () {
      final data = _bumpy(33);
      double spread(TerrainData d) {
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var j = 12; j <= 20; j++) {
          for (var i = 12; i <= 20; i++) {
            lo = math.min(lo, h(d, i, j));
            hi = math.max(hi, h(d, i, j));
          }
        }
        return hi - lo;
      }

      final rough = spread(data);
      for (var k = 0; k < 10; k++) {
        TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.smooth, x: 16, z: 16, radius: 8, strength: 2, seconds: 0.2));
      }
      expect(spread(data), lessThan(rough * 0.7));
      for (var k = 0; k < 20; k++) {
        TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.flatten, x: 16, z: 16, radius: 8, strength: 2, seconds: 0.5, target: 1.5));
      }
      expect(h(data, 16, 16), closeTo(1.5, 1e-3));
    });

    test('paint keeps the layers adding up; holes cut and filled', () {
      final data = TerrainData(17);
      for (var k = 0; k < 10; k++) {
        TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.paint, x: 8, z: 8, radius: 4, strength: 2, seconds: 0.2, layer: 2));
      }
      final k = data.index(8, 8) * 4;
      expect(data.weights[k + 2], greaterThan(200));
      for (var i = 0; i < 17 * 17; i++) {
        expect(data.weights[i * 4] + data.weights[i * 4 + 1] + data.weights[i * 4 + 2] + data.weights[i * 4 + 3], 255);
      }
      TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.hole, x: 8, z: 8, radius: 3));
      expect(data.isHole(8, 8), isTrue);
      expect(data.isHole(8, 12), isFalse);
      TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.hole, x: 8, z: 8, radius: 3, erase: true));
      expect(data.hasHoles, isFalse);
    });
  });

  group('its surface', () {
    test('a chunk: a vertex a sample, facing up, wound to face up', () {
      final data = TerrainData(9);
      expect(TerrainMesher.chunksPerSide(9, 4), 2);
      final mesh = TerrainMesher.chunk(data, cx: 0, cz: 0, chunkCells: 4, size: 8, colors: Terrain3D.defaultColors);
      expect(mesh.vertices.length, 25 * kVertexFloats);
      expect(mesh.triangleCount, 32);
      final v = mesh.vertices;
      Vector3 at(int i) => Vector3(v[i * kVertexFloats], v[i * kVertexFloats + 1], v[i * kVertexFloats + 2]);
      for (var t = 0; t < mesh.indices.length; t += 3) {
        final a = at(mesh.indices[t]), b = at(mesh.indices[t + 1]), c = at(mesh.indices[t + 2]);
        expect((b - a).cross(c - a).y, lessThan(0), reason: 'up is -Y');
      }
      expect([v[3], v[4], v[5]], [0, -1, 0]);
      expect([v[0], v[2]], [-4, -4], reason: 'about its middle');
      final (r, g, b) = GraphicsShapes.linear(Terrain3D.defaultColors.first);
      expect([v[12], v[13], v[14]], [closeTo(r, 1e-6), closeTo(g, 1e-6), closeTo(b, 1e-6)]);
    });

    test('a hole takes the cells round it out; layered keeps the weights', () {
      final data = TerrainData(9)..setHole(2, 2, true);
      final mesh = TerrainMesher.chunk(data, cx: 0, cz: 0, chunkCells: 4, size: 8);
      expect(mesh.triangleCount, 32 - 8);
      expect(mesh.vertices[12], 1, reason: 'layer 1 all of it');
    });

    test('solid as a height field, holes and all; built again once settled', () {
      final data = _bumpy(9)..setHole(1, 1, true);
      final terrain = Terrain3D(size: 16)..loaded = data;
      final field = terrain.solidParts.single as SolidHeightField;
      expect([field.sampleCount, field.cellSize, field.x, field.z], [9, 2, -8, -8]);
      // Rounded to a float: still a hole.
      expect(field.heights[data.index(1, 1)], greaterThanOrEqualTo(SolidHeightField.holeHeight));
      expect(field.heights[data.index(2, 1)], data.heights[data.index(2, 1)]);
      data.heights[0] = 7;
      expect(identical(terrain.solidParts.single, field), isTrue, reason: 'not while a stroke goes on');
      data.settle();
      expect((terrain.solidParts.single as SolidHeightField).heights[0], 7);
    });
  });

  group('the runtime', () {
    test('saved and read back; its file loaded through its reader', () async {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      final definitions = world.context.definitions;
      final t = Terrain3D(data: 'assets/terrain/a.jterrain', size: 100, material: 'assets/materials/ground.material.json')
        ..colors = [...Terrain3D.defaultColors]..colors[2] = const Color(0xFF123456);
      final back = definitions.decode(definitions.encode(t)!)! as Terrain3D;
      expect([back.data, back.size, back.material, back.colors[2]], [t.data, 100, t.material, const Color(0xFF123456)]);

      final files = TerrainFiles.of(world.context)..read = (path) async => _bumpy(17).encode();
      expect(files.get('assets/terrain/a.jterrain'), isNull, reason: 'loading');
      await files.load('assets/terrain/a.jterrain');
      expect(files.get('assets/terrain/a.jterrain')!.resolution, 17);
      files.read = (path) async => Uint8List(3);
      await files.load('assets/terrain/b.jterrain');
      expect(files.errorOf('assets/terrain/b.jterrain'), isA<FormatException>());
    });

    test('drawn a chunk at a time, again only where it changed', () async {
      final service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
      final engine = Engine(config: EngineConfig(extensions: [WorldBuilderKit.extension], graphics3D: service));
      await engine.initialize();
      addTearDown(engine.dispose);
      final data = TerrainData(65);
      TerrainFiles.of(engine.world.context).put('assets/terrain/t.jterrain', data);
      engine.world.createEntityWithComponents([TransformComponent(), Terrain3D(data: 'assets/terrain/t.jterrain', size: 64)]);
      final camera = RenderView()..lookAt(Vector3(0, -40, -60), Vector3.zero());
      final view = FrameView()
        ..viewportSize = const Size(64, 64)
        ..isPlanar = false;
      view.view.setFrom(camera.view);
      view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 300);
      view.viewProjection.setProduct(view.projection, view.view);
      view.cameraPosition.setFrom(Vector3(0, -40, -60));
      final renderer = service.sceneRenderer..update(view);
      final first = [for (final m in renderer.scene.instances) m.primitive];
      expect(first, hasLength(4));
      // A dab in the far corner: one chunk changes.
      TerrainBrush.apply(data, const TerrainDab(mode: TerrainBrushMode.raise, x: 60, z: 60, radius: 2, strength: 2, seconds: 1));
      renderer.update(view);
      final second = [for (final m in renderer.scene.instances) m.primitive];
      expect(second, hasLength(4));
      expect([for (var k = 0; k < 4; k++) identical(first[k], second[k])].where((same) => same), hasLength(3));
    });
  });

  group('the editor', () {
    late Directory root;
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    var modifiers = const ModifierKeys();

    setUp(() {
      root = Directory.systemTemp.createTempSync('terrain_');
      addTearDown(() => root.deleteSync(recursive: true));
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      WorldBuilderKit.install(world.context);
      scope = EditorScope(world: world, modules: [WorldBuilderModule(root: root.path)], builtIns: const [BuiltInEditorModule.new]);
      addTearDown(scope.dispose);
      scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
      scope.selectDesigner('world_builder');
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
      session.setTool(TerrainSculptTool.toolId);
    });

    TerrainSculptTool tool() => session.tools.byId(TerrainSculptTool.toolId)! as TerrainSculptTool;
    Offset at(Vector3 p) => view.projectToScreen(p)!;
    void press(Vector3 p) => session.onPointerDown(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void move(Vector3 p) => session.onPointerMove(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));
    void release(Vector3 p) => session.onPointerUp(Offset.zero, 32, screen: at(p), canvasSize: const Size(400, 400));

    Entity terrain() => makeTerrain(tool().designer, sceneName: 'level', size: 32, resolution: 33);

    test('a new terrain: its file beside the scene, one undo step', () {
      final e = terrain();
      final t = e.getComponent<Terrain3D>()!;
      expect(t.data, 'assets/terrain/level/${e.name}.jterrain');
      expect(TerrainFiles.of(scope.context).unsaved, {t.data});
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a stroke raises the ground; undone exactly, redone', () {
      final t = terrain().getComponent<Terrain3D>()!;
      final data = t.loaded ?? TerrainFiles.of(scope.context).get(t.data)!;
      final flat = Float32List.fromList(data.heights);
      final solid = data.solidRevision;
      press(Vector3(0, 0, 0));
      move(Vector3(3, 0, 0));
      release(Vector3(3, 0, 0));
      expect(data.heights.reduce(math.max), greaterThan(0.05));
      expect(data.solidRevision, greaterThan(solid), reason: 'solid again once the stroke is done');
      expect(scope.history.undoEntries, hasLength(2));
      final raised = Float32List.fromList(data.heights);
      scope.history.undo();
      expect(data.heights, flat);
      scope.history.redo();
      expect(data.heights, raised);
    });

    test('Shift lowers; [ and ] size the brush', () {
      final t = terrain().getComponent<Terrain3D>()!;
      final data = TerrainFiles.of(scope.context).get(t.data)!;
      modifiers = const ModifierKeys(shift: true);
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      expect(data.heights.reduce(math.min), lessThan(0));
      modifiers = const ModifierKeys();
      session.handleKey(LogicalKeyboardKey.bracketRight, gridSize: 32);
      expect(tool().radius.value, 8);
    });

    test('its file written as the scene is saved', () async {
      final t = terrain().getComponent<Terrain3D>()!;
      press(Vector3(0, 0, 0));
      release(Vector3(0, 0, 0));
      final failed = await scope.modules.notifySceneSaving('level');
      expect(failed, isEmpty);
      final file = File('${root.path}/${t.data}');
      expect(file.existsSync(), isTrue);
      expect(TerrainData.decode(file.readAsBytesSync()).heights, TerrainFiles.of(scope.context).get(t.data)!.heights);
      expect(TerrainFiles.of(scope.context).unsaved, isEmpty);
    });

    test('a shared file made unique: a copy of its own, one undo step', () {
      final first = terrain();
      final t = first.getComponent<Terrain3D>()!;
      final twin = scope.world.createEntityWithComponents([TransformComponent(), Terrain3D(data: t.data, size: 32)], name: 'Twin');
      scope.sceneState.registerEntity(twin);
      final files = TerrainFiles.of(scope.context);
      twin.getComponent<Terrain3D>()!.link(files);
      makeTerrainUnique(scope, twin, sceneName: 'level');
      final own = twin.getComponent<Terrain3D>()!.data;
      expect(own, isNot(t.data));
      expect(identical(files.get(own), files.get(t.data)), isFalse);
      scope.history.undo();
      expect(twin.getComponent<Terrain3D>()!.data, t.data);
    });
  });
}

int data0(int n, int i, int j) => j * n + i;

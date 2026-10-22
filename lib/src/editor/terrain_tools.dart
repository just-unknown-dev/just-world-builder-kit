import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_signals/just_signals.dart';

import '../terrain/terrain_brush.dart';
import '../terrain/terrain_component.dart';
import '../terrain/terrain_data.dart';
import 'panel_parts.dart';
import 'spline_tools.dart' show adoptEntities;
import 'world_builder_picks.dart';

/// The tool strip's group for terrain.
const String terrainGroup = 'worldBuilder.terrain';

/// A stroke of the Terrain tool: the blocks it changed of the ground in
/// the file at [path], as they were and as they became.
class TerrainStrokeCommand extends EditorCommand {
  TerrainStrokeCommand({
    required this.label,
    required this.files,
    required this.path,
    required this.sceneState,
    required this.before,
    required this.after,
  });

  @override
  final String label;

  final TerrainFiles files;
  final String path;
  final EditorSceneState sceneState;
  final List<TerrainBlock> before, after;

  void _apply(List<TerrainBlock> blocks) {
    final data = files.get(path);
    if (data == null) return;
    for (final b in blocks) {
      data.restore(b);
    }
    data.settle();
    files.changed(path);
    sceneState.markDirty();
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);
}

/// Where the Terrain tool's brush is: a circle on the ground.
final class TerrainBrushSpot {
  const TerrainBrushSpot(this.centre, this.radius, this.terrain, this.toWorld);

  /// Its middle, in the terrain's space.
  final Vector3 centre;

  /// Metres across, from the middle.
  final double radius;

  final Terrain3D terrain;
  final Matrix4 toWorld;
}

/// The Terrain tool: shapes the selected terrain (or the scene's first) —
/// raise, lower, smooth, flatten, roughen, paint a layer, cut holes — a
/// circle at a time, each stroke one undo step. Shift lowers what raises
/// and fills what cuts; [ and ] size the brush.
class TerrainSculptTool extends LevelToolHandler {
  TerrainSculptTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  final Signal<TerrainBrushMode> mode = Signal(TerrainBrushMode.raise, debugLabel: 'terrainMode');

  /// The brush's radius (metres).
  final Signal<double> radius = Signal(4, debugLabel: 'terrainRadius');

  /// How strong it is (see [TerrainDab.strength]).
  final Signal<double> strength = Signal(3, debugLabel: 'terrainStrength');

  /// The layer Paint paints (0–3).
  final Signal<int> layer = Signal(1, debugLabel: 'terrainLayer');

  /// Where the brush is now.
  final Signal<TerrainBrushSpot?> spot = Signal(null, debugLabel: 'terrainSpot');

  static const String toolId = 'worldBuilder.terrain';

  /// The radii offered (metres).
  static const List<double> radii = [1, 2, 4, 8, 16, 32];

  Entity? _entity;
  final Map<(int, int), TerrainBlock> _before = {};
  double _target = 0;
  Vector3? _last;

  @override
  String get id => toolId;

  @override
  String get label => 'Terrain';

  @override
  IconData get icon => Icons.terrain;

  @override
  String? get description => 'Shape and paint the terrain: drag to raise, lower, smooth, flatten, roughen, paint or cut holes; Shift the other way, [ ] size';

  @override
  int get order => 70;

  @override
  String get group => terrainGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  TerrainFiles get _files => TerrainFiles.of(designer.world.context);

  /// The terrain it shapes: the selected one, else the scene's first.
  Entity? get target {
    final selected = designer.sceneState.selectedEntity.value;
    if (selected != null && selected.hasComponent<Terrain3D>()) return selected;
    return designer.world.query([Terrain3D]).firstOrNull;
  }

  /// Where the pointer meets [entity]'s ground, in its space.
  Vector3? _groundUnder(SpaceContext space, Entity entity) {
    final t = entity.getComponent<Terrain3D>()!..link(_files);
    final toWorld = Matrix4.identity();
    entity.getComponent<TransformComponent>()?.localToWorldInto(toWorld);
    final toLocal = Matrix4.identity();
    if (toLocal.copyInverse(toWorld) == 0) return null;
    final origin = Vector3.zero(), direction = Vector3.zero();
    toLocal.transformPointInto(space.ray.origin, origin);
    toLocal.transformDirectionInto(space.ray.direction, direction);
    final hit = WorldBuilderRayTest.groundHit(t, origin, direction);
    if (hit == null) return null;
    return origin + direction * hit.t;
  }

  void _showAt(SpaceContext space) {
    final entity = _entity ?? target;
    final at = entity == null ? null : _groundUnder(space, entity);
    if (entity == null || at == null) {
      spot.value = null;
      return;
    }
    final toWorld = Matrix4.identity();
    entity.getComponent<TransformComponent>()?.localToWorldInto(toWorld);
    spot.value = TerrainBrushSpot(at, radius.value, entity.getComponent<Terrain3D>()!, toWorld);
  }

  /// One dab at [at] (the terrain's space).
  void _dab(Terrain3D t, TerrainData data, Vector3 at, bool shift) {
    final cell = t.cellSize;
    final x = (at.x - t.origin) / cell, z = (at.z - t.origin) / cell;
    final r = radius.value / cell;
    var m = mode.value;
    if (shift && m == TerrainBrushMode.raise) m = TerrainBrushMode.lower;
    final dab = TerrainDab(
      mode: m,
      x: x,
      z: z,
      radius: r,
      strength: strength.value,
      layer: layer.value,
      target: _target,
      erase: shift,
    );
    // Each block as it was before the stroke first touched it.
    for (final b in data.blocksIn((x - r).floor(), (z - r).floor(), (x + r).ceil(), (z + r).ceil())) {
      _before.putIfAbsent(b, () => data.capture(b.$1, b.$2));
    }
    TerrainBrush.apply(data, dab);
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final entity = target;
    if (entity == null) {
      context.controller.setStatus('Make a terrain in the Terrain panel first');
      return true;
    }
    final t = entity.getComponent<Terrain3D>()!..link(_files);
    final data = t.loaded;
    final at = _groundUnder(space, entity);
    if (data == null || at == null) return true;
    _entity = entity;
    _before.clear();
    final cell = t.cellSize;
    _target = data.heightAt((at.x - t.origin) / cell, (at.z - t.origin) / cell);
    _last = at;
    _dab(t, data, at, context.isShiftDown);
    _showAt(space);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, entity = _entity;
    if (space == null || entity == null) return;
    final t = entity.getComponent<Terrain3D>()!;
    final data = t.loaded;
    final at = _groundUnder(space, entity);
    if (data == null || at == null) return;
    // Dabs a quarter of the brush apart along the way.
    final last = _last ?? at;
    final gap = math.max(radius.value / 4, t.cellSize);
    final steps = math.max(1, ((at - last).length / gap).ceil());
    for (var k = 1; k <= steps; k++) {
      _dab(t, data, last + (at - last) * (k / steps), context.isShiftDown);
    }
    _last = at;
    _showAt(space);
  }

  @override
  void onPointerUp(ToolContext context) {
    final entity = _entity;
    _entity = null;
    _last = null;
    if (entity == null || _before.isEmpty) return;
    final t = entity.getComponent<Terrain3D>()!;
    final data = t.loaded;
    if (data == null) return;
    data.settle();
    _files.changed(t.data);
    final keys = _before.keys.toList();
    designer.history.pushApplied(
      TerrainStrokeCommand(
        label: '${mode.value.label} terrain',
        files: _files,
        path: t.data,
        sceneState: designer.sceneState,
        before: [for (final k in keys) _before[k]!],
        after: [for (final k in keys) data.capture(k.$1, k.$2)],
      ),
    );
    designer.sceneState.markDirty();
    _before.clear();
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    if (space != null) _showAt(space);
  }

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (key == LogicalKeyboardKey.bracketLeft || key == LogicalKeyboardKey.bracketRight) {
      // The next size up or down the list.
      final up = key == LogicalKeyboardKey.bracketRight;
      final r = radius.value;
      radius.value = up
          ? radii.firstWhere((v) => v > r + 1e-9, orElse: () => radii.last)
          : radii.lastWhere((v) => v < r - 1e-9, orElse: () => radii.first);
      context.controller.setStatus('Brush ${radius.value} m');
      onPointerHover(context);
      return true;
    }
    return false;
  }

  @override
  void onCancel() {
    final entity = _entity;
    final data = entity?.getComponent<Terrain3D>()?.loaded;
    if (data != null) {
      for (final b in _before.values) {
        data.restore(b);
      }
    }
    _before.clear();
    _entity = null;
    _last = null;
  }

  @override
  void onDeactivate() {
    if (_entity != null) onCancel();
    spot.value = null;
  }

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) {
    final muted = TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
    Widget pick<T>(Signal<T> signal, String Function(T) text, List<T> values, String tip) => SignalBuilder<T>(
      signal: signal,
      builder: (context, value, _) => PopupMenuButton<T>(
        tooltip: tip,
        initialValue: value,
        color: EditorTheme.menuBg,
        position: PopupMenuPosition.over,
        onSelected: (v) => signal.value = v,
        itemBuilder: (context) => [
          for (final v in values) editorMenuItem(v, text(v)),
        ],
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(text(value), style: muted)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pick<TerrainBrushMode>(mode, (m) => m.label, TerrainBrushMode.values, 'What it does'),
        const SizedBox(width: 6),
        pick<double>(radius, (r) => 'Brush ${r.toStringAsFixed(0)} m', radii, 'How big ([ ])'),
        const SizedBox(width: 6),
        pick<double>(strength, (s) => 'Strength ${s.toStringAsFixed(s < 1 ? 1 : 0)}', const [0.5, 1, 3, 6, 12], 'How strong'),
        SignalBuilder<TerrainBrushMode>(
          signal: mode,
          builder: (context, m, _) => m != TerrainBrushMode.paint
              ? const SizedBox.shrink()
              : pick<int>(layer, (l) => 'Layer ${l + 1}', const [0, 1, 2, 3], 'The layer it paints'),
        ),
      ],
    );
  }
}

/// The Terrain tool's brush: a circle laid on the ground.
class TerrainBrushOverlay extends DesignerOverlay {
  TerrainBrushOverlay(this.tool);

  final TerrainSculptTool? Function() tool;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'worldBuilder.terrainBrush';

  @override
  String get label => 'Terrain brush';

  @override
  IconData get icon => Icons.terrain;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(OverlayPaintContext context) {
    final t = tool();
    if (t == null || context.controller.toolId.value != TerrainSculptTool.toolId) return;
    final s = t.spot.value;
    final data = s?.terrain.loaded;
    if (s == null || data == null) return;
    final paint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final cell = s.terrain.cellSize, origin = s.terrain.origin;
    Offset? last;
    for (var k = 0; k <= 48; k++) {
      final a = 2 * math.pi * k / 48;
      final x = s.centre.x + math.cos(a) * s.radius, z = s.centre.z + math.sin(a) * s.radius;
      final local = Vector3(x, -data.heightAt((x - origin) / cell, (z - origin) / cell) - 0.05, z);
      final world = Vector3.zero();
      s.toWorld.transformPointInto(local, world);
      final at = context.draw.camera.projectToScreen(world);
      if (at != null && last != null) context.draw.canvas.drawLine(last, at, paint);
      last = at;
    }
  }
}

/// Makes a terrain [size] metres a side of [resolution] samples, at the
/// middle of the world, its file beside scene [sceneName]: one undo step.
Entity makeTerrain(DesignerToolContext designer, {required String sceneName, double size = 64, int resolution = 129}) {
  final name = designer.uniqueName('Terrain');
  final path = 'assets/terrain/$sceneName/$name${TerrainData.ending}';
  TerrainFiles.of(designer.world.context).put(path, TerrainData(resolution));
  final entity = designer.world.createEntityWithComponents(
    [
      TransformComponent(),
      Terrain3D(data: path, size: size, resolution: resolution),
      RigidBody3D(bodyType: BodyType3D.static),
      Collider3D(shape: ColliderShape3D.matchShape),
    ],
    name: name,
  );
  adoptEntities(designer, [entity], 'Make a terrain');
  return entity;
}

/// Gives [entity]'s terrain a file of its own — a copy of the ground it
/// shares — as one undo step.
void makeTerrainUnique(EditorScope scope, Entity entity, {required String sceneName}) {
  final t = entity.getComponent<Terrain3D>();
  final data = t?.loaded;
  if (t == null || data == null) return;
  final files = TerrainFiles.of(scope.context);
  final base = 'assets/terrain/$sceneName/${entity.name ?? 'terrain'}';
  var n = 2;
  String pathOf(int n) => '${base}_$n${TerrainData.ending}';
  while (files.get(pathOf(n)) != null || files.unsaved.contains(pathOf(n))) {
    n++;
  }
  final path = pathOf(n);
  files.put(path, data.copy());
  final edit = ComponentEdit.begin(scope, t);
  t.data = path;
  edit.commit('Make ${entity.name ?? 'terrain'} unique');
}

/// The designer's Terrain panel, open with the Terrain tool: the terrain
/// being shaped and the brush, then a new terrain's size and detail.
SidePanelSection terrainPanel(TerrainSculptTool? Function() tool) => SidePanelSection(
  id: 'worldBuilder.terrain',
  title: 'TERRAIN',
  order: 31,
  groups: const {terrainGroup},
  build: (context, session) => _TerrainPanel(session: session, tool: tool),
);

/// How finely a new terrain is sampled.
enum TerrainDetail {
  coarse('Coarse', 65),
  medium('Medium', 129),
  fine('Fine', 257);

  const TerrainDetail(this.label, this.resolution);

  final String label;

  /// Samples a side.
  final int resolution;
}

class _TerrainPanel extends StatefulWidget {
  const _TerrainPanel({required this.session, required this.tool});

  final DesignerSession session;
  final TerrainSculptTool? Function() tool;

  @override
  State<_TerrainPanel> createState() => _TerrainPanelState();
}

class _TerrainPanelState extends State<_TerrainPanel> {
  double _size = 64;
  TerrainDetail _detail = TerrainDetail.medium;

  static const List<(TerrainBrushMode, IconData)> _modes = [
    (TerrainBrushMode.raise, Icons.arrow_upward),
    (TerrainBrushMode.lower, Icons.arrow_downward),
    (TerrainBrushMode.smooth, Icons.blur_on),
    (TerrainBrushMode.flatten, Icons.horizontal_rule),
    (TerrainBrushMode.noise, Icons.grain),
    (TerrainBrushMode.paint, Icons.brush),
    (TerrainBrushMode.hole, Icons.circle_outlined),
  ];

  String _metres(double v) => v == v.roundToDouble() ? '${v.toInt()} m' : '${v.toStringAsFixed(2)} m';

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final tool = widget.tool();
    if (tool == null) return const SizedBox.shrink();
    // Live: the selection, every edit, and the brush.
    return SignalBuilder3<Entity?, int, TerrainBrushMode>(
      signal1: session.sceneState.selectedEntity,
      signal2: session.sceneState.revision,
      signal3: tool.mode,
      builder: (context, _, _, mode, _) {
        final entity = tool.target;
        final terrain = entity?.getComponent<Terrain3D>();
        final scene = session.sceneState.activeScene.value?.name ?? 'scene';
        final shared = terrain != null &&
            session.world.query([Terrain3D]).where((e) => e.getComponent<Terrain3D>()!.data == terrain.data).length > 1;
        final n = terrain?.loaded?.resolution ?? terrain?.resolution ?? 0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (terrain != null) ...[
                PanelTarget(
                  verb: 'Shaping',
                  name: entity!.name ?? 'terrain',
                  detail: '${_metres(terrain.size)} square · $n × $n samples, ${_metres(terrain.cellSize)} apart',
                ),
                if (shared) ...[
                  const SizedBox(height: 6),
                  EditorButton(
                    label: 'Make unique',
                    icon: Icons.call_split,
                    onPressed: () => makeTerrainUnique(session.scope, entity, sceneName: scene),
                  ),
                  const PanelHint('Another terrain uses the same file: shaping one shapes both until this one has its own.'),
                ],
                const PanelCaption('Brush'),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final (m, icon) in _modes)
                      EditorChip(label: m.label, icon: icon, selected: m == mode, onTap: () => tool.mode.value = m),
                  ],
                ),
                const SizedBox(height: 6),
                SignalBuilder<double>(
                  signal: tool.radius,
                  builder: (context, r, _) => PanelRow(
                    label: 'Size',
                    tooltip: '[ and ] change it too',
                    child: EditorSlider(
                      value: r,
                      min: 0.5,
                      max: 32,
                      step: 0.5,
                      decimals: 1,
                      unit: ' m',
                      onChanged: (v) => tool.radius.value = v,
                      onChangeEnd: (v) => tool.radius.value = v,
                    ),
                  ),
                ),
                SignalBuilder<double>(
                  signal: tool.strength,
                  builder: (context, s, _) => PanelRow(
                    label: 'Strength',
                    child: EditorSlider(
                      value: s,
                      min: 0.1,
                      max: 12,
                      step: 0.1,
                      decimals: 1,
                      onChanged: (v) => tool.strength.value = v,
                      onChangeEnd: (v) => tool.strength.value = v,
                    ),
                  ),
                ),
                if (mode == TerrainBrushMode.paint)
                  SignalBuilder<int>(
                    signal: tool.layer,
                    builder: (context, chosen, _) => PanelRow(
                      label: 'Layer',
                      child: Wrap(
                        spacing: 4,
                        children: [
                          for (var l = 0; l < 4; l++)
                            EditorChip(
                              label: '${l + 1}',
                              color: terrain.material.isEmpty ? terrain.colors[l] : null,
                              selected: chosen == l,
                              tooltip: terrain.material.isEmpty ? 'Layer ${l + 1}: its colour is in the inspector' : 'Layer ${l + 1} of its material',
                              onTap: () => tool.layer.value = l,
                            ),
                        ],
                      ),
                    ),
                  ),
                PanelHint(switch (mode) {
                  TerrainBrushMode.raise => 'Drag over the terrain to lift it; Shift lowers.',
                  TerrainBrushMode.lower => 'Drag over the terrain to sink it.',
                  TerrainBrushMode.smooth => 'Drag to even out bumps.',
                  TerrainBrushMode.flatten => 'Drag to bring the ground to the height where the drag began.',
                  TerrainBrushMode.noise => 'Drag to roughen the ground.',
                  TerrainBrushMode.paint => 'Drag to paint the chosen layer.',
                  TerrainBrushMode.hole => 'Drag to cut holes things fall through; Shift fills them back.',
                }),
              ] else
                const PanelHint('No terrain in this scene yet. Make one below, then drag over it to shape it.'),
              PanelCaption(terrain == null ? 'New terrain' : 'Another terrain'),
              PanelRow(
                label: 'Size',
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final s in const [32.0, 64.0, 128.0, 256.0])
                      EditorChip(label: _metres(s), selected: _size == s, onTap: () => setState(() => _size = s)),
                  ],
                ),
              ),
              PanelRow(
                label: 'Detail',
                tooltip: 'How many samples a side: finer shapes smaller bumps, and costs more',
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final d in TerrainDetail.values)
                      EditorChip(label: d.label, selected: _detail == d, onTap: () => setState(() => _detail = d)),
                  ],
                ),
              ),
              PanelHint('${_detail.resolution} × ${_detail.resolution} samples, ${_metres(_size / (_detail.resolution - 1))} apart.'),
              const SizedBox(height: 6),
              EditorButton(
                label: terrain == null ? 'New terrain' : 'Another terrain',
                icon: Icons.terrain,
                onPressed: () {
                  makeTerrain(tool.designer, sceneName: scene, size: _size, resolution: _detail.resolution);
                  session.setTool(TerrainSculptTool.toolId);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

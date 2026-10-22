import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_signals/just_signals.dart';

import '../scatter/scatter_brush.dart';
import '../scatter/scatter_components.dart';
import 'panel_parts.dart';
import 'spline_tools.dart' show adoptEntities;

/// The tool strip's group for scatter.
const String scatterGroup = 'worldBuilder.scatter';

/// A stroke of the Scatter brush: the pieces of the [Scatter3D] on the
/// entity named [entityName] as they were and as they became.
class ScatterStrokeCommand extends EditorCommand {
  ScatterStrokeCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required this.entityName,
    required this.before,
    required this.after,
  });

  @override
  final String label;

  final World world;
  final EditorSceneState sceneState;
  final String entityName;
  final List<ScatterInstance> before, after;

  void _apply(List<ScatterInstance> instances) {
    for (final e in world.entities) {
      if (e.name != entityName) continue;
      final s = e.getComponent<Scatter3D>();
      if (s == null) continue;
      s
        ..instances = List.of(instances)
        ..revision += 1;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);
}

/// The layers a new scatter starts with: grass, rocks (solid) and trees
/// (solid).
List<ScatterLayer> starterScatterLayers() => [
  ScatterLayer(name: 'Grass', color: const Color(0xFF7CB342), spacing: 1, minScale: 0.4, maxScale: 0.8, maxDistance: 150),
  ScatterLayer(
    name: 'Rocks',
    color: const Color(0xFF9E9E9E),
    spacing: 4,
    minScale: 0.6,
    maxScale: 1.4,
    alignToNormal: true,
    maxDistance: 300,
    collision: ScatterCollision.box,
    colliderRadius: 0.4,
    colliderHeight: 1.2,
  ),
  ScatterLayer(
    name: 'Trees',
    color: const Color(0xFF33691E),
    spacing: 6,
    minScale: 2,
    maxScale: 3.5,
    maxDistance: 0,
    collision: ScatterCollision.capsule,
    colliderRadius: 0.2,
    colliderHeight: 1.2,
  ),
];

/// Where the Scatter brush is: a disk on the surface under the pointer.
final class ScatterBrushSpot {
  const ScatterBrushSpot(this.centre, this.normal, this.radius, {this.erasing = false});

  final Vector3 centre, normal;
  final double radius;
  final bool erasing;
}

/// The Scatter brush: drag over any surface — ground, terrain, tiles — to
/// scatter the chosen layer's pieces, kept their spacing apart, each set
/// down on what is under it; Shift erases. Paints the selected scatter, or
/// the scene's first, or a new one; each stroke one undo step.
class ScatterTool extends LevelToolHandler {
  ScatterTool(this.designer, {math.Random? random}) : _random = random ?? math.Random();

  /// Where it makes entities.
  final DesignerToolContext designer;

  final math.Random _random;

  /// The layer scattered.
  final Signal<int> layer = Signal(0, debugLabel: 'scatterLayer');

  /// The brush's radius (metres).
  final Signal<double> radius = Signal(5, debugLabel: 'scatterRadius');

  /// Whether a drag erases rather than scatters (Shift does too).
  final Signal<bool> erase = Signal(false, debugLabel: 'scatterErase');

  /// Where the brush is now.
  final Signal<ScatterBrushSpot?> spot = Signal(null, debugLabel: 'scatterSpot');

  static const String toolId = 'worldBuilder.scatter';

  Entity? _entity;
  bool _made = false;
  List<ScatterInstance>? _before;
  ScatterSpacing? _spacing;
  Vector3? _last;

  @override
  String get id => toolId;

  @override
  String get label => 'Scatter';

  @override
  IconData get icon => Icons.grass;

  @override
  String? get description => 'Drag over the ground to scatter grass, rocks or trees, kept apart; Shift erases';

  @override
  int get order => 80;

  @override
  String get group => scatterGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  /// The scatter it paints: the selected one, else the scene's first.
  Entity? get target {
    final selected = designer.sceneState.selectedEntity.value;
    if (selected != null && selected.hasComponent<Scatter3D>()) return selected;
    return designer.world.query([Scatter3D]).firstOrNull;
  }

  /// What a piece can be set down on: anything with a size.
  Iterable<Entity> _grounds() {
    final definitions = designer.world.context.definitions;
    return designer.world.query([TransformComponent]).where(
      (e) => e.isActive && !e.hasComponent<Scatter3D>() && e.components.any((c) => definitions.definitionFor(c)?.extent != null),
    );
  }

  late final RayEntityPicker _picker = RayEntityPicker(tests: () => designer.scope.pickTests);

  /// What is straight under ([x], [z]), from [above] metres up.
  SurfacePoint? _groundAt(double x, double y, double z, List<Entity> grounds, {double above = 30}) {
    final ray = Ray3.originDirection(Vector3(x, y - above, z), Vector3(0, 1, 0));
    return _picker.placementAlong(ray, grounds);
  }

  (Matrix4, Matrix4) _spaceOf(Entity? entity) {
    final toWorld = Matrix4.identity();
    entity?.getComponent<TransformComponent>()?.localToWorldInto(toWorld);
    final toLocal = Matrix4.identity();
    if (toLocal.copyInverse(toWorld) == 0) toLocal.setIdentity();
    return (toWorld, toLocal);
  }

  Scatter3D _scatterFor() {
    final existing = _entity ?? target;
    if (existing != null) {
      _entity = existing;
      return existing.getComponent<Scatter3D>()!;
    }
    final scatter = Scatter3D(layers: starterScatterLayers());
    _entity = designer.world.createEntityWithComponents(
      [TransformComponent(), scatter, RigidBody3D(bodyType: BodyType3D.static), Collider3D(shape: ColliderShape3D.matchShape)],
      name: designer.uniqueName('Scatter'),
    );
    _made = true;
    return scatter;
  }

  /// One dab about [at] (the world).
  void _dab(Vector3 at, bool erasing) {
    final scatter = _scatterFor();
    final (toWorld, toLocal) = _spaceOf(_entity);
    final centre = Vector3.zero();
    toLocal.transformPointInto(at, centre);
    final r = radius.value;
    if (erasing) {
      final kept = ScatterBrush.erased(scatter.instances, centre.x, centre.z, r, layer: layer.value);
      if (kept.length != scatter.instances.length) {
        scatter
          ..instances = kept
          ..revision += 1;
        _spacing = null;
      }
      return;
    }
    final index = layer.value.clamp(0, scatter.layers.length - 1);
    if (scatter.layers.isEmpty) return;
    final l = scatter.layers[index];
    final spacing = _spacing ??= ScatterSpacing(scatter.instances, index, l.spacing);
    final grounds = _grounds().toList();
    var added = false;
    for (final (x, z) in ScatterBrush.spots(_random, at.x, at.z, r, ScatterBrush.triesFor(r, l.spacing))) {
      final ground = _groundAt(x, at.y, z, grounds);
      if (ground == null) continue;
      final local = Vector3.zero(), normal = Vector3.zero();
      toLocal.transformPointInto(ground.position, local);
      toLocal.transformDirectionInto(ground.normal, normal);
      if (!spacing.fits(local.x, local.z)) continue;
      // Not on walls: the ground must face up a little at least.
      if (normal.lengthSquared == 0 || (normal..normalize()).y > -0.3) continue;
      spacing.add(local.x, local.z);
      scatter.instances.add(
        ScatterInstance(
          layer: index,
          position: local,
          yaw: l.randomYaw ? _random.nextDouble() * 2 * math.pi : 0,
          scale: l.minScale + (l.maxScale - l.minScale) * _random.nextDouble(),
          normal: normal,
        ),
      );
      added = true;
    }
    if (added) scatter.revision++;
  }

  void _show(SpaceContext space, bool erasing) {
    final hit = space.surface(ignore: {?_entity});
    spot.value = ScatterBrushSpot(hit.position, hit.normal, radius.value, erasing: erasing);
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final erasing = erase.value || context.isShiftDown;
    _entity = null;
    _made = false;
    final existing = target;
    _before = List.of(existing?.getComponent<Scatter3D>()?.instances ?? const []);
    _spacing = null;
    final at = space.surface(ignore: {?existing}).position;
    _last = at;
    if (erasing && existing == null) return true;
    _dab(at, erasing);
    _show(space, erasing);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, last = _last;
    if (space == null || last == null) return;
    final erasing = erase.value || context.isShiftDown;
    final at = space.surface(ignore: {?_entity}).position;
    // A dab each third of the brush along the way.
    if ((at - last).length >= radius.value / 3) {
      _dab(at, erasing);
      _last = at;
    }
    _show(space, erasing);
  }

  @override
  void onPointerUp(ToolContext context) {
    final entity = _entity, before = _before;
    _last = null;
    _before = null;
    _spacing = null;
    if (entity == null || before == null) return;
    final scatter = entity.getComponent<Scatter3D>()!;
    final verb = erase.value || context.isShiftDown ? 'Erase' : 'Scatter';
    if (_made) {
      adoptEntities(designer, [entity], '$verb ${scatter.layers.isEmpty ? '' : scatter.layers[layer.value.clamp(0, scatter.layers.length - 1)].name.toLowerCase()}');
    } else if (scatter.instances.length != before.length) {
      designer.history.pushApplied(
        ScatterStrokeCommand(
          label: '$verb pieces',
          world: designer.world,
          sceneState: designer.sceneState,
          entityName: entity.name!,
          before: before,
          after: List.of(scatter.instances),
        ),
      );
      designer.sceneState
        ..markDirty()
        ..refresh();
    }
    final added = scatter.instances.length - before.length;
    context.controller.setStatus(
      added >= 0
          ? 'Scattered $added (${scatter.instances.length} in ${entity.name})'
          : 'Erased ${-added} (${scatter.instances.length} left in ${entity.name})',
    );
    _entity = null;
    _made = false;
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    if (space != null) _show(space, erase.value || context.isShiftDown);
  }

  @override
  void onCancel() {
    final entity = _entity, before = _before;
    if (entity != null) {
      if (_made) {
        designer.world.destroyEntity(entity);
      } else if (before != null) {
        entity.getComponent<Scatter3D>()!
          ..instances = before
          ..revision += 1;
      }
    }
    _entity = null;
    _made = false;
    _before = null;
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
    final layers = target?.getComponent<Scatter3D>()?.layers ?? starterScatterLayers();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SignalBuilder<bool>(
          signal: erase,
          builder: (context, value, _) => EditorSegmented<bool>(
            value: value,
            options: const [(false, 'Scatter'), (true, 'Erase')],
            onChanged: (v) => erase.value = v,
          ),
        ),
        const SizedBox(width: 6),
        SignalBuilder<int>(
          signal: layer,
          builder: (context, value, _) => PopupMenuButton<int>(
            tooltip: 'The layer',
            initialValue: value,
            color: EditorTheme.menuBg,
            position: PopupMenuPosition.over,
            onSelected: (v) => layer.value = v,
            itemBuilder: (context) => [
              for (final (i, l) in layers.indexed) editorMenuItem(i, l.name, icon: Icons.circle, iconColor: l.color),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(value < layers.length ? layers[value].name : 'Layer ${value + 1}', style: muted),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SignalBuilder<double>(
          signal: radius,
          builder: (context, value, _) => PopupMenuButton<double>(
            tooltip: 'How big',
            initialValue: value,
            color: EditorTheme.menuBg,
            position: PopupMenuPosition.over,
            onSelected: (v) => radius.value = v,
            itemBuilder: (context) => [
              for (final r in const [1.0, 2.0, 5.0, 10.0, 20.0])
                editorMenuItem(r, '${r.toInt()} m'),
            ],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('Brush ${value.toInt()} m', style: muted)),
          ),
        ),
      ],
    );
  }
}

/// The Scatter brush: a ring on the surface under the pointer.
class ScatterBrushOverlay extends DesignerOverlay {
  ScatterBrushOverlay(this.tool);

  final ScatterTool? Function() tool;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'worldBuilder.scatterBrush';

  @override
  String get label => 'Scatter brush';

  @override
  IconData get icon => Icons.grass;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(OverlayPaintContext context) {
    final t = tool();
    if (t == null || context.controller.toolId.value != ScatterTool.toolId) return;
    final s = t.spot.value;
    if (s == null) return;
    final paint = Paint()
      ..color = s.erasing ? const Color(0xFFEF5350) : const Color(0xFF9CCC65)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    // Two directions across the surface.
    final n = Vector3.copy(s.normal)..normalize();
    final helper = n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
    final u = n.cross(helper)..normalize();
    final v = n.cross(u)..normalize();
    Offset? last;
    for (var k = 0; k <= 48; k++) {
      final a = 2 * math.pi * k / 48;
      final p = s.centre + u * (math.cos(a) * s.radius) + v * (math.sin(a) * s.radius) - n * 0.03;
      final at = context.draw.camera.projectToScreen(p);
      if (at != null && last != null) context.draw.canvas.drawLine(last, at, paint);
      last = at;
    }
  }
}

/// The designer's Scatter panel, open with the Scatter brush: the scatter
/// being painted, the brush, and its layers — the one to paint, how many
/// pieces of each, and the chosen one's settings.
SidePanelSection scatterPanel(ScatterTool? Function() tool, String root) => SidePanelSection(
  id: 'worldBuilder.scatter',
  title: 'SCATTER',
  order: 32,
  groups: const {scatterGroup},
  build: (context, session) => _ScatterPanel(session: session, tool: tool, root: root),
);

/// What a scatter layer's collision is called in the panel.
String scatterCollisionLabel(ScatterCollision c) => switch (c) {
  ScatterCollision.none => 'Not solid',
  ScatterCollision.box => 'Box',
  ScatterCollision.capsule => 'Capsule',
};

/// How many pieces each of [scatter]'s layers has.
List<int> scatterCounts(Scatter3D scatter) {
  final counts = List<int>.filled(scatter.layers.length, 0);
  for (final p in scatter.instances) {
    if (p.layer >= 0 && p.layer < counts.length) counts[p.layer]++;
  }
  return counts;
}

class _ScatterPanel extends StatefulWidget {
  const _ScatterPanel({required this.session, required this.tool, required this.root});

  final DesignerSession session;
  final ScatterTool? Function() tool;
  final String root;

  @override
  State<_ScatterPanel> createState() => _ScatterPanelState();
}

class _ScatterPanelState extends State<_ScatterPanel> {
  late final List<String> _models = _findModels();

  /// The edit a slider's drag makes, recorded when it is let go.
  ComponentEdit? _drag;

  List<String> _findModels() {
    final assets = Directory('${widget.root}/assets');
    if (!assets.existsSync()) return const [];
    final root = widget.root.replaceAll(r'\', '/');
    return [
      for (final f in assets.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.glb') || f.path.endsWith('.gltf')) f.path.replaceAll(r'\', '/').substring(root.length + 1),
    ]..sort();
  }

  /// Changes [scatter]'s layers as one undo step called [label].
  void _edit(Scatter3D scatter, String label, void Function(List<ScatterLayer> layers) change) {
    final edit = ComponentEdit.begin(widget.session.scope, scatter);
    _apply(scatter, change);
    edit.commit(label);
  }

  void _apply(Scatter3D scatter, void Function(List<ScatterLayer> layers) change) {
    final layers = [for (final l in scatter.layers) l.copy()];
    change(layers);
    scatter
      ..layers = layers
      ..revision += 1;
  }

  /// A slider's change: shown at once, one undo step when let go.
  void _slide(Scatter3D scatter, String label, void Function(List<ScatterLayer> layers) change, {required bool end}) {
    _drag ??= ComponentEdit.begin(widget.session.scope, scatter);
    _apply(scatter, change);
    if (end) {
      _drag!.commit(label);
      _drag = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final tool = widget.tool();
    if (tool == null) return const SizedBox.shrink();
    return SignalBuilder3<Entity?, int, int>(
      signal1: session.sceneState.selectedEntity,
      signal2: session.sceneState.revision,
      signal3: tool.layer,
      builder: (context, _, _, chosen, _) {
        final entity = tool.target;
        final scatter = entity?.getComponent<Scatter3D>();
        final layers = scatter?.layers ?? starterScatterLayers();
        final counts = scatter == null ? List<int>.filled(layers.length, 0) : scatterCounts(scatter);
        final index = layers.isEmpty ? 0 : chosen.clamp(0, layers.length - 1);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scatter != null)
                PanelTarget(
                  verb: 'Painting',
                  name: entity!.name ?? 'scatter',
                  detail: '${scatter.instances.length} pieces in ${layers.length} layers',
                )
              else
                const PanelHint('No scatter in this scene yet: the first stroke makes one, with grass, rocks and trees.'),
              const PanelCaption('Brush'),
              SignalBuilder<bool>(
                signal: tool.erase,
                builder: (context, erasing, _) => EditorSegmented<bool>(
                  value: erasing,
                  expand: true,
                  options: const [(false, 'Scatter'), (true, 'Erase')],
                  tooltips: const {true: 'Shift erases too'},
                  onChanged: (v) => tool.erase.value = v,
                ),
              ),
              const SizedBox(height: 6),
              SignalBuilder<double>(
                signal: tool.radius,
                builder: (context, r, _) => PanelRow(
                  label: 'Size',
                  child: EditorSlider(
                    value: r,
                    min: 0.5,
                    max: 30,
                    step: 0.5,
                    decimals: 1,
                    unit: ' m',
                    onChanged: (v) => tool.radius.value = v,
                    onChangeEnd: (v) => tool.radius.value = v,
                  ),
                ),
              ),
              const PanelHint('Drag over the ground — terrain, tiles, shapes, models: each piece is set down on what is under it.'),
              const PanelCaption('Layers'),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final (i, l) in layers.indexed)
                    EditorChip(
                      label: l.name,
                      color: l.color,
                      count: counts[i],
                      selected: i == index,
                      tooltip: 'Paint ${l.name.toLowerCase()} (${counts[i]} pieces)',
                      onTap: () {
                        tool.layer.value = i;
                        session.setTool(ScatterTool.toolId);
                      },
                    ),
                ],
              ),
              if (scatter != null && layers.isNotEmpty) ..._layerSettings(scatter, index, layers[index]),
              if (scatter != null) ...[
                const SizedBox(height: 6),
                EditorButton(
                  label: 'Add a layer',
                  icon: Icons.add,
                  onPressed: () {
                    _edit(scatter, 'Add a scatter layer', (all) => all.add(ScatterLayer(name: 'Layer ${all.length + 1}')));
                    tool.layer.value = scatter.layers.length - 1;
                  },
                ),
                const PanelHint('Every setting, the colour and the reach among them, is in the inspector (Scatter 3D).'),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _layerSettings(Scatter3D scatter, int i, ScatterLayer l) {
    String label(String what) => 'Change ${l.name}: $what';
    return [
      PanelCaption('${l.name} settings'),
      PanelRow(
        label: 'Looks like',
        tooltip: 'What each piece is: one of the engine\'s shapes in the layer\'s colour, or a model',
        child: scatterLooksPicker(l, _models, (pick) => _edit(scatter, label('look'), (all) => pick.apply(all[i]))),
      ),
      PanelRow(
        label: 'Solid',
        tooltip: 'Whether the player bumps into its pieces',
        child: EditorSegmented<ScatterCollision>(
          value: l.collision,
          expand: true,
          options: [for (final c in ScatterCollision.values) (c, scatterCollisionLabel(c))],
          onChanged: (c) => _edit(scatter, label('collision'), (all) => all[i].collision = c),
        ),
      ),
      PanelRow(
        label: 'Spacing',
        tooltip: 'The least distance between two of its pieces',
        child: EditorSlider(
          value: l.spacing,
          min: 0.3,
          max: 20,
          step: 0.1,
          decimals: 1,
          unit: ' m',
          onChanged: (v) => _slide(scatter, label('spacing'), (all) => all[i].spacing = v, end: false),
          onChangeEnd: (v) => _slide(scatter, label('spacing'), (all) => all[i].spacing = v, end: true),
        ),
      ),
      PanelRow(
        label: 'Smallest',
        child: EditorSlider(
          value: l.minScale,
          min: 0.1,
          max: 5,
          step: 0.05,
          decimals: 2,
          unit: '×',
          onChanged: (v) => _slide(scatter, label('size'), (all) => all[i]
            ..minScale = v
            ..maxScale = v > all[i].maxScale ? v : all[i].maxScale, end: false),
          onChangeEnd: (v) => _slide(scatter, label('size'), (all) => all[i]
            ..minScale = v
            ..maxScale = v > all[i].maxScale ? v : all[i].maxScale, end: true),
        ),
      ),
      PanelRow(
        label: 'Largest',
        child: EditorSlider(
          value: l.maxScale,
          min: 0.1,
          max: 5,
          step: 0.05,
          decimals: 2,
          unit: '×',
          onChanged: (v) => _slide(scatter, label('size'), (all) => all[i]
            ..maxScale = v
            ..minScale = v < all[i].minScale ? v : all[i].minScale, end: false),
          onChangeEnd: (v) => _slide(scatter, label('size'), (all) => all[i]
            ..maxScale = v
            ..minScale = v < all[i].minScale ? v : all[i].minScale, end: true),
        ),
      ),
      PanelRow(
        label: 'Lean',
        tooltip: 'Whether its pieces lean with the slope under them, or stand upright',
        child: EditorSegmented<bool>(
          value: l.alignToNormal,
          expand: true,
          options: const [(false, 'Upright'), (true, 'With the ground')],
          onChanged: (v) => _edit(scatter, label('lean'), (all) => all[i].alignToNormal = v),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: EditorButton(
              label: 'Clear its pieces',
              icon: Icons.layers_clear,
              onPressed: scatterCounts(scatter)[i] == 0
                  ? null
                  : () {
                      final edit = ComponentEdit.begin(widget.session.scope, scatter);
                      scatter
                        ..instances = [for (final p in scatter.instances) if (p.layer != i) p]
                        ..revision += 1;
                      edit.commit('Clear ${l.name}');
                    },
            ),
          ),
          const SizedBox(width: 6),
          EditorIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove this layer and its pieces',
            onTap: () {
              final edit = ComponentEdit.begin(widget.session.scope, scatter);
              scatter
                ..layers = [for (final (k, x) in scatter.layers.indexed) if (k != i) x]
                ..instances = [
                  for (final p in scatter.instances)
                    if (p.layer != i)
                      ScatterInstance(
                        layer: p.layer > i ? p.layer - 1 : p.layer,
                        position: p.position,
                        yaw: p.yaw,
                        scale: p.scale,
                        normal: p.normal,
                      ),
                ]
                ..revision += 1;
              edit.commit('Remove ${l.name}');
              widget.tool()?.layer.value = 0;
            },
          ),
        ],
      ),
    ];
  }
}

/// What a scatter layer's pieces are: a shape, or a model file.
final class ScatterLook {
  const ScatterLook.shape(ScatterShape this.shape) : model = '';
  const ScatterLook.model(this.model) : shape = null;

  /// The model's path; empty for [shape].
  final String model;
  final ScatterShape? shape;

  /// [layer] made to look so.
  void apply(ScatterLayer layer) {
    layer.model = model;
    if (shape case final s?) layer.shape = s;
  }

  /// What [layer] looks like now.
  static ScatterLook of(ScatterLayer layer) =>
      layer.model.isEmpty ? ScatterLook.shape(layer.shape) : ScatterLook.model(layer.model);

  @override
  bool operator ==(Object other) => other is ScatterLook && other.model == model && other.shape == shape;

  @override
  int get hashCode => Object.hash(model, shape);
}

/// A searchable list of what [layer]'s pieces can be — the engine's
/// shapes in its colour, then [models] — calling [onPick].
Widget scatterLooksPicker(ScatterLayer layer, List<String> models, ValueChanged<ScatterLook> onPick) => EditorDropdown<ScatterLook>(
  value: ScatterLook.of(layer),
  searchable: true,
  tooltip: 'What each piece is',
  options: [
    for (final s in ScatterShape.values)
      EditorDropdownOption(value: ScatterLook.shape(s), label: s.label, color: layer.color, detail: 'shape'),
    for (final m in models)
      EditorDropdownOption(value: ScatterLook.model(m), label: m.split('/').last, detail: m.substring(0, m.lastIndexOf('/') + 1)),
  ],
  onChanged: onPick,
);

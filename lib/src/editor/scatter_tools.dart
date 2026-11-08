import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_signals/just_signals.dart';

import '../scatter/scatter.dart';
import 'panel_parts.dart';
import 'tool_parts.dart';
import 'world_builder_files.dart';

/// The tool strip's group for scatter.
const String scatterGroup = 'worldBuilder.scatter';

/// A stroke of the Scatter brush on the [Scatter3DComponent] of [entity] —
/// found again as the editor finds an entity rebuilt
/// (`EditorSceneState.liveEntity`), whatever it is named.
///
/// Made from its pieces as they were and as they became, it keeps only
/// what the stroke changed: the pieces it took out, where they were, and
/// the ones it put in, where they went. A history of strokes over a scatter
/// of many pieces holds the strokes, not that many pieces a step.
class ScatterStrokeCommand extends EditorCommand {
  ScatterStrokeCommand({
    required this.label,
    required this.sceneState,
    required this.entity,
    required List<ScatterInstance> before,
    required List<ScatterInstance> after,
  }) {
    final kept = Set<ScatterInstance>.identity()..addAll(after);
    final had = Set<ScatterInstance>.identity()..addAll(before);
    for (final (i, p) in before.indexed) {
      if (!kept.contains(p)) _removed.add((i, p));
    }
    for (final (i, p) in after.indexed) {
      if (!had.contains(p)) _added.add((i, p));
    }
  }

  @override
  final String label;

  final EditorSceneState sceneState;

  /// The entity painted, as it was when the stroke was made.
  final Entity entity;

  // Where each was in the pieces before the stroke, and after it.
  final List<(int, ScatterInstance)> _removed = [];
  final List<(int, ScatterInstance)> _added = [];

  /// How many pieces the stroke took out.
  int get removedCount => _removed.length;

  /// How many pieces the stroke put in.
  int get addedCount => _added.length;

  /// [from] with [take] taken out (by where they are in it) and [put] put
  /// in (where they go in the result).
  static List<ScatterInstance> _changed(
    List<ScatterInstance> from,
    List<(int, ScatterInstance)> take,
    List<(int, ScatterInstance)> put,
  ) {
    final out = List.of(from);
    for (final (i, _) in take.reversed) {
      out.removeAt(i);
    }
    for (final (i, p) in put) {
      out.insert(i, p);
    }
    return out;
  }

  void _apply({required bool forward}) {
    final scatter = sceneState
        .liveEntity(entity)
        ?.getComponent<Scatter3DComponent>();
    if (scatter != null) {
      scatter
        ..instances = forward
            ? _changed(scatter.instances, _removed, _added)
            : _changed(scatter.instances, _added, _removed)
        ..revision += 1;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void redo() => _apply(forward: true);

  @override
  void undo() => _apply(forward: false);
}

/// The layers a new scatter starts with: grass, rocks (solid) and trees
/// (solid).
List<ScatterLayer> starterScatterLayers() => [
  ScatterLayer(
    name: 'Grass',
    color: const Color(0xFF7CB342),
    spacing: 1,
    minScale: 0.4,
    maxScale: 0.8,
    maxDistance: 150,
  ),
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
  const ScatterBrushSpot(
    this.centre,
    this.normal,
    this.radius, {
    this.erasing = false,
  });

  final Vector3 centre, normal;
  final double radius;
  final bool erasing;
}

/// The Scatter brush: drag over any surface — ground, terrain, tiles — to
/// scatter the chosen layer's pieces, kept their spacing apart, each set
/// down on what is under it; Shift erases. Paints the selected scatter, or
/// the scene's first, or a new one; each stroke one undo step.
class ScatterTool extends LevelToolHandler {
  ScatterTool(this.designer, {math.Random? random})
    : _random = random ?? math.Random();

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
  final Signal<ScatterBrushSpot?> spot = Signal(
    null,
    debugLabel: 'scatterSpot',
  );

  static const String toolId = 'worldBuilder.scatter';

  Entity? _entity;
  bool _made = false;
  List<ScatterInstance>? _before;
  ScatterSpacing? _spacing;
  Vector3? _last;

  // What the stroke's pieces can be set down on, with their boxes in the
  // world: found once a stroke, then only those under a dab are tried.
  List<(Entity, Aabb3)>? _groundBoxes;

  @override
  String get id => toolId;

  @override
  String get label => 'Scatter';

  @override
  IconData get icon => Icons.grass;

  @override
  String? get description =>
      'Drag over the ground to scatter grass, rocks or trees, kept apart; Shift erases';

  @override
  int get order => 80;

  @override
  String get group => scatterGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  /// The scatter it paints: the selected one, else the scene's first.
  Entity? get target {
    final selected = designer.sceneState.selectedEntity.value;
    if (selected != null && selected.hasComponent<Scatter3DComponent>()) {
      return selected;
    }
    return designer.world.query([Scatter3DComponent]).firstOrNull;
  }

  /// What a piece can be set down on — anything with a size — and its box
  /// in the world, once a stroke.
  List<(Entity, Aabb3)> _grounds() => _groundBoxes ??= () {
    final definitions = designer.world.context.definitions;
    return [
      for (final e in designer.world.query([TransformComponent]))
        if (e.isActive &&
            !e.hasComponent<Scatter3DComponent>() &&
            e.components.any(
              (c) => definitions.definitionFor(c)?.extent != null,
            ))
          if (_boxOf(e) case final box?) (e, box),
    ];
  }();

  static Aabb3? _boxOf(Entity e) {
    final box = Aabb3();
    return RayEntityPicker.boundsOf(e, box) ? box : null;
  }

  /// The grounds whose boxes reach under a brush of radius [r] at ([x],
  /// [z]).
  List<Entity> _groundsUnder(double x, double z, double r) => [
    for (final (e, box) in _grounds())
      if (box.max.x >= x - r &&
          box.min.x <= x + r &&
          box.max.z >= z - r &&
          box.min.z <= z + r)
        e,
  ];

  late final RayEntityPicker _picker = RayEntityPicker(
    tests: () => designer.scope.pickTests,
  );

  /// What is straight under ([x], [z]), from [above] metres up.
  SurfacePoint? _groundAt(
    double x,
    double y,
    double z,
    List<Entity> grounds, {
    double above = 30,
  }) {
    final ray = Ray3D.originDirection(
      Vector3(x, y - above, z),
      Vector3(0, 1, 0),
    );
    return _picker.placementAlong(ray, grounds);
  }

  Scatter3DComponent _scatterFor() {
    final existing = _entity ?? target;
    if (existing != null) {
      _entity = existing;
      return existing.getComponent<Scatter3DComponent>()!;
    }
    final scatter = Scatter3DComponent(layers: starterScatterLayers());
    _entity = designer.world.createEntityWithComponents([
      TransformComponent(),
      scatter,
      RigidBody3DComponent(bodyType: Body3DType.static),
      Collider3DComponent(shape: Collider3DShape.matchShape),
    ], name: designer.uniqueName('Scatter'));
    _made = true;
    return scatter;
  }

  /// One dab about [at] (the world). A scatter is made only once a piece
  /// lands: a stroke where nothing does leaves the scene as it was.
  void _dab(Vector3 at, bool erasing) {
    final existing = _entity ?? target;
    final r = radius.value;
    if (erasing) {
      if (existing == null) return;
      final scatter = _scatterFor();
      final (_, toLocal) = spaceOf(_entity);
      final centre = Vector3.zero();
      toLocal.transformPointInto(at, centre);
      final kept = ScatterBrush.erased(
        scatter.instances,
        centre.x,
        centre.z,
        r,
        layer: layer.value,
      );
      if (kept.length != scatter.instances.length) {
        scatter
          ..instances = kept
          ..revision += 1;
        _spacing = null;
      }
      return;
    }
    // Into the scatter there is, or the one a first piece makes.
    final into = existing?.getComponent<Scatter3DComponent>();
    final layers = into?.layers ?? starterScatterLayers();
    if (layers.isEmpty) return;
    final index = layer.value.clamp(0, layers.length - 1);
    final l = layers[index];
    final (_, toLocal) = spaceOf(existing);
    final spacing = _spacing ??= ScatterSpacing(
      into?.instances ?? const [],
      index,
      l.spacing,
    );
    final grounds = _groundsUnder(at.x, at.z, r);
    final placed = <ScatterInstance>[];
    for (final (x, z) in ScatterBrush.spots(
      _random,
      at.x,
      at.z,
      r,
      ScatterBrush.triesFor(r, l.spacing),
    )) {
      final ground = _groundAt(x, at.y, z, grounds);
      if (ground == null) continue;
      final local = Vector3.zero(), normal = Vector3.zero();
      toLocal.transformPointInto(ground.position, local);
      toLocal.transformDirectionInto(ground.normal, normal);
      if (!spacing.fits(local.x, local.z)) continue;
      // Not on walls: the ground must face up a little at least.
      if (normal.lengthSquared == 0 || (normal..normalize()).y > -0.3) continue;
      spacing.add(local.x, local.z);
      placed.add(
        ScatterInstance(
          layer: index,
          position: local,
          yaw: l.randomYaw ? _random.nextDouble() * 2 * math.pi : 0,
          scale: l.minScale + (l.maxScale - l.minScale) * _random.nextDouble(),
          normal: normal,
        ),
      );
    }
    if (placed.isEmpty) return;
    final scatter = _scatterFor();
    scatter
      ..instances.addAll(placed)
      ..revision += 1;
  }

  /// The brush at [hit], the surface under the pointer.
  void _show(SurfacePoint hit, bool erasing) {
    spot.value = ScatterBrushSpot(
      hit.position,
      hit.normal,
      radius.value,
      erasing: erasing,
    );
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final erasing = erase.value || context.isShiftDown;
    _entity = null;
    _made = false;
    final existing = target;
    _before = List.of(
      existing?.getComponent<Scatter3DComponent>()?.instances ?? const [],
    );
    _spacing = null;
    _groundBoxes = null;
    final hit = space.surface(ignore: {?existing});
    _last = hit.position;
    if (erasing && existing == null) return true;
    _dab(hit.position, erasing);
    _show(hit, erasing);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, last = _last;
    if (space == null || last == null) return;
    final erasing = erase.value || context.isShiftDown;
    final hit = space.surface(ignore: {?_entity});
    final at = hit.position;
    // A dab each third of the brush along the way.
    if ((at - last).length >= radius.value / 3) {
      _dab(at, erasing);
      _last = at;
    }
    _show(hit, erasing);
  }

  @override
  void onPointerUp(ToolContext context) {
    final entity = _entity, before = _before;
    _last = null;
    _before = null;
    _spacing = null;
    _groundBoxes = null;
    if (entity == null || before == null) return;
    final scatter = entity.getComponent<Scatter3DComponent>()!;
    final verb = erase.value || context.isShiftDown ? 'Erase' : 'Scatter';
    if (_made) {
      adoptEntities(
        designer,
        [entity],
        '$verb ${scatter.layers.isEmpty ? '' : scatter.layers[layer.value.clamp(0, scatter.layers.length - 1)].name.toLowerCase()}',
      );
    } else if (!_same(scatter.instances, before)) {
      designer.history.pushApplied(
        ScatterStrokeCommand(
          label: '$verb pieces',
          sceneState: designer.sceneState,
          entity: entity,
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

  /// Whether [a] holds the very pieces [b] does, in order: a stroke that
  /// scattered some and erased as many (Shift pressed on the way) still
  /// changed them.
  static bool _same(List<ScatterInstance> a, List<ScatterInstance> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    if (space != null) {
      _show(
        space.surface(ignore: {?_entity}),
        erase.value || context.isShiftDown,
      );
    }
  }

  /// The pointer left the viewport: the brush goes with it, unless a
  /// stroke is under way.
  @override
  void onPointerExit() {
    if (_last == null) spot.value = null;
  }

  @override
  void onCancel() {
    final entity = _entity, before = _before;
    if (entity != null) {
      if (_made) {
        designer.world.destroyEntity(entity);
      } else if (before != null) {
        entity.getComponent<Scatter3DComponent>()!
          ..instances = before
          ..revision += 1;
      }
    }
    _entity = null;
    _made = false;
    _before = null;
    _last = null;
    _groundBoxes = null;
  }

  @override
  void onDeactivate() {
    if (_entity != null) onCancel();
    spot.value = null;
  }

  /// The layers of the scatter it paints, or a new one's: read as the
  /// options bar is drawn, and as its menu opens, never kept.
  List<ScatterLayer> get _layers =>
      target?.getComponent<Scatter3DComponent>()?.layers ??
      starterScatterLayers();

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) {
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
          builder: (context, value, _) =>
              _LayerPicker(tool: this, value: value),
        ),
        const SizedBox(width: 6),
        SignalBuilder<double>(
          signal: radius,
          builder: (context, value, _) => ToolOptionPicker<double>(
            value: value,
            values: const [1.0, 2.0, 5.0, 10.0, 20.0],
            label: (r) =>
                'Brush ${r.toStringAsFixed(r == r.roundToDouble() ? 0 : 1)} m',
            tooltip: 'How big',
            onSelected: (v) => radius.value = v,
          ),
        ),
      ],
    );
  }
}

/// The options bar's layer: the scatter's layers read as it is drawn and as
/// its menu opens, so a layer added, taken out or another scatter selected
/// shows at once.
class _LayerPicker extends StatelessWidget {
  const _LayerPicker({required this.tool, required this.value});

  final ScatterTool tool;
  final int value;

  @override
  Widget build(BuildContext context) {
    final layers = tool._layers;
    return PopupMenuButton<int>(
      tooltip: 'The layer',
      initialValue: value,
      color: EditorTheme.menuBg,
      position: PopupMenuPosition.over,
      onSelected: (v) => tool.layer.value = v,
      itemBuilder: (context) => [
        for (final (i, l) in tool._layers.indexed)
          editorMenuItem(i, l.name, icon: Icons.circle, iconColor: l.color),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          value < layers.length ? layers[value].name : 'Layer ${value + 1}',
          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
        ),
      ),
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
    if (t == null || context.controller.toolId.value != ScatterTool.toolId) {
      return;
    }
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
    paintRing(
      context.draw.canvas,
      paint,
      (a) =>
          s.centre +
          u * (math.cos(a) * s.radius) +
          v * (math.sin(a) * s.radius) -
          n * 0.03,
      context.draw.camera.projectToScreen,
    );
  }
}

/// The designer's Scatter panel, open with the Scatter brush: the scatter
/// being painted, the brush, and its layers — the one to paint, how many
/// pieces of each, and the chosen one's settings.
SidePanelSection scatterPanel(
  ScatterTool? Function() tool,
  WorldBuilderFiles files,
) => SidePanelSection(
  id: 'worldBuilder.scatter',
  title: 'SCATTER',
  order: 32,
  groups: const {scatterGroup},
  build: (context, session) =>
      _ScatterPanel(session: session, tool: tool, files: files),
);

/// What a scatter layer's collision is called in the panel.
String scatterCollisionLabel(ScatterCollision c) => switch (c) {
  ScatterCollision.none => 'Not solid',
  ScatterCollision.box => 'Box',
  ScatterCollision.capsule => 'Capsule',
};

/// Takes layer [index] out of [scatter], and its pieces with it — the
/// pieces of the layers after it now count one less — as one undo step.
void removeScatterLayer(
  EditorScope scope,
  Scatter3DComponent scatter,
  int index,
) {
  if (index < 0 || index >= scatter.layers.length) return;
  final name = scatter.layers[index].name;
  final edit = ComponentEdit.begin(scope, scatter);
  scatter
    ..layers = [
      for (final (k, x) in scatter.layers.indexed)
        if (k != index) x,
    ]
    ..instances = [
      for (final p in scatter.instances)
        if (p.layer != index)
          p.layer < index
              ? p
              : ScatterInstance(
                  layer: p.layer - 1,
                  position: p.position,
                  yaw: p.yaw,
                  scale: p.scale,
                  normal: p.normal,
                ),
    ]
    ..revision += 1;
  edit.commit('Remove $name');
}

/// How many pieces each of [scatter]'s layers has.
List<int> scatterCounts(Scatter3DComponent scatter) {
  final counts = List<int>.filled(scatter.layers.length, 0);
  for (final p in scatter.instances) {
    if (p.layer >= 0 && p.layer < counts.length) counts[p.layer]++;
  }
  return counts;
}

class _ScatterPanel extends StatefulWidget {
  const _ScatterPanel({
    required this.session,
    required this.tool,
    required this.files,
  });

  final DesignerSession session;
  final ScatterTool? Function() tool;
  final WorldBuilderFiles files;

  @override
  State<_ScatterPanel> createState() => _ScatterPanelState();
}

class _ScatterPanelState extends State<_ScatterPanel> {
  List<String> _models = const [];

  /// The edit a slider's drag makes, recorded when it is let go — or when
  /// the panel goes first — under [_dragLabel].
  ComponentEdit? _drag;
  String _dragLabel = '';

  @override
  void initState() {
    super.initState();
    // The project's models, read off the UI thread.
    widget.files.models().then((models) {
      if (mounted) setState(() => _models = models);
    });
  }

  @override
  void dispose() {
    // A drag the panel was closed in the middle of is still one step.
    _drag?.commit(_dragLabel);
    _drag = null;
    super.dispose();
  }

  /// Changes [scatter]'s layers as one undo step called [label].
  void _edit(
    Scatter3DComponent scatter,
    String label,
    void Function(List<ScatterLayer> layers) change,
  ) {
    final edit = ComponentEdit.begin(widget.session.scope, scatter);
    _apply(scatter, change);
    edit.commit(label);
  }

  void _apply(
    Scatter3DComponent scatter,
    void Function(List<ScatterLayer> layers) change,
  ) {
    final layers = [for (final l in scatter.layers) l.copy()];
    change(layers);
    scatter
      ..layers = layers
      ..revision += 1;
  }

  /// A slider's change: shown at once, one undo step when let go.
  void _slide(
    Scatter3DComponent scatter,
    String label,
    void Function(List<ScatterLayer> layers) change, {
    required bool end,
  }) {
    _drag ??= ComponentEdit.begin(widget.session.scope, scatter);
    _dragLabel = label;
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
        final scatter = entity?.getComponent<Scatter3DComponent>();
        final layers = scatter?.layers ?? starterScatterLayers();
        final counts = scatter == null
            ? List<int>.filled(layers.length, 0)
            : scatterCounts(scatter);
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
                  detail:
                      '${scatter.instances.length} pieces in ${layers.length} layers',
                )
              else
                const PanelHint(
                  'No scatter in this scene yet: the first stroke makes one, with grass, rocks and trees.',
                ),
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
              const PanelHint(
                'Drag over the ground — terrain, tiles, shapes, models: each piece is set down on what is under it.',
              ),
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
                      tooltip:
                          'Paint ${l.name.toLowerCase()} (${counts[i]} pieces)',
                      onTap: () {
                        tool.layer.value = i;
                        session.setTool(ScatterTool.toolId);
                      },
                    ),
                ],
              ),
              if (scatter != null && layers.isNotEmpty)
                ..._layerSettings(scatter, index, layers[index]),
              if (scatter != null) ...[
                const SizedBox(height: 6),
                EditorButton(
                  label: 'Add a layer',
                  icon: Icons.add,
                  onPressed: () {
                    _edit(
                      scatter,
                      'Add a scatter layer',
                      (all) => all.add(
                        ScatterLayer(name: 'Layer ${all.length + 1}'),
                      ),
                    );
                    tool.layer.value = scatter.layers.length - 1;
                  },
                ),
                const PanelHint(
                  'Every setting, the colour and the reach among them, is in the inspector (Scatter 3D).',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _layerSettings(
    Scatter3DComponent scatter,
    int i,
    ScatterLayer l,
  ) {
    String label(String what) => 'Change ${l.name}: $what';
    return [
      PanelCaption('${l.name} settings'),
      PanelRow(
        label: 'Looks like',
        tooltip:
            'What each piece is: one of the engine\'s shapes in the layer\'s colour, or a model',
        child: scatterLooksPicker(
          l,
          _models,
          (pick) => _edit(scatter, label('look'), (all) => pick.apply(all[i])),
        ),
      ),
      PanelRow(
        label: 'Solid',
        tooltip: 'Whether the player bumps into its pieces',
        child: EditorSegmented<ScatterCollision>(
          value: l.collision,
          expand: true,
          options: [
            for (final c in ScatterCollision.values)
              (c, scatterCollisionLabel(c)),
          ],
          onChanged: (c) =>
              _edit(scatter, label('collision'), (all) => all[i].collision = c),
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
          onChanged: (v) => _slide(
            scatter,
            label('spacing'),
            (all) => all[i].spacing = v,
            end: false,
          ),
          onChangeEnd: (v) => _slide(
            scatter,
            label('spacing'),
            (all) => all[i].spacing = v,
            end: true,
          ),
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
          onChanged: (v) => _slide(
            scatter,
            label('size'),
            (all) => all[i]
              ..minScale = v
              ..maxScale = v > all[i].maxScale ? v : all[i].maxScale,
            end: false,
          ),
          onChangeEnd: (v) => _slide(
            scatter,
            label('size'),
            (all) => all[i]
              ..minScale = v
              ..maxScale = v > all[i].maxScale ? v : all[i].maxScale,
            end: true,
          ),
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
          onChanged: (v) => _slide(
            scatter,
            label('size'),
            (all) => all[i]
              ..maxScale = v
              ..minScale = v < all[i].minScale ? v : all[i].minScale,
            end: false,
          ),
          onChangeEnd: (v) => _slide(
            scatter,
            label('size'),
            (all) => all[i]
              ..maxScale = v
              ..minScale = v < all[i].minScale ? v : all[i].minScale,
            end: true,
          ),
        ),
      ),
      PanelRow(
        label: 'Lean',
        tooltip:
            'Whether its pieces lean with the slope under them, or stand upright',
        child: EditorSegmented<bool>(
          value: l.alignToNormal,
          expand: true,
          options: const [(false, 'Upright'), (true, 'With the ground')],
          onChanged: (v) =>
              _edit(scatter, label('lean'), (all) => all[i].alignToNormal = v),
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
                      final edit = ComponentEdit.begin(
                        widget.session.scope,
                        scatter,
                      );
                      scatter
                        ..instances = [
                          for (final p in scatter.instances)
                            if (p.layer != i) p,
                        ]
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
              removeScatterLayer(widget.session.scope, scatter, i);
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
  static ScatterLook of(ScatterLayer layer) => layer.model.isEmpty
      ? ScatterLook.shape(layer.shape)
      : ScatterLook.model(layer.model);

  @override
  bool operator ==(Object other) =>
      other is ScatterLook && other.model == model && other.shape == shape;

  @override
  int get hashCode => Object.hash(model, shape);
}

/// A searchable list of what [layer]'s pieces can be — the engine's
/// shapes in its colour, then [models] — calling [onPick].
Widget scatterLooksPicker(
  ScatterLayer layer,
  List<String> models,
  ValueChanged<ScatterLook> onPick,
) => EditorDropdown<ScatterLook>(
  value: ScatterLook.of(layer),
  searchable: true,
  tooltip: 'What each piece is',
  options: [
    for (final s in ScatterShape.values)
      EditorDropdownOption(
        value: ScatterLook.shape(s),
        label: s.label,
        color: layer.color,
        detail: 'shape',
      ),
    for (final m in models)
      EditorDropdownOption(
        value: ScatterLook.model(m),
        label: m.split('/').last,
        detail: m.substring(0, m.lastIndexOf('/') + 1),
      ),
  ],
  onChanged: onPick,
);

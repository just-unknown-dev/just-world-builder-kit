import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../splines/spline_components.dart';
import '../splines/spline_path.dart';
import '../splines/spline_render.dart';
import 'spline_tools.dart' show rotationOfBasis;

/// The inspector's row for a [Spline3D]'s points: how many and how long,
/// with Reverse and Flatten. The points themselves are dragged in the
/// viewport.
Widget splinePointsEditor(FieldEditorContext context) {
  final points = [for (final p in (context.value as List?) ?? const []) if (p is SplinePoint) p];
  final component = context.component;
  final closed = component is Spline3D && component.closed;
  final length = SplinePath.of(
    Spline3D(
      points: points,
      closed: closed,
      interpolation: component is Spline3D ? component.interpolation : SplineInterpolation.catmullRom,
    ),
  ).length;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReadonlyRow(
        label: context.hint.label ?? 'Points',
        value: '${points.length} points · ${length.toStringAsFixed(1)} m',
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          EditorButton(
            label: 'Reverse',
            kind: EditorButtonKind.ghost,
            onPressed: context.readOnly || points.length < 2 ? null : () => context.onChanged(SplineEdits.reversed(points)),
          ),
          const SizedBox(width: 4),
          EditorButton(
            label: 'Flatten',
            kind: EditorButtonKind.ghost,
            onPressed: context.readOnly || points.length < 2 ? null : () => context.onChanged(SplineEdits.flattened(points)),
          ),
        ],
      ),
    ],
  );
}

/// Edits to a spline's points and what is laid along it.
abstract final class SplineEdits {
  /// [points] the other way round: their handles swapped.
  static List<SplinePoint> reversed(List<SplinePoint> points) => [
    for (final p in points.reversed)
      SplinePoint(
        position: Vector3.copy(p.position),
        inTangent: Vector3.copy(p.outTangent),
        outTangent: Vector3.copy(p.inTangent),
        roll: -p.roll,
        mode: p.mode,
      ),
  ];

  /// [points] all at the first one's height, their handles level.
  static List<SplinePoint> flattened(List<SplinePoint> points) {
    if (points.isEmpty) return const [];
    final y = points.first.position.y;
    return [
      for (final p in points)
        p.copy()
          ..position.y = y
          ..inTangent.y = 0
          ..outTangent.y = 0,
    ];
  }

  /// Where [entity]'s spline goes, every [spacing] metres from [startAt]:
  /// a world position and turn for each place.
  static List<(Vector3, Quaternion)> placesAlong(
    Entity entity, {
    required double spacing,
    double startAt = 0,
    double side = 0,
    bool align = true,
  }) {
    final spline = entity.getComponent<Spline3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (spline == null || transform == null) return const [];
    final instances = SplineInstances3D(spacing: spacing, startAt: startAt, sideOffset: side, alignToPath: align);
    final path = SplinePath.of(spline);
    final world = Matrix4.identity();
    transform.localToWorldInto(world);
    final own = Quaternion.identity();
    transform.rotationInto(own);
    final out = <(Vector3, Quaternion)>[];
    for (final local in InstancesRenderProvider.placements(instances, path)) {
      final s = local.storage;
      final at = Vector3.zero();
      world.transformPointInto(Vector3(s[12], s[13], s[14]), at);
      final turn = align
          ? rotationOfBasis(
              Vector3(s[0], s[1], s[2])..normalize(),
              Vector3(s[4], s[5], s[6])..normalize(),
              Vector3(s[8], s[9], s[10])..normalize(),
            )
          : Quaternion.identity();
      out.add((at, Quaternion.copy(own)..multiply(turn)));
    }
    return out;
  }

  /// Copies of each of [sources] — and of what is inside it — standing
  /// every [spacing] metres along [splineEntity]'s spline, turned to face
  /// along it, as one undo step. Returns how many were made.
  static int layAlong(EditorScope scope, Entity splineEntity, List<Entity> sources, double spacing) {
    final world = scope.world;
    final places = placesAlong(splineEntity, spacing: spacing);
    final outermost = _outermost(world, [for (final e in sources) if (!identical(e, splineEntity)) e]);
    if (places.isEmpty || outermost.isEmpty) return 0;
    final namer = _namer(world);
    final specs = <EntitySpec>[];
    for (final source in outermost) {
      final t = source.getComponent<TransformComponent>();
      if (t == null) continue;
      final from = Vector3.copy(t.position);
      final fromTurn = Quaternion.identity();
      t.rotationInto(fromTurn);
      final undo = Quaternion.copy(fromTurn)..invert();
      for (final (at, turn) in places) {
        // The whole of it moved and turned as one: from its own place to
        // this one.
        final delta = Quaternion.copy(turn)..multiply(undo);
        void move(TransformComponent c) {
          final offset = c.position - from;
          delta.rotate(offset);
          c.position.setFrom(at + offset);
          final own = Quaternion.identity();
          c.rotationInto(own);
          c.setRotation(Quaternion.copy(delta)..multiply(own));
        }

        specs.addAll(_copies(world, scope.codec, source, move, namer));
      }
    }
    if (specs.isEmpty) return 0;
    scope.history.push(
      CreateEntitiesCommand(
        label: 'Lay ${outermost.length == 1 ? outermost.single.name ?? 'entity' : '${outermost.length} entities'} along ${splineEntity.name ?? 'the spline'}',
        world: world,
        sceneState: scope.sceneState,
        specs: specs,
      ),
    );
    scope.sceneState.markDirty();
    return places.length * outermost.length;
  }

  /// [entity]'s [SplineInstances3D] made into entities of their own —
  /// each a model (or a cube) under one new group — the component taken
  /// off, as one undo step. Returns how many were made.
  static int bake(EditorScope scope, Entity entity) {
    final instances = entity.getComponent<SplineInstances3D>();
    if (instances == null) return 0;
    final places = placesAlong(
      entity,
      spacing: instances.spacing,
      startAt: instances.startAt,
      side: instances.sideOffset,
      align: instances.alignToPath,
    );
    if (places.isEmpty) return 0;
    final world = scope.world;
    final namer = _namer(world);
    final codec = scope.codec;
    final stem = instances.model.isEmpty
        ? 'Post'
        : instances.model.split('/').last.split('.').first;
    final groupName = namer('${stem}_row');
    final owner = entity.getComponent<TransformComponent>()!;
    final scale = Vector3.copy(owner.scale)..scale(instances.scale);
    final specs = <EntitySpec>[
      EntitySpec(
        name: groupName,
        componentsJson: codec.encodeAll([TransformComponent(position: Vector3.copy(owner.position))]),
        codec: codec,
      ),
    ];
    for (final (at, turn) in places) {
      final position = Vector3.copy(at);
      if (instances.model.isEmpty) {
        // A metre cube standing on the spline, as it was drawn.
        final lift = Vector3(0, -0.5 * scale.y, 0);
        turn.rotate(lift);
        position.add(lift);
      }
      final transform = TransformComponent(position: position, scale: Vector3.copy(scale))..setRotation(turn);
      specs.add(
        EntitySpec(
          name: namer(stem),
          componentsJson: codec.encodeAll([
            transform,
            if (instances.model.isEmpty)
              Cube3D(width: 1, height: 1, depth: 1, castShadows: instances.castShadows)
            else
              ModelComponent(model: instances.model, castShadows: instances.castShadows),
          ]),
          codec: codec,
          parentName: groupName,
        ),
      );
    }
    scope.history.push(
      CompositeCommand(
        label: 'Bake ${places.length} copies along ${entity.name ?? 'the spline'}',
        commands: [
          CreateEntitiesCommand(label: 'Bake copies', world: world, sceneState: scope.sceneState, specs: specs),
          RemoveComponentCommand(entity: entity, component: instances, sceneState: scope.sceneState),
        ],
      ),
    );
    scope.sceneState
      ..markDirty()
      ..refresh();
    return places.length;
  }

  /// Names of the form `prefix_N` not used in [world], nor handed out
  /// before by the namer.
  static String Function(String prefix) _namer(World world) {
    final taken = {...world.query([TransformComponent]).map((e) => e.name).whereType<String>()};
    return (prefix) {
      var index = 0;
      while (taken.contains('${prefix}_$index')) {
        index++;
      }
      final name = '${prefix}_$index';
      taken.add(name);
      return name;
    };
  }

  /// [entities] less anything inside another of them.
  static List<Entity> _outermost(World world, List<Entity> entities) {
    final ids = {for (final e in entities) e.id};
    bool inside(Entity e) {
      var parent = e.getComponent<ParentComponent>()?.parentId;
      for (var guard = 0; parent != null && guard < 64; guard++) {
        if (ids.contains(parent)) return true;
        parent = world.getEntity(parent)?.getComponent<ParentComponent>()?.parentId;
      }
      return false;
    }

    return [for (final e in entities) if (!inside(e)) e];
  }

  /// A copy of [entity] and of everything inside it, each moved by [edit],
  /// renamed, the copies inside the copy.
  static List<EntitySpec> _copies(
    World world,
    SceneCodec codec,
    Entity entity,
    void Function(TransformComponent transform) edit,
    String Function(String prefix) namer,
  ) {
    final renamed = <String, String>{};
    String copyName(Entity e) {
      final base = (e.name ?? 'Entity').replaceFirst(RegExp(r'_\d+$'), '');
      final name = namer(base);
      if (e.name != null) renamed[e.name!] = name;
      return name;
    }

    final specs = [EntitySpec.of(entity, codec, world: world).transformed(edit, newName: copyName(entity))];
    final queue = [entity];
    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      for (final id in parent.getComponent<ChildrenComponent>()?.childIds ?? const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child == null) continue;
        final spec = EntitySpec.of(child, codec, world: world);
        specs.add(spec.transformed(edit, newName: copyName(child)).under(renamed[spec.parentName] ?? spec.parentName));
        queue.add(child);
      }
    }
    return specs;
  }
}

/// The inspector's Spline section, under a [Spline3D]'s components: lay
/// the rest of the selection along it, and bake its copies into entities.
InspectorSection splineSection() => InspectorSection(
  id: 'worldBuilder.spline',
  order: 60,
  appliesTo: (entity) => entity.hasComponent<Spline3D>(),
  build: (context, entity, scope) => _SplineSection(entity: entity, scope: scope),
);

class _SplineSection extends StatefulWidget {
  const _SplineSection({required this.entity, required this.scope});

  final Entity entity;
  final EditorScope scope;

  @override
  State<_SplineSection> createState() => _SplineSectionState();
}

class _SplineSectionState extends State<_SplineSection> {
  static const List<double> _spacings = [1, 2, 3, 4, 5, 8, 10];
  double _spacing = 2;

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    return SignalBuilder<Set<EntityId>>(
      signal: scope.sceneState.multiSelectedIds,
      builder: (context, ids, _) {
        final others = [
          for (final id in ids)
            if (id != widget.entity.id) ?scope.world.getEntity(id),
        ];
        final baked = widget.entity.hasComponent<SplineInstances3D>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EditorSectionHeader('Spline'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<double>(
                    tooltip: 'How far apart',
                    initialValue: _spacing,
                    color: EditorTheme.menuBg,
                    onSelected: (v) => setState(() => _spacing = v),
                    itemBuilder: (context) => [
                      for (final v in _spacings)
                        editorMenuItem(v, 'Every ${_metres(v)}'),
                    ],
                    child: Text('Every ${_metres(_spacing)}', style: InspectorField.valueStyle.copyWith(color: EditorTheme.textSecondary)),
                  ),
                  EditorButton(
                    label: others.isEmpty ? 'Select what to lay along it too' : 'Lay ${others.length} selected along it',
                    icon: Icons.linear_scale,
                    onPressed: others.isEmpty
                        ? null
                        : () => SplineEdits.layAlong(scope, widget.entity, others, _spacing),
                  ),
                  if (baked)
                    EditorButton(
                      label: 'Bake copies to entities',
                      icon: Icons.call_split,
                      onPressed: () => SplineEdits.bake(scope, widget.entity),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _metres(double v) => v == v.roundToDouble() ? '${v.toInt()} m' : '$v m';
}

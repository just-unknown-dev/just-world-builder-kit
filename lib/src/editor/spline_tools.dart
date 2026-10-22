import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_signals/just_signals.dart';

import '../splines/spline_components.dart';
import '../splines/spline_path.dart';
import 'blockout_tools.dart' show BlockoutPreview;

/// The tool strip's group for splines.
const String splineGroup = 'worldBuilder.splines';

/// What the Spline tool makes of the points clicked.
enum SplineMake {
  /// A spline alone: a route for a [PathFollower3D].
  path('Path', Icons.gesture),

  /// A road along it, solid.
  road('Road', Icons.add_road),

  /// A wall standing on it, solid.
  wall('Wall', Icons.fence),

  /// A pipe round it, solid.
  pipe('Pipe', Icons.circle_outlined),

  /// A low rail standing on it, solid.
  rail('Rail', Icons.horizontal_rule),

  /// Posts along it, a metre cube each until a model is chosen.
  fence('Posts', Icons.more_horiz),

  /// A spline and a platform that rides it, there and back.
  route('Platform route', Icons.route);

  const SplineMake(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Adds [entities], made already, to the scene as one undo step called
/// [label], and selects the first.
void adoptEntities(DesignerToolContext context, List<Entity> entities, String label) {
  if (entities.isEmpty) return;
  context.history.pushApplied(
    CreateEntitiesCommand.adopting(
      label: label,
      world: context.world,
      sceneState: context.sceneState,
      entities: entities,
      codec: context.scope.codec,
    ),
  );
  context.sceneState
    ..markDirty()
    ..refresh()
    ..selectEntity(entities.first);
}

/// The rotation whose matrix has the columns [x], [y] and [z] — unit
/// length, square to each other, right-handed.
Quaternion rotationOfBasis(Vector3 x, Vector3 y, Vector3 z) {
  final m00 = x.x, m10 = x.y, m20 = x.z;
  final m01 = y.x, m11 = y.y, m21 = y.z;
  final m02 = z.x, m12 = z.y, m22 = z.z;
  final trace = m00 + m11 + m22;
  final double qx, qy, qz, qw;
  if (trace > 0) {
    final s = math.sqrt(trace + 1) * 2;
    qw = s / 4;
    qx = (m21 - m12) / s;
    qy = (m02 - m20) / s;
    qz = (m10 - m01) / s;
  } else if (m00 > m11 && m00 > m22) {
    final s = math.sqrt(1 + m00 - m11 - m22) * 2;
    qw = (m21 - m12) / s;
    qx = s / 4;
    qy = (m01 + m10) / s;
    qz = (m02 + m20) / s;
  } else if (m11 > m22) {
    final s = math.sqrt(1 + m11 - m00 - m22) * 2;
    qw = (m02 - m20) / s;
    qx = (m01 + m10) / s;
    qy = s / 4;
    qz = (m12 + m21) / s;
  } else {
    final s = math.sqrt(1 + m22 - m00 - m11) * 2;
    qw = (m10 - m01) / s;
    qx = (m02 + m20) / s;
    qy = (m12 + m21) / s;
    qz = s / 4;
  }
  return Quaternion.identity()
    ..setValues(qx, qy, qz, qw)
    ..normalize();
}

/// The Spline tool: click points along any surface — Enter, a double-click
/// or a click on the first point finishes; Backspace takes one back — for
/// a road, a wall, a pipe, a rail, posts, a platform's route or a bare
/// path, as its options say. Drag the points after with the selection's
/// handles.
class SplineTool extends LevelToolHandler {
  SplineTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  /// What it would make now.
  final Signal<BlockoutPreview?> preview = Signal(null, debugLabel: 'splinePreview');

  /// What it makes.
  final Signal<SplineMake> make = Signal(SplineMake.road, debugLabel: 'splineMake');

  /// Whether it runs round from its last point to its first.
  final Signal<bool> closed = Signal(false, debugLabel: 'splineClosed');

  /// Curved through its points, or straight between them.
  final Signal<bool> smooth = Signal(true, debugLabel: 'splineSmooth');

  static const String toolId = 'worldBuilder.spline';

  /// How near the first point, on screen, a click closes the spline.
  static const double closeReach = 10;

  final List<Vector3> _points = [];
  Vector3? _hover;

  @override
  String get id => toolId;

  @override
  String get label => 'Spline';

  @override
  IconData get icon => Icons.gesture;

  @override
  String? get description =>
      'Click points along any surface; Enter, a double-click or the first point finishes a road, wall, pipe, posts or a route';

  @override
  int get order => 50;

  @override
  String get group => splineGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  /// The points clicked so far, in the world.
  List<Vector3> get points => List.unmodifiable(_points);

  void _show() {
    if (_points.isEmpty) {
      preview.value = null;
      return;
    }
    final spline = Spline3D(
      points: [for (final p in [..._points, ?_hover]) SplinePoint(position: p)],
      interpolation: smooth.value ? SplineInterpolation.catmullRom : SplineInterpolation.linear,
      closed: closed.value,
    );
    final path = SplinePath.of(spline, perSegment: 12);
    preview.value = BlockoutPreview(outline: path.positions, markers: List.of(_points));
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final p = space.snappedSurface().position;
    if (_points.length >= 2 && context.isDoubleClick) {
      _finish(context);
      return true;
    }
    final first = _points.isEmpty ? null : space.view.projectToScreen(_points.first);
    if (_points.length >= 3 && first != null && (first - space.screen).distance <= closeReach) {
      closed.value = true;
      _finish(context);
      return true;
    }
    _points.add(p);
    _show();
    return true;
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    if (space == null || _points.isEmpty) return;
    _hover = space.snappedSurface().position;
    _show();
  }

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (_points.isEmpty) return false;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _finish(context);
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _points.removeLast();
      _show();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      _reset();
      return true;
    }
    return false;
  }

  void _finish(ToolContext context) {
    if (_points.length < 2) {
      context.controller.setStatus('A spline needs two points or more');
      return;
    }
    final kind = make.value;
    final made = build(
      designer,
      _points,
      kind,
      closed: closed.value && _points.length >= 3,
      smooth: smooth.value,
    );
    _reset();
    adoptEntities(designer, made, 'Draw a ${kind.label.toLowerCase()}');
    final length = SplinePath.of(made.first.getComponent<Spline3D>()!).length;
    context.controller.setStatus('${kind.label}: ${length.toStringAsFixed(1)} m');
  }

  /// The entities a spline through [points] (in the world) makes as
  /// [kind]: the spline's first, standing at the first point.
  static List<Entity> build(
    DesignerToolContext designer,
    List<Vector3> points,
    SplineMake kind, {
    bool closed = false,
    bool smooth = true,
  }) {
    // +Y is down. A road's top is on the spline: lifted off the ground it
    // was drawn on; a pipe's middle is, lifted by its radius, and a
    // platform's, by half its thickness.
    const pipeRadius = 0.5, platformThickness = 0.4;
    final lift = switch (kind) {
      SplineMake.road => 0.02,
      SplineMake.pipe => pipeRadius,
      SplineMake.route => platformThickness / 2,
      _ => 0.0,
    };
    final origin = Vector3.copy(points.first)..y -= lift;
    final spline = Spline3D(
      points: [for (final p in points) SplinePoint(position: Vector3(p.x - origin.x, p.y - lift - origin.y, p.z - origin.z))],
      closed: closed,
      interpolation: smooth ? SplineInterpolation.catmullRom : SplineInterpolation.linear,
    );
    List<Component> solid(SplineSweep3D sweep) => [
      sweep,
      RigidBody3D(bodyType: BodyType3D.static),
      Collider3D(shape: ColliderShape3D.matchShape),
    ];
    final name = designer.uniqueName(switch (kind) {
      SplineMake.path || SplineMake.route => 'Path',
      _ => kind.label,
    });
    final pieces = <Component>[
      TransformComponent(position: origin),
      spline,
      ...switch (kind) {
        SplineMake.path || SplineMake.route => const <Component>[],
        SplineMake.road => solid(SplineSweep3D(profile: SweepProfile.road, width: 3, height: 0.3)),
        SplineMake.wall => solid(SplineSweep3D(profile: SweepProfile.wall, width: 0.3, height: 2.5)),
        SplineMake.pipe => solid(SplineSweep3D(profile: SweepProfile.pipe, radius: pipeRadius)),
        SplineMake.rail => solid(SplineSweep3D(profile: SweepProfile.rail, width: 0.2, height: 0.2, color: const Color(0xFF8D6E63))),
        SplineMake.fence => [SplineInstances3D(spacing: 2, scale: 0.3)],
      },
    ];
    final made = [designer.world.createEntityWithComponents(pieces, name: name)];
    if (kind == SplineMake.route) {
      // A platform riding it, its middle on the spline.
      made.add(
        designer.world.createEntityWithComponents(
          [
            TransformComponent(position: Vector3.copy(origin)),
            Cube3D(width: 3, height: platformThickness, depth: 3),
            RigidBody3D(bodyType: BodyType3D.kinematic),
            Collider3D(shape: ColliderShape3D.matchShape),
            PathFollower3D(path: EntityTarget.name(name)),
          ],
          name: designer.uniqueName('Platform'),
        ),
      );
    }
    return made;
  }

  void _reset() {
    _points.clear();
    _hover = null;
    preview.value = null;
  }

  @override
  void onDeactivate() => _reset();

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SignalBuilder<SplineMake>(
        signal: make,
        builder: (context, value, _) => PopupMenuButton<SplineMake>(
          tooltip: 'What it makes',
          initialValue: value,
          color: EditorTheme.menuBg,
          position: PopupMenuPosition.over,
          onSelected: (v) => make.value = v,
          itemBuilder: (context) => [
            for (final m in SplineMake.values)
              editorMenuItem(m, m.label, icon: m.icon),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Make ${value.label}', style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SignalBuilder<bool>(
        signal: smooth,
        builder: (context, value, _) => EditorSegmented<bool>(
          value: value,
          options: const [(true, 'Curved'), (false, 'Straight')],
          onChanged: (v) {
            smooth.value = v;
            _show();
          },
        ),
      ),
      const SizedBox(width: 8),
      SignalBuilder<bool>(
        signal: closed,
        builder: (context, value, _) => EditorSegmented<bool>(
          value: value,
          options: const [(false, 'Open'), (true, 'Closed')],
          onChanged: (v) {
            closed.value = v;
            _show();
          },
        ),
      ),
    ],
  );
}

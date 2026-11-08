import 'dart:math' as math;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

// What the World Builder's tools share: an entity's space, making entities
// as one undo step, a box's edges and a ring drawn over the viewport, the
// points a tool is clicked round, and the pickers in a tool's options bar.

/// [entity]'s space to the world's, and back; the world's own for none (or
/// for a space that cannot be turned back).
@internal
(Matrix4, Matrix4) spaceOf(Entity? entity) {
  final toWorld = Matrix4.identity();
  entity?.getComponent<TransformComponent>()?.localToWorldInto(toWorld);
  final toLocal = Matrix4.identity();
  if (toLocal.copyInverse(toWorld) == 0) toLocal.setIdentity();
  return (toWorld, toLocal);
}

/// [normal], a direction square to a surface in the space [toLocal] turns
/// the world into, in the world: through the transpose of [toLocal], so it
/// stays square to the surface under a scale that is not the same on every
/// axis. Into [out], unit length (zero when [normal] is).
@internal
void normalToWorld(Matrix4 toLocal, Vector3 normal, Vector3 out) {
  final m = toLocal.storage;
  // Column i of the 3×3 part, dotted with [normal]: its transpose's row i.
  final x = m[0] * normal.x + m[1] * normal.y + m[2] * normal.z;
  final y = m[4] * normal.x + m[5] * normal.y + m[6] * normal.z;
  final z = m[8] * normal.x + m[9] * normal.y + m[10] * normal.z;
  out.setValues(x, y, z);
  if (out.lengthSquared > 0) out.normalize();
}

/// Adds [entities], made already, to the scene as one undo step called
/// [label], and selects the first.
@internal
void adoptEntities(
  DesignerToolContext context,
  List<Entity> entities,
  String label,
) {
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

/// Makes an entity of [components] named after [prefix], selected, as one
/// undo step called [label] — solid, as the engine's Solid shapes are: a
/// static body and a collider matching its shape, so a blocked-out level
/// plays at once.
@internal
Entity makeSolid(
  DesignerToolContext context,
  List<Component> components,
  String prefix,
  String label,
) {
  final entity = context.world.createEntityWithComponents([
    ...components,
    RigidBody3DComponent(bodyType: Body3DType.static),
    Collider3DComponent(shape: Collider3DShape.matchShape),
  ], name: context.uniqueName(prefix));
  adoptEntities(context, [entity], label);
  return entity;
}

/// A box's twelve edges, by its corners: corner `i` takes the low or high
/// side on X by bit 0, on Y by bit 1 and on Z by bit 2.
@internal
const List<(int, int)> boxEdges = [
  (0, 1),
  (2, 3),
  (4, 5),
  (6, 7),
  (0, 2),
  (1, 3),
  (4, 6),
  (5, 7),
  (0, 4),
  (1, 5),
  (2, 6),
  (3, 7),
];

/// Draws the edges of the box whose corner `i` is [corners]`[i]` on screen
/// ([boxEdges]); a corner behind the eye (null) leaves out its edges.
@internal
void paintBoxEdges(Canvas canvas, List<Offset?> corners, Paint paint) {
  for (final (a, b) in boxEdges) {
    final from = corners[a], to = corners[b];
    if (from != null && to != null) canvas.drawLine(from, to, paint);
  }
}

/// How many points a brush's ring is drawn through.
@internal
const int ringSegments = 48;

/// Draws a closed ring through the [ringSegments] + 1 points [at] gives for
/// the angles round it (radians), projected by [project]: a brush on the
/// ground.
@internal
void paintRing(
  Canvas canvas,
  Paint paint,
  Vector3 Function(double angle) at,
  Offset? Function(Vector3 world) project,
) {
  Offset? last;
  for (var k = 0; k <= ringSegments; k++) {
    final p = project(at(2 * math.pi * k / ringSegments));
    if (p != null && last != null) canvas.drawLine(last, p, paint);
    last = p;
  }
}

/// The points a tool is clicked round — a floor's corners, a spline's
/// points — and where the pointer would add the next.
@internal
final class ClickedPoints {
  final List<Vector3> _points = [];

  /// Where the pointer is, past the last point; null when not over a
  /// surface or before the first.
  Vector3? hover;

  /// The points clicked, in order.
  List<Vector3> get points => List.unmodifiable(_points);

  int get length => _points.length;
  bool get isEmpty => _points.isEmpty;
  Vector3 get first => _points.first;
  Vector3 get last => _points.last;

  /// Adds [p] — unless it is where the last one is: the second click of a
  /// double-click, which would put one point in twice.
  bool add(Vector3 p) {
    if (_points.isNotEmpty && (_points.last - p).lengthSquared < 1e-6) {
      return false;
    }
    _points.add(p);
    return true;
  }

  /// Takes the last point back.
  void removeLast() {
    if (_points.isNotEmpty) _points.removeLast();
  }

  /// No points.
  void clear() {
    _points.clear();
    hover = null;
  }
}

/// A tool option's value, its [label] shown in the options bar; [values]
/// to choose from in a menu.
@internal
class ToolOptionPicker<T> extends StatelessWidget {
  const ToolOptionPicker({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.onSelected,
    this.tooltip,
    this.icon,
  });

  final T value;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;
  final String? tooltip;

  /// A dot of colour beside a value in the menu, if any.
  final (IconData, Color)? Function(T value)? icon;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    initialValue: values.contains(value) ? value : null,
    color: EditorTheme.menuBg,
    position: PopupMenuPosition.over,
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final v in values)
        if (icon?.call(v) case (final IconData i, final Color c))
          editorMenuItem(v, label(v), icon: i, iconColor: c)
        else
          editorMenuItem(v, label(v)),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label(value),
        style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
      ),
    ),
  );
}

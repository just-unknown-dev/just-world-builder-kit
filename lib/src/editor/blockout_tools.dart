import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

/// The tool strip's group for blockout.
const String blockoutGroup = 'worldBuilder.blockout';

/// What a blockout tool would make now, drawn before it is made: the
/// edges of a box, an outline, or a line, in the world.
final class BlockoutPreview {
  const BlockoutPreview({this.box, this.outline = const [], this.closed = false, this.markers = const [], this.line});

  /// A box, by its corners.
  final Aabb3? box;

  /// An outline's corners, in order.
  final List<Vector3> outline;

  /// Whether [outline] closes back on its first corner.
  final bool closed;

  /// Points marked with a dot: the corners or points clicked.
  final List<Vector3> markers;

  /// A line from one point to another.
  final (Vector3, Vector3)? line;
}

/// Makes an entity of [components] named after [prefix], selected, as one
/// undo step called [label].
Entity _make(DesignerToolContext context, List<Component> components, String prefix, String label) {
  final entity = context.world.createEntityWithComponents(components, name: context.uniqueName(prefix));
  context.history.pushApplied(
    CreateEntitiesCommand.adopting(
      label: label,
      world: context.world,
      sceneState: context.sceneState,
      entities: [entity],
      codec: context.scope.codec,
    ),
  );
  context.sceneState
    ..markDirty()
    ..refresh()
    ..selectEntity(entity);
  return entity;
}

/// The axis (0 X, 1 Y, 2 Z) [n] runs most along.
int _axisOf(Vector3 n) {
  final ax = n.x.abs(), ay = n.y.abs(), az = n.z.abs();
  return ay >= ax && ay >= az ? 1 : (ax >= az ? 0 : 2);
}

double _get(Vector3 v, int axis) => switch (axis) {
  0 => v.x,
  1 => v.y,
  _ => v.z,
};

void _set(Vector3 v, int axis, double value) {
  switch (axis) {
    case 0:
      v.x = value;
    case 1:
      v.y = value;
    default:
      v.z = value;
  }
}

/// Where [ray] meets the plane through [point] facing [normal]; null when
/// it runs along it or away.
Vector3? _onPlane(Ray3 ray, Vector3 point, Vector3 normal) {
  final denom = normal.dot(ray.direction);
  if (denom.abs() < 1e-9) return null;
  final t = normal.dot(point - ray.origin) / denom;
  if (t < 0) return null;
  return ray.origin + ray.direction * t;
}

/// How far along the line through [point] in [direction] (unit) the point
/// nearest [ray] is; null when they run side by side.
double? _alongLine(Ray3 ray, Vector3 point, Vector3 direction) {
  final d = ray.direction, w = point - ray.origin;
  final a = direction.dot(direction), b = direction.dot(d), c = d.dot(d);
  final e = direction.dot(w), f = d.dot(w);
  final denom = a * c - b * b;
  if (denom.abs() < 1e-12) return null;
  return (b * f - c * e) / denom;
}

double _snap(double v, SpaceContext space) =>
    space.snapping && space.moveStep > 0 ? (v / space.moveStep).roundToDouble() * space.moveStep : v;

/// Blockout's Block: drag a footprint on any surface — the ground, a wall,
/// the top of another block — then move the pointer for its height and
/// click. A click alone makes a 1 m block on the surface. Makes a
/// [Cube3D].
class BlockTool extends LevelToolHandler {
  BlockTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  /// What it would make now.
  final Signal<BlockoutPreview?> preview = Signal(null, debugLabel: 'blockPreview');

  static const String toolId = 'worldBuilder.block';

  // The surface the footprint is on, the corner dragged to, and — once
  // the footprint is down — how high it goes.
  Vector3? _base;
  Vector3 _normal = Vector3(0, -1, 0);
  Vector3? _corner;
  bool _raising = false;
  double _height = 0;

  @override
  String get id => toolId;

  @override
  String get label => 'Block';

  @override
  IconData get icon => Icons.check_box_outline_blank;

  @override
  String? get description =>
      'Drag a footprint on any surface, then move up for its height and click; a click alone makes a 1 m block';

  @override
  int get order => 40;

  @override
  String get group => blockoutGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  /// The box from the footprint and [_height]; null before a footprint.
  Aabb3? get _box {
    final base = _base, corner = _corner;
    if (base == null || corner == null) return null;
    final axis = _axisOf(_normal);
    final sign = _get(_normal, axis) < 0 ? -1.0 : 1.0;
    final a = Vector3.copy(base), b = Vector3.copy(corner);
    _set(b, axis, _get(base, axis) + sign * _height);
    return Aabb3()
      ..setValues(
        math.min(a.x, b.x),
        math.min(a.y, b.y),
        math.min(a.z, b.z),
        math.max(a.x, b.x),
        math.max(a.y, b.y),
        math.max(a.z, b.z),
      );
  }

  void _show() {
    final box = _box;
    preview.value = box == null ? null : BlockoutPreview(box: box);
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    if (_raising) {
      _commit(context);
      return true;
    }
    final at = space.snappedSurface();
    final axis = _axisOf(at.normal);
    _normal = Vector3.zero();
    _set(_normal, axis, _get(at.normal, axis) < 0 ? -1 : 1);
    _base = Vector3.copy(at.position);
    _corner = Vector3.copy(at.position);
    _height = 0;
    _show();
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, base = _base;
    if (space == null || base == null || _raising) return;
    final hit = _onPlane(space.ray, base, _normal);
    if (hit == null) return;
    _corner = space.snapping && space.moveStep > 0
        ? SpaceContext.snapAcross(hit, _normal, space.moveStep)
        : hit;
    _set(_corner!, _axisOf(_normal), _get(base, _axisOf(_normal)));
    _show();
  }

  @override
  void onPointerUp(ToolContext context) {
    final base = _base, corner = _corner;
    if (base == null || corner == null || _raising) return;
    final axis = _axisOf(_normal);
    final spread = [for (var i = 0; i < 3; i++) if (i != axis) (_get(corner, i) - _get(base, i)).abs()];
    if (spread.every((s) => s < 0.05)) {
      // A click: a metre each way, standing on the surface.
      final c = Vector3.copy(base), d = Vector3.copy(base);
      for (var i = 0; i < 3; i++) {
        if (i == axis) continue;
        _set(c, i, _get(base, i) - 0.5);
        _set(d, i, _get(base, i) + 0.5);
      }
      _base = c;
      _corner = d;
      _height = 1;
      _commit(context);
      return;
    }
    _raising = true;
    context.controller.setStatus('Move up for its height, and click');
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space, corner = _corner;
    if (!_raising || space == null || corner == null) return;
    final along = _alongLine(space.ray, corner, _normal);
    if (along == null) return;
    _height = math.max(_snap(along, space), 0.05);
    _show();
  }

  void _commit(ToolContext context) {
    final box = _box;
    _reset();
    if (box == null) return;
    final size = Vector3.zero(), centre = Vector3.zero();
    box
      ..sizeInto(size)
      ..centerInto(centre);
    _make(
      designer,
      [
        TransformComponent(position: centre),
        Cube3D(width: math.max(size.x, 0.01), height: math.max(size.y, 0.01), depth: math.max(size.z, 0.01)),
      ],
      'Block',
      'Block out a box',
    );
    context.controller.setStatus('Blocked out ${size.x.toStringAsFixed(2)} × ${size.y.toStringAsFixed(2)} × ${size.z.toStringAsFixed(2)} m');
  }

  void _reset() {
    _base = null;
    _corner = null;
    _raising = false;
    _height = 0;
    preview.value = null;
  }

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (key != LogicalKeyboardKey.escape || _base == null) return false;
    _reset();
    return true;
  }

  @override
  void onCancel() {
    if (!_raising) _reset();
  }

  @override
  void onDeactivate() => _reset();
}

/// Blockout's Floor: click round an outline on any level surface — Enter,
/// a double-click or a click on the first corner closes it — for a floor
/// slab that shape, its top on the surface. Backspace takes back a corner.
/// Makes a [Polygon3D].
class FloorTool extends LevelToolHandler {
  FloorTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  /// What it would make now.
  final Signal<BlockoutPreview?> preview = Signal(null, debugLabel: 'floorPreview');

  /// How thick a floor is (metres).
  final Signal<double> thickness = Signal(0.2, debugLabel: 'floorThickness');

  static const String toolId = 'worldBuilder.floor';

  /// How near the first corner, on screen, a click closes the outline.
  static const double closeReach = 10;

  final List<Vector3> _points = [];
  Vector3? _hover;
  double _level = 0;

  @override
  String get id => toolId;

  @override
  String get label => 'Floor';

  @override
  IconData get icon => Icons.pentagon_outlined;

  @override
  String? get description =>
      'Click round an outline; Enter, a double-click or the first corner closes it into a floor';

  @override
  int get order => 41;

  @override
  String get group => blockoutGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  Vector3? _pointAt(SpaceContext space) {
    if (_points.isEmpty) return space.snappedSurface().position;
    final hit = _onPlane(space.ray, Vector3(0, _level, 0), Vector3(0, -1, 0));
    if (hit == null) return null;
    return space.snapping && space.moveStep > 0 ? SpaceContext.snapAcross(hit, Vector3(0, -1, 0), space.moveStep) : hit;
  }

  void _show() {
    preview.value = _points.isEmpty
        ? null
        : BlockoutPreview(outline: [..._points, ?_hover], closed: true, markers: List.of(_points));
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final p = _pointAt(space);
    if (p == null) return true;
    if (_points.isEmpty) _level = p.y;
    final first = _points.isEmpty ? null : space.view.projectToScreen(_points.first);
    if (_points.length >= 3 && (context.isDoubleClick || (first != null && (first - space.screen).distance <= closeReach))) {
      _finish(context);
      return true;
    }
    _points.add(Vector3(p.x, _level, p.z));
    _show();
    return true;
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    if (space == null || _points.isEmpty) return;
    final p = _pointAt(space);
    _hover = p == null ? null : Vector3(p.x, _level, p.z);
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
    if (_points.length < 3) {
      context.controller.setStatus('A floor needs three corners or more');
      return;
    }
    var cx = 0.0, cz = 0.0;
    for (final p in _points) {
      cx += p.x;
      cz += p.z;
    }
    cx /= _points.length;
    cz /= _points.length;
    final t = thickness.value;
    final points = [for (final p in _points) Offset(p.x - cx, p.z - cz)];
    _reset();
    // +Y is down: its top on the surface, its middle half its thickness
    // below.
    _make(
      designer,
      [TransformComponent(position: Vector3(cx, _level + t / 2, cz)), Polygon3D(points: points, height: t)],
      'Floor',
      'Block out a floor',
    );
    context.controller.setStatus('A floor of ${points.length} corners');
  }

  void _reset() {
    _points.clear();
    _hover = null;
    preview.value = null;
  }

  @override
  void onDeactivate() => _reset();

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) => _Choices<double>(
    label: 'Thickness',
    signal: thickness,
    values: const [0.1, 0.2, 0.5, 1],
    text: (v) => '$v m',
  );
}

/// Ramps and stairs, as Ramp and Stairs make them.
enum SlopeKind { ramp, stairs }

/// Blockout's Ramp: drag from where a slope starts at the bottom to where
/// it reaches at the top — onto a ledge, say — for a ramp or a flight of
/// stairs that wide, facing the way it was dragged. Makes a [Ramp3D] or a
/// [Stairs3D].
class RampTool extends LevelToolHandler {
  RampTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  /// What it would make now.
  final Signal<BlockoutPreview?> preview = Signal(null, debugLabel: 'rampPreview');

  /// A ramp or stairs.
  final Signal<SlopeKind> kind = Signal(SlopeKind.ramp, debugLabel: 'slopeKind');

  /// How wide (metres).
  final Signal<double> width = Signal(2, debugLabel: 'slopeWidth');

  static const String toolId = 'worldBuilder.ramp';

  /// How high a stair is, as near as whole steps allow (metres).
  static const double stepHeight = 0.2;

  Vector3? _foot, _top;

  @override
  String get id => toolId;

  @override
  String get label => 'Ramp';

  @override
  IconData get icon => Icons.trending_up;

  @override
  String? get description => 'Drag from the foot of a slope up to its top for a ramp or stairs';

  @override
  int get order => 42;

  @override
  String get group => blockoutGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    _foot = space.snappedSurface().position;
    _top = Vector3.copy(_foot!);
    preview.value = BlockoutPreview(line: (_foot!, _top!));
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, foot = _foot;
    if (space == null || foot == null) return;
    _top = space.snappedSurface().position;
    preview.value = BlockoutPreview(line: (foot, _top!));
  }

  @override
  void onPointerUp(ToolContext context) {
    var foot = _foot, top = _top;
    _foot = _top = null;
    preview.value = null;
    if (foot == null || top == null) return;
    // +Y is down: the top is the higher end, whichever way it was dragged.
    if (top.y > foot.y) (foot, top) = (top, foot);
    final rise = foot.y - top.y;
    final run = Vector3(top.x - foot.x, 0, top.z - foot.z);
    if (run.length < 0.1 || rise < 0.05) {
      context.controller.setStatus('Drag from the foot of the slope up to its top');
      return;
    }
    final w = width.value;
    final turn = math.atan2(run.x, run.z);
    final centre = Vector3((foot.x + top.x) / 2, foot.y - rise / 2, (foot.z + top.z) / 2);
    final stairs = kind.value == SlopeKind.stairs;
    final transform = TransformComponent(position: centre)..setEuler(0, turn, 0);
    _make(
      designer,
      [
        transform,
        if (stairs)
          Stairs3D(width: w, height: rise, depth: run.length, steps: math.max(2, (rise / stepHeight).round()))
        else
          Ramp3D(width: w, height: rise, depth: run.length),
      ],
      stairs ? 'Stairs' : 'Ramp',
      stairs ? 'Block out stairs' : 'Block out a ramp',
    );
    final degrees = math.atan2(rise, run.length) * 180 / math.pi;
    context.controller.setStatus('${stairs ? 'Stairs' : 'A ramp'}: ${rise.toStringAsFixed(2)} m up over ${run.length.toStringAsFixed(2)} m (${degrees.round()}°)');
  }

  @override
  void onCancel() {
    _foot = _top = null;
    preview.value = null;
  }

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SignalBuilder<SlopeKind>(
        signal: kind,
        builder: (context, k, _) => EditorSegmented<SlopeKind>(
          value: k,
          options: const [(SlopeKind.ramp, 'Ramp'), (SlopeKind.stairs, 'Stairs')],
          onChanged: (v) => kind.value = v,
        ),
      ),
      const SizedBox(width: 8),
      _Choices<double>(label: 'Width', signal: width, values: const [1, 2, 3, 4, 6], text: (v) => '$v m'),
    ],
  );
}

/// A small picker of a few values, with a label.
class _Choices<T> extends StatelessWidget {
  const _Choices({required this.label, required this.signal, required this.values, required this.text});

  final String label;
  final Signal<T> signal;
  final List<T> values;
  final String Function(T value) text;

  @override
  Widget build(BuildContext context) => SignalBuilder<T>(
    signal: signal,
    builder: (context, value, _) => PopupMenuButton<T>(
      tooltip: label,
      initialValue: value,
      color: EditorTheme.menuBg,
      position: PopupMenuPosition.over,
      onSelected: (v) => signal.value = v,
      itemBuilder: (context) => [
        for (final v in values)
          editorMenuItem(v, text(v)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('$label ${text(value)}', style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11)),
      ),
    ),
  );
}

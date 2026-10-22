import 'dart:ui';

import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../splines/spline_components.dart';
import '../splines/spline_path.dart';

/// A selected [Spline3D]'s points to drag along the ground (Ctrl, Cmd on
/// macOS, snaps to the grid), each with a diamond a metre above it to raise or lower it.
/// Between each two a "+": click it for a point there, or drag it to place
/// one; past an open spline's last point one more, to go on. Alt-click a
/// point to remove it (two always stay). A Bézier spline's points also
/// have their handles, the other turning with one dragged unless the
/// point is a corner.
final class SplineHandles extends ViewportHandles {
  @override
  String get id => 'worldBuilder.spline';

  /// How far above its point a height handle is (metres).
  static const double raise = 1;

  /// Up, in the world: +Y is down.
  static final Vector3 up = Vector3(0, -1, 0);

  @override
  List<ViewportHandle> handlesOf(Entity entity, EditorScope scope) {
    final spline = entity.getComponent<Spline3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (spline == null || transform == null) return const [];
    final world = Matrix4.identity();
    transform.localToWorldInto(world);
    final inverse = Matrix4.identity();
    if (inverse.copyInverse(world) == 0) return const [];

    Vector3 toWorld(Vector3 local) {
      final out = Vector3.zero();
      world.transformPointInto(local, out);
      return out;
    }

    Vector3 toLocal(Vector3 point) {
      final out = Vector3.zero();
      inverse.transformPointInto(point, out);
      return out;
    }

    /// Where the pointer is on the level plane through where the drag
    /// began, snapped across it, in the spline's space.
    Vector3? onGround(HandleDrag drag) {
      final hit = drag.onPlane(drag.start, up);
      if (hit == null) return null;
      return toLocal(Vector3(drag.snapped(hit.x), hit.y, drag.snapped(hit.z)));
    }

    void replace(void Function(List<SplinePoint> points) edit) {
      final points = [for (final p in spline.points) p.copy()];
      edit(points);
      spline.points = points;
    }

    final points = spline.points;
    final n = points.length;
    final handles = <ViewportHandle>[];
    for (var i = 0; i < n; i++) {
      final at = toWorld(points[i].position);
      handles
        ..add(
          ViewportHandle(
            position: at,
            component: spline,
            tooltip: 'Drag to move this point; Alt-click to remove it',
            onDrag: (drag) {
              final p = onGround(drag);
              if (p == null || i >= spline.points.length) return;
              replace((all) => all[i].position = p);
            },
            onClick: (click) {
              if (click.alt && spline.points.length > 2 && i < spline.points.length) {
                replace((all) => all.removeAt(i));
              }
            },
          ),
        )
        ..add(
          ViewportHandle(
            position: at + up * raise,
            component: spline,
            style: ViewportHandleStyle.size,
            tooltip: 'Drag to raise or lower this point',
            onDrag: (drag) {
              final along = drag.alongLine(drag.start, up);
              if (along == null || i >= spline.points.length) return;
              final point = drag.start + up * (along - raise);
              // +Y is down: a height is snapped as its y.
              point.y = drag.snapped(point.y);
              final local = toLocal(point);
              replace((all) => all[i].position = local);
            },
          ),
        );
      if (spline.interpolation == SplineInterpolation.bezier) {
        handles.addAll(_tangents(spline, i, toWorld, onGround, replace));
      }
    }
    if (n >= 2) {
      // The middle of each stretch, on the curve.
      final mids = SplinePath.of(spline, perSegment: 2).positions;
      final stretches = spline.closed && n >= 3 ? n : n - 1;
      for (var s = 0; s < stretches && 2 * s + 1 < mids.length; s++) {
        handles.add(_insert(spline, s + 1, mids[2 * s + 1], toWorld, onGround, replace));
      }
      if (!spline.closed) {
        final last = points[n - 1].position, before = points[n - 2].position;
        final way = last - before;
        final step = way.length < 1e-6 ? Vector3(2, 0, 0) : (way..normalize()) * 2;
        handles.add(_insert(spline, n, last + step, toWorld, onGround, replace, tip: 'Click or drag to go on from here'));
      }
    }
    return handles;
  }

  /// A "+" at [local] that becomes point [index] when clicked or dragged.
  static ViewportHandle _insert(
    Spline3D spline,
    int index,
    Vector3 local,
    Vector3 Function(Vector3 local) toWorld,
    Vector3? Function(HandleDrag drag) onGround,
    void Function(void Function(List<SplinePoint> points) edit) replace, {
    String tip = 'Click or drag for a point here',
  }) {
    var added = false;
    void add() {
      if (added) return;
      added = true;
      replace((all) => all.insert(index.clamp(0, all.length), SplinePoint(position: Vector3.copy(local))));
    }

    return ViewportHandle(
      position: toWorld(local),
      component: spline,
      style: ViewportHandleStyle.add,
      tooltip: tip,
      onDrag: (drag) {
        add();
        final p = onGround(drag);
        if (p != null && index < spline.points.length) replace((all) => all[index].position = p);
      },
      onClick: (_) => add(),
    );
  }

  /// Point [i]'s two Bézier handles.
  static List<ViewportHandle> _tangents(
    Spline3D spline,
    int i,
    Vector3 Function(Vector3 local) toWorld,
    Vector3? Function(HandleDrag drag) onGround,
    void Function(void Function(List<SplinePoint> points) edit) replace,
  ) {
    final point = spline.points[i];
    final n = spline.points.length;
    // An automatic handle is shown where the curve would put it.
    Vector3 shown(bool out) {
      final own = out ? point.outTangent : point.inTangent;
      if (point.mode != SplineTangentMode.auto && own.lengthSquared > 0) return own;
      final before = spline.points[i == 0 ? (spline.closed ? n - 1 : 0) : i - 1].position;
      final after = spline.points[i == n - 1 ? (spline.closed ? 0 : n - 1) : i + 1].position;
      final t = (after - before) / 6;
      return out ? t : -t;
    }

    ViewportHandle one(bool out) => ViewportHandle(
      position: toWorld(point.position + shown(out)),
      component: spline,
      tooltip: out ? 'Drag to shape the curve leaving this point' : 'Drag to shape the curve reaching this point',
      onDrag: (drag) {
        final p = onGround(drag);
        if (p == null || i >= spline.points.length) return;
        replace((all) {
          final q = all[i];
          final handle = p - q.position;
          final other = out ? q.inTangent : q.outTangent;
          final otherLength = other.lengthSquared > 0 ? other.length : handle.length;
          if (q.mode == SplineTangentMode.auto) {
            q.mode = SplineTangentMode.aligned;
          }
          if (out) {
            q.outTangent = handle;
          } else {
            q.inTangent = handle;
          }
          if (q.mode == SplineTangentMode.aligned && handle.lengthSquared > 0) {
            final mirrored = -(Vector3.copy(handle)..normalize()) * otherLength;
            if (out) {
              q.inTangent = mirrored;
            } else {
              q.outTangent = mirrored;
            }
          }
        });
      },
    );

    return [if (i > 0 || spline.closed) one(false), if (i < n - 1 || spline.closed) one(true)];
  }
}

/// Every spline in the level as a line — a bare path is otherwise unseen —
/// brighter and with its points when selected.
final class SplinesOverlay extends ViewportOverlay {
  @override
  String get id => 'worldBuilder.splines';

  @override
  String get label => 'Splines';

  @override
  Dimensions get dimensions => Dimensions.threeD;

  final Expando<(Object, List<Vector3>)> _samples = Expando();

  @override
  void paint(ViewportOverlayContext context) {
    final faint = Paint()
      ..color = const Color(0x9926A69A)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final bright = Paint()
      ..color = const Color(0xFF4DD0E1)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = const Color(0xFF4DD0E1);
    final world = Matrix4.identity();
    final at = Vector3.zero();
    for (final entity in context.world.query([Spline3D, TransformComponent])) {
      if (!context.isShown(entity)) continue;
      final spline = entity.getComponent<Spline3D>()!;
      final key = spline.shapeKey;
      final known = _samples[spline];
      final samples = known != null && known.$1 == key
          ? known.$2
          : (_samples[spline] = (key, SplinePath.of(spline, perSegment: 12).positions)).$2;
      entity.getComponent<TransformComponent>()!.localToWorldInto(world);
      final selected = context.isSelected(entity);
      Offset? last;
      for (final p in samples) {
        world.transformPointInto(p, at);
        final screen = context.project(at);
        if (screen != null && last != null) {
          context.canvas.drawLine(last, screen, selected ? bright : faint);
        }
        last = screen;
      }
      if (!selected) continue;
      for (final p in spline.points) {
        world.transformPointInto(p.position, at);
        final screen = context.project(at);
        if (screen != null) context.canvas.drawCircle(screen, 2.5, dot);
      }
    }
  }
}

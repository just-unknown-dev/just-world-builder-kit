import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';
import 'spline_path.dart';

/// Moves each [PathFollower3D] along its path's [Spline3D]: [speed] metres
/// a second, resting at the ends, looping, going back and forth or
/// stopping as its mode says. Runs before physics, so a kinematic body is
/// carried, and what stands on it with it.
///
/// Writes only the follower's transform and its runtime fields.
class PathFollower3DSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform;

  @override
  List<Type> get requiredComponents => const [TransformComponent, PathFollower3D];

  // Each spline's sampled path, while its shape stays the same.
  final Expando<(Object, SplinePath)> _paths = Expando();
  final Matrix4 _toWorld = Matrix4.identity();
  final Vector3 _point = Vector3.zero();
  final Vector3 _way = Vector3.zero();

  /// [spline]'s path, sampled again only when it changed.
  SplinePath pathOf(Spline3D spline) {
    final key = spline.shapeKey;
    final known = _paths[spline];
    if (known != null && known.$1 == key) return known.$2;
    final path = SplinePath.of(spline);
    _paths[spline] = (key, path);
    return path;
  }

  @override
  void update(double deltaTime) {
    for (final entity in entities) {
      if (!entity.isActive) continue;
      final f = entity.getComponent<PathFollower3D>()!;
      final owner = f.path.resolve(world, entity);
      if (owner == null || identical(owner, entity)) continue;
      final spline = owner.getComponent<Spline3D>();
      if (spline == null) continue;
      final path = pathOf(spline);
      if (path.isEmpty) continue;
      if (f.travelled.isNaN) {
        f
          ..travelled = path.closed ? f.startAt % path.length : f.startAt.clamp(0.0, path.length)
          ..direction = 1
          ..resting = 0;
      } else if (deltaTime > 0) {
        advance(f, path, deltaTime);
      }
      place(entity, f, owner, path);
    }
  }

  /// Moves [f] [deltaTime] seconds further along [path].
  static void advance(PathFollower3D f, SplinePath path, double deltaTime) {
    final length = path.length;
    if (f.speed <= 0) return;
    var time = deltaTime;
    if (f.resting > 0) {
      // Moving again only for what is left of the step once rested.
      if (f.resting > time + 1e-9) {
        f.resting -= time;
        return;
      }
      time -= f.resting;
      f.resting = 0;
    }
    f.travelled += f.direction * f.speed * time;
    switch (f.mode) {
      case FollowMode.loop:
        if (path.closed) {
          f.travelled %= length;
        } else if (f.travelled >= length) {
          f
            ..travelled = 0
            ..direction = 1
            ..resting = f.wait;
        }
      case FollowMode.pingPong:
        if (f.travelled >= length) {
          f
            ..travelled = length
            ..direction = -1
            ..resting = f.wait;
        } else if (f.travelled <= 0) {
          f
            ..travelled = 0
            ..direction = 1
            ..resting = f.wait;
        }
      case FollowMode.once:
        if (f.travelled >= length) {
          f
            ..travelled = length
            ..direction = 1;
        } else if (f.travelled < 0) {
          f.travelled = 0;
        }
    }
  }

  /// Puts [entity] where [f] is along [path], laid out by [owner].
  void place(Entity entity, PathFollower3D f, Entity owner, SplinePath path) {
    final t = entity.getComponent<TransformComponent>()!;
    final at = path.at(f.travelled);
    final ownerTransform = owner.getComponent<TransformComponent>();
    if (ownerTransform == null) {
      t.position.setFrom(at.position);
      _way.setFrom(at.tangent);
    } else {
      ownerTransform.localToWorldInto(_toWorld);
      _toWorld.transformPointInto(at.position, _point);
      t.position.setFrom(_point);
      _toWorld.transformDirectionInto(at.tangent, _way);
    }
    if (!f.faceAlong) return;
    final dx = _way.x * f.direction, dz = _way.z * f.direction;
    if (dx * dx + dz * dz < 1e-12) return;
    t.setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), math.atan2(dx, dz)));
  }
}

/// Ties each [SplineSweep3D] and [SplineInstances3D] to the [Spline3D] on
/// its entity, before physics, so a sweep is solid even where nothing
/// draws it. Writes only their runtime links.
class SplineLinkSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform + 1;

  @override
  List<Type> get requiredComponents => const [Spline3D];

  @override
  void update(double deltaTime) {
    for (final entity in entities) {
      final spline = entity.getComponent<Spline3D>()!;
      final sweep = entity.getComponent<SplineSweep3D>();
      if (sweep != null && !identical(sweep.spline, spline)) sweep.spline = spline;
      final instances = entity.getComponent<SplineInstances3D>();
      if (instances != null && !identical(instances.spline, spline)) instances.spline = spline;
    }
  }
}

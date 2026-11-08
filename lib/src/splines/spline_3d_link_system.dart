import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';

/// Ties each [SplineSweep3DComponent] and [SplineInstances3DComponent] to the [Spline3DComponent] on
/// its entity, before physics, so a sweep is solid even where nothing
/// draws it. Writes only their runtime links.
class Spline3DLinkSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform + 1;

  @override
  List<Type> get requiredComponents => const [Spline3DComponent];

  @override
  void update(double deltaTime) {
    for (final entity in entities) {
      final spline = entity.getComponent<Spline3DComponent>()!;
      final sweep = entity.getComponent<SplineSweep3DComponent>();
      if (sweep != null && !identical(sweep.spline, spline)) {
        sweep.spline = spline;
      }
      final instances = entity.getComponent<SplineInstances3DComponent>();
      if (instances != null && !identical(instances.spline, spline)) {
        instances.spline = spline;
      }
    }
  }
}

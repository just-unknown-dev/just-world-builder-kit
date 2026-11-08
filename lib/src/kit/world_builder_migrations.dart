import 'package:just_game_engine/just_game_engine.dart';

/// Levels saved with older versions of the kit, brought forward as they
/// load.
///
/// A renamed component goes in [renamedTypes], old name → new, and the
/// entries already there stay: the engine applies the table to every
/// scene, prefab and timeline it loads, whatever format they were saved
/// at (a scene saved at the newest format too), and follows a chain of
/// renames to the newest name. A definition needs no `aliases` for it.
abstract final class WorldBuilderMigrations {
  /// Adds the kit's renames to [context]'s migrations
  /// (`context.migrations`). Installing `WorldBuilderKit.extension` calls
  /// it, once per context.
  static void install(EngineContext context) {
    context.migrations.renamedTypes.addAll(renamedTypes);
  }

  /// The kit's components, old name → new.
  ///
  /// Scene format 11 renamed them, when every component's name came to end
  /// in `Component`.
  static const Map<String, String> renamedTypes = {
    'Scatter3D': 'Scatter3DComponent',
    'Spline3D': 'Spline3DComponent',
    'SplineSweep3D': 'SplineSweep3DComponent',
    'SplineInstances3D': 'SplineInstances3DComponent',
    'PathFollower3D': 'PathFollower3DComponent',
    'Terrain3D': 'Terrain3DComponent',
    'GridTiles3D': 'GridTiles3DComponent',
  };
}

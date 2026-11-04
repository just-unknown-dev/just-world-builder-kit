import 'package:just_game_engine/just_game_engine_3d.dart' show ContextRenderProviders;
import 'package:just_game_engine/just_game_engine.dart';

import 'splines/path_follower_system.dart';
import 'splines/spline_render.dart';
import 'splines/spline_definitions.dart';
import 'scatter/scatter_render.dart';
import 'scatter/scatter_definitions.dart';
import 'terrain/terrain_3d_component.dart';
import 'terrain/terrain_render.dart';
import 'terrain/terrain_definitions.dart';
import 'tiles/grid_render.dart';
import 'tiles/grid_tiles.dart';
import 'tiles/mesh_library.dart';
import 'tiles/tile_definitions.dart';

/// The world builder kit's front door.
///
/// ```dart
/// final engine = Engine(config: EngineConfig(
///   extensions: [WorldBuilderKit.extension],
///   graphics3D: Graphics3D(),
///   physics3D: Physics3D(),
/// ));
/// await engine.initialize();
/// WorldBuilderKit.registerSystems(engine.world);
/// await SceneLoader.loadAsset(engine.world, 'assets/scenes/level_01.scene.json');
/// await WorldBuilderKit.ready(engine.world);
/// engine.start();
/// ```
abstract final class WorldBuilderKit {
  /// Give it to the engine: the kit's components (saved, loaded, shown in
  /// the editor), field types and what draws them.
  static const ContextExtension extension = _WorldBuilderKitExtension();

  /// The id the kit's extension installs under.
  static const String id = 'just_world_builder_kit';

  /// Every component the kit saves.
  static List<ComponentDefinition> get definitions => [
    ...SplineDefinitions.all,
    ...TileDefinitions.all,
    ...TerrainDefinitions.all,
    ...ScatterDefinitions.all,
  ];

  /// The field types the kit's components save through.
  static List<FieldType> get fieldTypes => [
    SplineDefinitions.splinePoints,
    TileDefinitions.gridCells,
    ScatterDefinitions.layersType,
    ScatterDefinitions.instancesType,
  ];

  /// What [extension] does, for a context of your own.
  static void install(EngineContext context) {
    // Its levels use the engine's own components too.
    context.install(BuiltInComponents.extension);
    context.fieldTypes.registerAll(fieldTypes);
    context.definitions.registerAll(definitions, ifAbsent: true);
    context.migrations.renamedTypes.addAll(renamedTypes);
    registerRenderers(context);
  }

  /// The kit's components renamed in scene format 11, when every
  /// component's name came to end in `Component`: old name → new. Levels
  /// saved before are brought forward as they load.
  static const Map<String, String> renamedTypes = {
    'Scatter3D': 'Scatter3DComponent',
    'Spline3D': 'Spline3DComponent',
    'SplineSweep3D': 'SplineSweep3DComponent',
    'SplineInstances3D': 'SplineInstances3DComponent',
    'PathFollower3D': 'PathFollower3DComponent',
    'Terrain3D': 'Terrain3DComponent',
    'GridTiles3D': 'GridTiles3DComponent',
  };

  /// What draws the kit's pieces in 3-D.
  static void registerRenderers(EngineContext context) {
    context.renderProviders
      ..register(SweepRenderProvider())
      ..register(InstancesRenderProvider())
      ..register(GridTilesRenderProvider(context))
      ..register(TerrainRenderProvider(context))
      ..register(ScatterRenderProvider());
  }

  /// The kit's systems.
  static List<System> systems() => [SplineLinkSystem(), GridTilesLinkSystem(), TerrainLinkSystem(), PathFollower3DSystem()];

  /// Adds [systems] to [world].
  static void registerSystems(World world) {
    for (final system in systems()) {
      world.addSystem(system);
    }
  }

  /// The files [world]'s pieces read — each `Terrain3DComponent`'s `.jterrain`,
  /// each `GridTiles3DComponent`'s mesh library — read, and the pieces tied to
  /// them; the files no piece of [world] uses any more let go (changes not
  /// yet written are kept).
  ///
  /// Await it after loading a level and before the game runs: its ground
  /// and tiles are then solid from the first physics step. Without it they
  /// are read in the background once the game runs, and are not solid
  /// until they arrive. A file that cannot be read leaves its piece empty
  /// and says why (`TerrainFiles.errorOf`, `MeshLibraries.errorOf`).
  static Future<void> ready(World world) async {
    final terrains = [for (final e in world.query([Terrain3DComponent])) e.getComponent<Terrain3DComponent>()!];
    final grids = [for (final e in world.query([GridTiles3DComponent])) e.getComponent<GridTiles3DComponent>()!];
    final files = TerrainFiles.of(world.context);
    final libraries = MeshLibraries.of(world.context);
    files.releaseUnused([for (final t in terrains) t.data]);
    libraries.releaseUnused([for (final g in grids) g.library]);
    await Future.wait<Object?>([
      for (final path in {for (final t in terrains) t.data}) files.ready(path),
      for (final path in {for (final g in grids) g.library}) libraries.ready(path),
    ]);
    for (final t in terrains) {
      t.link(files);
    }
    for (final g in grids) {
      g.link(libraries);
    }
  }
}

final class _WorldBuilderKitExtension implements RefreshableExtension {
  const _WorldBuilderKitExtension();

  @override
  String get id => WorldBuilderKit.id;

  @override
  void install(EngineContext context) => WorldBuilderKit.install(context);

  @override
  void refresh(EngineContext context) {
    context.fieldTypes.registerAll(WorldBuilderKit.fieldTypes, override: true);
    context.definitions.refresh(WorldBuilderKit.definitions);
    WorldBuilderKit.registerRenderers(context);
  }
}

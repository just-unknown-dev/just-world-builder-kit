import 'package:just_game_engine/graphics_3d.dart' show RenderProviders;
import 'package:just_game_engine/just_game_engine.dart';

import 'splines/path_follower_system.dart';
import 'splines/spline_render.dart';
import 'splines/spline_schemas.dart';
import 'scatter/scatter_render.dart';
import 'scatter/scatter_schemas.dart';
import 'terrain/terrain_component.dart';
import 'terrain/terrain_render.dart';
import 'terrain/terrain_schemas.dart';
import 'tiles/grid_render.dart';
import 'tiles/grid_tiles.dart';
import 'tiles/mesh_library.dart';
import 'tiles/tile_schemas.dart';

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
  static List<ComponentSchema> get schemas => [
    ...SplineSchemas.all,
    ...TileSchemas.all,
    ...TerrainSchemas.all,
    ...ScatterSchemas.all,
  ];

  /// The field types the kit's components save through.
  static List<FieldType> get fieldTypes => [
    SplineSchemas.splinePoints,
    TileSchemas.gridCells,
    ScatterSchemas.layersType,
    ScatterSchemas.instancesType,
  ];

  /// What [extension] does, for a context of your own.
  static void install(EngineContext context) {
    context.fieldTypes.registerAll(fieldTypes);
    context.definitions.registerAll(schemas, ifAbsent: true);
    registerRenderers(context);
  }

  /// What draws the kit's pieces in 3-D.
  static void registerRenderers(EngineContext context) {
    RenderProviders.of(context)
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

  /// The files [world]'s pieces read — each `Terrain3D`'s `.jterrain`,
  /// each `GridTiles3D`'s mesh library — read, and the pieces tied to
  /// them; the files no piece of [world] uses any more let go (changes not
  /// yet written are kept).
  ///
  /// Await it after loading a level and before the game runs: its ground
  /// and tiles are then solid from the first physics step. Without it they
  /// are read in the background once the game runs, and are not solid
  /// until they arrive. A file that cannot be read leaves its piece empty
  /// and says why (`TerrainFiles.errorOf`, `MeshLibraries.errorOf`).
  static Future<void> ready(World world) async {
    final terrains = [for (final e in world.query([Terrain3D])) e.getComponent<Terrain3D>()!];
    final grids = [for (final e in world.query([GridTiles3D])) e.getComponent<GridTiles3D>()!];
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
    context.definitions.refresh(WorldBuilderKit.schemas);
    WorldBuilderKit.registerRenderers(context);
  }
}

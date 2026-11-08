import 'package:just_game_engine/just_game_engine_3d.dart'
    show ContextRenderProviders;
import 'package:just_game_engine/just_game_engine.dart';

import '../scatter/scatter.dart';
import '../splines/splines.dart';
import '../terrain/terrain.dart';
import '../tiles/tiles.dart';
import 'world_builder_migrations.dart';

/// The world builder kit's front door.
///
/// ```dart
/// final engine = Engine(config: EngineConfig(
///   extensions: [WorldBuilderKit.extension],
///   services: [Graphics3D(), Physics3D()],
/// ));
/// await engine.initialize();
/// WorldBuilderKit.registerSystems(engine.world);
/// await SceneLoader.loadAsset(engine.world, 'assets/scenes/level_01.scene.json');
/// await WorldBuilderKit.ready(engine.world);
/// engine.start();
/// ```
abstract final class WorldBuilderKit {
  /// Give it to the engine: the kit's components (saved, loaded, shown in
  /// the editor), field types, migrations and what draws them.
  static const ContextExtension extension = _WorldBuilderKitExtension();

  /// The id the kit's extension installs under.
  static const String id = 'just_world_builder_kit';

  /// Every component the kit saves.
  static List<ComponentDefinition> get definitions => [
    ...Spline3DDefinitions.all,
    ...GridTiles3DDefinitions.all,
    ...Terrain3DDefinitions.all,
    ...Scatter3DDefinitions.all,
  ];

  /// The field types the kit's components save through.
  static List<FieldType> get fieldTypes => [
    Spline3DDefinitions.splinePoints,
    GridTiles3DDefinitions.gridCells,
    Scatter3DDefinitions.layersType,
    Scatter3DDefinitions.instancesType,
  ];

  /// What [extension] does, for a context of your own.
  static void install(EngineContext context) {
    // Its levels use the engine's own components too.
    context.install(BuiltInComponents.extension);
    context.fieldTypes.registerAll(fieldTypes);
    context.definitions.registerAll(definitions, ifAbsent: true);
    // Levels saved by an older kit are brought forward as they load.
    WorldBuilderMigrations.install(context);
    registerRenderers(context);
  }

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
  static List<System> systems() => [
    Spline3DLinkSystem(),
    GridTiles3DLinkSystem(),
    Terrain3DLinkSystem(),
    PathFollower3DSystem(),
  ];

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
  /// until they arrive; the link systems let go of the files no piece uses
  /// any more either way. A file that cannot be read leaves its piece empty
  /// and says why (`TerrainFiles.errorOf`, `MeshLibraries.errorOf`).
  static Future<void> ready(World world) async {
    final terrains = [
      for (final e in world.query([Terrain3DComponent]))
        e.getComponent<Terrain3DComponent>()!,
    ];
    final grids = [
      for (final e in world.query([GridTiles3DComponent]))
        e.getComponent<GridTiles3DComponent>()!,
    ];
    final files = TerrainFiles.of(world.context);
    final libraries = MeshLibraries.of(world.context);
    files.releaseUnused([for (final t in terrains) t.data]);
    libraries.releaseUnused([for (final g in grids) g.library]);
    await Future.wait<Object?>([
      for (final path in {for (final t in terrains) t.data}) files.ready(path),
      for (final path in {for (final g in grids) g.library})
        libraries.ready(path),
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

  /// After a hot reload, in an editor: the field types, components and
  /// renderers as the code now makes them. The migrations, which append,
  /// are left as installed.
  @override
  void refresh(EngineContext context) {
    context.fieldTypes.registerAll(WorldBuilderKit.fieldTypes, override: true);
    context.definitions.refresh(WorldBuilderKit.definitions);
    WorldBuilderKit.registerRenderers(context);
  }
}

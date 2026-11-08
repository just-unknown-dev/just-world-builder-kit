import 'package:just_game_engine/just_game_engine.dart';

import 'grid_tiles_3d_component.dart';
import 'mesh_libraries.dart';

/// Ties each [GridTiles3DComponent] to its mesh library, before physics, so
/// its tiles are solid even where nothing draws them; and, whenever the
/// libraries the world's grids use change (a level unloaded, another
/// loaded), lets go of the ones none uses any more
/// ([MeshLibraries.releaseUnused]). Writes only the grids' runtime links.
class GridTiles3DLinkSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform + 1;

  @override
  List<Type> get requiredComponents => const [GridTiles3DComponent];

  // What the grids used last step: their libraries' hashes folded
  // together, with how many there were.
  int? _used;

  @override
  void update(double deltaTime) {
    final libraries = MeshLibraries.of(world.context);
    var used = 17;
    var count = 0;
    for (final entity in entities) {
      final tiles = entity.getComponent<GridTiles3DComponent>()!
        ..link(libraries);
      used = (used * 31 + tiles.library.hashCode) & 0x3FFFFFFF;
      count++;
    }
    used = (used * 31 + count) & 0x3FFFFFFF;
    if (used == _used) return;
    _used = used;
    libraries.releaseUnused([
      for (final e in entities) e.getComponent<GridTiles3DComponent>()!.library,
    ]);
  }
}

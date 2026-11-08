import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_3d_component.dart';
import 'terrain_files.dart';

/// Ties each [Terrain3DComponent] to its file, before physics, so it is
/// solid even where nothing draws it; and, whenever the files the world's
/// terrains use change (a level unloaded, another loaded), lets go of the
/// ones none uses any more ([TerrainFiles.releaseUnused]). Writes only the
/// terrains' runtime links.
class Terrain3DLinkSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform + 1;

  @override
  List<Type> get requiredComponents => const [Terrain3DComponent];

  // What the terrains used last step: their files' hashes folded
  // together, with how many there were.
  int? _used;

  @override
  void update(double deltaTime) {
    final files = TerrainFiles.of(world.context);
    var used = 17;
    var count = 0;
    for (final entity in entities) {
      final terrain = entity.getComponent<Terrain3DComponent>()!..link(files);
      used = (used * 31 + terrain.data.hashCode) & 0x3FFFFFFF;
      count++;
    }
    used = (used * 31 + count) & 0x3FFFFFFF;
    if (used == _used) return;
    _used = used;
    files.releaseUnused([
      for (final e in entities) e.getComponent<Terrain3DComponent>()!.data,
    ]);
  }
}

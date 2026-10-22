/// World building for just_game_engine in 3D: the pieces a level is built
/// from, and what draws them and makes them solid.
///
/// [WorldBuilderKit] installs it all. The Level Designer's tools that make
/// them are in `package:just_world_builder_kit/editor.dart`, which this
/// library never imports.
library;

export 'src/scatter/scatter_brush.dart';
export 'src/scatter/scatter_components.dart';
export 'src/scatter/scatter_render.dart';
export 'src/scatter/scatter_schemas.dart';
export 'src/splines/path_follower_system.dart';
export 'src/splines/spline_components.dart';
export 'src/splines/spline_path.dart';
export 'src/splines/spline_render.dart';
export 'src/splines/spline_schemas.dart';
export 'src/splines/spline_sweep.dart';
export 'src/terrain/terrain_brush.dart';
export 'src/terrain/terrain_component.dart';
export 'src/terrain/terrain_data.dart';
export 'src/terrain/terrain_mesher.dart';
export 'src/terrain/terrain_render.dart';
export 'src/terrain/terrain_schemas.dart';
export 'src/tiles/grid_orientations.dart';
export 'src/tiles/grid_render.dart';
export 'src/tiles/grid_tiles.dart';
export 'src/tiles/mesh_library.dart';
export 'src/tiles/tile_schemas.dart';
export 'src/world_builder_kit.dart';

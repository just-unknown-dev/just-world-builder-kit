/// The design-time half of the world builder kit: the Level Designer's
/// **World Builder** — blockout, and the tools for the kit's pieces — in
/// 3-D scenes.
///
/// Kept out of `just_world_builder_kit.dart` so the runtime library carries
/// no dependency on the editor. Import this only from a debug entry point.
///
/// ```dart
/// JustGameEditorPlugin.register(engine: engine, modules: [WorldBuilderModule()]);
/// ```
library;

export 'src/editor/blockout_tools.dart';
export 'src/editor/scatter_inspector.dart';
export 'src/editor/scatter_tools.dart';
export 'src/editor/spline_handles.dart';
export 'src/editor/spline_inspector.dart';
export 'src/editor/mesh_library_workspace.dart';
export 'src/editor/spline_tools.dart';
export 'src/editor/terrain_tools.dart';
export 'src/editor/tile_panel.dart';
export 'src/editor/tile_tools.dart';
export 'src/editor/world_builder_picks.dart';
export 'src/editor/world_builder_module.dart';

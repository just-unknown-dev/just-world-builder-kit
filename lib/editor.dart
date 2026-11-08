/// The design-time half of the world builder kit: the Level Designer's
/// **World Builder** — blockout, and the tools for the kit's pieces — in
/// 3-D scenes.
///
/// Builds on `just_editor_core` alone, and is kept out of
/// `just_world_builder_kit.dart` so the runtime library carries no
/// dependency on the editor. Import this only from a debug entry point.
///
/// ```dart
/// await JustGameEditorPlugin.register(engine: engine, modules: [WorldBuilderModule()]);
/// ```
library;

export 'src/editor/editor.dart';

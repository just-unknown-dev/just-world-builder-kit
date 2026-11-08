import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../tiles/tiles.dart';
import 'tile_tools.dart';
import 'tool_parts.dart';
import 'world_builder_files.dart';

/// The designer's Tiles panel: which library, which piece, how it is
/// turned.
SidePanelSection tilesPanel(
  GridTileTool? Function() tool,
  WorldBuilderFiles files,
) => SidePanelSection(
  id: 'worldBuilder.tiles',
  title: 'TILES',
  order: 30,
  groups: const {tilesGroup},
  build: (context, session) {
    final t = tool();
    if (t == null) return const SizedBox.shrink();
    return _TilesPanel(tool: t, session: session, files: files);
  },
);

class _TilesPanel extends StatefulWidget {
  const _TilesPanel({
    required this.tool,
    required this.session,
    required this.files,
  });

  final GridTileTool tool;
  final DesignerSession session;
  final WorldBuilderFiles files;

  @override
  State<_TilesPanel> createState() => _TilesPanelState();
}

class _TilesPanelState extends State<_TilesPanel> {
  List<String> _found = const [];
  Object? _createError;

  GridTileTool get _tool => widget.tool;

  MeshLibraries get _libraries =>
      MeshLibraries.of(widget.session.world.context);

  @override
  void initState() {
    super.initState();
    // A library read again (saved in its workspace, let go) shows its
    // pieces as they now are.
    _libraries.changes.addListener(_changed);
    _list(chooseFirst: _tool.library.value.isEmpty);
  }

  @override
  void dispose() {
    _libraries.changes.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The project's libraries, read off the UI thread; the first chosen
  /// when [chooseFirst] and none is.
  Future<void> _list({bool chooseFirst = false}) async {
    final found = await widget.files.libraries();
    if (!mounted) return;
    setState(() => _found = found);
    if (chooseFirst && _tool.library.value.isEmpty && found.isNotEmpty) {
      _choose(found.first);
    }
  }

  /// Paints from [path], read when it is not yet: an open panel never
  /// reads a library twice.
  void _choose(String path) {
    _tool.library.value = path;
    _libraries.ready(path);
  }

  Future<void> _create() async {
    try {
      final path = await widget.files.create(
        widget.session.world.context.definitions,
      );
      if (!mounted) return;
      _createError = null;
      await _list();
      _choose(path);
    } on Object catch (error) {
      if (mounted) setState(() => _createError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
    return SignalBuilder<String>(
      signal: _tool.library,
      builder: (context, path, _) {
        // Asked for, it starts loading; [changes] says when it is in.
        final library = _libraries.get(path);
        final error = _libraries.errorOf(path) ?? _createError;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _found.isEmpty
                        ? Text('No mesh libraries yet', style: muted)
                        : EditorDropdown<String>(
                            value: _found.contains(path) ? path : null,
                            hint: 'Choose a library',
                            tooltip: 'The mesh library painted from',
                            options: [
                              for (final f in _found)
                                EditorDropdownOption(
                                  value: f,
                                  label: f.split('/').last,
                                  detail: f.substring(
                                    0,
                                    f.lastIndexOf('/') + 1,
                                  ),
                                ),
                            ],
                            onChanged: _choose,
                          ),
                  ),
                  EditorIconButton(
                    icon: Icons.add,
                    tooltip: 'New mesh library',
                    onTap: _create,
                  ),
                ],
              ),
              if (error != null)
                Text(
                  identical(error, _createError)
                      ? 'Could not make a library: $error'
                      : (library == null
                            ? 'Could not read it: $error'
                            : 'A piece of it could not be made: $error'),
                  style: TextStyle(color: EditorTheme.error, fontSize: 11),
                ),
              if (library != null) ...[
                const SizedBox(height: 6),
                SignalBuilder<int>(
                  signal: _tool.item,
                  builder: (context, chosen, _) => Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final item in library.items)
                        EditorChip(
                          label: item.name.isEmpty
                              ? 'Piece ${item.id}'
                              : item.name,
                          selected: item.id == chosen,
                          onTap: () {
                            _tool.item.value = item.id;
                            widget.session.setTool(GridTileTool.toolId);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SignalBuilder<int>(
                  signal: _tool.orientation,
                  builder: (context, turn, _) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Turn $turn of ${GridOrientations.count}  ·  ${library.cellSize} m cells',
                          style: muted,
                        ),
                      ),
                      EditorIconButton(
                        icon: Icons.rotate_right,
                        tooltip: 'Turn about up (Z)',
                        onTap: () => _tool.orientation.value =
                            GridOrientations.turned(turn, 1),
                      ),
                      EditorIconButton(
                        icon: Icons.screen_rotation_alt,
                        tooltip: 'Tip over (X)',
                        onTap: () => _tool.orientation.value =
                            GridOrientations.turned(turn, 0),
                      ),
                      EditorIconButton(
                        icon: Icons.restart_alt,
                        tooltip: 'As made',
                        onTap: () => _tool.orientation.value = 0,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The cells the Tiles tool would change, as a box's edges: blue to
/// paint, red to erase.
class GridTilePreviewOverlay extends DesignerOverlay {
  GridTilePreviewOverlay(this.tool);

  final GridTileTool? Function() tool;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'worldBuilder.tilePreview';

  @override
  String get label => 'Tile preview';

  @override
  IconData get icon => Icons.grid_view;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(OverlayPaintContext context) {
    final t = tool();
    if (t == null || context.controller.toolId.value != GridTileTool.toolId) {
      return;
    }
    final p = t.preview.value;
    if (p == null) return;
    final view = context.draw.camera;
    final paint = Paint()
      ..color = p.erasing ? const Color(0xFFEF5350) : const Color(0xFF4FC3F7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final s = p.cellSize;
    final lo = Vector3(
      (p.from.x < p.to.x ? p.from.x : p.to.x) * s,
      (p.from.y < p.to.y ? p.from.y : p.to.y) * s,
      (p.from.z < p.to.z ? p.from.z : p.to.z) * s,
    );
    final hi = Vector3(
      ((p.from.x > p.to.x ? p.from.x : p.to.x) + 1) * s,
      ((p.from.y > p.to.y ? p.from.y : p.to.y) + 1) * s,
      ((p.from.z > p.to.z ? p.from.z : p.to.z) + 1) * s,
    );
    Offset? corner(int i) {
      final local = Vector3(
        i & 1 == 0 ? lo.x : hi.x,
        i & 2 == 0 ? lo.y : hi.y,
        i & 4 == 0 ? lo.z : hi.z,
      );
      final world = Vector3.zero();
      p.toWorld.transformPointInto(local, world);
      return view.projectToScreen(world);
    }

    paintBoxEdges(context.draw.canvas, [
      for (var i = 0; i < 8; i++) corner(i),
    ], paint);
  }
}

/// The inspector's row for a [GridTiles3DComponent]'s cells: how many.
Widget gridCellsEditor(FieldEditorContext context) {
  final cells = context.value is Map ? (context.value! as Map).length : 0;
  return ReadonlyFieldRow(
    label: context.hint.label ?? 'Tiles',
    value: '$cells tile${cells == 1 ? '' : 's'} — paint with the Tiles tool',
  );
}

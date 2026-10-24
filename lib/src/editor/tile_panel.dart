import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../tiles/grid_orientations.dart';
import '../tiles/grid_tiles.dart';
import '../tiles/mesh_library.dart';
import 'tile_tools.dart';

/// The project's mesh libraries, and making new ones, for the Tiles
/// panel: files under [root] (the project folder).
final class MeshLibraryFiles {
  MeshLibraryFiles([String? root]) : root = (root ?? Directory.current.path).replaceAll(r'\', '/');

  /// The project folder.
  final String root;

  /// Every `.meshlib.json` under `assets/`, project-relative.
  List<String> list() {
    final assets = Directory('$root/assets');
    if (!assets.existsSync()) return const [];
    return [
      for (final f in assets.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith(MeshLibrary.ending)) f.path.replaceAll(r'\', '/').substring(root.length + 1),
    ]..sort();
  }

  /// A new library of the engine's shapes in `assets/tiles/` — `tiles`, or
  /// `tiles_2` and on — and its path.
  Future<String> create(ComponentDefinitionRegistry definitions) async {
    var n = 1;
    String pathOf(int n) => 'assets/tiles/tiles${n == 1 ? '' : '_$n'}${MeshLibrary.ending}';
    while (await File('$root/${pathOf(n)}').exists()) {
      n++;
    }
    final path = pathOf(n);
    final file = File('$root/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(MeshLibrary.starter(definitions).encode());
    return path;
  }
}

/// The designer's Tiles panel: which library, which piece, how it is
/// turned.
SidePanelSection tilesPanel(GridTileTool? Function() tool, MeshLibraryFiles files) => SidePanelSection(
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
  const _TilesPanel({required this.tool, required this.session, required this.files});

  final GridTileTool tool;
  final DesignerSession session;
  final MeshLibraryFiles files;

  @override
  State<_TilesPanel> createState() => _TilesPanelState();
}

class _TilesPanelState extends State<_TilesPanel> {
  late List<String> _found = widget.files.list();

  GridTileTool get _tool => widget.tool;

  MeshLibraries get _libraries => MeshLibraries.of(widget.session.world.context);

  @override
  void initState() {
    super.initState();
    if (_tool.library.value.isEmpty && _found.isNotEmpty) _choose(_found.first);
  }

  void _choose(String path) {
    _tool.library.value = path;
    _libraries.load(path).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _create() async {
    final path = await widget.files.create(widget.session.world.context.definitions);
    if (!mounted) return;
    setState(() => _found = widget.files.list());
    _choose(path);
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
    return SignalBuilder<String>(
      signal: _tool.library,
      builder: (context, path, _) {
        final library = _libraries.get(path);
        final error = _libraries.errorOf(path);
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
                                  detail: f.substring(0, f.lastIndexOf('/') + 1),
                                ),
                            ],
                            onChanged: _choose,
                          ),
                  ),
                  EditorIconButton(icon: Icons.add, tooltip: 'New mesh library', onTap: _create),
                ],
              ),
              if (error != null)
                Text(
                  library == null ? 'Could not read it: $error' : 'A piece of it could not be made: $error',
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
                          label: item.name.isEmpty ? 'Piece ${item.id}' : item.name,
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
                      Expanded(child: Text('Turn $turn of ${GridOrientations.count}  ·  ${library.cellSize} m cells', style: muted)),
                      EditorIconButton(
                        icon: Icons.rotate_right,
                        tooltip: 'Turn about up (Z)',
                        onTap: () => _tool.orientation.value = GridOrientations.turned(turn, 1),
                      ),
                      EditorIconButton(
                        icon: Icons.screen_rotation_alt,
                        tooltip: 'Tip over (X)',
                        onTap: () => _tool.orientation.value = GridOrientations.turned(turn, 0),
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
    if (t == null || context.controller.toolId.value != GridTileTool.toolId) return;
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
      final local = Vector3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z);
      final world = Vector3.zero();
      p.toWorld.transformPointInto(local, world);
      return view.projectToScreen(world);
    }

    final corners = [for (var i = 0; i < 8; i++) corner(i)];
    for (final (a, b) in const [
      (0, 1), (2, 3), (4, 5), (6, 7),
      (0, 2), (1, 3), (4, 6), (5, 7),
      (0, 4), (1, 5), (2, 6), (3, 7),
    ]) {
      final from = corners[a], to = corners[b];
      if (from != null && to != null) context.draw.canvas.drawLine(from, to, paint);
    }
  }
}

/// The inspector's row for a [GridTiles3D]'s cells: how many.
Widget gridCellsEditor(FieldEditorContext context) {
  final cells = context.value is Map ? (context.value! as Map).length : 0;
  return ReadonlyRow(label: context.hint.label ?? 'Tiles', value: '$cells tile${cells == 1 ? '' : 's'} — paint with the Tiles tool');
}

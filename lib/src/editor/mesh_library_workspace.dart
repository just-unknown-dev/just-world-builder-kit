import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../tiles/mesh_library.dart';

/// A mesh library's pieces (`*.meshlib.json`): the workspace one opens in.
/// Add a shape or a model, name it, say how it is solid, nudge it in its
/// cell. Its edits have an undo of their own; Save writes the file, and
/// every grid using it changes.
class MeshLibraryWorkspace extends StatefulWidget {
  const MeshLibraryWorkspace({
    super.key,
    required this.path,
    required this.root,
    required this.definitions,
    required this.workspace,
    this.loadOnStart = true,
  });

  /// The library, project-relative.
  final String path;

  /// The project folder.
  final String root;

  /// Turns a shape piece into its saved form and back.
  final ComponentDefinitionRegistry definitions;

  /// The editor's handle on the workspace.
  final WorkspaceContext workspace;

  /// Whether it reads the file as it opens; a test calls
  /// [MeshLibraryWorkspaceState.load] itself instead.
  final bool loadOnStart;

  @override
  State<MeshLibraryWorkspace> createState() => MeshLibraryWorkspaceState();
}

/// The shapes a piece can be, made to fill a cell of [size].
final List<(String, Primitive3D Function(double size))> meshLibraryShapes = [
  ('Block', (s) => Cube3D(width: s, height: s, depth: s)),
  ('Ramp', (s) => Ramp3D(width: s, height: s, depth: s)),
  ('Stairs', (s) => Stairs3D(width: s, height: s, depth: s, steps: 4)),
  ('Pillar', (s) => Cylinder3D(radius: s * 0.15, height: s)),
  ('Arch', (s) => Arch3D(radius: s / 2, thickness: s * 0.15, depth: s)),
];

/// The state of a [MeshLibraryWorkspace]; public for tests.
class MeshLibraryWorkspaceState extends State<MeshLibraryWorkspace> {
  String _saved = '';
  final List<MeshLibrary> _history = [MeshLibrary()];
  int _at = 0;
  Object? _error;

  /// The library being edited.
  MeshLibrary get library => _history[_at];

  /// Whether it differs from the file.
  bool get dirty => library.encode() != _saved;

  File get _file => File('${widget.root}/${widget.path}');

  @override
  void initState() {
    super.initState();
    widget.workspace.setCloseGuard?.call(() async => mayLeaveUnsaved(context, dirty: dirty, save: save));
    if (widget.loadOnStart) load();
  }

  /// Reads the file.
  Future<void> load() async {
    try {
      final text = await _file.readAsString();
      final read = MeshLibrary.parse(text);
      if (!mounted) return;
      setState(() {
        _saved = read.encode();
        _history
          ..clear()
          ..add(read);
        _at = 0;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Changes the library as one undo step: [change] edits a copy.
  void edit(void Function(MeshLibrary library) change) {
    final next = library.copy();
    change(next);
    setState(() {
      _history
        ..removeRange(_at + 1, _history.length)
        ..add(next);
      _at = _history.length - 1;
    });
  }

  void undo() {
    if (_at > 0) setState(() => _at--);
  }

  void redo() {
    if (_at < _history.length - 1) setState(() => _at++);
  }

  /// Writes the file; whether it went through.
  Future<bool> save() async {
    final text = library.encode();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(text);
      setState(() => _saved = text);
      widget.workspace.reloadAssets?.call(widget.path);
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
  }

  /// Adds a shape piece, filling a cell.
  void addShape(String name, Primitive3D Function(double size) make) => edit((l) {
    l.items.add(
      MeshLibraryItem(
        id: l.takeId(),
        name: name,
        shape: Map<String, Object?>.from(widget.definitions.encode(make(l.cellSize))!),
        collision: name == 'Block' ? PieceCollision.box : PieceCollision.shape,
      ),
    );
  });

  /// Adds a model piece.
  void addModel(String model) => edit((l) {
    l.items.add(
      MeshLibraryItem(id: l.takeId(), name: model.split('/').last.split('.').first, model: model),
    );
  });

  List<String> _models() {
    final assets = Directory('${widget.root}/assets');
    if (!assets.existsSync()) return const [];
    final root = widget.root.replaceAll(r'\', '/');
    return [
      for (final f in assets.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.glb') || f.path.endsWith('.gltf')) f.path.replaceAll(r'\', '/').substring(root.length + 1),
    ]..sort();
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
    return ColoredBox(
      color: EditorTheme.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHeader(
            icon: Icons.grid_view,
            title: 'Mesh library',
            file: widget.path.split('/').last,
            dirty: dirty,
            onSave: save,
            onUndo: _at > 0 ? undo : null,
            onRedo: _at < _history.length - 1 ? redo : null,
            fullScreen: widget.workspace.fullScreen,
            onToggleFullScreen: widget.workspace.onToggleFullScreen,
            onClose: widget.workspace.onClose,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$_error', style: TextStyle(color: EditorTheme.error, fontSize: 11)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Text('Cells', style: muted),
                const SizedBox(width: 8),
                for (final size in const [1.0, 2.0, 3.0, 4.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: EditorChip(
                      label: '${size.toInt()} m',
                      selected: library.cellSize == size,
                      onTap: () => edit((l) => l.cellSize = size),
                    ),
                  ),
                const Spacer(),
                PopupMenuButton<int>(
                  tooltip: 'Add a shape',
                  color: EditorTheme.menuBg,
                  onSelected: (i) => addShape(meshLibraryShapes[i].$1, meshLibraryShapes[i].$2),
                  itemBuilder: (context) => [
                    for (final (i, (name, _)) in meshLibraryShapes.indexed)
                      editorMenuItem(i, name),
                  ],
                  child: Padding(padding: const EdgeInsets.all(6), child: Text('+ Shape', style: muted)),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Add a model',
                  color: EditorTheme.menuBg,
                  onSelected: addModel,
                  itemBuilder: (context) {
                    final models = _models();
                    return [
                      if (models.isEmpty)
                        editorMenuItem('', 'No models in assets/', enabled: false),
                      for (final m in models) editorMenuItem(m, m),
                    ];
                  },
                  child: Padding(padding: const EdgeInsets.all(6), child: Text('+ Model', style: muted)),
                ),
              ],
            ),
          ),
          const EditorDivider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                if (library.items.isEmpty)
                  const EditorEmptyState(icon: Icons.grid_view, title: 'No pieces yet', hint: 'Add a shape or a model.'),
                for (final (i, item) in library.items.indexed) _row(i, item, muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int index, MeshLibraryItem item, TextStyle muted) {
    final kind = item.model.isNotEmpty ? item.model : (item.shape?['type'] as String? ?? 'shape');
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('${item.id}', style: muted)),
          SizedBox(
            width: 140,
            child: TextFormField(
              key: ValueKey('name${item.id}$_at'),
              initialValue: item.name,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              onFieldSubmitted: (v) => edit((l) => l.item(item.id)!.name = v.trim()),
            ),
          ),
          Expanded(child: Text(kind, style: muted, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 110,
            child: EditorDropdown<PieceCollision>(
              value: item.collision,
              tooltip: 'How it is solid',
              options: [
                for (final c in PieceCollision.values)
                  EditorDropdownOption(
                    value: c,
                    label: switch (c) {
                      PieceCollision.none => 'Not solid',
                      PieceCollision.box => 'Solid cell',
                      PieceCollision.shape => 'Solid shape',
                    },
                  ),
              ],
              onChanged: (c) => edit((l) => l.item(item.id)!.collision = c),
            ),
          ),
          EditorIconButton(
            icon: Icons.arrow_upward,
            tooltip: 'Up in its cell',
            onTap: () => edit((l) => l.item(item.id)!.offset.y -= l.cellSize / 8),
          ),
          EditorIconButton(
            icon: Icons.arrow_downward,
            tooltip: 'Down in its cell',
            onTap: () => edit((l) => l.item(item.id)!.offset.y += l.cellSize / 8),
          ),
          EditorIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove (tiles of it are left empty; its number is never given to another piece)',
            onTap: () => edit((l) => l.remove(item.id)),
          ),
        ],
      ),
    );
  }
}

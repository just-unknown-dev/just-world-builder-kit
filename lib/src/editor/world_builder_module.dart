import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../scatter/scatter.dart';
import '../splines/splines.dart';
import '../terrain/terrain.dart';
import '../tiles/tiles.dart';
import 'blockout_tools.dart';
import 'mesh_library_workspace.dart';
import 'scatter_inspector.dart';
import 'scatter_tools.dart';
import 'spline_handles.dart';
import 'spline_inspector.dart';
import 'spline_tools.dart';
import 'terrain_tools.dart';
import 'tile_panel.dart';
import 'tile_tools.dart';
import 'tool_parts.dart';
import 'world_builder_files.dart';
import 'world_builder_picks.dart';

/// The world builder kit in the editor: a Level Designer kit for 3-D
/// scenes ("World Builder" in its switch) whose tools build a level's
/// shape — blockout, splines, grid tiles, terrain, scatter — with the handles,
/// overlays, panels, inspector pieces and workspaces for what they make.
/// Terrain files are read from the project and written as the scene is
/// saved.
///
/// Design-time only; see `package:just_world_builder_kit/editor.dart`.
class WorldBuilderModule extends EditorModule {
  /// The tools of the designer session now open, for their previews.
  final List<LevelToolHandler> _tools = [];

  EditorScope? _scope;

  /// The kit's tools for a project in [root] (the working folder when
  /// null).
  WorldBuilderModule({String? root}) : files = WorldBuilderFiles(root);

  /// The project's mesh libraries and models; [WorldBuilderFiles.root] is
  /// the project folder terrain files are read from and written to.
  final WorldBuilderFiles files;

  /// The workspace a mesh library opens in.
  static const String meshLibraryWorkspaceId = 'worldBuilder.meshLibrary';

  @override
  void onRegister(EditorModuleContext context) {
    _scope = context.scope;
    // The project's terrain files, not the bundle's.
    TerrainFiles.of(context.scope.context).read = (path) =>
        File('${files.root}/$path').readAsBytes();
  }

  GridTileTool? _tileTool() => _tools.whereType<GridTileTool>().firstOrNull;

  TerrainSculptTool? _terrainTool() =>
      _tools.whereType<TerrainSculptTool>().firstOrNull;

  ScatterTool? _scatterTool() => _tools.whereType<ScatterTool>().firstOrNull;

  /// The terrains of the scene being saved, written with it: each file
  /// changed since it was last written.
  ///
  /// A file that cannot be written leaves the others to be written all
  /// the same, stays unsaved, and fails the save with what went wrong
  /// ([TerrainSaveException]). A file changed while it was written (a
  /// stroke ending meanwhile) stays unsaved too: what was written is not
  /// what it is now.
  @override
  Future<void> onSceneSaving(String sceneName) async {
    final scope = _scope;
    if (scope == null) return;
    final terrainFiles = TerrainFiles.of(scope.context);
    final used = {
      for (final e in scope.world.query([Terrain3DComponent]))
        e.getComponent<Terrain3DComponent>()!.data,
    };
    final failed = <String, Object>{};
    for (final path in terrainFiles.unsaved.where(used.contains).toList()) {
      final data = terrainFiles.get(path);
      if (data == null) continue;
      final revision = data.revision;
      try {
        final file = File('${files.root}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data.encode());
      } on Object catch (error) {
        failed[path] = error;
        continue;
      }
      if (data.revision == revision) terrainFiles.saved(path);
    }
    if (failed.isNotEmpty) throw TerrainSaveException(failed);
  }

  /// Another scene, or this one again: terrain changes never saved are
  /// dropped with the rest of its changes, and the files the scene left
  /// behind are let go.
  @override
  void onSceneOpened(String sceneName) {
    final scope = _scope;
    if (scope == null) return;
    final terrainFiles = TerrainFiles.of(scope.context);
    for (final path in terrainFiles.unsaved.toList()) {
      terrainFiles.forget(path);
    }
    terrainFiles.releaseUnused([
      for (final e in scope.world.query([Terrain3DComponent]))
        e.getComponent<Terrain3DComponent>()!.data,
    ]);
    MeshLibraries.of(scope.context).releaseUnused([
      for (final e in scope.world.query([GridTiles3DComponent]))
        e.getComponent<GridTiles3DComponent>()!.library,
    ]);
  }

  @override
  String get id => 'world_builder';

  @override
  String get name => 'World Builder';

  @override
  IconData? get icon => Icons.landscape_outlined;

  /// A kit for the Level Designer in 3-D scenes.
  @override
  Set<SceneMode> get designerModes => const {SceneMode.threeD};

  @override
  List<ToolGroup> get toolGroups => const [
    ToolGroup(id: blockoutGroup, label: 'BLOCKOUT', order: 15),
    ToolGroup(id: splineGroup, label: 'SPLINES', order: 16),
    ToolGroup(id: tilesGroup, label: 'TILES', order: 17),
    ToolGroup(id: terrainGroup, label: 'TERRAIN', order: 18),
    ToolGroup(id: scatterGroup, label: 'SCATTER', order: 19),
  ];

  @override
  List<LevelToolHandler> createTools(DesignerToolContext context) {
    _tools
      ..clear()
      ..addAll([
        BlockTool(context),
        FloorTool(context),
        RampTool(context),
        SplineTool(context),
        GridTileTool(context),
        TerrainSculptTool(context),
        ScatterTool(context),
      ]);
    return List.of(_tools);
  }

  @override
  List<DesignerOverlay> get overlays => [
    BlockoutPreviewOverlay(() => _tools),
    GridTilePreviewOverlay(_tileTool),
    TerrainBrushOverlay(_terrainTool),
    ScatterBrushOverlay(_scatterTool),
  ];

  @override
  List<SidePanelSection> get designerPanels => [
    tilesPanel(_tileTool, files),
    terrainPanel(_terrainTool, root: files.root),
    scatterPanel(_scatterTool, files),
  ];

  @override
  List<ViewportOverlay> get viewportOverlays => [SplinesOverlay()];

  @override
  List<ViewportHandles> get viewportHandles => [SplineHandles()];

  @override
  List<EntityRayTest> get pickTests => const [WorldBuilderRayTest()];

  @override
  Map<String, FieldEditorBuilder> get fieldEditors => const {
    SplinePointsFieldType.typeId: splinePointsEditor,
    GridCellsFieldType.typeId: gridCellsEditor,
    ScatterLayersFieldType.typeId: scatterLayersEditor,
    ScatterInstancesFieldType.typeId: scatterInstancesEditor,
  };

  /// The mesh library kind: `.meshlib.json`, opened in its workspace.
  static const AssetKind meshLibraryKind = AssetKind(
    'meshLibrary',
    'Mesh libraries',
    icon: Icons.grid_view,
    color: Color(0xFF26A69A),
    endings: [MeshLibrary.ending],
    filterable: true,
  );

  @override
  List<AssetKind> get assetKinds => const [meshLibraryKind];

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: meshLibraryWorkspaceId,
      label: 'Mesh library',
      icon: Icons.grid_view,
      fileExtensions: const ['meshlib.json'],
      build: (context, workspace) => MeshLibraryWorkspace(
        path: workspace.path!,
        files: files,
        definitions: workspace.scope.context.definitions,
        workspace: workspace,
      ),
    ),
  ];

  /// A mesh library saved: read again by what draws and collides with it.
  /// A library or a model changed: the panels' lists are read again.
  @override
  void onAssetChanged(String path) {
    if (path.endsWith(MeshLibrary.ending) ||
        path.endsWith('.glb') ||
        path.endsWith('.gltf')) {
      files.refresh();
    }
    if (!path.endsWith(MeshLibrary.ending)) return;
    final scope = _scope;
    if (scope != null) MeshLibraries.of(scope.context).forget(path);
  }

  @override
  List<InspectorSection> get inspectorSections => [splineSection()];
}

/// What a blockout tool would make, before it is made: a box's edges, an
/// outline, or a slope's line.
class BlockoutPreviewOverlay extends DesignerOverlay {
  BlockoutPreviewOverlay(this.tools);

  /// The tools now open.
  final List<LevelToolHandler> Function() tools;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'worldBuilder.blockoutPreview';

  @override
  String get label => 'Blockout preview';

  @override
  IconData get icon => Icons.check_box_outline_blank;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(OverlayPaintContext context) {
    final active = context.controller.toolId.value;
    BlockoutPreview? preview;
    for (final tool in tools()) {
      if (tool.id != active) continue;
      preview = switch (tool) {
        BlockTool t => t.preview.value,
        FloorTool t => t.preview.value,
        RampTool t => t.preview.value,
        SplineTool t => t.preview.value,
        _ => null,
      };
    }
    if (preview == null) return;
    final view = context.draw.camera;
    final canvas = context.draw.canvas;
    final paint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    void line(Vector3 a, Vector3 b) {
      final p = view.projectToScreen(a), q = view.projectToScreen(b);
      if (p != null && q != null) canvas.drawLine(p, q, paint);
    }

    if (preview.box case final box?) {
      Offset? corner(int i) => view.projectToScreen(
        Vector3(
          i & 1 == 0 ? box.min.x : box.max.x,
          i & 2 == 0 ? box.min.y : box.max.y,
          i & 4 == 0 ? box.min.z : box.max.z,
        ),
      );
      paintBoxEdges(canvas, [for (var i = 0; i < 8; i++) corner(i)], paint);
    }
    final outline = preview.outline;
    for (var i = 0; i + 1 < outline.length; i++) {
      line(outline[i], outline[i + 1]);
    }
    if (preview.closed && outline.length > 2) line(outline.last, outline.first);
    for (final p in preview.markers) {
      final at = view.projectToScreen(p);
      if (at != null) {
        canvas.drawCircle(at, 3, Paint()..color = const Color(0xFF4FC3F7));
      }
    }
    if (preview.line case (final a, final b)) line(a, b);
  }
}

/// Terrain files a scene's save could not write, by path: what each threw.
/// They stay unsaved, to be written by the next save.
final class TerrainSaveException implements Exception {
  const TerrainSaveException(this.failed);

  /// What writing each file threw, by its project-relative path.
  final Map<String, Object> failed;

  @override
  String toString() =>
      'Could not write ${failed.length == 1 ? 'a terrain file' : '${failed.length} terrain files'}: '
      '${[for (final MapEntry(:key, :value) in failed.entries) '$key ($value)'].join('; ')}';
}

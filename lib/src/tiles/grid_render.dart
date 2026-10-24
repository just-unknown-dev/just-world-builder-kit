import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'grid_orientations.dart';
import 'grid_tiles.dart';
import 'mesh_library.dart';

/// Draws a [GridTiles3D]: each item's tiles in batches, one per item for
/// each block of [chunkCells]³ cells, so blocks out of sight are skipped.
/// Built again when its cells, its library or a model it shows changes.
final class GridTilesRenderProvider extends RenderProvider<GridTiles3D> {
  GridTilesRenderProvider(this.context);

  /// The engine the libraries are loaded for.
  final EngineContext context;

  /// How many cells along each side a batch covers.
  static const int chunkCells = 8;

  GraphicsModels? _models;

  MeshLibraries get _libraries => MeshLibraries.of(context);

  @override
  Object? revisionOf(GridTiles3D c) => (
    c.revision,
    c.library,
    c.castShadows,
    c.maxDistance,
    _libraries.revision,
    _modelsReady(c),
  );

  /// How many of the models [c]'s library shows are loaded: a count that
  /// changes as they arrive.
  int _modelsReady(GridTiles3D c) {
    final library = c.loaded, models = _models;
    if (library == null || models == null) return 0;
    var ready = 0;
    for (final item in library.items) {
      if (item.model.isNotEmpty && models.get(item.model) != null) ready++;
    }
    return ready;
  }

  @override
  void build(RenderProviderContext ctx, Entity entity, GridTiles3D c, RenderProviderOutput out) {
    _models = ctx.models;
    c.link(_libraries);
    final library = c.loaded;
    if (library == null || c.cells.isEmpty) return;
    final reach = c.maxDistance <= 0 ? double.infinity : c.maxDistance;
    for (final MapEntry(key: item, value: places) in placements(c, library).entries) {
      final piece = library.item(item);
      if (piece == null) continue;
      final parts = _partsOf(ctx, c.library, piece);
      for (final chunk in places.values) {
        for (final (primitive, material, local) in parts) {
          out.addBatch(
            primitive,
            material,
            [for (final m in chunk) local == null ? m : m.multiplied(local)],
            maxDistance: reach,
            castShadows: c.castShadows,
          );
        }
      }
    }
  }

  /// What [item], of the library at [path], draws: its model's parts, or
  /// its shape.
  List<(GpuPrimitive, GpuMaterial, Matrix4?)> _partsOf(RenderProviderContext ctx, String path, MeshLibraryItem item) {
    if (item.model.isNotEmpty) {
      final model = ctx.models.get(item.model);
      if (model == null) return const [];
      return [for (final part in RenderScene().addModel(model, Matrix4.identity())) (part.primitive, part.material, part.world)];
    }
    final shape = _libraries.shapeOf(path, item);
    if (shape == null) return const [];
    final mesh = ctx.shapes.meshFor(shape, Vector3(1, 1, 1));
    if (mesh == null) return const [];
    return [(mesh, ctx.shapes.materialFor(shape), null)];
  }

  /// Where each of [c]'s tiles goes, in its entity's space: by item, then
  /// by block of cells.
  static Map<int, Map<int, List<Matrix4>>> placements(GridTiles3D c, MeshLibrary library) {
    final size = library.cellSize;
    final out = <int, Map<int, List<Matrix4>>>{};
    // By id, once: not a search of the items for every cell.
    final items = {for (final i in library.items) i.id: i};
    for (final MapEntry(:key, :value) in c.cells.entries) {
      final tile = GridTiles3D.unpack(value);
      final item = items[tile.item];
      if (item == null) continue;
      final cell = GridTiles3D.cellOf(key);
      final block = GridTiles3D.keyOf(
        (cell.x / chunkCells).floor(),
        (cell.y / chunkCells).floor(),
        (cell.z / chunkCells).floor(),
      );
      ((out[tile.item] ??= {})[block] ??= []).add(matrixOf(cell, tile.orientation, item, size));
    }
    return out;
  }

  /// Where a tile of [item] in [cell], turned [orientation], is drawn.
  static Matrix4 matrixOf(GridCell cell, int orientation, MeshLibraryItem item, double cellSize) {
    final at = GridTiles3D.centreOf(cell.x, cell.y, cell.z, cellSize) + GridOrientations.apply(orientation, item.offset);
    return Matrix4.identity()..setFromTrs(at, GridOrientations.of(orientation), Vector3(item.scale, item.scale, item.scale));
  }
}

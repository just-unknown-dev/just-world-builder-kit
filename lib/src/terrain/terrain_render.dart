import 'dart:math' as math;

import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_component.dart';
import 'terrain_data.dart';
import 'terrain_mesher.dart';

/// Draws a [Terrain3D] in chunks, each made again only when a sample in it
/// changed: with its layered material file when it has one (the layers'
/// weights in the vertex colour), else in its layers' colours mixed.
final class TerrainRenderProvider extends RenderProvider<Terrain3D> {
  TerrainRenderProvider(this.context);

  /// The engine the files are loaded for.
  final EngineContext context;

  TerrainFiles get _files => TerrainFiles.of(context);

  MaterialLibrary? _library;
  ModelUploader? _uploader;
  GpuMaterial? _plain;

  // Chunks built, by terrain and place: what they were built from, and
  // what was uploaded.
  final Expando<Map<(int, int), (Object, GpuPrimitive?)>> _chunks = Expando();

  @override
  Object? revisionOf(Terrain3D t) => (
    identityHashCode(t.loaded),
    t.loaded?.revision,
    t.size,
    t.material,
    Object.hashAll([for (final c in t.colors) c.toARGB32()]),
    t.chunkCells,
    t.castShadows,
    _files.revision,
    t.material.isEmpty ? null : _library?.revision,
  );

  @override
  void build(RenderProviderContext ctx, Entity entity, Terrain3D t, RenderProviderOutput out) {
    t.link(_files);
    final data = t.loaded;
    if (data == null) return;
    if (!identical(_uploader, ctx.uploader)) {
      _uploader = ctx.uploader;
      _plain = null;
    }
    _library = ctx.shapes.library;
    final layered = t.material.isEmpty ? null : _library?.gpuOf(t.material);
    final material = layered ?? (_plain ??= ctx.uploader.material(const MaterialData(metallic: 0, roughness: 0.95)));
    final cells = t.chunkCells.clamp(8, 128);
    final perSide = TerrainMesher.chunksPerSide(data.resolution, cells);
    final cache = _chunks[data] ??= {};
    final mode = (layered != null, t.size, cells, Object.hashAll([for (final c in t.colors) c.toARGB32()]));
    for (var cz = 0; cz < perSide; cz++) {
      for (var cx = 0; cx < perSide; cx++) {
        final key = (mode, chunkRevision(data, cx, cz, cells));
        final known = cache[(cx, cz)];
        GpuPrimitive? primitive;
        if (known != null && known.$1 == key) {
          primitive = known.$2;
        } else {
          final mesh = TerrainMesher.chunk(
            data,
            cx: cx,
            cz: cz,
            chunkCells: cells,
            size: t.size,
            colors: layered == null ? t.colors : null,
          );
          primitive = mesh.triangleCount == 0
              ? null
              : ctx.uploader.uploadPrimitive(
                  PrimitiveData(vertices: mesh.vertices, indices: mesh.indices, material: 0, bounds: mesh.bounds, hasTangents: false),
                );
          cache[(cx, cz)] = (key, primitive);
        }
        if (primitive != null) out.addMesh(primitive, material, castShadows: t.castShadows);
      }
    }
  }

  /// What chunk ([cx], [cz]) of [cells] cells is built from: its blocks'
  /// revisions.
  static int chunkRevision(TerrainData data, int cx, int cz, int cells) {
    final last = data.resolution - 1;
    final i0 = cx * cells, j0 = cz * cells;
    final i1 = math.min(i0 + cells, last), j1 = math.min(j0 + cells, last);
    var h = 17;
    for (final (bx, bz) in data.blocksIn(i0, j0, i1, j1)) {
      h = Object.hash(h, data.blockRevision(bx, bz));
    }
    return h;
  }
}

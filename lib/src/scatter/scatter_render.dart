import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'scatter_components.dart';

/// Draws a [Scatter3D]: each layer's pieces in batches, one for each
/// square of its cells, not drawn beyond the layer's reach. A layer with
/// no model shows its shape, in its colour.
final class ScatterRenderProvider extends RenderProvider<Scatter3D> {
  ScatterRenderProvider();

  GraphicsModels? _models;

  @override
  Object? revisionOf(Scatter3D c) => (c.revision, c.castShadows, c.cellSize, _modelsReady(c));

  /// How many of [c]'s layers' models are loaded: a count that changes as
  /// they arrive.
  int _modelsReady(Scatter3D c) {
    final models = _models;
    if (models == null) return 0;
    var ready = 0;
    for (final l in c.layers) {
      if (l.model.isNotEmpty && models.get(l.model) != null) ready++;
    }
    return ready;
  }

  @override
  void build(RenderProviderContext ctx, Entity entity, Scatter3D c, RenderProviderOutput out) {
    _models = ctx.models;
    if (c.instances.isEmpty) return;
    for (final MapEntry(key: layer, value: cells) in placements(c).entries) {
      final l = c.layers[layer];
      final parts = _partsOf(ctx, l);
      final reach = l.maxDistance <= 0 ? double.infinity : l.maxDistance;
      for (final matrices in cells.values) {
        for (final (primitive, material, local) in parts) {
          out.addBatch(
            primitive,
            material,
            [for (final m in matrices) local == null ? m : m.multiplied(local)],
            maxDistance: reach,
            castShadows: c.castShadows,
          );
        }
      }
    }
  }

  List<(GpuPrimitive, GpuMaterial, Matrix4?)> _partsOf(RenderProviderContext ctx, ScatterLayer l) {
    if (l.model.isNotEmpty) {
      final model = ctx.models.get(l.model);
      if (model == null) return const [];
      return [for (final part in RenderScene().addModel(model, Matrix4.identity())) (part.primitive, part.material, part.world)];
    }
    final (shape, height) = shapeOf(l);
    final mesh = ctx.shapes.meshFor(shape, Vector3(1, 1, 1));
    if (mesh == null) return const [];
    // Standing on its spot: its middle half its height up (+Y is down).
    return [
      (
        mesh,
        ctx.shapes.materialFor(shape),
        Matrix4.identity()..setFromTrs(Vector3(0, -height / 2, 0), Quaternion.identity(), Vector3(1, 1, 1)),
      ),
    ];
  }

  /// The shape [layer]'s pieces are without a model, and how tall it is.
  static (Primitive3D, double) shapeOf(ScatterLayer layer) => switch (layer.shape) {
    ScatterShape.cone => (Cone3D(radius: 0.4, height: 1.2, color: layer.color), 1.2),
    ScatterShape.cube => (Cube3D(width: 0.8, height: 0.8, depth: 0.8, color: layer.color), 0.8),
    ScatterShape.sphere => (Sphere3D(radius: 0.45, color: layer.color), 0.9),
    ScatterShape.cylinder => (Cylinder3D(radius: 0.3, height: 1.2, color: layer.color), 1.2),
    ScatterShape.capsule => (Capsule3D(radius: 0.3, height: 1.2, color: layer.color), 1.2),
  };

  /// Where [c]'s pieces are drawn, in its entity's space: by layer, then
  /// by square.
  static Map<int, Map<(int, int), List<Matrix4>>> placements(Scatter3D c) {
    final size = c.cellSize <= 0 ? 32.0 : c.cellSize;
    final out = <int, Map<(int, int), List<Matrix4>>>{};
    for (final i in c.instances) {
      if (i.layer < 0 || i.layer >= c.layers.length) continue;
      final square = ((i.position.x / size).floor(), (i.position.z / size).floor());
      ((out[i.layer] ??= {})[square] ??= []).add(i.matrix(lean: c.layers[i.layer].alignToNormal));
    }
    return out;
  }
}

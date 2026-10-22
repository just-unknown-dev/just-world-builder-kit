import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'scatter_components.dart';

/// How [Scatter3D] is saved, loaded and shown, in the group "World
/// Builder".
abstract final class ScatterSchemas {
  static const ScatterLayersFieldType layersType = ScatterLayersFieldType();
  static const ScatterInstancesFieldType instancesType = ScatterInstancesFieldType();

  /// Every one.
  static List<ComponentSchema> get all => [scatter];

  /// [Scatter3D].
  static ComponentSchema<Scatter3D> get scatter => ComponentSchema<Scatter3D>(
    type: 'Scatter3D',
    id: 'scatter_3d_a91f0d64',
    create: Scatter3D.new,
    extent: const _ScatterExtent(),
    hints: const ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Scatter 3D',
      group: 'World Builder',
      description: 'Grass, flowers, rocks, trees scattered over the ground with the Scatter brush; layers that say so are solid through a Collider 3D set to match its shape.',
      icon: Icons.grass,
      accentColor: Color(0xFF26A69A),
      fields: {
        'layers': FieldHint(label: 'Layers', description: 'Edit them in the Scatter panel.', editable: false),
        'instances': FieldHint(label: 'Pieces', description: 'Paint them with the Scatter brush.', editable: false),
        'cellSize': FieldHint(label: 'Squares', description: 'Metres a side of each square its pieces are drawn in.', scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'm')),
        'castShadows': FieldHint(label: 'Shadows'),
      },
    ),
    fields: [
      SchemaField(
        name: 'layers',
        kind: layersType,
        read: (c) => [for (final l in (c as Scatter3D).layers) l.copy()],
        write: (c, v) {
          final s = c as Scatter3D;
          s
            ..layers = [for (final l in (v as List?) ?? const []) l is ScatterLayer ? l.copy() : ScatterLayer.fromJson(l)]
            ..revision += 1;
        },
      ),
      SchemaField(
        name: 'instances',
        kind: instancesType,
        read: (c) => List<ScatterInstance>.of((c as Scatter3D).instances),
        write: (c, v) {
          final s = c as Scatter3D;
          s
            ..instances = List<ScatterInstance>.of((v as List?)?.cast<ScatterInstance>() ?? const [])
            ..revision += 1;
        },
      ),
      SchemaField(
        name: 'cellSize',
        kind: FieldTypes.decimal,
        read: (c) => (c as Scatter3D).cellSize,
        write: (c, v) {
          final s = c as Scatter3D;
          s
            ..cellSize = (v as num).toDouble().clamp(4.0, 512.0)
            ..revision += 1;
        },
      ),
      SchemaField(
        name: 'castShadows',
        kind: FieldTypes.boolean,
        read: (c) => (c as Scatter3D).castShadows,
        write: (c, v) => (c as Scatter3D).castShadows = v as bool,
      ),
    ],
  );
}

/// Scattered pieces take up the box round them, a little more.
final class _ScatterExtent extends ComponentExtent {
  const _ScatterExtent();

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    if (!boundsInto(component, b)) return null;
    return Size(b.max.x - b.min.x, b.max.y - b.min.y);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final s = component as Scatter3D;
    if (s.instances.isEmpty) return false;
    out.setEmpty();
    for (final i in s.instances) {
      final p = i.position, r = i.scale;
      out
        ..addXYZ(p.x - r, p.y - 2 * r, p.z - r)
        ..addXYZ(p.x + r, p.y, p.z + r);
    }
    return true;
  }
}

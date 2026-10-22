import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_component.dart';

/// How [Terrain3D] is saved, loaded and shown, in the group "World
/// Builder".
abstract final class TerrainSchemas {
  /// Every one.
  static List<ComponentSchema> get all => [terrain];

  static bool _ownColours(Component c) => (c as Terrain3D).material.isEmpty;

  /// [Terrain3D].
  static ComponentSchema<Terrain3D> get terrain => ComponentSchema<Terrain3D>(
    type: 'Terrain3D',
    id: 'terrain_3d_3c8e51a6',
    create: Terrain3D.new,
    extent: const _TerrainExtent(),
    hints: const ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Terrain 3D',
      group: 'World Builder',
      description: 'Ground shaped by hand — hills, paths, holes — kept in a .jterrain file beside the scene. Shape it with the Terrain tool; solid through a Collider 3D set to match its shape.',
      icon: Icons.terrain,
      accentColor: Color(0xFF26A69A),
      fields: {
        'data': FieldHint(
          label: 'File',
          description: 'Its heights and layers. Terrains sharing a file share their ground.',
          fileExtensions: ['jterrain'],
        ),
        'size': FieldHint(label: 'Size', scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'm')),
        'resolution': FieldHint(label: 'Samples', description: 'Samples a side of a new file; the file\'s own once it has one.', editable: false),
        'material': FieldHint(
          label: 'Material',
          description: 'A layered material file: its four layers are the terrain\'s. Empty for the colours below.',
          fileExtensions: ['material.json'],
        ),
        'layer1': FieldHint(label: 'Layer 1', visibleWhen: _ownColours),
        'layer2': FieldHint(label: 'Layer 2', visibleWhen: _ownColours),
        'layer3': FieldHint(label: 'Layer 3', visibleWhen: _ownColours),
        'layer4': FieldHint(label: 'Layer 4', visibleWhen: _ownColours),
        'chunkCells': FieldHint(label: 'Chunk', description: 'Cells a side of each piece it is drawn in.'),
        'castShadows': FieldHint(label: 'Shadows'),
      },
    ),
    fields: [
      SchemaField(
        name: 'data',
        kind: FieldTypes.assetRef,
        read: (c) => (c as Terrain3D).data,
        write: (c, v) => (c as Terrain3D).data = v as String? ?? '',
      ),
      SchemaField(
        name: 'size',
        kind: FieldTypes.decimal,
        read: (c) => (c as Terrain3D).size,
        write: (c, v) => (c as Terrain3D).size = math.max(1, (v as num).toDouble()),
      ),
      SchemaField(
        name: 'resolution',
        kind: FieldTypes.integer,
        read: (c) => (c as Terrain3D).resolution,
        write: (c, v) => (c as Terrain3D).resolution = (v as num).toInt().clamp(2, 4097),
      ),
      SchemaField(
        name: 'material',
        kind: FieldTypes.assetRef,
        read: (c) => (c as Terrain3D).material,
        write: (c, v) => (c as Terrain3D).material = v as String? ?? '',
      ),
      for (var l = 0; l < 4; l++)
        SchemaField(
          name: 'layer${l + 1}',
          kind: FieldTypes.color,
          read: (c) => (c as Terrain3D).colors[l],
          write: (c, v) {
            final t = c as Terrain3D;
            t.colors = [...t.colors]..[l] = v as Color;
          },
        ),
      SchemaField(
        name: 'chunkCells',
        kind: FieldTypes.integer,
        read: (c) => (c as Terrain3D).chunkCells,
        write: (c, v) => (c as Terrain3D).chunkCells = (v as num).toInt().clamp(8, 128),
      ),
      SchemaField(
        name: 'castShadows',
        kind: FieldTypes.boolean,
        read: (c) => (c as Terrain3D).castShadows,
        write: (c, v) => (c as Terrain3D).castShadows = v as bool,
      ),
    ],
  );
}

/// A terrain takes up its square, from its lowest ground to its highest.
final class _TerrainExtent extends ComponentExtent {
  const _TerrainExtent();

  @override
  Size? sizeOf(Component component) {
    final t = component as Terrain3D;
    return Size(t.size, t.size);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final t = component as Terrain3D;
    final half = t.size / 2;
    final (low, high) = t.loaded?.heightRange ?? (0.0, 0.0);
    // +Y is down: the highest ground is the most negative y.
    out.setValues(-half, -high - 0.05, -half, half, -low + 0.05, half);
    return true;
  }

}

/// Ties each [Terrain3D] to its file, before physics, so it is solid even
/// where nothing draws it. Writes only its runtime link.
class TerrainLinkSystem extends System {
  @override
  int get priority => SystemPriorities.movingPlatform + 1;

  @override
  List<Type> get requiredComponents => const [Terrain3D];

  @override
  void update(double deltaTime) {
    final files = TerrainFiles.of(world.context);
    for (final entity in entities) {
      entity.getComponent<Terrain3D>()!.link(files);
    }
  }
}

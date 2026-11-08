import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_3d_component.dart';

/// How [Terrain3DComponent] is saved, loaded and shown, in the group "World
/// Builder".
abstract final class Terrain3DDefinitions {
  /// Every one.
  static List<ComponentDefinition> get all => [terrain];

  static bool _ownColors(Component c) =>
      (c as Terrain3DComponent).material.isEmpty;

  /// [Terrain3DComponent].
  static ComponentDefinition<Terrain3DComponent>
  get terrain => ComponentDefinition<Terrain3DComponent>(
    type: 'Terrain3DComponent',
    id: 'terrain_3d_3c8e51a6',
    create: Terrain3DComponent.new,
    extent: const _TerrainExtent(),
    hints: const ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Terrain 3D',
      group: 'World Builder',
      description:
          'Ground shaped by hand — hills, paths, holes — kept in a .jterrain file beside the scene. Shape it with the Terrain tool; solid through a Collider 3D set to match its shape.',
      icon: Icons.terrain,
      accentColor: Color(0xFF26A69A),
      fields: {
        'data': FieldHint(
          label: 'File',
          description:
              'Its heights and layers. Terrains sharing a file share their ground.',
          fileExtensions: ['jterrain'],
        ),
        'size': FieldHint(
          label: 'Size',
          scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'm'),
        ),
        'resolution': FieldHint(
          label: 'Samples',
          description:
              'Samples a side of a new file; the file\'s own once it has one.',
          editable: false,
        ),
        'material': FieldHint(
          label: 'Material',
          description:
              'A layered material file: its four layers are the terrain\'s. Empty for the colours below.',
          fileExtensions: ['material.json'],
        ),
        'layer1': FieldHint(label: 'Layer 1', visibleWhen: _ownColors),
        'layer2': FieldHint(label: 'Layer 2', visibleWhen: _ownColors),
        'layer3': FieldHint(label: 'Layer 3', visibleWhen: _ownColors),
        'layer4': FieldHint(label: 'Layer 4', visibleWhen: _ownColors),
        'chunkCells': FieldHint(
          label: 'Chunk',
          description: 'Cells a side of each piece it is drawn in.',
        ),
        'castShadows': FieldHint(label: 'Shadows'),
      },
    ),
    fields: [
      FieldDefinition(
        name: 'data',
        kind: FieldTypes.assetRef,
        read: (c) => (c as Terrain3DComponent).data,
        write: (c, v) => (c as Terrain3DComponent).data = v as String? ?? '',
      ),
      FieldDefinition(
        name: 'size',
        kind: FieldTypes.decimal,
        read: (c) => (c as Terrain3DComponent).size,
        write: (c, v) =>
            (c as Terrain3DComponent).size = math.max(1, (v as num).toDouble()),
      ),
      FieldDefinition(
        name: 'resolution',
        kind: FieldTypes.integer,
        read: (c) => (c as Terrain3DComponent).resolution,
        write: (c, v) => (c as Terrain3DComponent).resolution = (v as num)
            .toInt()
            .clamp(2, 4097),
      ),
      FieldDefinition(
        name: 'material',
        kind: FieldTypes.assetRef,
        read: (c) => (c as Terrain3DComponent).material,
        write: (c, v) =>
            (c as Terrain3DComponent).material = v as String? ?? '',
      ),
      for (var l = 0; l < 4; l++)
        FieldDefinition(
          name: 'layer${l + 1}',
          kind: FieldTypes.color,
          read: (c) => (c as Terrain3DComponent).colors[l],
          write: (c, v) {
            final t = c as Terrain3DComponent;
            t.colors = [...t.colors]..[l] = v as Color;
          },
        ),
      FieldDefinition(
        name: 'chunkCells',
        kind: FieldTypes.integer,
        read: (c) => (c as Terrain3DComponent).chunkCells,
        write: (c, v) => (c as Terrain3DComponent).chunkCells = (v as num)
            .toInt()
            .clamp(8, 128),
      ),
      FieldDefinition(
        name: 'castShadows',
        kind: FieldTypes.boolean,
        read: (c) => (c as Terrain3DComponent).castShadows,
        write: (c, v) => (c as Terrain3DComponent).castShadows = v as bool,
      ),
    ],
  );
}

/// A terrain takes up its square, from its lowest ground to its highest.
final class _TerrainExtent extends ComponentExtent {
  const _TerrainExtent();

  @override
  Size? sizeOf(Component component) {
    final t = component as Terrain3DComponent;
    return Size(t.size, t.size);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final t = component as Terrain3DComponent;
    final half = t.size / 2;
    final (low, high) = t.loaded?.heightRange ?? (0.0, 0.0);
    // +Y is down: the highest ground is the most negative y.
    out.setValues(-half, -high - 0.05, -half, half, -low + 0.05, half);
    return true;
  }
}

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'grid_cells_field_type.dart';
import 'grid_tiles_3d_component.dart';

/// How [GridTiles3DComponent] is saved, loaded and shown, in the group "World
/// Builder".
abstract final class GridTiles3DDefinitions {
  /// The cells' type.
  static const GridCellsFieldType gridCells = GridCellsFieldType();

  /// Every one.
  static List<ComponentDefinition> get all => [gridTiles];

  /// [GridTiles3DComponent].
  static ComponentDefinition<GridTiles3DComponent>
  get gridTiles => ComponentDefinition<GridTiles3DComponent>(
    type: 'GridTiles3DComponent',
    id: 'grid_tiles_3d_7f02c6b9',
    create: GridTiles3DComponent.new,
    extent: const _TilesExtent(),
    hints: const ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Grid Tiles 3D',
      group: 'World Builder',
      description:
          'Tiles in a 3-D grid — floors, walls, ramps from a mesh library — painted with the Tiles tool. Solid through a Collider 3D set to match its shape.',
      icon: Icons.grid_view,
      accentColor: Color(0xFF26A69A),
      fields: {
        'library': FieldHint(
          label: 'Library',
          description: 'The mesh library its pieces come from.',
          fileExtensions: ['meshlib.json'],
        ),
        'cells': FieldHint(
          label: 'Tiles',
          description: 'Paint them with the Tiles tool.',
          editable: false,
        ),
        'castShadows': FieldHint(label: 'Shadows'),
        'maxDistance': FieldHint(
          label: 'Reach',
          description:
              'Not drawn beyond this far from the camera; 0 for always.',
          scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'm'),
        ),
      },
    ),
    fields: [
      FieldDefinition(
        name: 'library',
        kind: FieldTypes.assetRef,
        read: (c) => (c as GridTiles3DComponent).library,
        write: (c, v) {
          final tiles = c as GridTiles3DComponent;
          tiles
            ..library = v as String? ?? ''
            ..revision += 1;
        },
      ),
      FieldDefinition(
        name: 'cells',
        kind: gridCells,
        read: (c) => Map<int, int>.of((c as GridTiles3DComponent).cells),
        write: (c, v) {
          final tiles = c as GridTiles3DComponent;
          tiles
            ..cells = Map<int, int>.of(
              (v as Map?)?.cast<int, int>() ?? const {},
            )
            ..revision += 1;
        },
      ),
      FieldDefinition(
        name: 'castShadows',
        kind: FieldTypes.boolean,
        read: (c) => (c as GridTiles3DComponent).castShadows,
        write: (c, v) => (c as GridTiles3DComponent).castShadows = v as bool,
      ),
      FieldDefinition(
        name: 'maxDistance',
        kind: FieldTypes.decimal,
        read: (c) => (c as GridTiles3DComponent).maxDistance,
        write: (c, v) =>
            (c as GridTiles3DComponent).maxDistance = (v as num).toDouble(),
      ),
    ],
  );
}

/// Tiles take up the box round their cells.
final class _TilesExtent extends ComponentExtent {
  const _TilesExtent();

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    if (!boundsInto(component, b)) return null;
    return Size(b.max.x - b.min.x, b.max.y - b.min.y);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final tiles = component as GridTiles3DComponent;
    if (tiles.cells.isEmpty) return false;
    final size = tiles.loaded?.cellSize ?? 2;
    out.setEmpty();
    for (final key in tiles.cells.keys) {
      final c = GridTiles3DComponent.cellOf(key);
      out
        ..addXYZ(c.x * size, c.y * size, c.z * size)
        ..addXYZ((c.x + 1) * size, (c.y + 1) * size, (c.z + 1) * size);
    }
    return true;
  }
}

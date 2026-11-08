import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_data.dart';
import 'terrain_files.dart';

/// Ground to walk on, shaped by hand: hills, valleys, paths painted in,
/// holes cut — [size] metres a side about its entity, its heights and
/// layers kept in a `.jterrain` file ([data]) beside the scene. Drawn by
/// the kit's renderer in chunks; solid, through a `Collider3DComponent` set to
/// match its shape, as a height field.
///
/// Up to four layers show: the four colour layers of a layered material
/// file ([material]), or else [colors].
class Terrain3DComponent extends Component implements SolidShapeSource {
  Terrain3DComponent({
    this.data = '',
    this.size = 64,
    this.resolution = 129,
    this.material = '',
    List<Color>? colors,
    this.chunkCells = 32,
    this.castShadows = true,
  }) : colors = colors ?? List.of(defaultColors);

  /// The layers' colours without a material: grass, earth, rock, sand.
  static const List<Color> defaultColors = [
    Color(0xFF6B8E3D),
    Color(0xFF8B6B4A),
    Color(0xFF8C8C8C),
    Color(0xFFD8C79A),
  ];

  /// Its file (`.jterrain`), project-relative.
  String data;

  /// Metres a side.
  double size;

  /// Samples a side of a new file; the file's own once it has one.
  int resolution;

  /// A layered material file (`.material.json`) whose four layers it
  /// shows; empty for [colors].
  String material;

  /// Four layers' colours, used without a [material].
  List<Color> colors;

  /// Cells a side of each piece it is drawn in.
  int chunkCells;

  /// Whether it casts shadows on what is under and beside it.
  bool castShadows;

  /// Runtime: its ground, once loaded, linked by whoever draws or collides
  /// it ([link]).
  TerrainData? loaded;

  (Object, List<SolidPart>)? _solid;

  /// Ties it to its file in [files] — loading it, the first time.
  void link(TerrainFiles files) => loaded = files.get(data);

  /// Metres between samples.
  double get cellSize {
    final n = loaded?.resolution ?? resolution;
    return n < 2 ? size : size / (n - 1);
  }

  /// Where sample (0, 0) is: its corner, the entity in its middle.
  double get origin => -size / 2;

  /// Its ground (which terrains sharing a file share), how far it is done,
  /// and its size: terrains on one file and of one size are the same solid.
  @override
  Object get solidKey => (loaded?.identity, loaded?.solidRevision, size);

  @override
  List<SolidPart> get solidParts {
    final ground = loaded;
    if (ground == null) return const [];
    final key = solidKey;
    final known = _solid;
    if (known != null && known.$1 == key) return known.$2;
    final heights = Float32List.fromList(ground.heights);
    if (ground.hasHoles) {
      final n = ground.resolution;
      for (var j = 0; j < n; j++) {
        for (var i = 0; i < n; i++) {
          if (ground.isHole(i, j)) {
            heights[ground.index(i, j)] = SolidHeightField.holeHeight;
          }
        }
      }
    }
    final parts = [
      SolidHeightField(
        heights,
        ground.resolution,
        cellSize,
        x: origin,
        z: origin,
      ),
    ];
    _solid = (key, parts);
    return parts;
  }
}

import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_data.dart';

/// Ground to walk on, shaped by hand: hills, valleys, paths painted in,
/// holes cut — [size] metres a side about its entity, its heights and
/// layers kept in a `.jterrain` file ([data]) beside the scene. Drawn by
/// the kit's renderer in chunks; solid, through a `Collider3D` set to
/// match its shape, as a height field.
///
/// Up to four layers show: the four colour layers of a layered material
/// file ([material]), or else [colors].
class Terrain3D extends Component implements SolidShapeSource {
  Terrain3D({
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

  @override
  Object get solidKey => (identityHashCode(loaded), loaded?.solidRevision, size);

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
          if (ground.isHole(i, j)) heights[ground.index(i, j)] = SolidHeightField.holeHeight;
        }
      }
    }
    final parts = [SolidHeightField(heights, ground.resolution, cellSize, x: origin, z: origin)];
    _solid = (key, parts);
    return parts;
  }
}

/// The terrain files one engine has loaded — shared by every terrain
/// using one, and changed in place by the editor — read through [read]:
/// the game's bundle, unless an editor points it at the project.
final class TerrainFiles {
  TerrainFiles(this.context) : read = ((path) async {
    final data = await context.bundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });

  /// The files of [context], made on first use.
  static TerrainFiles of(EngineContext context) => context.slot(TerrainFiles, () => TerrainFiles(context));

  final EngineContext context;

  /// Reads a file's bytes.
  Future<Uint8List> Function(String path) read;

  final Map<String, TerrainData?> _loaded = {};
  final Map<String, Future<TerrainData?>> _loading = {};
  final Map<String, Object> _errors = {};
  final Set<String> _unsaved = {};
  int _revision = 0;

  /// Bumped whenever one finishes loading or is replaced.
  int get revision => _revision;

  /// The ground at [path] once loaded, or null while it loads (it starts
  /// loading) or when it could not be read.
  TerrainData? get(String path) {
    if (path.isEmpty) return null;
    if (_loaded.containsKey(path)) return _loaded[path];
    load(path);
    return null;
  }

  /// Why the file at [path] could not be read, if it could not.
  Object? errorOf(String path) => _errors[path];

  /// Loads the file at [path].
  Future<TerrainData?> load(String path) => _loading[path] ??= () async {
    try {
      final data = TerrainData.decode(await read(path));
      _loaded[path] = data;
      _errors.remove(path);
      return data;
    } on Object catch (e) {
      _loaded[path] = null;
      _errors[path] = e;
      return null;
    } finally {
      _loading.remove(path);
      _revision++;
    }
  }();

  /// [data] as the file at [path], not yet written: a new terrain, or a
  /// copy made unique.
  void put(String path, TerrainData data) {
    _loaded[path] = data;
    _errors.remove(path);
    _unsaved.add(path);
    _revision++;
  }

  /// Marks the file at [path] changed since it was written.
  void changed(String path) {
    if (_loaded[path] != null) _unsaved.add(path);
  }

  /// The files changed since they were written.
  Set<String> get unsaved => Set.unmodifiable(_unsaved);

  /// Marks the file at [path] written.
  void saved(String path) => _unsaved.remove(path);

  /// Reads the file at [path] again next time — dropping changes not
  /// written.
  void forget(String path) {
    _loaded.remove(path);
    _errors.remove(path);
    _unsaved.remove(path);
    _revision++;
  }
}

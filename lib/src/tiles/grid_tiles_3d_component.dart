import 'package:just_game_engine/just_game_engine.dart';

import 'grid_tile_solids.dart';
import 'mesh_libraries.dart';
import 'mesh_library.dart';

/// A cell of a [GridTiles3DComponent]: where it is, counted in cells.
typedef GridCell = ({int x, int y, int z});

/// What is in a cell: a [MeshLibrary] item, turned one of the
/// [GridOrientations].
typedef GridTile = ({int item, int orientation});

/// Tiles in a 3-D grid — floors, walls, ramps from a [MeshLibrary] — each
/// cell holding one, turned any of 24 ways: a level built like bricks.
/// Drawn by the kit's renderer, many to a draw; solid, through a
/// `Collider3DComponent` set to match its shape, as each item says.
///
/// Cell (x, y, z) spans x to x + 1 cells along X, and so on: +Y is down,
/// so the cells above the ground at y = 0 are y = -1, -2…
class GridTiles3DComponent extends Component implements SolidShapeSource {
  GridTiles3DComponent({
    this.library = '',
    Map<int, int>? cells,
    this.castShadows = true,
    this.maxDistance = 0,
  }) : cells = cells ?? {};

  /// The mesh library (`.meshlib.json`) its items come from.
  String library;

  /// Its tiles: [keyOf] a cell to [pack]ed item and orientation. Changed
  /// through [setTile] and [clearTile], which keep [revision] up.
  Map<int, int> cells;

  /// Whether its tiles cast shadows.
  bool castShadows;

  /// Beyond how many metres from the camera its tiles are not drawn; 0 for
  /// always.
  double maxDistance;

  /// Runtime: bumped whenever [cells] change, so what draws and collides
  /// with them builds again.
  int revision = 0;

  /// Runtime: its library, once loaded, linked by whoever draws or
  /// collides it ([link]).
  MeshLibrary? loaded;

  MeshLibraries? _libraries;
  (Object, List<SolidPart>)? _solid;

  // Equal only to itself: what keeps this grid's solid key its own. Every
  // grid read from a scene has the same [revision], and grids on one
  // library share it, so neither tells one grid's tiles from another's.
  final Object _identity = Object();

  /// Ties it to its library in [libraries] — loading it, the first time.
  void link(MeshLibraries libraries) {
    _libraries = libraries;
    loaded = libraries.get(library);
  }

  /// [cell]'s key in [cells].
  static int keyOf(int x, int y, int z) =>
      ((x + 0x8000) & 0xFFFF) * 0x100000000 +
      ((y + 0x8000) & 0xFFFF) * 0x10000 +
      ((z + 0x8000) & 0xFFFF);

  /// The cell a [keyOf] key names.
  static GridCell cellOf(int key) => (
    x: (key ~/ 0x100000000) - 0x8000,
    y: ((key ~/ 0x10000) & 0xFFFF) - 0x8000,
    z: (key & 0xFFFF) - 0x8000,
  );

  /// An item and orientation as [cells] holds them.
  static int pack(int item, int orientation) => item * 32 + (orientation & 31);

  /// What a [pack]ed value holds.
  static GridTile unpack(int value) =>
      (item: value ~/ 32, orientation: value & 31);

  /// What is in cell ([x], [y], [z]), if anything.
  GridTile? tileAt(int x, int y, int z) {
    final v = cells[keyOf(x, y, z)];
    return v == null ? null : unpack(v);
  }

  /// Puts [item], turned [orientation], in cell ([x], [y], [z]).
  void setTile(int x, int y, int z, int item, [int orientation = 0]) {
    cells[keyOf(x, y, z)] = pack(item, orientation);
    revision++;
  }

  /// Empties cell ([x], [y], [z]).
  void clearTile(int x, int y, int z) {
    if (cells.remove(keyOf(x, y, z)) != null) revision++;
  }

  /// The middle of cell ([x], [y], [z]) in its entity's space, for cells
  /// [cellSize] across.
  static Vector3 centreOf(int x, int y, int z, double cellSize) =>
      Vector3((x + 0.5) * cellSize, (y + 0.5) * cellSize, (z + 0.5) * cellSize);

  /// The cell [point] (in its entity's space) is in.
  static GridCell cellAt(Vector3 point, double cellSize) => (
    x: (point.x / cellSize).floor(),
    y: (point.y / cellSize).floor(),
    z: (point.z / cellSize).floor(),
  );

  /// This grid's own, its [revision] and the library it is built from: a
  /// physics engine that keeps shapes by key never mistakes another grid
  /// for this one.
  @override
  Object get solidKey => (_identity, revision, loaded);

  @override
  List<SolidPart> get solidParts {
    final library = loaded;
    if (library == null) return const [];
    final key = solidKey;
    final known = _solid;
    if (known != null && known.$1 == key) return known.$2;
    final libraries = _libraries;
    final parts = GridTileSolids.of(
      this,
      library,
      shapeOf: libraries == null
          ? null
          : (item) => libraries.shapeOf(this.library, item),
    );
    _solid = (key, parts);
    return parts;
  }
}

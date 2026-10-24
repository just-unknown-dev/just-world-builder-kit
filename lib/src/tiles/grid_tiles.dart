import 'dart:convert';
import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'grid_orientations.dart';
import 'mesh_library.dart';

/// A cell of a [GridTiles3D]: where it is, counted in cells.
typedef GridCell = ({int x, int y, int z});

/// What is in a cell: a [MeshLibrary] item, turned one of the
/// [GridOrientations].
typedef GridTile = ({int item, int orientation});

/// Tiles in a 3-D grid — floors, walls, ramps from a [MeshLibrary] — each
/// cell holding one, turned any of 24 ways: a level built like bricks.
/// Drawn by the kit's renderer, many to a draw; solid, through a
/// `Collider3D` set to match its shape, as each item says.
///
/// Cell (x, y, z) spans x to x + 1 cells along X, and so on: +Y is down,
/// so the cells above the ground at y = 0 are y = -1, -2…
class GridTiles3D extends Component implements SolidShapeSource {
  GridTiles3D({this.library = '', Map<int, int>? cells, this.castShadows = true, this.maxDistance = 0})
    : cells = cells ?? {};

  /// The mesh library (`.meshlib.json`) its items come from.
  String library;

  /// Its tiles: [keyOf] a cell to [pack]ed item and orientation. Changed
  /// through [setTile] and [clearTile], which keep [revision] up.
  Map<int, int> cells;

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
      ((x + 0x8000) & 0xFFFF) * 0x100000000 + ((y + 0x8000) & 0xFFFF) * 0x10000 + ((z + 0x8000) & 0xFFFF);

  /// The cell a [keyOf] key names.
  static GridCell cellOf(int key) => (
    x: (key ~/ 0x100000000) - 0x8000,
    y: ((key ~/ 0x10000) & 0xFFFF) - 0x8000,
    z: (key & 0xFFFF) - 0x8000,
  );

  /// An item and orientation as [cells] holds them.
  static int pack(int item, int orientation) => item * 32 + (orientation & 31);

  /// What a [pack]ed value holds.
  static GridTile unpack(int value) => (item: value ~/ 32, orientation: value & 31);

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
      shapeOf: libraries == null ? null : (item) => libraries.shapeOf(this.library, item),
    );
    _solid = (key, parts);
    return parts;
  }
}

/// What makes a [GridTiles3D] solid: a box for each run of box tiles along
/// X — whole rows, not cell by cell — and each shape tile's own parts,
/// turned with it.
abstract final class GridTileSolids {
  /// [tiles]' solid parts, from [library].
  static List<SolidPart> of(GridTiles3D tiles, MeshLibrary library, {Primitive3D? Function(MeshLibraryItem item)? shapeOf}) {
    final c = library.cellSize;
    final half = c / 2;
    final out = <SolidPart>[];
    // Box cells, by row (y, z), each row's x in order.
    final rows = <(int, int), List<int>>{};
    final items = {for (final i in library.items) i.id: i};
    for (final MapEntry(:key, :value) in tiles.cells.entries) {
      final tile = GridTiles3D.unpack(value);
      final item = items[tile.item];
      if (item == null || item.collision == PieceCollision.none) continue;
      final cell = GridTiles3D.cellOf(key);
      final shape = item.collision == PieceCollision.shape ? shapeOf?.call(item) : null;
      if (shape case final SolidShapeSource source) {
        final centre = GridTiles3D.centreOf(cell.x, cell.y, cell.z, c);
        final at = centre + GridOrientations.apply(tile.orientation, item.offset);
        final turned = [for (final part in source.solidParts) _turned(part, tile.orientation, at, item.scale)];
        if (turned.isNotEmpty && !turned.contains(null)) {
          out.addAll(turned.nonNulls);
          continue;
        }
      }
      // Solid as its cell.
      (rows[(cell.y, cell.z)] ??= []).add(cell.x);
    }
    for (final MapEntry(key: (y, z), value: xs) in rows.entries) {
      xs.sort();
      var start = xs.first, end = xs.first;
      void flush() {
        final count = end - start + 1;
        out.add(SolidBox(count * half, half, half, x: (start + end + 1) * half, y: (y + 0.5) * c, z: (z + 0.5) * c));
      }

      for (final x in xs.skip(1)) {
        if (x == end + 1) {
          end = x;
        } else {
          flush();
          start = end = x;
        }
      }
      flush();
    }
    return out;
  }

  /// [part] turned by [orientation], grown by [scale] and moved to [at];
  /// null when it cannot be.
  static SolidPart? _turned(SolidPart part, int orientation, Vector3 at, double scale) {
    Vector3 point(double x, double y, double z) => at + GridOrientations.apply(orientation, Vector3(x, y, z) * scale);
    switch (part) {
      case SolidBox(:final halfX, :final halfY, :final halfZ, :final x, :final y, :final z):
        // A quarter turn keeps a box square to the axes: its sides change
        // places.
        final size = GridOrientations.apply(orientation, Vector3(halfX, halfY, halfZ));
        final middle = point(x, y, z);
        return SolidBox(
          size.x.abs() * scale,
          size.y.abs() * scale,
          size.z.abs() * scale,
          x: middle.x,
          y: middle.y,
          z: middle.z,
        );
      case SolidSphere(:final radius, :final x, :final y, :final z):
        final middle = point(x, y, z);
        return SolidSphere(radius * scale, x: middle.x, y: middle.y, z: middle.z);
      case SolidHull(:final points):
        final out = Float32List(points.length);
        for (var i = 0; i + 2 < points.length; i += 3) {
          final p = point(points[i], points[i + 1], points[i + 2]);
          out[i] = p.x;
          out[i + 1] = p.y;
          out[i + 2] = p.z;
        }
        return SolidHull(out);
      case SolidMesh(:final positions, :final indices):
        final out = Float32List(positions.length);
        for (var i = 0; i + 2 < positions.length; i += 3) {
          final p = point(positions[i], positions[i + 1], positions[i + 2]);
          out[i] = p.x;
          out[i + 1] = p.y;
          out[i + 2] = p.z;
        }
        return SolidMesh(out, indices);
      // Upright, along Y: kept so only while its tile is spun about Y, and
      // solid as its cell when tipped over.
      case SolidCylinder(:final halfHeight, :final radius, :final x, :final y, :final z) when orientation < 4:
        final middle = point(x, y, z);
        return SolidCylinder(halfHeight * scale, radius * scale, x: middle.x, y: middle.y, z: middle.z);
      case SolidCapsule(:final halfHeight, :final radius, :final x, :final y, :final z) when orientation < 4:
        final middle = point(x, y, z);
        return SolidCapsule(halfHeight * scale, radius * scale, x: middle.x, y: middle.y, z: middle.z);
      case SolidCylinder() || SolidCapsule() || SolidHeightField():
        return null;
    }
  }
}

/// A [GridTiles3D]'s cells, saved as base64 of zlib-packed records — a
/// version byte, then x, y, z (16 bits each) and the packed tile (32 bits)
/// per cell, in key order.
class GridCellsFieldType extends FieldType<Map<int, int>> {
  const GridCellsFieldType();

  /// The id the editor finds its field editor under.
  static const String typeId = 'worldBuilder.gridCells';

  static const int _version = 1;
  static const ZlibCodec _zlib = ZlibCodec();

  /// The most bytes the cells may unpack to (64 MB, six million cells): a
  /// damaged text fails at once instead of filling memory.
  static const int maxBytes = 64 << 20;

  @override
  String get id => typeId;

  @override
  Object? encode(Map<int, int> value) => encodeCells(value);

  @override
  Object? decode(Object? json, FieldConstraints constraints) => json is String ? decodeCells(json) : json;

  /// [cells] as text.
  static String encodeCells(Map<int, int> cells) {
    final keys = cells.keys.toList()..sort();
    final bytes = ByteData(1 + keys.length * 10)..setUint8(0, _version);
    var o = 1;
    for (final key in keys) {
      final cell = GridTiles3D.cellOf(key);
      bytes
        ..setInt16(o, cell.x, Endian.little)
        ..setInt16(o + 2, cell.y, Endian.little)
        ..setInt16(o + 4, cell.z, Endian.little)
        ..setUint32(o + 6, cells[key]!, Endian.little);
      o += 10;
    }
    return base64Encode(_zlib.encode(bytes.buffer.asUint8List()));
  }

  /// The cells [text] holds; a [FormatException] when it holds none.
  static Map<int, int> decodeCells(String text) {
    if (text.isEmpty) return {};
    final raw = _zlib.decode(base64Decode(text), maxOutputSize: maxBytes);
    if (raw.isEmpty || raw[0] > _version || (raw.length - 1) % 10 != 0) {
      throw const FormatException('Not grid tile cells');
    }
    final bytes = ByteData.sublistView(raw);
    final out = <int, int>{};
    for (var o = 1; o < raw.length; o += 10) {
      out[GridTiles3D.keyOf(
        bytes.getInt16(o, Endian.little),
        bytes.getInt16(o + 2, Endian.little),
        bytes.getInt16(o + 4, Endian.little),
      )] = bytes.getUint32(o + 6, Endian.little);
    }
    return out;
  }
}

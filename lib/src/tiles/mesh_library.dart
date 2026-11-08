import 'dart:convert';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// How a tile is solid.
enum PieceCollision {
  /// Not at all: grass, a lamp's light.
  none,

  /// As its whole cell, whatever it shows: a block that fills it. Rows of
  /// them are merged into long boxes, the cheapest to collide with.
  box,

  /// As its own shape — a floor's slab, a wall, a ramp's slope, stairs'
  /// steps — for a shape tile; a model tile is solid as its cell.
  shape,
}

/// One piece of a [MeshLibrary]: a model, or one of the engine's shapes,
/// placed in a cell — moved by [offset] from its middle and grown by
/// [scale] — and solid as [collision] says.
final class MeshLibraryItem {
  MeshLibraryItem({
    required this.id,
    this.name = '',
    this.model = '',
    this.shape,
    this.collision = PieceCollision.box,
    Vector3? offset,
    this.scale = 1,
  }) : offset = offset ?? Vector3.zero();

  /// Which it is, in a [GridTiles3DComponent]'s cells: 1 and up, never reused
  /// ([MeshLibrary.nextId]).
  final int id;

  String name;

  /// The model (`.glb`, `.gltf`) it shows; empty for [shape].
  String model;

  /// The shape it shows when it has no model: a shape component as a
  /// scene saves it (`{"type": "Cube3DComponent", ...}`).
  Map<String, Object?>? shape;

  PieceCollision collision;

  /// From the middle of its cell (metres).
  Vector3 offset;

  double scale;

  MeshLibraryItem copy() => MeshLibraryItem(
    id: id,
    name: name,
    model: model,
    shape: shape == null
        ? null
        : jsonDecode(jsonEncode(shape)) as Map<String, Object?>,
    collision: collision,
    offset: Vector3.copy(offset),
    scale: scale,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (model.isNotEmpty) 'model': model,
    if (model.isEmpty && shape != null) 'shape': shape,
    'collision': collision.name,
    if (offset.lengthSquared > 0) 'offset': [offset.x, offset.y, offset.z],
    if (scale != 1) 'scale': scale,
  };

  factory MeshLibraryItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! int || id < 1) {
      throw FormatException(
        'A mesh library item needs an id of 1 or more: $id',
      );
    }
    final offset = json['offset'];
    double n(Object? v) => v is num ? v.toDouble() : 0;
    final shape = json['shape'];
    return MeshLibraryItem(
      id: id,
      name: json['name'] as String? ?? '',
      model: json['model'] as String? ?? '',
      shape: shape is Map ? Map<String, Object?>.from(shape) : null,
      collision:
          PieceCollision.values
              .where((c) => c.name == json['collision'])
              .firstOrNull ??
          PieceCollision.box,
      offset: offset is List && offset.length >= 3
          ? Vector3(n(offset[0]), n(offset[1]), n(offset[2]))
          : null,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
    );
  }
}

/// The pieces a [GridTiles3DComponent] is built from — floors, walls, ramps, the
/// models of a kit of parts — and how big its cells are: a
/// `.meshlib.json` file.
final class MeshLibrary {
  MeshLibrary({this.cellSize = 2, List<MeshLibraryItem>? items, int lastId = 0})
    : items = items ?? [],
      lastId = (items ?? const <MeshLibraryItem>[]).fold(
        lastId,
        (top, i) => i.id > top ? i.id : top,
      );

  /// What its files end with.
  static const String ending = '.meshlib.json';

  /// The format's name and version, written in every file.
  static const String format = 'just.meshlib';

  /// The version this code writes; [parse] refuses a newer one.
  ///
  /// Version 1 named the engine's shapes as scene format 10 did (`Cube3D`);
  /// [parse] reads them under their names now (`Cube3DComponent`).
  static const int version = 2;

  /// How big a cell is, along each side (metres).
  double cellSize;

  List<MeshLibraryItem> items;

  /// The item with [id], if any.
  MeshLibraryItem? item(int id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The highest id any item has had, kept in the file: an item taken out
  /// leaves its id behind, so tiles of it stay empty rather than turning
  /// into the next piece made.
  int lastId;

  /// An id no item has had.
  int get nextId => items.fold(lastId, (top, i) => i.id > top ? i.id : top) + 1;

  /// [nextId], kept as had: the id to give a new item.
  int takeId() => lastId = nextId;

  /// Takes the item with [id] out, keeping its id as had.
  void remove(int id) {
    lastId = nextId - 1;
    items.removeWhere((i) => i.id == id);
  }

  MeshLibrary copy() => MeshLibrary(
    cellSize: cellSize,
    items: [for (final i in items) i.copy()],
    lastId: lastId,
  );

  /// The file's text.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'cellSize': cellSize,
        'lastId': nextId - 1,
        'items': [for (final i in items) i.toJson()],
      })}\n';

  /// The library [text] holds; a [FormatException] when it is not one.
  static MeshLibrary parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map || json['format'] != format) {
      throw const FormatException('Not a mesh library');
    }
    final v = json['version'];
    if (v is! int || v > version) {
      throw FormatException(
        'Mesh library version $v is newer than this engine reads ($version)',
      );
    }
    final cell = (json['cellSize'] as num?)?.toDouble() ?? 2;
    if (!(cell > 0)) {
      throw FormatException('A mesh library\'s cells need a size: $cell');
    }
    final items = json['items'];
    final lastId = json['lastId'];
    return MeshLibrary(
      cellSize: cell,
      lastId: lastId is int && lastId > 0 ? lastId : 0,
      items: [
        if (items is List)
          for (final i in items)
            if (i is Map)
              MeshLibraryItem.fromJson(
                _upgraded(Map<String, Object?>.from(i), v),
              ),
      ],
    );
  }

  /// [item], read at version [from], with its shape named as now.
  static Map<String, Object?> _upgraded(Map<String, Object?> item, int from) {
    final shape = item['shape'];
    if (from < 2 && shape is Map) {
      final type = shape['type'];
      item['shape'] = {
        ...shape,
        'type': SceneFormat.renamedComponents[type] ?? type,
      };
    }
    return item;
  }

  /// A library of the engine's shapes, sized to cells of [cellSize]: a
  /// floor, a block, a wall, a ramp, stairs and a pillar.
  static MeshLibrary starter(
    ComponentDefinitionRegistry definitions, {
    double cellSize = 2,
  }) {
    final c = cellSize;
    const slab = 0.2;
    Map<String, Object?> shape(Primitive3DComponent p) =>
        Map<String, Object?>.from(definitions.encode(p)!);
    return MeshLibrary(
      cellSize: c,
      items: [
        // +Y is down: a floor lies on its cell's bottom. Floors and walls
        // are solid as their slabs: as their cells, a floor would hold
        // the player up a cell above it and a wall would fill its cell.
        MeshLibraryItem(
          id: 1,
          name: 'Floor',
          shape: shape(
            Cube3DComponent(
              width: c,
              height: slab,
              depth: c,
              color: const Color(0xFF9FA8B3),
            ),
          ),
          collision: PieceCollision.shape,
          offset: Vector3(0, c / 2 - slab / 2, 0),
        ),
        MeshLibraryItem(
          id: 2,
          name: 'Block',
          shape: shape(
            Cube3DComponent(
              width: c,
              height: c,
              depth: c,
              color: const Color(0xFFB0BEC5),
            ),
          ),
        ),
        MeshLibraryItem(
          id: 3,
          name: 'Wall',
          shape: shape(
            Cube3DComponent(
              width: c,
              height: c,
              depth: slab,
              color: const Color(0xFFD7CCC8),
            ),
          ),
          collision: PieceCollision.shape,
          offset: Vector3(0, 0, -(c / 2 - slab / 2)),
        ),
        MeshLibraryItem(
          id: 4,
          name: 'Ramp',
          shape: shape(
            Ramp3DComponent(
              width: c,
              height: c,
              depth: c,
              color: const Color(0xFFA1887F),
            ),
          ),
          collision: PieceCollision.shape,
        ),
        MeshLibraryItem(
          id: 5,
          name: 'Stairs',
          shape: shape(
            Stairs3DComponent(
              width: c,
              height: c,
              depth: c,
              steps: 4,
              color: const Color(0xFFBCAAA4),
            ),
          ),
          collision: PieceCollision.shape,
        ),
        MeshLibraryItem(
          id: 6,
          name: 'Pillar',
          shape: shape(
            Cylinder3DComponent(
              radius: c * 0.15,
              height: c,
              color: const Color(0xFFCFD8DC),
            ),
          ),
          collision: PieceCollision.shape,
        ),
      ],
    );
  }
}

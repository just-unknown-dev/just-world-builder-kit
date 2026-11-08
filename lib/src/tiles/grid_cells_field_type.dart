import 'dart:convert';
import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'grid_tiles_3d_component.dart';

/// A [GridTiles3DComponent]'s cells, saved as base64 of zlib-packed records — a
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
  Object? decode(Object? json, FieldConstraints constraints) =>
      json is String ? decodeCells(json) : json;

  /// [cells] as text.
  static String encodeCells(Map<int, int> cells) {
    final keys = cells.keys.toList()..sort();
    final bytes = ByteData(1 + keys.length * 10)..setUint8(0, _version);
    var o = 1;
    for (final key in keys) {
      final cell = GridTiles3DComponent.cellOf(key);
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
      out[GridTiles3DComponent.keyOf(
        bytes.getInt16(o, Endian.little),
        bytes.getInt16(o + 2, Endian.little),
        bytes.getInt16(o + 4, Endian.little),
      )] = bytes.getUint32(
        o + 6,
        Endian.little,
      );
    }
    return out;
  }
}

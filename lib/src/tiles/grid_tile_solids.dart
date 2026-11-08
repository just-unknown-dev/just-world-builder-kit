import 'dart:typed_data';

import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'grid_orientations.dart';
import 'grid_tiles_3d_component.dart';
import 'mesh_library.dart';

/// What makes a [GridTiles3DComponent] solid: a box for each run of box tiles along
/// X — whole rows, not cell by cell — and each shape tile's own parts,
/// turned with it.
abstract final class GridTileSolids {
  /// [tiles]' solid parts, from [library].
  static List<SolidPart> of(
    GridTiles3DComponent tiles,
    MeshLibrary library, {
    Primitive3DComponent? Function(MeshLibraryItem item)? shapeOf,
  }) {
    final c = library.cellSize;
    final half = c / 2;
    final out = <SolidPart>[];
    // Box cells, by row (y, z), each row's x in order.
    final rows = <(int, int), List<int>>{};
    final items = {for (final i in library.items) i.id: i};
    for (final MapEntry(:key, :value) in tiles.cells.entries) {
      final tile = GridTiles3DComponent.unpack(value);
      final item = items[tile.item];
      if (item == null || item.collision == PieceCollision.none) continue;
      final cell = GridTiles3DComponent.cellOf(key);
      final shape = item.collision == PieceCollision.shape
          ? shapeOf?.call(item)
          : null;
      if (shape case final SolidShapeSource source) {
        final centre = GridTiles3DComponent.centreOf(cell.x, cell.y, cell.z, c);
        final at =
            centre + GridOrientations.apply(tile.orientation, item.offset);
        final turned = [
          for (final part in source.solidParts)
            _turned(part, tile.orientation, at, item.scale),
        ];
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
        out.add(
          SolidBox(
            count * half,
            half,
            half,
            x: (start + end + 1) * half,
            y: (y + 0.5) * c,
            z: (z + 0.5) * c,
          ),
        );
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
  static SolidPart? _turned(
    SolidPart part,
    int orientation,
    Vector3 at,
    double scale,
  ) {
    Vector3 point(double x, double y, double z) =>
        at + GridOrientations.apply(orientation, Vector3(x, y, z) * scale);
    switch (part) {
      case SolidBox(
        :final halfX,
        :final halfY,
        :final halfZ,
        :final x,
        :final y,
        :final z,
      ):
        // A quarter turn keeps a box square to the axes: its sides change
        // places.
        final size = GridOrientations.apply(
          orientation,
          Vector3(halfX, halfY, halfZ),
        );
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
        return SolidSphere(
          radius * scale,
          x: middle.x,
          y: middle.y,
          z: middle.z,
        );
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
      case SolidCylinder(
            :final halfHeight,
            :final radius,
            :final x,
            :final y,
            :final z,
          )
          when orientation < 4:
        final middle = point(x, y, z);
        return SolidCylinder(
          halfHeight * scale,
          radius * scale,
          x: middle.x,
          y: middle.y,
          z: middle.z,
        );
      case SolidCapsule(
            :final halfHeight,
            :final radius,
            :final x,
            :final y,
            :final z,
          )
          when orientation < 4:
        final middle = point(x, y, z);
        return SolidCapsule(
          halfHeight * scale,
          radius * scale,
          x: middle.x,
          y: middle.y,
          z: middle.z,
        );
      case SolidCylinder() || SolidCapsule() || SolidHeightField():
        return null;
    }
  }
}

// Grid tiles' cells: keys, and packed small.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cells', () {
    test('a cell\'s key and back, below zero too', () {
      for (final (x, y, z) in [
        (0, 0, 0),
        (-1, -5, 7),
        (32767, -32768, 12),
        (-300, 2, -9),
      ]) {
        final c = GridTiles3DComponent.cellOf(
          GridTiles3DComponent.keyOf(x, y, z),
        );
        expect([c.x, c.y, c.z], [x, y, z]);
      }
      final t = GridTiles3DComponent.unpack(
        GridTiles3DComponent.pack(1234, 23),
      );
      expect([t.item, t.orientation], [1234, 23]);
    });

    test('packed small and read back', () {
      final random = math.Random(7);
      final cells = <int, int>{
        for (var i = 0; i < 1000; i++)
          GridTiles3DComponent.keyOf(
            random.nextInt(200) - 100,
            -random.nextInt(20),
            random.nextInt(200) - 100,
          ): GridTiles3DComponent.pack(
            1 + random.nextInt(5),
            random.nextInt(24),
          ),
      };
      final text = GridCellsFieldType.encodeCells(cells);
      expect(GridCellsFieldType.decodeCells(text), cells);
      expect(
        text.length,
        lessThan(cells.length * 10 * 4 ~/ 3),
        reason: 'packed',
      );
      expect(
        GridCellsFieldType.decodeCells(GridCellsFieldType.encodeCells({})),
        isEmpty,
      );
      expect(
        () => GridCellsFieldType.decodeCells('bm90IHRpbGVz'),
        throwsA(anything),
      );
    });
  });
}

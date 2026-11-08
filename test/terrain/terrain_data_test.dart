// Terrain ground: a new one, its file written and read back, heights
// between samples, blocks kept for undo.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_deflate/just_deflate.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

/// A bumpy terrain of [n] samples a side.
TerrainData _bumpy(int n) {
  final data = TerrainData(n);
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      data.heights[data.index(i, j)] = math.sin(i * 0.7) + math.cos(j * 0.4);
    }
  }
  return data;
}

int data0(int n, int i, int j) => j * n + i;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the ground', () {
    test('a new one: flat, all of the first layer', () {
      final data = TerrainData(9);
      expect(data.heights.every((h) => h == 0), isTrue);
      expect(
        [data.weights[0], data.weights[1], data.weights[2], data.weights[3]],
        [255, 0, 0, 0],
      );
      expect(data.hasHoles, isFalse);
    });

    test('its file, written and read back', () {
      final data = _bumpy(33)
        ..setHole(4, 5, true)
        ..weights[data0(33, 3, 3) * 4 + 2] = 99;
      final back = TerrainData.decode(data.encode());
      expect(back.resolution, 33);
      expect(back.heights, data.heights);
      expect(back.weights, data.weights);
      expect(back.isHole(4, 5), isTrue);
      expect(back.isHole(5, 4), isFalse);
      expect(
        () =>
            TerrainData.decode(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])),
        throwsFormatException,
      );
      final newer = data.encode()..[4] = 9;
      expect(() => TerrainData.decode(newer), throwsFormatException);
      // A body that unpacks to more than its header says: refused as it
      // unpacks.
      final head = Uint8List.fromList(data.encode().sublist(0, 8))
        ..[6] = 3
        ..[7] = 0;
      final big = Uint8List.fromList([
        ...head,
        ...const ZlibCodec().encode(Uint8List(100000)),
      ]);
      expect(() => TerrainData.decode(big), throwsFormatException);
    });

    test('heights between samples', () {
      final data = TerrainData(3)
        ..heights[0] = 0
        ..heights[1] = 2;
      expect(data.heightAt(0.5, 0), closeTo(1, 1e-9));
      expect(data.heightAt(0.5, 0.5), closeTo(0.5, 1e-9));
      expect(data.heightAt(-4, 0), 0, reason: 'held at its edge');
    });

    test('a block kept and put back; changes counted by block', () {
      final data = _bumpy(40);
      final before = data.blockRevision(1, 1);
      final kept = data.capture(1, 1);
      data.heights[data.index(20, 20)] = 50;
      data.touch(20, 20, 20, 20);
      expect(data.blockRevision(1, 1), greaterThan(before));
      expect(data.blockRevision(0, 0), 0, reason: 'nothing near it changed');
      data.touch(16, 16, 16, 16);
      expect(
        data.blockRevision(0, 0),
        greaterThan(0),
        reason: 'a slope next to it did',
      );
      data.restore(kept);
      expect(
        data.heights[data.index(20, 20)],
        closeTo(math.sin(14) + math.cos(8), 1e-6),
      );
    });
  });
}

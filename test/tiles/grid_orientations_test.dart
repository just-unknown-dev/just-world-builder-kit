// Grid tiles' 24 turns.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('turns', () {
    test('24 different ones, the first as made', () {
      final seen = {
        for (var i = 0; i < GridOrientations.count; i++)
          GridOrientations.matrixOf(i).join(','),
      };
      expect(seen, hasLength(24));
      expect(GridOrientations.matrixOf(0), [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    });

    test('the first four only spin: up stays up', () {
      for (var i = 0; i < 4; i++) {
        final up = GridOrientations.apply(i, Vector3(0, -1, 0));
        expect([up.x, up.y, up.z], [0, -1, 0]);
      }
      expect(
        GridOrientations.apply(4, Vector3(0, -1, 0)).y,
        1,
        reason: 'then upside down',
      );
    });

    test('turned about an axis and back; four turns come round', () {
      for (var i = 0; i < 24; i++) {
        for (var axis = 0; axis < 3; axis++) {
          expect(
            GridOrientations.turned(GridOrientations.turned(i, axis), axis, -1),
            i,
          );
          expect(GridOrientations.turned(i, axis, 4), i);
        }
      }
      // A quarter turn about up from as made: the first spin.
      expect(GridOrientations.turned(0, 1), 1);
    });

    test('its turn matches its matrix', () {
      for (var i = 0; i < 24; i++) {
        final v = Vector3(1, 2, 3);
        GridOrientations.of(i).rotate(v);
        final m = GridOrientations.apply(i, Vector3(1, 2, 3));
        expect(
          [v.x, v.y, v.z],
          [closeTo(m.x, 1e-9), closeTo(m.y, 1e-9), closeTo(m.z, 1e-9)],
        );
      }
    });
  });
}

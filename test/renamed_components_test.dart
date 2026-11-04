// Files saved before every component's name ended in `Component`: levels
// (scene format 10) load with the kit's components under their new names,
// and a version 1 mesh library reads its shapes under the engine's.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

void main() {
  test('v10 kit components load under their new names', () {
    final context = EngineContext(extensions: [WorldBuilderKit.extension]);
    final old = WorldBuilderKit.renamedTypes.keys.toList();
    final scene = SceneFormat.migrate({
      'version': 10,
      'name': 's',
      'entities': [
        for (final type in old)
          {
            'name': type,
            'components': [
              {'type': type, 'fields': <String, dynamic>{}},
            ],
          },
      ],
    }, hooks: context.migrations);
    final types = [
      for (final e in scene['entities'] as List)
        ((e as Map)['components'] as List).single['type'],
    ];
    expect(types, WorldBuilderKit.renamedTypes.values.toList());
    for (final type in types) {
      expect(
        context.definitions.definitionByType(type as String),
        isNotNull,
        reason: type,
      );
    }
  });

  test('a version 1 mesh library reads its shapes under their new names', () {
    final library = MeshLibrary.parse(
      jsonEncode({
        'format': MeshLibrary.format,
        'version': 1,
        'cellSize': 2,
        'items': [
          {
            'id': 1,
            'name': 'Block',
            'shape': {
              'type': 'Cube3D',
              'fields': {'material': ''},
            },
          },
          {'id': 2, 'name': 'Rock', 'model': 'assets/models/rock.glb'},
        ],
      }),
    );
    expect(library.item(1)!.shape, {
      'type': 'Cube3DComponent',
      'fields': {'material': ''},
    });
    expect(library.item(2)!.shape, isNull);
    expect(jsonDecode(library.encode())['version'], MeshLibrary.version);
  });
}

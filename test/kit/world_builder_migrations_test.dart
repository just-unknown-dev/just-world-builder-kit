// Levels saved before every component's name ended in `Component` load
// with the kit's components under their new names — saved at scene format
// 10, and at the newest format too: the kit's renames apply to a scene of
// any format.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_world_builder_kit/just_world_builder_kit.dart';

/// A scene of [version] with one entity per type in [types].
Map<String, dynamic> _scene(int version, Iterable<String> types) => {
  'version': version,
  'name': 's',
  'entities': [
    for (final type in types)
      {
        'name': type,
        'components': [
          {'type': type, 'fields': <String, dynamic>{}},
        ],
      },
  ],
};

List<Object?> _types(Map<String, dynamic> scene) => [
  for (final e in scene['entities'] as List)
    ((e as Map)['components'] as List).single['type'],
];

void main() {
  test('installing the kit installs its renames', () {
    final context = EngineContext(extensions: [WorldBuilderKit.extension]);
    for (final MapEntry(:key, :value)
        in WorldBuilderMigrations.renamedTypes.entries) {
      expect(context.migrations.renamedTypes[key], value, reason: key);
    }
  });

  test('v10 kit components load under their new names', () {
    final context = EngineContext(extensions: [WorldBuilderKit.extension]);
    final old = WorldBuilderMigrations.renamedTypes.keys.toList();
    final scene = SceneFormat.migrate(
      _scene(10, old),
      hooks: context.migrations,
    );
    final types = _types(scene);
    expect(types, WorldBuilderMigrations.renamedTypes.values.toList());
    for (final type in types) {
      expect(
        context.definitions.definitionByType(type as String),
        isNotNull,
        reason: type,
      );
    }
  });

  test(
    'a scene at the newest format that names an old type loads it renamed',
    () {
      final context = EngineContext(extensions: [WorldBuilderKit.extension]);
      final scene = SceneFormat.migrate(
        _scene(SceneFormat.current, [
          'Terrain3D',
          'GridTiles3D',
          'Spline3DComponent',
        ]),
        hooks: context.migrations,
      );
      expect(_types(scene), [
        'Terrain3DComponent',
        'GridTiles3DComponent',
        'Spline3DComponent',
      ]);
    },
  );

  test('a scene naming only the new types comes back as it was', () {
    final context = EngineContext(extensions: [WorldBuilderKit.extension]);
    final scene = _scene(
      SceneFormat.current,
      WorldBuilderMigrations.renamedTypes.values,
    );
    expect(
      identical(SceneFormat.migrate(scene, hooks: context.migrations), scene),
      isTrue,
    );
  });
}

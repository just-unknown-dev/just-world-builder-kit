import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart';

import '../tiles/tiles.dart';

/// The project's files the World Builder lists and makes, under [root]
/// (the project folder): its mesh libraries and models under `assets/`,
/// and where terrain files are read from and written to.
///
/// A listing is read off the UI thread the first time it is asked for and
/// kept: a panel opening, or a menu, never walks the folder again. [refresh]
/// reads them afresh next time — the module calls it when a library or a
/// model changes.
final class WorldBuilderFiles {
  WorldBuilderFiles([String? root])
    : root = (root ?? Directory.current.path).replaceAll(r'\', '/');

  /// The project folder.
  final String root;

  Future<List<String>>? _libraries;
  Future<List<String>>? _models;

  /// Every `.meshlib.json` under `assets/`, project-relative, in order.
  Future<List<String>> libraries() =>
      _libraries ??= _list(const [MeshLibrary.ending]);

  /// Every model (`.glb`, `.gltf`) under `assets/`, project-relative, in
  /// order.
  Future<List<String>> models() => _models ??= _list(const ['.glb', '.gltf']);

  /// Lists the files again next time they are asked for.
  void refresh() {
    _libraries = null;
    _models = null;
  }

  Future<List<String>> _list(List<String> endings) async {
    final assets = Directory('$root/assets');
    final out = <String>[];
    try {
      if (!await assets.exists()) return const [];
      await for (final entry in assets.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File) continue;
        final path = entry.path.replaceAll(r'\', '/');
        if (endings.any(path.endsWith)) {
          out.add(path.substring(root.length + 1));
        }
      }
    } on FileSystemException {
      // A folder that cannot be read: what was found before it.
    }
    return out..sort();
  }

  /// A new library of the engine's shapes in `assets/tiles/` — `tiles`, or
  /// `tiles_2` and on — and its path.
  Future<String> create(ComponentDefinitionRegistry definitions) async {
    var n = 1;
    String pathOf(int n) =>
        'assets/tiles/tiles${n == 1 ? '' : '_$n'}${MeshLibrary.ending}';
    while (await File('$root/${pathOf(n)}').exists()) {
      n++;
    }
    final path = pathOf(n);
    final file = File('$root/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(MeshLibrary.starter(definitions).encode());
    _libraries = null;
    return path;
  }
}

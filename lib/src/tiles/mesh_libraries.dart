import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'mesh_library.dart';

/// The mesh libraries one engine has loaded, read through its text seam
/// (`EngineContext.tiles.readText`: the game's bundle, or the project's
/// files in the editor).
final class MeshLibraries {
  MeshLibraries(this.context);

  /// The libraries of [context], made on first use.
  static MeshLibraries of(EngineContext context) =>
      context.slot(MeshLibraries, () => MeshLibraries(context));

  final EngineContext context;

  final Map<String, MeshLibrary?> _loaded = {};
  final Map<String, Future<MeshLibrary?>> _loading = {};
  final Map<String, Object> _errors = {};
  final Map<(String, int), Primitive3DComponent?> _shapes = {};
  int _revision = 0;
  final _Changes _changes = _Changes();

  /// Bumped whenever one finishes loading or changes.
  int get revision => _revision;

  /// Told whenever [revision] is bumped: a library loaded, read again,
  /// forgotten or let go — what an editor's panel listing a library's
  /// pieces listens to.
  Listenable get changes => _changes;

  void _bump() {
    _revision++;
    _changes.tell();
  }

  /// The library at [path] once loaded, or null while it loads (it starts
  /// loading) or when it could not be read.
  MeshLibrary? get(String path) {
    if (path.isEmpty) return null;
    if (_loaded.containsKey(path)) return _loaded[path];
    load(path);
    return null;
  }

  /// Why the library at [path] could not be read — or, once read, why a
  /// piece of it could not be made — if one could not.
  Object? errorOf(String path) => _errors[path];

  /// The library at [path], loaded first when it is not yet (null when it
  /// could not be read): what a game awaits before its level starts
  /// (`WorldBuilderKit.ready`).
  Future<MeshLibrary?> ready(String path) async {
    if (path.isEmpty) return null;
    if (_loaded.containsKey(path)) return _loaded[path];
    return load(path);
  }

  /// Loads the library at [path].
  Future<MeshLibrary?> load(String path) => _loading[path] ??= () async {
    try {
      final library = MeshLibrary.parse(await context.tiles.readText(path));
      _loaded[path] = library;
      _errors.remove(path);
      return library;
    } on Object catch (e) {
      _loaded[path] = null;
      _errors[path] = e;
      return null;
    } finally {
      _loading.remove(path);
      _shapes.removeWhere((key, _) => key.$1 == path);
      _bump();
    }
  }();

  /// Reads the library at [path] again next time it is asked for.
  void forget(String path) {
    if (_loaded.remove(path) == null && !_errors.containsKey(path)) return;
    _errors.remove(path);
    _shapes.removeWhere((key, _) => key.$1 == path);
    _bump();
  }

  /// Lets go of every library loaded but not in [used] — what a level no
  /// longer shows; one still loading is kept.
  void releaseUnused(Iterable<String> used) {
    final keep = used.toSet();
    final gone = [
      for (final path in _loaded.keys)
        if (!keep.contains(path)) path,
    ];
    if (gone.isEmpty) return;
    for (final path in gone) {
      _loaded.remove(path);
      _errors.remove(path);
    }
    _shapes.removeWhere((key, _) => !keep.contains(key.$1));
    _bump();
  }

  /// [item]'s shape, from the library at [path]; null for a model piece,
  /// or one whose shape could not be made (why is [errorOf] the path):
  /// it is then solid as its cell, and not drawn.
  Primitive3DComponent? shapeOf(String path, MeshLibraryItem item) {
    final json = item.shape;
    if (item.model.isNotEmpty || json == null) return null;
    return _shapes.putIfAbsent((path, item.id), () {
      try {
        final decoded = context.definitions.decode(
          Map<String, dynamic>.from(json),
        );
        return decoded is Primitive3DComponent ? decoded : null;
      } on Object catch (e) {
        _errors[path] = FormatException('Piece ${item.id} (${item.name}): $e');
        return null;
      }
    });
  }
}

/// What tells a [MeshLibraries]' listeners.
final class _Changes extends ChangeNotifier {
  void tell() => notifyListeners();
}

import 'dart:typed_data';

import 'package:just_game_engine/just_game_engine.dart';

import 'terrain_data.dart';

/// The terrain files one engine has loaded — shared by every terrain
/// using one, and changed in place by the editor — read through [read]:
/// the game's bundle, unless an editor points it at the project.
final class TerrainFiles {
  TerrainFiles(this.context)
    : read = ((path) async {
        final data = await context.bundle.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      });

  /// The files of [context], made on first use.
  static TerrainFiles of(EngineContext context) =>
      context.slot(TerrainFiles, () => TerrainFiles(context));

  final EngineContext context;

  /// Reads a file's bytes.
  Future<Uint8List> Function(String path) read;

  final Map<String, TerrainData?> _loaded = {};
  final Map<String, Future<TerrainData?>> _loading = {};
  final Map<String, Object> _errors = {};
  final Set<String> _unsaved = {};
  int _revision = 0;

  /// Bumped whenever one finishes loading or is replaced.
  int get revision => _revision;

  /// The ground at [path] once loaded, or null while it loads (it starts
  /// loading) or when it could not be read.
  TerrainData? get(String path) {
    if (path.isEmpty) return null;
    if (_loaded.containsKey(path)) return _loaded[path];
    load(path);
    return null;
  }

  /// Why the file at [path] could not be read, if it could not.
  Object? errorOf(String path) => _errors[path];

  /// Whether [path] is taken here: loaded (or found missing), loading, or
  /// put and not yet written. Unlike [get], asking starts no load.
  bool knows(String path) =>
      _loaded.containsKey(path) ||
      _loading.containsKey(path) ||
      _unsaved.contains(path);

  /// Loads the file at [path]. Ground [put] at [path] while it was read
  /// is kept: changes not yet written are dropped only by [forget].
  Future<TerrainData?> load(String path) => _loading[path] ??= () async {
    try {
      final data = TerrainData.decode(await read(path));
      if (_unsaved.contains(path)) return _loaded[path];
      _loaded[path] = data;
      _errors.remove(path);
      return data;
    } on Object catch (e) {
      if (_unsaved.contains(path)) return _loaded[path];
      _loaded[path] = null;
      _errors[path] = e;
      return null;
    } finally {
      _loading.remove(path);
      _revision++;
    }
  }();

  /// The ground at [path], loaded first when it is not yet (null when it
  /// could not be read): what a game awaits before its level starts
  /// (`WorldBuilderKit.ready`).
  Future<TerrainData?> ready(String path) async {
    if (path.isEmpty) return null;
    if (_loaded.containsKey(path)) return _loaded[path];
    return load(path);
  }

  /// Lets go of every file loaded but not in [used] — what a level no
  /// longer shows. Changes not yet written ([unsaved]) are kept, and so is
  /// one still loading.
  void releaseUnused(Iterable<String> used) {
    final keep = {...used, ..._unsaved};
    final gone = [
      for (final path in _loaded.keys)
        if (!keep.contains(path)) path,
    ];
    if (gone.isEmpty) return;
    for (final path in gone) {
      _loaded.remove(path);
      _errors.remove(path);
    }
    _revision++;
  }

  /// [data] as the file at [path], not yet written: a new terrain, or a
  /// copy made unique.
  void put(String path, TerrainData data) {
    _loaded[path] = data;
    _errors.remove(path);
    _unsaved.add(path);
    _revision++;
  }

  /// Marks the file at [path] changed since it was written.
  void changed(String path) {
    if (_loaded[path] != null) _unsaved.add(path);
  }

  /// The files changed since they were written.
  Set<String> get unsaved => Set.unmodifiable(_unsaved);

  /// Marks the file at [path] written.
  void saved(String path) => _unsaved.remove(path);

  /// Reads the file at [path] again next time — dropping changes not
  /// written.
  void forget(String path) {
    _loaded.remove(path);
    _errors.remove(path);
    _unsaved.remove(path);
    _revision++;
  }
}

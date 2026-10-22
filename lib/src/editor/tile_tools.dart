import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_signals/just_signals.dart';

import '../tiles/grid_orientations.dart';
import '../tiles/grid_tiles.dart';
import '../tiles/mesh_library.dart';
import 'spline_tools.dart' show adoptEntities;

/// The tool strip's group for tiles.
const String tilesGroup = 'worldBuilder.tiles';

/// What a drag of the Tiles tool does.
enum GridTileMode {
  /// Puts the chosen piece in each cell passed over.
  paint('Paint'),

  /// Empties each cell passed over.
  erase('Erase'),

  /// Fills the box dragged out, on the floor level.
  fill('Fill');

  const GridTileMode(this.label);

  final String label;
}

/// The cells the Tiles tool would change now, in the world: from one
/// corner cell to another, [cellSize] across, laid out by [toWorld].
final class GridTilePreview {
  const GridTilePreview({required this.from, required this.to, required this.cellSize, required this.toWorld, this.erasing = false});

  final GridCell from, to;
  final double cellSize;
  final Matrix4 toWorld;
  final bool erasing;
}

/// A stroke of the Tiles tool: cells as they were and as they became, on
/// the [GridTiles3D] of the entity named [entityName] — found again by
/// name, so it outlives the entity being rebuilt.
class GridTileStrokeCommand extends EditorCommand {
  GridTileStrokeCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required this.entityName,
    required this.before,
    required this.after,
  });

  @override
  final String label;

  final World world;
  final EditorSceneState sceneState;
  final String entityName;

  /// Cell key to packed tile, or null for empty: before, and after.
  final Map<int, int?> before, after;

  GridTiles3D? get _tiles {
    for (final e in world.entities) {
      if (e.name == entityName) return e.getComponent<GridTiles3D>();
    }
    return null;
  }

  void _apply(Map<int, int?> cells) {
    final tiles = _tiles;
    if (tiles == null) return;
    for (final MapEntry(:key, :value) in cells.entries) {
      if (value == null) {
        tiles.cells.remove(key);
      } else {
        tiles.cells[key] = value;
      }
    }
    tiles.revision++;
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);
}

/// The Tiles tool: paints pieces of a mesh library into a 3-D grid — on
/// the floor level (Page Up / Page Down), or stacked on whatever is under
/// the pointer — drag to paint a run; erase; fill a box. Z turns the piece
/// about up, X and C tip it (Shift the other way); Alt-click picks the
/// piece under the pointer up. Paints into the selected Grid Tiles 3D, or
/// one using the same library, or a new one.
class GridTileTool extends LevelToolHandler {
  GridTileTool(this.designer);

  /// Where it makes entities.
  final DesignerToolContext designer;

  final Signal<GridTileMode> mode = Signal(GridTileMode.paint, debugLabel: 'tileMode');

  /// The mesh library painted from.
  final Signal<String> library = Signal('', debugLabel: 'tileLibrary');

  /// The piece painted.
  final Signal<int> item = Signal(1, debugLabel: 'tileItem');

  /// How it is turned (see [GridOrientations]).
  final Signal<int> orientation = Signal(0, debugLabel: 'tileOrientation');

  /// The floor level painted on: 0 on the ground, 1 a cell up, and on.
  final Signal<int> floor = Signal(0, debugLabel: 'tileFloor');

  /// Whether a paint stacks on what is under the pointer rather than
  /// going to the floor level.
  final Signal<bool> onSurfaces = Signal(true, debugLabel: 'tileOnSurfaces');

  /// What it would change now.
  final Signal<GridTilePreview?> preview = Signal(null, debugLabel: 'tilePreview');

  static const String toolId = 'worldBuilder.tiles';

  Entity? _target;
  bool _madeTarget = false;
  final Map<int, int?> _before = {};
  GridCell? _fillFrom, _last;

  @override
  String get id => toolId;

  @override
  String get label => 'Tiles';

  @override
  IconData get icon => Icons.grid_view;

  @override
  String? get description =>
      'Paint pieces of a mesh library into a 3-D grid; Z turns, X/C tip, Alt-click picks one up, Page Up/Down change floor';

  @override
  int get order => 60;

  @override
  String get group => tilesGroup;

  @override
  Dimensions get dimensions => Dimensions.threeD;

  MeshLibraries get _libraries => MeshLibraries.of(designer.world.context);

  /// The library painted from, once loaded.
  MeshLibrary? get loadedLibrary => _libraries.get(library.value);

  /// The tiles it paints into: the selected ones, else the first using
  /// its library; null for none yet.
  Entity? get target {
    final selected = designer.sceneState.selectedEntity.value;
    if (selected != null && selected.hasComponent<GridTiles3D>()) return selected;
    for (final e in designer.world.query([GridTiles3D])) {
      if (e.getComponent<GridTiles3D>()!.library == library.value) return e;
    }
    return null;
  }

  /// [entity]'s space to the world's, and back; the world's own for none.
  (Matrix4, Matrix4) _spaceOf(Entity? entity) {
    final toWorld = Matrix4.identity();
    entity?.getComponent<TransformComponent>()?.localToWorldInto(toWorld);
    final toLocal = Matrix4.identity();
    if (toLocal.copyInverse(toWorld) == 0) toLocal.setIdentity();
    return (toWorld, toLocal);
  }

  /// The cell the pointer is over: next to the surface it is on for a
  /// paint on surfaces, in the surface for an erase or a pick, and on the
  /// floor level — or [onFloor] — otherwise.
  GridCell? _cellAt(SpaceContext space, MeshLibrary library, {required bool inside, int? onFloor}) {
    final (_, toLocal) = _spaceOf(_target ?? target);
    final size = library.cellSize;
    Vector3 local(Vector3 world) {
      final out = Vector3.zero();
      toLocal.transformPointInto(world, out);
      return out;
    }

    if (onFloor == null && (inside || onSurfaces.value)) {
      final hit = space.surface();
      if (hit.onto != null) {
        final normal = Vector3.copy(hit.normal)..normalize();
        final probe = hit.position + normal * (size * 0.5 * (inside ? -1 : 1));
        return GridTiles3D.cellAt(local(probe), size);
      }
      if (inside) return null;
    }
    // +Y is down: floor n is n cells up.
    final storey = onFloor ?? floor.value;
    final level = -storey * size;
    final ray = space.ray;
    final origin = local(ray.origin), ahead = local(ray.origin + ray.direction);
    final direction = ahead - origin;
    if (direction.y.abs() < 1e-9) return null;
    final t = (level - origin.y) / direction.y;
    if (t < 0) return null;
    final at = origin + direction * t;
    final cell = GridTiles3D.cellAt(at, size);
    return (x: cell.x, y: -storey - 1, z: cell.z);
  }

  void _show(GridCell? from, GridCell? to, MeshLibrary library) {
    if (from == null || to == null) {
      preview.value = null;
      return;
    }
    final (toWorld, _) = _spaceOf(_target ?? target);
    preview.value = GridTilePreview(
      from: from,
      to: to,
      cellSize: library.cellSize,
      toWorld: toWorld,
      erasing: mode.value == GridTileMode.erase,
    );
  }

  /// The tiles painted into, made when there are none.
  GridTiles3D _tilesFor() {
    final existing = _target ?? target;
    if (existing != null) {
      _target = existing;
      return existing.getComponent<GridTiles3D>()!;
    }
    final tiles = GridTiles3D(library: library.value);
    _target = designer.world.createEntityWithComponents(
      [
        TransformComponent(),
        tiles,
        RigidBody3D(bodyType: BodyType3D.static),
        Collider3D(shape: ColliderShape3D.matchShape),
      ],
      name: designer.uniqueName('Tiles'),
    );
    _madeTarget = true;
    return tiles;
  }

  void _put(GridCell cell) {
    final tiles = _tilesFor();
    final key = GridTiles3D.keyOf(cell.x, cell.y, cell.z);
    _before.putIfAbsent(key, () => tiles.cells[key]);
    if (mode.value == GridTileMode.erase) {
      tiles.clearTile(cell.x, cell.y, cell.z);
    } else {
      tiles.setTile(cell.x, cell.y, cell.z, item.value, orientation.value);
    }
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    final loaded = loadedLibrary;
    if (space == null) return false;
    if (loaded == null) {
      context.controller.setStatus(library.value.isEmpty ? 'Choose a mesh library in the Tiles panel' : 'Loading ${library.value}…');
      return true;
    }
    if (context.isAltDown) {
      _pick(space, loaded, context);
      return true;
    }
    _begin();
    final cell = _cellAt(space, loaded, inside: mode.value == GridTileMode.erase);
    if (cell == null) return true;
    if (mode.value == GridTileMode.fill) {
      _fillFrom = cell;
      _show(cell, cell, loaded);
      return true;
    }
    _last = cell;
    _put(cell);
    _show(cell, cell, loaded);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space, loaded = loadedLibrary;
    if (space == null || loaded == null) return;
    if (mode.value == GridTileMode.fill) {
      final from = _fillFrom;
      if (from == null) return;
      // On the floor level the fill started on.
      final to = _cellAt(space, loaded, inside: false, onFloor: -from.y - 1);
      if (to != null) _show(from, to, loaded);
      return;
    }
    if (_last == null) return;
    final cell = _cellAt(space, loaded, inside: mode.value == GridTileMode.erase);
    if (cell == null || cell == _last) return;
    _last = cell;
    _put(cell);
    _show(cell, cell, loaded);
  }

  @override
  void onPointerUp(ToolContext context) {
    final loaded = loadedLibrary;
    if (mode.value == GridTileMode.fill && _fillFrom != null && loaded != null) {
      final box = preview.value;
      if (box != null) {
        for (var x = math.min(box.from.x, box.to.x); x <= math.max(box.from.x, box.to.x); x++) {
          for (var z = math.min(box.from.z, box.to.z); z <= math.max(box.from.z, box.to.z); z++) {
            _put((x: x, y: box.from.y, z: z));
          }
        }
      }
    }
    _commit(context);
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space, loaded = loadedLibrary;
    if (space == null || loaded == null) {
      preview.value = null;
      return;
    }
    final cell = _cellAt(space, loaded, inside: mode.value == GridTileMode.erase);
    _show(cell, cell, loaded);
  }

  void _begin() {
    _before.clear();
    _target = null;
    _madeTarget = false;
    _fillFrom = null;
    _last = null;
  }

  void _commit(ToolContext context) {
    final target = _target;
    final changed = {for (final MapEntry(:key, :value) in _before.entries) if (target?.getComponent<GridTiles3D>()?.cells[key] != value) key: value};
    _fillFrom = null;
    _last = null;
    if (target == null) return;
    final tiles = target.getComponent<GridTiles3D>()!;
    final verb = mode.value == GridTileMode.erase ? 'Erase' : (mode.value == GridTileMode.fill ? 'Fill' : 'Paint');
    if (_madeTarget) {
      adoptEntities(designer, [target], '$verb tiles');
    } else if (changed.isNotEmpty) {
      designer.history.pushApplied(
        GridTileStrokeCommand(
          label: '$verb ${changed.length} tile${changed.length == 1 ? '' : 's'}',
          world: designer.world,
          sceneState: designer.sceneState,
          entityName: target.name!,
          before: changed,
          after: {for (final key in changed.keys) key: tiles.cells[key]},
        ),
      );
      designer.sceneState.markDirty();
    }
    context.controller.setStatus('${tiles.cells.length} tiles');
    _before.clear();
    _madeTarget = false;
    _target = null;
  }

  /// Takes the piece under the pointer up: its item and turn.
  void _pick(SpaceContext space, MeshLibrary loaded, ToolContext context) {
    final tiles = (target)?.getComponent<GridTiles3D>();
    final cell = _cellAt(space, loaded, inside: true);
    final tile = cell == null ? null : tiles?.tileAt(cell.x, cell.y, cell.z);
    if (tile == null) {
      context.controller.setStatus('No tile there');
      return;
    }
    item.value = tile.item;
    orientation.value = tile.orientation;
    context.controller.setStatus('Picked ${loaded.item(tile.item)?.name ?? 'piece ${tile.item}'}');
  }

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (key == LogicalKeyboardKey.escape && (_target != null || _fillFrom != null)) {
      _cancelStroke();
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown) {
      floor.value += key == LogicalKeyboardKey.pageUp ? 1 : -1;
      context.controller.setStatus('Floor ${floor.value}');
      onPointerHover(context);
      return true;
    }
    // A letter with a modifier is not the bare letter: the primary one and
    // Alt, and the one no shortcut is made with (Ctrl on a Mac).
    if (context.isCtrlDown || context.isAltDown || context.modifiers.other) {
      return false;
    }
    final axis = switch (key) {
      LogicalKeyboardKey.keyZ => 1,
      LogicalKeyboardKey.keyX => 0,
      LogicalKeyboardKey.keyC => 2,
      _ => -1,
    };
    if (axis < 0) return false;
    orientation.value = GridOrientations.turned(orientation.value, axis, context.isShiftDown ? -1 : 1);
    context.controller.setStatus('Turned: ${orientation.value} of 24');
    return true;
  }

  void _cancelStroke() {
    final target = _target;
    if (target != null) {
      final tiles = target.getComponent<GridTiles3D>()!;
      if (_madeTarget) {
        designer.world.destroyEntity(target);
      } else {
        for (final MapEntry(:key, :value) in _before.entries) {
          if (value == null) {
            tiles.cells.remove(key);
          } else {
            tiles.cells[key] = value;
          }
        }
        tiles.revision++;
      }
    }
    _begin();
    preview.value = null;
  }

  @override
  void onCancel() => _cancelStroke();

  @override
  void onDeactivate() {
    if (_target != null) _cancelStroke();
    preview.value = null;
  }

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SignalBuilder<GridTileMode>(
        signal: mode,
        builder: (context, value, _) => EditorSegmented<GridTileMode>(
          value: value,
          options: [for (final m in GridTileMode.values) (m, m.label)],
          onChanged: (v) => mode.value = v,
        ),
      ),
      const SizedBox(width: 8),
      SignalBuilder<bool>(
        signal: onSurfaces,
        builder: (context, value, _) => EditorSegmented<bool>(
          value: value,
          options: const [(true, 'On surfaces'), (false, 'On floor')],
          onChanged: (v) => onSurfaces.value = v,
        ),
      ),
      const SizedBox(width: 8),
      SignalBuilder<int>(
        signal: floor,
        builder: (context, value, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EditorIconButton(icon: Icons.arrow_downward, tooltip: 'Floor down (Page Down)', onTap: () => floor.value--),
            Text('Floor $value', style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11)),
            EditorIconButton(icon: Icons.arrow_upward, tooltip: 'Floor up (Page Up)', onTap: () => floor.value++),
          ],
        ),
      ),
    ],
  );
}

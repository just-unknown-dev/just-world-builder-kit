import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';
import 'spline_path.dart';
import 'spline_render.dart';
import 'spline_sweep.dart';

/// A [Spline3D]'s points, saved as a list of `{p, in, out, roll, mode}`.
///
/// Read and written as copies, so a value an editor keeps for undo never
/// moves with the spline.
class SplinePointsFieldType extends FieldType<List<SplinePoint>> {
  const SplinePointsFieldType();

  /// The id the editor finds its field editor under.
  static const String typeId = 'worldBuilder.splinePoints';

  @override
  String get id => typeId;

  @override
  Object? encode(List<SplinePoint> value) => [for (final p in value) p.toJson()];

  @override
  Object? decode(Object? json, FieldConstraints constraints) =>
      json is List ? [for (final p in json) SplinePoint.fromJson(p)] : json;
}

/// How the kit's spline components are saved, loaded and shown: all 3-D,
/// in the group "World Builder".
abstract final class SplineSchemas {
  static const String _group = 'World Builder';
  static const Color _accent = Color(0xFF26A69A);

  /// The [SplinePoint] list type.
  static const SplinePointsFieldType splinePoints = SplinePointsFieldType();

  static const _interpolation = EnumFieldType(
    SplineInterpolation.values,
    fallback: SplineInterpolation.catmullRom,
    id: 'worldBuilder.splineInterpolation',
  );
  static const _profile = EnumFieldType(SweepProfile.values, fallback: SweepProfile.road, id: 'worldBuilder.sweepProfile');
  static const _followMode = EnumFieldType(FollowMode.values, fallback: FollowMode.pingPong, id: 'worldBuilder.followMode');

  /// Every one.
  static List<ComponentSchema> get all => [spline, sweep, instances, follower];

  static ComponentHints _hints(String name, String description, IconData icon, Map<String, FieldHint> fields) =>
      ComponentHints(
        dimensions: Dimensions.threeD,
        name: name,
        group: _group,
        description: description,
        icon: icon,
        accentColor: _accent,
        fields: fields,
      );

  static FieldHint _num(String label, String suffix, {double step = 0.1, int digits = 2, String? description}) =>
      FieldHint(
        label: label,
        description: description,
        scrub: ScrubHint(step: step, fractionDigits: digits, suffix: suffix),
      );

  /// [Spline3D].
  static ComponentSchema<Spline3D> get spline => ComponentSchema<Spline3D>(
    type: 'Spline3D',
    id: 'spline_3d_5d1e8a37',
    create: Spline3D.new,
    extent: const _SplineExtent(),
    hints: _hints(
      'Spline 3D',
      'A path through space, in its entity\'s own space: a road\'s line, a rail\'s, the way a platform goes.',
      Icons.gesture,
      {
        'points': const FieldHint(label: 'Points', description: 'Drag them in the viewport with the Spline tool.'),
        'closed': const FieldHint(label: 'Closed', description: 'Runs on from its last point back to its first.'),
        'interpolation': const FieldHint(label: 'Curve'),
      },
    ),
    fields: [
      SchemaField(
        name: 'points',
        kind: splinePoints,
        read: (c) => [for (final p in (c as Spline3D).points) p.copy()],
        write: (c, v) => (c as Spline3D).points = [
          for (final p in (v as List?) ?? const []) p is SplinePoint ? p.copy() : SplinePoint.fromJson(p),
        ],
      ),
      _bool<Spline3D>('closed', (c) => c.closed, (c, v) => c.closed = v),
      SchemaField(
        name: 'interpolation',
        kind: _interpolation,
        read: (c) => (c as Spline3D).interpolation,
        write: (c, v) => (c as Spline3D).interpolation = v as SplineInterpolation,
      ),
    ],
  );

  static bool _isPipe(Component c) => (c as SplineSweep3D).profile == SweepProfile.pipe;
  static bool _notPipe(Component c) => !_isPipe(c);
  static bool _ownLook(Component c) => (c as SplineSweep3D).material.isEmpty;

  /// [SplineSweep3D].
  static ComponentSchema<SplineSweep3D> get sweep => ComponentSchema<SplineSweep3D>(
    type: 'SplineSweep3D',
    id: 'spline_sweep_3d_9b47c2e0',
    create: SplineSweep3D.new,
    extent: const _SweepExtent(),
    hints: _hints(
      'Spline Sweep 3D',
      'A road, wall, pipe or rail swept along its entity\'s spline. Solid through a Collider 3D set to match its shape.',
      Icons.add_road,
      {
        'profile': const FieldHint(label: 'Profile'),
        'width': const FieldHint(
          label: 'Width',
          visibleWhen: _notPipe,
          scrub: ScrubHint(step: 0.1, fractionDigits: 2, suffix: 'm'),
        ),
        'height': const FieldHint(
          label: 'Height',
          visibleWhen: _notPipe,
          scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
        ),
        'radius': const FieldHint(
          label: 'Radius',
          visibleWhen: _isPipe,
          scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
        ),
        'sides': const FieldHint(label: 'Sides', visibleWhen: _isPipe),
        'step': _num('Step', 'm', description: 'How far apart its cross-sections are: smaller is smoother.'),
        'material': const FieldHint(
          label: 'Material',
          description: 'A material file; empty for its colour.',
          fileExtensions: ['material.json'],
        ),
        'color': const FieldHint(label: 'Colour', visibleWhen: _ownLook),
        'tiling': _num('Tiling', '×', description: 'How many times its material repeats a metre along it.'),
        'castShadows': const FieldHint(label: 'Shadows'),
      },
    ),
    fields: [
      SchemaField(
        name: 'profile',
        kind: _profile,
        read: (c) => (c as SplineSweep3D).profile,
        write: (c, v) => (c as SplineSweep3D).profile = v as SweepProfile,
      ),
      _decimal<SplineSweep3D>('width', (c) => c.width, (c, v) => c.width = v),
      _decimal<SplineSweep3D>('height', (c) => c.height, (c, v) => c.height = v),
      _decimal<SplineSweep3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _decimal<SplineSweep3D>('step', (c) => c.step, (c, v) => c.step = v),
      _int<SplineSweep3D>('sides', (c) => c.sides, (c, v) => c.sides = v),
      SchemaField(
        name: 'material',
        kind: FieldTypes.assetRef,
        read: (c) => (c as SplineSweep3D).material,
        write: (c, v) => (c as SplineSweep3D).material = v as String? ?? '',
      ),
      SchemaField(
        name: 'color',
        kind: FieldTypes.color,
        read: (c) => (c as SplineSweep3D).color,
        write: (c, v) => (c as SplineSweep3D).color = v as Color,
      ),
      _decimal<SplineSweep3D>('tiling', (c) => c.tiling, (c, v) => c.tiling = v),
      _bool<SplineSweep3D>('castShadows', (c) => c.castShadows, (c, v) => c.castShadows = v),
    ],
  );

  /// [SplineInstances3D].
  static ComponentSchema<SplineInstances3D> get instances => ComponentSchema<SplineInstances3D>(
    type: 'SplineInstances3D',
    id: 'spline_instances_3d_e3a6f514',
    create: SplineInstances3D.new,
    extent: const _InstancesExtent(),
    hints: _hints(
      'Spline Instances 3D',
      'Copies of a model laid along its entity\'s spline — posts, lamps, trees — drawn in one go.',
      Icons.more_horiz,
      {
        'model': const FieldHint(
          label: 'Model',
          description: 'What each copy shows; empty for a metre cube.',
          fileExtensions: ['glb', 'gltf'],
        ),
        'spacing': _num('Spacing', 'm'),
        'startAt': _num('Start', 'm', description: 'How far along the first one is.'),
        'sideOffset': _num('Side', 'm', description: 'How far to the right of the spline they stand.'),
        'alignToPath': const FieldHint(label: 'Face along'),
        'scale': _num('Scale', '×', step: 0.05),
        'maxDistance': _num('Reach', 'm', step: 1, digits: 0, description: 'Not drawn beyond this far from the camera; 0 for always.'),
        'castShadows': const FieldHint(label: 'Shadows'),
      },
    ),
    fields: [
      SchemaField(
        name: 'model',
        kind: FieldTypes.assetRef,
        read: (c) => (c as SplineInstances3D).model,
        write: (c, v) => (c as SplineInstances3D).model = v as String? ?? '',
      ),
      _decimal<SplineInstances3D>('spacing', (c) => c.spacing, (c, v) => c.spacing = v),
      _decimal<SplineInstances3D>('startAt', (c) => c.startAt, (c, v) => c.startAt = v),
      _decimal<SplineInstances3D>('sideOffset', (c) => c.sideOffset, (c, v) => c.sideOffset = v),
      _bool<SplineInstances3D>('alignToPath', (c) => c.alignToPath, (c, v) => c.alignToPath = v),
      _decimal<SplineInstances3D>('scale', (c) => c.scale, (c, v) => c.scale = v),
      _decimal<SplineInstances3D>('maxDistance', (c) => c.maxDistance, (c, v) => c.maxDistance = v),
      _bool<SplineInstances3D>('castShadows', (c) => c.castShadows, (c, v) => c.castShadows = v),
    ],
  );

  /// [PathFollower3D].
  static ComponentSchema<PathFollower3D> get follower => ComponentSchema<PathFollower3D>(
    type: 'PathFollower3D',
    id: 'path_follower_3d_47c90b2d',
    create: PathFollower3D.new,
    hints: _hints(
      'Path Follower 3D',
      'Moves its entity along another\'s spline — a platform\'s route (give it a kinematic body), a train\'s track.',
      Icons.route,
      {
        'path': const FieldHint(label: 'Path', description: 'The entity whose Spline 3D it follows.'),
        'speed': _num('Speed', 'm/s'),
        'mode': const FieldHint(label: 'Mode'),
        'wait': _num('Rest', 's', description: 'Seconds it rests at each end.'),
        'startAt': _num('Start', 'm', description: 'How far along it starts.'),
        'faceAlong': const FieldHint(label: 'Face along', description: 'Turns to face the way it goes.'),
      },
    ),
    fields: [
      SchemaField(
        name: 'path',
        kind: FieldTypes.target,
        read: (c) => (c as PathFollower3D).path,
        write: (c, v) => (c as PathFollower3D).path = v as EntityTarget? ?? EntityTarget.none,
      ),
      _decimal<PathFollower3D>('speed', (c) => c.speed, (c, v) => c.speed = v),
      SchemaField(
        name: 'mode',
        kind: _followMode,
        read: (c) => (c as PathFollower3D).mode,
        write: (c, v) => (c as PathFollower3D).mode = v as FollowMode,
      ),
      _decimal<PathFollower3D>('wait', (c) => c.wait, (c, v) => c.wait = v),
      _decimal<PathFollower3D>('startAt', (c) => c.startAt, (c, v) => c.startAt = v),
      _bool<PathFollower3D>('faceAlong', (c) => c.faceAlong, (c, v) => c.faceAlong = v),
    ],
  );

  static SchemaField _decimal<T extends Component>(
    String name,
    double Function(T c) read,
    void Function(T c, double v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toDouble()),
  );

  static SchemaField _int<T extends Component>(
    String name,
    int Function(T c) read,
    void Function(T c, int v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toInt()),
  );

  static SchemaField _bool<T extends Component>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool),
  );
}

/// A box's size seen from the front, for 2-D layouts.
Size? _front(Aabb3 b) => b.isEmpty ? null : Size(b.max.x - b.min.x, b.max.y - b.min.y);

final Expando<(Object, SplinePath)> _paths = Expando();

/// [spline]'s path, sampled again only when it changed.
SplinePath _pathOf(Spline3D spline) {
  final key = spline.shapeKey;
  final known = _paths[spline];
  if (known != null && known.$1 == key) return known.$2;
  final path = SplinePath.of(spline, perSegment: 8);
  _paths[spline] = (key, path);
  return path;
}

/// A spline takes up the box round its path, and a little more: what
/// picks and frames a bare path.
final class _SplineExtent extends ComponentExtent {
  const _SplineExtent();

  static const double margin = 0.3;

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    return boundsInto(component, b) ? _front(b) : null;
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final positions = _pathOf(component as Spline3D).positions;
    if (positions.isEmpty) return false;
    out.setEmpty();
    for (final p in positions) {
      out.addXYZ(p.x, p.y, p.z);
    }
    out.setValues(
      out.min.x - margin,
      out.min.y - margin,
      out.min.z - margin,
      out.max.x + margin,
      out.max.y + margin,
      out.max.z + margin,
    );
    return true;
  }
}

/// A sweep takes up its mesh, once tied to its spline.
final class _SweepExtent extends ComponentExtent {
  const _SweepExtent();

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    return boundsInto(component, b) ? _front(b) : null;
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final sweep = component as SplineSweep3D;
    final spline = sweep.spline;
    if (spline == null) return false;
    final mesh = SplineSweeper.meshFor(sweep, spline);
    if (mesh == null) return false;
    out.setEmpty();
    final p = mesh.positions;
    for (var i = 0; i + 2 < p.length; i += 3) {
      out.addXYZ(p[i], p[i + 1], p[i + 2]);
    }
    return !out.isEmpty;
  }
}

/// Copies along a spline take up where they stand, a metre round each
/// (as big as they are drawn).
final class _InstancesExtent extends ComponentExtent {
  const _InstancesExtent();

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    return boundsInto(component, b) ? _front(b) : null;
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final c = component as SplineInstances3D;
    final spline = c.spline;
    if (spline == null) return false;
    final places = InstancesRenderProvider.placements(c, _pathOf(spline));
    if (places.isEmpty) return false;
    final r = c.scale.abs();
    out.setEmpty();
    for (final m in places) {
      final s = m.storage;
      out
        ..addXYZ(s[12] - r, s[13] - 2 * r, s[14] - r)
        ..addXYZ(s[12] + r, s[13] + r * 0.1, s[14] + r);
    }
    return true;
  }
}

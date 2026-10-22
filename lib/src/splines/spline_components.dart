import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart';

import 'spline_sweep.dart';

/// How a [Spline3D] runs between its points.
enum SplineInterpolation {
  /// Smoothly through every point, its tangents worked out from its
  /// neighbours.
  catmullRom,

  /// Smoothly through every point, shaped by each point's own handles.
  bezier,

  /// Straight from point to point.
  linear,
}

/// How a point's two handles move together, as they are dragged.
enum SplineTangentMode {
  /// Worked out from the neighbours, not dragged.
  auto,

  /// Opposite each other: dragging one turns the other.
  aligned,

  /// Each its own: a corner.
  free,
}

/// One point of a [Spline3D], in its entity's own space: where it is, its
/// handles (relative to it, for [SplineInterpolation.bezier]), and how far
/// what is laid along the spline is rolled about it there.
final class SplinePoint {
  SplinePoint({
    Vector3? position,
    Vector3? inTangent,
    Vector3? outTangent,
    this.roll = 0,
    this.mode = SplineTangentMode.auto,
  }) : position = position ?? Vector3.zero(),
       inTangent = inTangent ?? Vector3.zero(),
       outTangent = outTangent ?? Vector3.zero();

  /// Where it is.
  Vector3 position;

  /// Its handles, relative to [position]: the way the spline comes in, and
  /// goes out.
  Vector3 inTangent, outTangent;

  /// The roll about the spline here (radians).
  double roll;

  SplineTangentMode mode;

  SplinePoint copy() => SplinePoint(
    position: Vector3.copy(position),
    inTangent: Vector3.copy(inTangent),
    outTangent: Vector3.copy(outTangent),
    roll: roll,
    mode: mode,
  );

  /// Equal while it is the same.
  Object get key => Object.hash(
    position.x,
    position.y,
    position.z,
    inTangent.x,
    inTangent.y,
    inTangent.z,
    outTangent.x,
    outTangent.y,
    outTangent.z,
    roll,
    mode,
  );

  Map<String, Object?> toJson() => {
    'p': [position.x, position.y, position.z],
    if (inTangent.lengthSquared > 0) 'in': [inTangent.x, inTangent.y, inTangent.z],
    if (outTangent.lengthSquared > 0) 'out': [outTangent.x, outTangent.y, outTangent.z],
    if (roll != 0) 'roll': roll,
    if (mode != SplineTangentMode.auto) 'mode': mode.name,
  };

  static Vector3? _vector(Object? json) {
    if (json is! List || json.length < 3) return null;
    double n(Object? v) => v is num ? v.toDouble() : 0;
    return Vector3(n(json[0]), n(json[1]), n(json[2]));
  }

  factory SplinePoint.fromJson(Object? json) {
    if (json is! Map) return SplinePoint();
    final mode = json['mode'];
    return SplinePoint(
      position: _vector(json['p']),
      inTangent: _vector(json['in']),
      outTangent: _vector(json['out']),
      roll: (json['roll'] as num?)?.toDouble() ?? 0,
      mode: SplineTangentMode.values.where((m) => m.name == mode).firstOrNull ?? SplineTangentMode.auto,
    );
  }
}

/// A path through space — a road's line, a rail's, the way a platform
/// goes — of [points] in its entity's own space. What is laid along it
/// ([SplineSweep3D], [SplineInstances3D]) and what follows it
/// ([PathFollower3D]) read it.
class Spline3D extends Component {
  Spline3D({List<SplinePoint>? points, this.closed = false, this.interpolation = SplineInterpolation.catmullRom})
    : points = points ?? [];

  List<SplinePoint> points;

  /// Whether it runs on from its last point back to its first.
  bool closed;

  SplineInterpolation interpolation;

  /// Equal for as long as its shape stays the same.
  Object get shapeKey => Object.hash(closed, interpolation, Object.hashAll([for (final p in points) p.key]));
}

/// A cross-section a [SplineSweep3D] sweeps along its spline.
enum SweepProfile {
  /// A flat deck to walk on: [SplineSweep3D.width] across,
  /// [SplineSweep3D.height] thick, its top on the spline.
  road,

  /// A wall standing on the spline: [SplineSweep3D.width] thick,
  /// [SplineSweep3D.height] high.
  wall,

  /// A tube round the spline, [SplineSweep3D.radius] across.
  pipe,

  /// A bar along the spline: [SplineSweep3D.width] by
  /// [SplineSweep3D.height], standing on it.
  rail,
}

/// A solid swept along its entity's [Spline3D]: a road, a wall, a pipe, a
/// rail. Drawn by the kit's renderer; solid — for what stands still, or is
/// moved by hand — through a `Collider3D` set to match its shape.
class SplineSweep3D extends Component implements SolidShapeSource {
  SplineSweep3D({
    this.profile = SweepProfile.road,
    this.width = 3,
    this.height = 0.3,
    this.radius = 0.5,
    this.step = 1,
    this.sides = 12,
    this.material = '',
    this.color = const Color(0xFF9E9E9E),
    this.tiling = 1,
    this.castShadows = true,
  });

  SweepProfile profile;

  /// Across (road, rail) or thick (wall), in metres.
  double width;

  /// Thick (road) or high (wall, rail), in metres.
  double height;

  /// A pipe's radius, in metres.
  double radius;

  /// How far apart, along the spline, its cross-sections are (metres):
  /// smaller is smoother and heavier.
  double step;

  /// How many sides a pipe has.
  int sides;

  /// A material file it is drawn with; empty for [color].
  String material;

  /// Its colour without a material file.
  Color color;

  /// How many times a material's maps repeat a metre along it.
  double tiling;

  bool castShadows;

  /// The spline it was last swept along (its entity's, linked by whoever
  /// draws or collides it): runtime only.
  Spline3D? spline;

  // The mesh the last sweep made, and what it was made from.
  SweptMesh? cached;
  Object? cachedKey;

  /// Equal while what it would sweep stays the same.
  Object get sweepKey => Object.hash(
    profile,
    width,
    height,
    radius,
    step,
    sides,
    tiling,
    spline?.shapeKey,
  );

  @override
  Object get solidKey => sweepKey;

  @override
  List<SolidPart> get solidParts {
    final linked = spline;
    if (linked == null) return const [];
    final mesh = SplineSweeper.meshFor(this, linked);
    if (mesh == null || mesh.triangleCount == 0) return const [];
    return [SolidMesh(mesh.positions, mesh.indices)];
  }
}

/// Triangles a sweep made: positions, normals and texture coordinates per
/// point, three indices per triangle.
final class SweptMesh {
  SweptMesh(this.positions, this.normals, this.uvs, this.indices);

  final Float32List positions, normals, uvs;
  final Uint32List indices;

  int get triangleCount => indices.length ~/ 3;
}

/// Copies of a model laid along its entity's [Spline3D] — fence posts,
/// lamps, trees by a road — [spacing] apart, drawn in one go. The editor
/// can make them entities of their own.
class SplineInstances3D extends Component {
  SplineInstances3D({
    this.model = '',
    this.spacing = 2,
    this.startAt = 0,
    this.sideOffset = 0,
    this.alignToPath = true,
    this.scale = 1,
    this.maxDistance = 0,
    this.castShadows = true,
  });

  /// The model (`.glb`, `.gltf`) each copy shows; empty for a metre cube.
  String model;

  /// Metres between copies along the spline.
  double spacing;

  /// How far along the first one is.
  double startAt;

  /// How far to the side of the spline they stand (metres; right is
  /// positive).
  double sideOffset;

  /// Whether each turns to face along the spline.
  bool alignToPath;

  double scale;

  /// Beyond how many metres from the camera they are not drawn; 0 for
  /// always.
  double maxDistance;

  bool castShadows;

  /// The spline they were last laid along (their entity's, linked by
  /// whoever draws them): runtime only.
  Spline3D? spline;

  /// Equal while where they go stays the same.
  Object get layoutKey => Object.hash(spacing, startAt, sideOffset, alignToPath, scale, spline?.shapeKey);
}

/// How a [PathFollower3D] goes along its spline.
enum FollowMode {
  /// To the end, then round again from the start.
  loop,

  /// To the end and back, and again.
  pingPong,

  /// To the end, and stops.
  once,
}

/// Moves its entity along a spline — a platform's route, a train's track:
/// [speed] metres a second, pausing [wait] seconds at each end. A
/// kinematic body is carried along, and characters standing on it with it.
class PathFollower3D extends Component {
  PathFollower3D({
    EntityTarget? path,
    this.speed = 2,
    this.mode = FollowMode.pingPong,
    this.wait = 1,
    this.startAt = 0,
    this.faceAlong = false,
  }) : path = path ?? EntityTarget.none;

  /// The entity whose [Spline3D] it follows.
  EntityTarget path;

  double speed;
  FollowMode mode;

  /// Seconds it rests at each end.
  double wait;

  /// How far along it starts (metres).
  double startAt;

  /// Whether it turns to face the way it goes.
  bool faceAlong;

  /// Runtime: how far along it is, which way it goes, how long it rests.
  double travelled = double.nan;
  double direction = 1;
  double resting = 0;
}

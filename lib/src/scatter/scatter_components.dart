import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_deflate/just_deflate.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// How a scattered piece is solid.
enum ScatterCollision {
  /// Not at all: grass, flowers.
  none,

  /// As an upright box: rocks, crates.
  box,

  /// As an upright capsule: trees, posts.
  capsule,
}

/// The engine shape a scatter layer's pieces are, when they show no model:
/// about a metre tall, of the layer's colour, standing on their spot.
enum ScatterShape {
  cone('Cone'),
  cube('Cube'),
  sphere('Sphere'),
  cylinder('Cylinder'),
  capsule('Capsule');

  const ScatterShape(this.label);

  final String label;
}

/// One kind of thing a [Scatter3D] scatters — grass, rocks, trees — and how:
/// at least [spacing] metres apart, sized between [minScale] and
/// [maxScale], turned at random, leaning with the ground or upright.
final class ScatterLayer {
  ScatterLayer({
    this.name = 'Layer',
    this.model = '',
    this.shape = ScatterShape.cone,
    this.color = const Color(0xFF558B2F),
    this.spacing = 1.5,
    this.minScale = 0.8,
    this.maxScale = 1.2,
    this.randomYaw = true,
    this.alignToNormal = false,
    this.maxDistance = 80,
    this.collision = ScatterCollision.none,
    this.colliderRadius = 0.4,
    this.colliderHeight = 1.2,
  });

  String name;

  /// The model (`.glb`, `.gltf`) each piece shows; empty for [shape].
  String model;

  /// The shape each piece is without a [model], of [color].
  ScatterShape shape;

  Color color;

  /// The least distance between two of its pieces (metres).
  double spacing;

  double minScale, maxScale;

  /// Whether each piece is turned at random about its up.
  bool randomYaw;

  /// Whether each piece leans with the ground under it.
  bool alignToNormal;

  /// Beyond how many metres from the camera its pieces are not drawn; 0
  /// for always.
  double maxDistance;

  ScatterCollision collision;

  /// The solid part of a piece, at scale 1 (metres): half as wide as it
  /// is across, and as tall as it is. As big as the cone a new layer
  /// shows, until it is set for what the layer shows.
  double colliderRadius, colliderHeight;

  ScatterLayer copy() => ScatterLayer.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'name': name,
    if (model.isNotEmpty) 'model': model,
    if (shape != ScatterShape.cone) 'shape': shape.name,
    'color': color.toARGB32(),
    'spacing': spacing,
    'minScale': minScale,
    'maxScale': maxScale,
    'randomYaw': randomYaw,
    'alignToNormal': alignToNormal,
    'maxDistance': maxDistance,
    'collision': collision.name,
    'colliderRadius': colliderRadius,
    'colliderHeight': colliderHeight,
  };

  factory ScatterLayer.fromJson(Object? json) {
    if (json is! Map) return ScatterLayer();
    double n(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
    return ScatterLayer(
      name: json['name'] as String? ?? 'Layer',
      model: json['model'] as String? ?? '',
      shape: ScatterShape.values.where((s) => s.name == json['shape']).firstOrNull ?? ScatterShape.cone,
      color: Color(json['color'] is int ? json['color'] as int : 0xFF558B2F),
      spacing: n(json['spacing'], 1.5),
      minScale: n(json['minScale'], 0.8),
      maxScale: n(json['maxScale'], 1.2),
      randomYaw: json['randomYaw'] as bool? ?? true,
      alignToNormal: json['alignToNormal'] as bool? ?? false,
      maxDistance: n(json['maxDistance'], 80),
      collision: ScatterCollision.values.where((c) => c.name == json['collision']).firstOrNull ?? ScatterCollision.none,
      colliderRadius: n(json['colliderRadius'], 0.4),
      colliderHeight: n(json['colliderHeight'], 1.2),
    );
  }

  /// Equal while it would scatter and draw the same.
  Object get key => jsonEncode(toJson());
}

/// One scattered piece: of layer [layer], standing at [position] (its
/// entity's space), turned [yaw] about its up, grown by [scale], leaning
/// with [normal] (unit; up is -Y).
final class ScatterInstance {
  ScatterInstance({required this.layer, required this.position, this.yaw = 0, this.scale = 1, Vector3? normal})
    : normal = normal ?? Vector3(0, -1, 0);

  final int layer;
  final Vector3 position;
  final double yaw, scale;
  final Vector3 normal;

  /// How it is turned: [yaw] about its up, then leant with [normal] when
  /// [lean].
  Quaternion turn({bool lean = false}) {
    final turn = Quaternion.axisAngle(Vector3(0, 1, 0), yaw);
    if (lean) {
      final up = Vector3(0, -1, 0), n = Vector3.copy(normal)..normalize();
      final axis = up.cross(n);
      final s = axis.length;
      if (s > 1e-6) {
        turn.premultiply(Quaternion.axisAngle(axis..normalize(), math.atan2(s, up.dot(n))));
      }
    }
    return turn;
  }

  /// Where it is drawn: moved, leant, turned and grown.
  Matrix4 matrix({bool lean = false}) =>
      Matrix4.identity()..setFromTrs(position, turn(lean: lean), Vector3(scale, scale, scale));
}

/// Things scattered over the ground — grass, flowers, rocks, trees — of a
/// few [layers], painted with the Scatter brush: drawn many to a draw and
/// not at all far off; solid, for layers that say so, through a
/// `Collider3D` set to match its shape.
class Scatter3D extends Component implements SolidShapeSource {
  Scatter3D({List<ScatterLayer>? layers, List<ScatterInstance>? instances, this.cellSize = 32, this.castShadows = true})
    : layers = layers ?? [ScatterLayer(name: 'Grass')],
      instances = instances ?? [];

  List<ScatterLayer> layers;

  /// Every piece, changed through edits that bump [revision].
  List<ScatterInstance> instances;

  /// Metres a side of each square its pieces are drawn in.
  double cellSize;

  bool castShadows;

  /// Runtime: bumped whenever [layers] or [instances] change.
  int revision = 0;

  (int, List<SolidPart>)? _solid;

  // Equal only to itself: what keeps this scatter's solid key its own.
  // Every scatter read from a scene has the same [revision].
  final Object _identity = Object();

  /// This scatter's own, and its [revision]: a physics engine that keeps
  /// shapes by key never mistakes another scatter for this one.
  @override
  Object get solidKey => (_identity, revision);

  /// Its solid layers' pieces: a box turned and leant as its piece is
  /// drawn, or an upright capsule (a trunk stands up whatever the ground
  /// does), each standing on its spot.
  @override
  List<SolidPart> get solidParts {
    final known = _solid;
    if (known != null && known.$1 == revision) return known.$2;
    final parts = <SolidPart>[];
    for (final i in instances) {
      if (i.layer < 0 || i.layer >= layers.length) continue;
      final l = layers[i.layer];
      final r = l.colliderRadius * i.scale, h = l.colliderHeight * i.scale;
      // Upright, standing on its spot: its middle half its height up.
      final p = i.position;
      switch (l.collision) {
        case ScatterCollision.none:
          break;
        case ScatterCollision.box:
          final turn = i.turn(lean: l.alignToNormal);
          if (turn.w.abs() >= 1 - 1e-12) {
            parts.add(SolidBox(r, h / 2, r, x: p.x, y: p.y - h / 2, z: p.z));
            break;
          }
          // Turned: its eight corners, as the piece is turned.
          final corners = Float32List(24);
          var k = 0;
          for (final cx in [-r, r]) {
            for (final cy in [0.0, -h]) {
              for (final cz in [-r, r]) {
                final v = Vector3(cx, cy, cz);
                turn.rotate(v);
                corners
                  ..[k++] = p.x + v.x
                  ..[k++] = p.y + v.y
                  ..[k++] = p.z + v.z;
              }
            }
          }
          parts.add(SolidHull(corners));
        case ScatterCollision.capsule:
          parts.add(SolidCapsule(math.max(0, h / 2 - r), r, x: p.x, y: p.y - h / 2, z: p.z));
      }
    }
    _solid = (revision, parts);
    return parts;
  }
}

/// A [Scatter3D]'s layers, saved as a list.
class ScatterLayersFieldType extends FieldType<List<ScatterLayer>> {
  const ScatterLayersFieldType();

  static const String typeId = 'worldBuilder.scatterLayers';

  @override
  String get id => typeId;

  @override
  Object? encode(List<ScatterLayer> value) => [for (final l in value) l.toJson()];

  @override
  Object? decode(Object? json, FieldConstraints constraints) => json is List ? [for (final l in json) ScatterLayer.fromJson(l)] : json;
}

/// A [Scatter3D]'s pieces, saved as base64 of zlib-packed records: a
/// version byte, then per piece its layer (8 bits), position, turn, size
/// and lean (32-bit floats).
class ScatterInstancesFieldType extends FieldType<List<ScatterInstance>> {
  const ScatterInstancesFieldType();

  static const String typeId = 'worldBuilder.scatterInstances';

  static const int _version = 1;
  static const int _record = 29;

  /// The most bytes the pieces may unpack to (64 MB, two million pieces):
  /// a damaged text fails at once instead of filling memory.
  static const int maxBytes = 64 << 20;
  static const ZlibCodec _zlib = ZlibCodec();

  @override
  String get id => typeId;

  @override
  Object? encode(List<ScatterInstance> value) => encodeInstances(value);

  @override
  Object? decode(Object? json, FieldConstraints constraints) => json is String ? decodeInstances(json) : json;

  /// [instances] as text.
  static String encodeInstances(List<ScatterInstance> instances) {
    final bytes = ByteData(1 + instances.length * _record)..setUint8(0, _version);
    var o = 1;
    for (final i in instances) {
      bytes
        ..setUint8(o, i.layer.clamp(0, 255))
        ..setFloat32(o + 1, i.position.x, Endian.little)
        ..setFloat32(o + 5, i.position.y, Endian.little)
        ..setFloat32(o + 9, i.position.z, Endian.little)
        ..setFloat32(o + 13, i.yaw, Endian.little)
        ..setFloat32(o + 17, i.scale, Endian.little)
        ..setFloat32(o + 21, i.normal.x, Endian.little)
        ..setFloat32(o + 25, i.normal.z, Endian.little);
      o += _record;
    }
    return base64Encode(_zlib.encode(bytes.buffer.asUint8List()));
  }

  /// The pieces [text] holds; a [FormatException] when it holds none.
  static List<ScatterInstance> decodeInstances(String text) {
    if (text.isEmpty) return [];
    final raw = _zlib.decode(base64Decode(text), maxOutputSize: maxBytes);
    if (raw.isEmpty || raw[0] > _version || (raw.length - 1) % _record != 0) {
      throw const FormatException('Not scattered pieces');
    }
    final b = ByteData.sublistView(raw);
    return [
      for (var o = 1; o < raw.length; o += _record)
        () {
          final nx = b.getFloat32(o + 21, Endian.little), nz = b.getFloat32(o + 25, Endian.little);
          // Up is -Y: the lean's y is what is left of its length, upward.
          final ny = -math.sqrt(math.max(0, 1 - nx * nx - nz * nz));
          return ScatterInstance(
            layer: b.getUint8(o),
            position: Vector3(b.getFloat32(o + 1, Endian.little), b.getFloat32(o + 5, Endian.little), b.getFloat32(o + 9, Endian.little)),
            yaw: b.getFloat32(o + 13, Endian.little),
            scale: b.getFloat32(o + 17, Endian.little),
            normal: Vector3(nx, ny, nz),
          );
        }(),
    ];
  }
}

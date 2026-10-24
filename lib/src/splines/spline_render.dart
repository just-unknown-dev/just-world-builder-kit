import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'spline_components.dart';
import 'spline_path.dart';
import 'spline_sweep.dart';

/// Ties [c] to the [Spline3D] now on the entity it was last drawn on
/// ([owners]): a spline put in another's place — removed, and the removal
/// undone — is followed at once, in the editor too, where the link systems
/// do not run.
void _relink(Component c, Expando<Entity> owners) {
  final owner = owners[c];
  if (owner == null) return;
  final current = owner.getComponent<Spline3D>();
  switch (c) {
    case SplineSweep3D() when !identical(c.spline, current):
      c.spline = current;
    case SplineInstances3D() when !identical(c.spline, current):
      c.spline = current;
    default:
  }
}

/// Draws a [SplineSweep3D]: its swept mesh, in its material file or its
/// colour, made again when the sweep or its spline changes.
final class SweepRenderProvider extends RenderProvider<SplineSweep3D> {
  SweepRenderProvider();

  /// How many plain colours' materials it keeps: the ones drawn last. One
  /// still drawn stays alive with what draws it.
  static const int colourLimit = 64;

  // Least recently used first.
  final Map<int, GpuMaterial> _colours = {};
  ModelUploader? _uploader;
  MaterialLibrary? _library;
  final Expando<Entity> _owners = Expando();

  /// How many plain colours' materials it keeps now.
  int get colourCount => _colours.length;

  @override
  Object? revisionOf(SplineSweep3D sweep) {
    _relink(sweep, _owners);
    return (
      sweep.sweepKey,
      sweep.material,
      sweep.color.toARGB32(),
      sweep.castShadows,
      sweep.material.isEmpty ? null : _library?.revision,
    );
  }

  @override
  void build(RenderProviderContext context, Entity entity, SplineSweep3D sweep, RenderProviderOutput out) {
    _owners[sweep] = entity;
    final spline = entity.getComponent<Spline3D>();
    if (spline == null) return;
    final mesh = SplineSweeper.meshFor(sweep, spline);
    if (mesh == null || mesh.triangleCount == 0) return;
    final primitive = context.uploader.uploadPrimitive(
      ShapeMesh(positions: mesh.positions, normals: mesh.normals, uvs: mesh.uvs, indices: mesh.indices).toPrimitive(),
    );
    _library = context.shapes.library;
    final material =
        (sweep.material.isEmpty ? null : _library?.gpuOf(sweep.material)) ?? _colour(context, sweep.color);
    out.addMesh(primitive, material, castShadows: sweep.castShadows);
  }

  GpuMaterial _colour(RenderProviderContext context, Color color) {
    // Made on one renderer's device: forgotten when another draws.
    if (!identical(_uploader, context.uploader)) {
      _colours.clear();
      _uploader = context.uploader;
    }
    final key = color.toARGB32();
    final material = _colours.remove(key) ?? context.uploader.material(materialData(color));
    _colours[key] = material;
    while (_colours.length > colourLimit) {
      _colours.remove(_colours.keys.first);
    }
    return material;
  }

  /// A plain material of [color].
  static MaterialData materialData(Color color) {
    final (r, g, b) = GraphicsShapes.linear(color);
    return MaterialData(baseColor: (r, g, b, color.a), metallic: 0, roughness: 0.85);
  }
}

/// Draws a [SplineInstances3D]: its model once at each place along its
/// spline, every part of it in one batch.
final class InstancesRenderProvider extends RenderProvider<SplineInstances3D> {
  InstancesRenderProvider();

  GraphicsModels? _models;
  final Expando<Entity> _owners = Expando();

  @override
  Object? revisionOf(SplineInstances3D c) {
    _relink(c, _owners);
    return (
      c.layoutKey,
      c.model,
      c.maxDistance,
      c.castShadows,
      c.model.isEmpty ? true : _models?.get(c.model) != null,
    );
  }

  @override
  void build(RenderProviderContext context, Entity entity, SplineInstances3D c, RenderProviderOutput out) {
    _owners[c] = entity;
    final spline = entity.getComponent<Spline3D>();
    _models = context.models;
    c.spline = spline;
    if (spline == null) return;
    final places = placements(c, SplinePath.of(spline));
    if (places.isEmpty) return;
    final reach = c.maxDistance <= 0 ? double.infinity : c.maxDistance;
    if (c.model.isEmpty) {
      // A metre cube each, standing on the spline.
      final cube = Cube3D();
      final mesh = context.shapes.meshFor(cube, Vector3(1, 1, 1));
      if (mesh == null) return;
      final lift = Matrix4.identity()..setFromTrs(Vector3(0, -0.5, 0), Quaternion.identity(), Vector3(1, 1, 1));
      out.addBatch(
        mesh,
        context.shapes.materialFor(cube),
        [for (final p in places) p.multiplied(lift)],
        maxDistance: reach,
        castShadows: c.castShadows,
      );
      return;
    }
    final model = context.models.get(c.model);
    if (model == null) return;
    for (final part in RenderScene().addModel(model, Matrix4.identity())) {
      out.addBatch(
        part.primitive,
        part.material,
        [for (final p in places) p.multiplied(part.world)],
        maxDistance: reach,
        castShadows: c.castShadows,
      );
    }
  }

  /// Where [c]'s copies go along [path], in its entity's space.
  static List<Matrix4> placements(SplineInstances3D c, SplinePath path) {
    if (path.isEmpty) return const [];
    final spacing = math.max(c.spacing, 0.05);
    final out = <Matrix4>[];
    final end = path.closed ? path.length - spacing * 0.5 : path.length + 1e-9;
    for (var d = math.max(0.0, c.startAt); d <= end && out.length < 10000; d += spacing) {
      if (c.alignToPath) {
        out.add(path.matrixAt(d, side: c.sideOffset, scale: c.scale));
      } else {
        final f = path.at(d);
        final p = f.position + f.right * c.sideOffset;
        out.add(Matrix4.identity()..setFromTrs(p, Quaternion.identity(), Vector3(c.scale, c.scale, c.scale)));
      }
    }
    return out;
  }
}

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../scatter/scatter_components.dart';
import 'scatter_tools.dart' show removeScatterLayer, scatterCollisionLabel, scatterCounts;

/// The inspector's editor for a [Scatter3D]'s layers: a card for each —
/// its colour, name and pieces on top, its settings inside — and Add a
/// layer. Each change is one undo step of the field.
Widget scatterLayersEditor(FieldEditorContext context) => _ScatterLayersEditor(context: context);

/// The inspector's row for a [Scatter3D]'s pieces: how many of each
/// layer, and Clear.
Widget scatterInstancesEditor(FieldEditorContext context) {
  final pieces = [for (final p in (context.value as List?) ?? const []) if (p is ScatterInstance) p];
  final scatter = context.component is Scatter3D ? context.component as Scatter3D : null;
  final layers = scatter?.layers ?? const <ScatterLayer>[];
  final counts = List<int>.filled(layers.length, 0);
  for (final p in pieces) {
    if (p.layer >= 0 && p.layer < counts.length) counts[p.layer]++;
  }
  final each = [
    for (final (i, l) in layers.indexed)
      if (counts[i] > 0) '${counts[i]} ${l.name.toLowerCase()}',
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReadonlyRow(
        label: context.label,
        value: pieces.isEmpty ? 'None yet — paint them with the Scatter brush' : '${pieces.length}: ${each.join(', ')}',
      ),
      if (pieces.isNotEmpty && !context.readOnly)
        Align(
          alignment: Alignment.centerRight,
          child: EditorButton(
            label: 'Clear them all',
            kind: EditorButtonKind.ghost,
            onPressed: () => context.onChanged(const <ScatterInstance>[]),
          ),
        ),
    ],
  );
}

class _ScatterLayersEditor extends StatefulWidget {
  const _ScatterLayersEditor({required this.context});

  final FieldEditorContext context;

  @override
  State<_ScatterLayersEditor> createState() => _ScatterLayersEditorState();
}

class _ScatterLayersEditorState extends State<_ScatterLayersEditor> {
  /// The cards opened, by place.
  final Set<int> _open = {0};

  static const _shape = EnumFieldType(
    ScatterShape.values,
    fallback: ScatterShape.cone,
    id: 'worldBuilder.scatterShape',
  );

  static const _collision = EnumFieldType(
    ScatterCollision.values,
    fallback: ScatterCollision.none,
    id: 'worldBuilder.scatterCollision',
  );

  FieldEditorContext get _c => widget.context;

  List<ScatterLayer> get _layers => [for (final l in (_c.value as List?) ?? const []) if (l is ScatterLayer) l];

  /// The layers with layer [i] changed by [change], written back.
  void _change(int i, void Function(ScatterLayer layer) change) {
    final next = [for (final l in _layers) l.copy()];
    change(next[i]);
    _c.onChanged(next);
  }

  /// One setting of layer [i], with the inspector's own editor for [kind].
  Widget _row(
    int i,
    String name,
    FieldType kind,
    Object? value,
    void Function(ScatterLayer layer, Object? v) write, {
    String? label,
    String? description,
    ScrubHint? scrub,
    List<String>? fileExtensions,
  }) {
    final field = SchemaField(
      name: name,
      kind: kind,
      read: (_) => value,
      write: (_, _) {},
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _c.editors.build(
        FieldEditorContext(
          field: field,
          hint: FieldHint(label: label ?? name, description: description, scrub: scrub, fileExtensions: fileExtensions),
          value: value,
          component: _c.component,
          onChanged: (v) => _change(i, (l) => write(l, v)),
          editors: _c.editors,
          readOnly: _c.readOnly,
          entityNames: _c.entityNames,
          world: _c.world,
          sceneState: _c.sceneState,
          scope: _c.scope,
        ),
      ),
    );
  }

  double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

  @override
  Widget build(BuildContext context) {
    final layers = _layers;
    final scatter = _c.component is Scatter3D ? _c.component as Scatter3D : null;
    final counts = scatter == null ? List<int>.filled(layers.length, 0) : scatterCounts(scatter);
    const metres = ScrubHint(step: 0.1, fractionDigits: 1, suffix: 'm');
    const times = ScrubHint(step: 0.05, fractionDigits: 2, suffix: '×');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_c.label, style: InspectorField.labelStyle),
        const SizedBox(height: 4),
        for (final (i, l) in layers.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border.all(color: EditorTheme.border),
              borderRadius: BorderRadius.circular(InspectorField.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _open.contains(i) ? _open.remove(i) : _open.add(i)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        Icon(_open.contains(i) ? Icons.expand_more : Icons.chevron_right, size: 16, color: EditorTheme.textSecondary),
                        const SizedBox(width: 4),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(l.name, style: InspectorField.valueStyle, overflow: TextOverflow.ellipsis),
                        ),
                        Text(
                          '${i < counts.length ? counts[i] : 0} pieces · ${scatterCollisionLabel(l.collision).toLowerCase()}',
                          style: InspectorField.valueStyle.copyWith(color: EditorTheme.textMuted),
                        ),
                        if (!_c.readOnly && _c.scope != null && scatter != null)
                          EditorIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Remove this layer and its pieces',
                            // The pieces too: the layers after it move up one,
                            // and their pieces with them.
                            onTap: () => removeScatterLayer(_c.scope!, scatter, i),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_open.contains(i))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _row(i, 'name', FieldTypes.text, l.name, (x, v) => x.name = '$v', label: 'Name'),
                        _row(i, 'model', FieldTypes.assetRef, l.model, (x, v) => x.model = v as String? ?? '',
                            label: 'Model', description: 'What each piece shows; empty for the shape below, in its colour.', fileExtensions: const ['glb', 'gltf']),
                        if (l.model.isEmpty)
                          _row(i, 'shape', _shape, l.shape, (x, v) => x.shape = v as ScatterShape,
                              label: 'Shape', description: 'What each piece is without a model.'),
                        _row(i, 'color', FieldTypes.color, l.color, (x, v) => x.color = v as Color, label: 'Colour'),
                        _row(i, 'spacing', FieldTypes.decimal, l.spacing, (x, v) => x.spacing = _num(v, x.spacing).clamp(0.05, 100.0),
                            label: 'Spacing', description: 'The least distance between two of its pieces.', scrub: metres),
                        _row(i, 'minScale', FieldTypes.decimal, l.minScale, (x, v) {
                          x.minScale = _num(v, x.minScale).clamp(0.01, 100.0);
                          if (x.maxScale < x.minScale) x.maxScale = x.minScale;
                        }, label: 'Smallest', scrub: times),
                        _row(i, 'maxScale', FieldTypes.decimal, l.maxScale, (x, v) {
                          x.maxScale = _num(v, x.maxScale).clamp(0.01, 100.0);
                          if (x.minScale > x.maxScale) x.minScale = x.maxScale;
                        }, label: 'Largest', scrub: times),
                        _row(i, 'randomYaw', FieldTypes.boolean, l.randomYaw, (x, v) => x.randomYaw = v == true, label: 'Turned at random'),
                        _row(i, 'alignToNormal', FieldTypes.boolean, l.alignToNormal, (x, v) => x.alignToNormal = v == true,
                            label: 'Lean with the ground'),
                        _row(i, 'maxDistance', FieldTypes.decimal, l.maxDistance, (x, v) => x.maxDistance = _num(v, x.maxDistance).clamp(0.0, 10000.0),
                            label: 'Reach', description: 'Not drawn beyond this far from the camera; 0 for always.',
                            scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: 'm')),
                        _row(i, 'collision', _collision, l.collision, (x, v) => x.collision = v as ScatterCollision,
                            label: 'Solid', description: 'Whether the player bumps into its pieces, and as what.'),
                        if (l.collision != ScatterCollision.none) ...[
                          _row(i, 'colliderRadius', FieldTypes.decimal, l.colliderRadius,
                              (x, v) => x.colliderRadius = _num(v, x.colliderRadius).clamp(0.01, 50.0),
                              label: 'Solid radius', scrub: metres),
                          _row(i, 'colliderHeight', FieldTypes.decimal, l.colliderHeight,
                              (x, v) => x.colliderHeight = _num(v, x.colliderHeight).clamp(0.01, 100.0),
                              label: 'Solid height', scrub: metres),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (!_c.readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: EditorButton(
              label: 'Add a layer',
              icon: Icons.add,
              kind: EditorButtonKind.ghost,
              onPressed: () {
                _c.onChanged([for (final x in layers) x.copy(), ScatterLayer(name: 'Layer ${layers.length + 1}')]);
                setState(() => _open.add(layers.length));
              },
            ),
          ),
      ],
    );
  }
}

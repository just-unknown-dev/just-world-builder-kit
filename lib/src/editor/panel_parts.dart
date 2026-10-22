import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';

/// A small caption over a part of a side-panel section: "BRUSH", "NEW
/// TERRAIN".
class PanelCaption extends StatelessWidget {
  const PanelCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(color: EditorTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    ),
  );
}

/// A label and what it labels, on one line.
class PanelRow extends StatelessWidget {
  const PanelRow({super.key, required this.label, required this.child, this.tooltip});

  final String label;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 64, child: tooltip == null ? text : Tooltip(message: tooltip!, child: text)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A quiet line of help.
class PanelHint extends StatelessWidget {
  const PanelHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: TextStyle(color: EditorTheme.textMuted, fontSize: 11, height: 1.35)),
  );
}

/// The thing a tool works on, named: "Shaping Terrain_0", with a line
/// about it under.
class PanelTarget extends StatelessWidget {
  const PanelTarget({super.key, required this.verb, required this.name, required this.detail});

  final String verb, name, detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$verb ', style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12)),
            TextSpan(text: name, style: TextStyle(color: EditorTheme.textBright, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      const SizedBox(height: 2),
      Text(detail, style: TextStyle(color: EditorTheme.textMuted, fontSize: 11)),
    ],
  );
}

import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';
import 'primitives.dart';

/// Kept · Moved · Removed · Added, with time and budget deltas. Nothing applies until the traveller taps Apply.
class ChangeDiff extends StatelessWidget {
  const ChangeDiff({super.key, required this.change});
  final TripChange change;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final saving = (change.budgetDelta?.amountMinor ?? 0) < 0;
    Widget group(String label, IconData icon, Color color, List<DiffEntry> items, {bool strike = false}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: ArivoSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label.toUpperCase(), style: t.label.copyWith(color: color, letterSpacing: 1)),
            const SizedBox(width: 6),
            Text('${items.length}', style: t.monoS.copyWith(color: p.muted)),
          ]),
          const SizedBox(height: ArivoSpace.s2),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(e.name, style: t.bodyM.copyWith(decoration: strike ? TextDecoration.lineThrough : null, decorationColor: p.emberText)),
                if (e.fromTime != null && e.toTime != null) Text('${e.fromTime} → ${e.toTime}', style: t.monoS.copyWith(color: p.muted)),
                if (e.reason != null) Text(e.reason!, style: t.caption),
                if (e.detail != null) Text(e.detail!, style: t.caption),
              ]),
            ),
        ]),
      );
    }

    return Semantics(
      label: 'Plan changes: ${change.moved.length} moved, ${change.removed.length} removed, ${change.added.length} added',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _Delta(label: 'Time', value: change.timeDeltaMin == 0 ? 'Same end' : '${change.timeDeltaMin > 0 ? '+' : '−'}${duration(change.timeDeltaMin.abs())}')),
          Expanded(
            child: _Delta(
              label: 'Budget',
              value: change.budgetDelta == null || change.budgetDelta!.amountMinor == 0 ? 'No change' : signedMoney(change.budgetDelta!),
              color: change.budgetDelta == null ? null : (saving ? p.signalText : p.emberText),
            ),
          ),
        ]),
        const Divider(height: ArivoSpace.s8),
        group('Kept', Icons.check_rounded, p.muted, change.kept),
        group('Moved', Icons.arrow_forward_rounded, p.signalText, change.moved),
        group('Removed', Icons.remove_rounded, p.emberText, change.removed, strike: true),
        group('Added', Icons.add_rounded, p.voltText, change.added),
      ]),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.label, required this.value, this.color});
  final String label, value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: context.type.caption),
        Row(children: [
          Flexible(child: Text(value, style: context.type.monoL.copyWith(color: color))),
          if (label == 'Budget') const ProvenanceTag(Provenance.est),
        ]),
      ]);
}

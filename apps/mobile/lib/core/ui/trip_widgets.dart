import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';
import 'primitives.dart';

/// One itinerary stop: time · place · duration · leg · price+provenance · reason · status.
class StopCard extends StatelessWidget {
  const StopCard({super.key, required this.item, this.onTap, this.isNext = false, this.compact = false});
  final ItineraryItem item;
  final VoidCallback? onTap;
  final bool isNext, compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final meta = <String>[duration(item.durationMin)];
    final spoken = [hhmm(item.start), item.name, duration(item.durationMin), if (item.cost != null) money(item.cost!), item.reason].join(', ');
    return Semantics(
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      child: Material(
        color: p.raised,
        borderRadius: BorderRadius.circular(ArivoRadius.s),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: item.isBooked
                  ? Border(left: BorderSide(color: p.volt, width: 3))
                  : isNext
                      ? Border.all(color: p.signal, width: 2)
                      : null,
              borderRadius: BorderRadius.circular(ArivoRadius.s),
            ),
            padding: const EdgeInsets.all(ArivoSpace.s4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 52, child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(hhmm(item.start), style: t.monoM))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: ArivoSpace.s2, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(item.name, style: t.titleM),
                    if (item.isBooked) const StatusChip(ChipTone.booked),
                    if (item.status == 'done') const StatusChip(ChipTone.done),
                    if (item.status == 'closed') const StatusChip(ChipTone.closed),
                    if (item.lane == 'iconic') _Lane('Iconic', p.muted),
                    if (item.lane == 'local') _Lane('Local', p.voltText),
                    if (item.lane == 'pulse') _Lane('Pulse', p.lanternText),
                  ]),
                  const SizedBox(height: 2),
                  Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ...meta.map((m) => Text(m, style: t.caption)),
                    if (item.cost != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(item.cost!.amountMinor == 0 ? 'Free' : money(item.cost!), style: t.monoS.copyWith(color: p.text)),
                        ProvenanceTag(item.cost!.amountMinor == 0 ? Provenance.est : item.costProvenance),
                      ]),
                  ]),
                  if (!compact && item.reason.isNotEmpty) ...[
                    const SizedBox(height: ArivoSpace.s2),
                    Text(item.reason, style: t.bodyM.copyWith(color: p.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: context.type.monoS.copyWith(color: color, fontSize: 10.5));
}

/// The Route Thread as a timeline: dashed day-colour line, nodes at stops, legs between.
class TripSpine extends StatelessWidget {
  const TripSpine({super.key, required this.day, required this.onTapItem, this.nextItemId});
  final ItineraryDay day;
  final void Function(ItineraryItem) onTapItem;
  final String? nextItemId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.route(day.routeColor);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < day.items.length; i++) ...[
        if (day.items[i].leg != null && i > 0) _LegRow(leg: day.items[i].leg!, color: color),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 22, child: CustomPaint(painter: _ThreadPainter(color, first: i == 0, last: i == day.items.length - 1, next: day.items[i].id == nextItemId))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                child: StopCard(item: day.items[i], isNext: day.items[i].id == nextItemId, onTap: () => onTapItem(day.items[i])),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg, required this.color});
  final Leg leg;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(children: [
        SizedBox(width: 22, child: CustomPaint(painter: _ThreadPainter(color, leg: true))),
        Padding(
          padding: const EdgeInsets.fromLTRB(ArivoSpace.s2, 2, 0, ArivoSpace.s2),
          child: Row(children: [
            Icon(leg.isWalk ? Icons.directions_walk_rounded : Icons.train_outlined, size: 14, color: context.palette.muted),
            const SizedBox(width: 6),
            Text(legLabel(leg), style: context.type.caption),
            ProvenanceTag(leg.provenance, source: leg.note),
          ]),
        ),
      ]),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter(this.color, {this.first = false, this.last = false, this.leg = false, this.next = false});
  final Color color;
  final bool first, last, leg, next;

  @override
  void paint(Canvas canvas, Size size) {
    final x = 7.0;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final top = first && !leg ? 22.0 : 0.0, bottom = last && !leg ? 22.0 : size.height;
    for (var y = top; y < bottom; y += 11) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + 6).clamp(0, bottom)), line);
    }
    if (!leg) {
      const cy = 22.0;
      if (next) canvas.drawCircle(const Offset(7, cy), 11, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(const Offset(7, cy), 7, Paint()..color = next ? color : ArivoColors.paper50);
      canvas.drawCircle(const Offset(7, cy), 7, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(covariant _ThreadPainter o) => o.color != color || o.next != next;
}

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

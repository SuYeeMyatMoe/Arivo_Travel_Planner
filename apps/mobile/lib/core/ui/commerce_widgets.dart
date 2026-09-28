import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';
import 'primitives.dart';

/// Budget Brain ring: spent (solid), reserved (hatched), forecast (lantern dashed arc), remaining in the centre.
class BudgetGauge extends StatelessWidget {
  const BudgetGauge({super.key, required this.view});
  final BudgetView view;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final total = view.total <= 0 ? 1.0 : view.total;
    final stateLabel = switch (view.state) { 'over' => 'Over budget', 'tight' => 'Tight', 'no_budget' => 'No budget set', _ => 'On track' };
    final stateColor = switch (view.state) { 'over' => p.emberText, 'tight' => p.lanternText, _ => p.signalText };
    return Semantics(
      label: '${moneyOf(view.spent, view.currency)} of ${moneyOf(view.total, view.currency)} spent, '
          '${moneyOf(view.reserved, view.currency)} reserved, forecast ${moneyOf(view.forecast, view.currency)}. $stateLabel.',
      excludeSemantics: true,
      child: Row(children: [
        SizedBox(
          width: 136,
          height: 136,
          child: CustomPaint(
            painter: _GaugePainter(spent: view.spent / total, reserved: view.reserved / total, forecast: view.forecast / total, p: p, over: view.state == 'over'),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Remaining', style: t.caption),
                FittedBox(child: Text(moneyOf(view.remaining, view.currency), style: t.monoL)),
                Text(stateLabel, style: t.caption.copyWith(color: stateColor, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: ArivoSpace.s4),
        Expanded(
          child: Column(children: [
            _LegendRow('Spent', moneyOf(view.spent, view.currency), p.text, Provenance.you),
            _LegendRow('Reserved', moneyOf(view.reserved, view.currency), p.muted, Provenance.live),
            _LegendRow('Forecast', moneyOf(view.forecast, view.currency), p.lantern, Provenance.est),
            _LegendRow('Total', moneyOf(view.total, view.currency), p.line, Provenance.you),
          ]),
        ),
      ]),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(this.label, this.value, this.swatch, this.prov);
  final String label, value;
  final Color swatch;
  final Provenance prov;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: context.type.caption)),
          Text(value, style: context.type.monoS.copyWith(color: context.palette.text)),
          ProvenanceTag(prov),
        ]),
      );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.spent, required this.reserved, required this.forecast, required this.p, required this.over});
  final double spent, reserved, forecast;
  final ArivoPalette p;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 14;
    const start = -math.pi / 2;
    final track = Paint()
      ..color = p.sunken
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(c, r, track);
    final s = spent.clamp(0.0, 1.0), rs = reserved.clamp(0.0, 1.0 - s);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, math.pi * 2 * s, false, Paint()
      ..color = p.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round);
    // reserved: hatched look via short dashes
    final dash = Paint()
      ..color = p.muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    for (var a = s; a < s + rs; a += 0.012) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start + math.pi * 2 * a, math.pi * 2 * 0.006, false, dash);
    }
    final fc = Paint()
      ..color = over ? p.ember : p.lantern
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var a = 0.0; a < forecast.clamp(0.0, 1.0); a += 0.02) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r + 11), start + math.pi * 2 * a, math.pi * 2 * 0.011, false, fc);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.spent != spent || o.reserved != reserved || o.forecast != forecast;
}

/// Booking as a ticket: route stub, perforation (the Route Thread), status and reference.
class BoardingPassCard extends StatelessWidget {
  const BoardingPassCard({super.key, required this.offer, this.state, this.reference, this.onTap, this.note});
  final TravelOffer offer;
  final String? state, reference, note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final tone = switch (state) {
      'CONFIRMED' => ChipTone.confirmed,
      'FAILED' => ChipTone.failed,
      'CANCELLED' || 'REFUNDED' => ChipTone.cancelled,
      null => null,
      _ => ChipTone.pending,
    };
    final icon = switch (offer.type) { 'stay' => Icons.hotel_outlined, 'rail' => Icons.train_outlined, 'bus' => Icons.directions_bus_outlined, _ => Icons.flight_outlined };
    final route = offer.type == 'stay' ? offer.title : '${offer.origin ?? ''} → ${offer.destination ?? ''}';
    return Material(
      color: p.raised,
      borderRadius: BorderRadius.circular(ArivoRadius.m),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 13,
              child: Padding(
                padding: const EdgeInsets.all(ArivoSpace.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 14, color: p.muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text(offer.segments.isNotEmpty ? '${offer.segments.first.carrier} ${offer.segments.first.number ?? ''}' : offer.subtitle,
                        style: t.caption, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 4),
                  Text(route, style: offer.type == 'stay' ? t.titleM : t.monoL, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (offer.departure != null && offer.arrival != null) ...[
                    const SizedBox(height: 2),
                    Text(offer.type == 'stay' ? '${dayLabel(offer.departure!)} → ${dayLabel(offer.arrival!)}' : '${hhmm(offer.departure!)} — ${hhmm(offer.arrival!)}',
                        style: t.monoM),
                    Text(offer.type == 'stay' ? offer.subtitle : '${dayLabel(offer.departure!)} · ${offer.durationMin != null ? duration(offer.durationMin!) : ''}',
                        style: t.caption),
                  ],
                ]),
              ),
            ),
            const _Perforation(),
            Expanded(
              flex: 10,
              child: Padding(
                padding: const EdgeInsets.all(ArivoSpace.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (tone != null) StatusChip(tone),
                    if (offer.sandbox) const StatusChip(ChipTone.sandbox),
                    for (final b in offer.badges) _Badge(b),
                  ]),
                  const Spacer(),
                  if (reference != null) ...[
                    Text('Reference', style: t.caption),
                    Text(reference!, style: t.monoM),
                  ] else ...[
                    Text(money(offer.price), style: t.monoL),
                    Text('total · ${offer.refundable ? 'refundable' : 'non-refundable'}', style: t.caption),
                  ],
                  if (note != null) Text(note!, style: t.caption),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = text == 'BEST FIT' || text == 'BEST LOCATION' ? p.voltText : text == 'CHEAPEST' ? p.signalText : p.lanternText;
    return Text(text, style: context.type.monoS.copyWith(color: color, fontSize: 10.5, fontWeight: FontWeight.w700));
  }
}

class _Perforation extends StatelessWidget {
  const _Perforation();
  @override
  Widget build(BuildContext context) => SizedBox(width: 18, child: CustomPaint(painter: _PerfPainter(context.palette)));
}

class _PerfPainter extends CustomPainter {
  _PerfPainter(this.p);
  final ArivoPalette p;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = p.line
      ..strokeWidth = 2;
    for (var y = 12.0; y < size.height - 12; y += 10) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, y + 5), paint);
    }
    final notch = Paint()..color = p.surface;
    canvas.drawCircle(Offset(size.width / 2, 0), 9, notch);
    canvas.drawCircle(Offset(size.width / 2, size.height), 9, notch);
  }

  @override
  bool shouldRepaint(covariant _PerfPainter old) => false;
}

/// Every fee before payment. When revalidation changed the price, the banner forces reconfirmation.
class PriceBreakdown extends StatelessWidget {
  const PriceBreakdown({super.key, required this.offer, this.changedFrom});
  final TravelOffer offer;
  final String? changedFrom;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (changedFrom != null)
        Container(
          margin: const EdgeInsets.only(bottom: ArivoSpace.s3),
          padding: const EdgeInsets.all(ArivoSpace.s3),
          decoration: BoxDecoration(border: Border.all(color: p.emberText, width: 1.5), borderRadius: BorderRadius.circular(ArivoRadius.s)),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: p.emberText),
            const SizedBox(width: ArivoSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Price changed', style: t.label.copyWith(color: p.emberText)),
                Text(changedFrom!, style: t.monoM),
                Text('Confirm the new total to continue. Nothing has been charged.', style: t.caption),
              ]),
            ),
          ]),
        ),
      for (final l in offer.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(l.label, style: t.bodyM.copyWith(color: p.muted))), Text(money(l.amount), style: t.monoM)]),
        ),
      const Divider(height: ArivoSpace.s4),
      Row(children: [
        Expanded(child: Text('Total · ${offer.price.currency}', style: t.titleM)),
        Text(money(offer.price), style: t.monoL),
        const ProvenanceTag(Provenance.live, source: 'Supplier quote, revalidated'),
      ]),
      const SizedBox(height: ArivoSpace.s3),
      for (final term in [offer.cancellationPolicy, offer.changePolicy, if (offer.baggage != null) 'Baggage: ${offer.baggage}'])
        if (term.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $term', style: t.caption)),
    ]);
  }
}

/// How well a stay serves this itinerary.
class LocationFitMeter extends StatelessWidget {
  const LocationFitMeter({super.key, required this.score, this.sentence});
  final int score;
  final String? sentence;
  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Semantics(
      label: 'Location fit $score percent. ${sentence ?? ''}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('Location fit', style: t.label)), Text('$score%', style: t.monoL)]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: score / 100, minHeight: 8, backgroundColor: p.sunken, color: p.signal),
        ),
        if (sentence != null) ...[const SizedBox(height: 6), Text(sentence!, style: t.bodyM.copyWith(color: p.muted))],
      ]),
    );
  }
}

/// Arivo Pulse mark: shown only when evidence exists.
class PulseBadge extends StatelessWidget {
  const PulseBadge({super.key, required this.score, required this.label});
  final num score;
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(ArivoRadius.pill), border: Border.all(color: p.lantern, width: 1.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: const Size(18, 14), painter: _PulseGlyph(p.lanternText)),
        const SizedBox(width: 6),
        Text(score.round().toString(), style: context.type.monoM),
        const SizedBox(width: 6),
        Text(label, style: context.type.label.copyWith(color: p.lanternText)),
      ]),
    );
  }
}

class _PulseGlyph extends CustomPainter {
  _PulseGlyph(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, s.height / 2)
      ..lineTo(s.width * 0.25, s.height / 2)
      ..lineTo(s.width * 0.4, 0)
      ..lineTo(s.width * 0.6, s.height)
      ..lineTo(s.width * 0.72, s.height / 2)
      ..lineTo(s.width, s.height / 2);
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _PulseGlyph o) => o.color != color;
}

/// Arivo Crew constellation: members as stars in their colour, shared interests as lines, conflicts dashed ember.
class CrewConstellation extends StatelessWidget {
  const CrewConstellation({super.key, required this.names, required this.colors, this.links = const []});
  final List<String> names;
  final List<int> colors;
  final List<(int, int, String, bool)> links; // a, b, label, conflict

  @override
  Widget build(BuildContext context) {
    return AspectRatio(aspectRatio: 1.7, child: CustomPaint(painter: _ConstellationPainter(names, colors, links, context.palette, context.type)));
  }
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter(this.names, this.colors, this.links, this.p, this.t);
  final List<String> names;
  final List<int> colors;
  final List<(int, int, String, bool)> links;
  final ArivoPalette p;
  final ArivoText t;

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(1, names.length);
    final cx = size.width / 2, cy = size.height / 2 - 6;
    final pos = [
      for (var i = 0; i < names.length; i++)
        Offset(cx + math.cos(i / n * math.pi * 2 - math.pi / 2 + math.pi / n) * size.width * 0.34,
            cy + math.sin(i / n * math.pi * 2 - math.pi / 2 + math.pi / n) * size.height * 0.3)
    ];
    for (final (a, b, label, conflict) in links) {
      if (a >= pos.length || b >= pos.length) continue;
      final paint = Paint()
        ..color = conflict ? p.ember : p.muted
        ..strokeWidth = 1.5;
      if (conflict) {
        final d = pos[b] - pos[a];
        final len = d.distance;
        for (var s = 0.0; s < len; s += 10) {
          canvas.drawLine(pos[a] + d * (s / len), pos[a] + d * (math.min(len, s + 5) / len), paint);
        }
      } else {
        canvas.drawLine(pos[a], pos[b], paint);
      }
      final mid = (pos[a] + pos[b]) / 2;
      _text(canvas, label, mid.translate(0, -12), t.caption.copyWith(color: p.muted, fontSize: 11));
    }
    for (var i = 0; i < names.length; i++) {
      final path = Path();
      for (var k = 0; k < 8; k++) {
        final r = k.isEven ? 13.0 : 5.5, a = k / 8 * math.pi * 2 - math.pi / 2;
        final pt = pos[i] + Offset(math.cos(a) * r, math.sin(a) * r);
        k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = p.crew(colors[i]));
      _text(canvas, names[i], pos[i].translate(0, 26), t.label.copyWith(color: p.text));
    }
  }

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: 140);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter o) => true;
}

/// Filled-in progress bar for crew balance rows.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.value, required this.color});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 6, color: color, backgroundColor: context.palette.sunken),
      );
}

/// Unused-color guard so tokens stay referenced in one place.
const kSheetRadius = BorderRadius.vertical(top: Radius.circular(ArivoRadius.l));

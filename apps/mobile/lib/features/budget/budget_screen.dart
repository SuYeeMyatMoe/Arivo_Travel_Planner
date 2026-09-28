import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';
import '../you/you_screen.dart';

const _palette = [Color(0xFF1F6BFF), Color(0xFFF97316), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF06B6D4), Color(0xFF64748B)];

/// Budget Breakdown: planned split by category as a donut, then live tracking (spent, reserved, forecast) and expenses.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final trip = ref.watch(tripProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text('Budget Breakdown', style: t.titleM.copyWith(fontWeight: FontWeight.w700))),
      body: PageWidth(
        child: trip == null
            ? StateMessage(title: 'No trip yet', body: 'Plan a trip and its budget appears here.', action: 'Plan a trip', onAction: () => context.go('/start'))
            : ref.watch(budgetProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => StateMessage(title: 'Budget unavailable', body: '$e', action: 'Try again', onAction: () => ref.invalidate(budgetProvider), icon: Icons.cloud_off),
                  data: (b) => b == null ? const SizedBox.shrink() : _Body(trip: trip, view: b),
                ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.trip, required this.view});
  final Trip trip;
  final BudgetView view;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    double planned(Json l) => math.max((l['planned'] as num).toDouble(), (l['forecast'] as num? ?? 0).toDouble());
    final lines = view.lines.where((l) => planned(l) > 0).toList()..sort((a, b) => planned(b).compareTo(planned(a)));
    final sum = lines.fold<double>(0, (a, l) => a + planned(l));
    final headline = view.total > 0 ? view.total : sum;
    final perPerson = trip.crewSize > 1 ? headline / trip.crewSize : null;
    return ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, 120), children: [
      Center(
        child: SizedBox.square(
          dimension: 220,
          child: CustomPaint(
            painter: _Donut([for (var i = 0; i < lines.length; i++) (planned(lines[i]) / (sum <= 0 ? 1 : sum), _palette[i % _palette.length])], p.sunken),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(child: Text(moneyOf(headline, view.currency), style: t.displayM)),
                Text(perPerson == null ? 'Total' : '${moneyOf(perPerson, view.currency)} / person', style: t.caption),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: ArivoSpace.s6),
      if (lines.isEmpty)
        Text('No cost estimates yet for this trip.', style: t.bodyM.copyWith(color: p.muted))
      else
        CleanCard(
          padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4, vertical: ArivoSpace.s2),
          child: Column(children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                  const SizedBox(width: ArivoSpace.s3),
                  Expanded(child: Text(titleCase(lines[i]['category'] as String), style: t.bodyM)),
                  Text(moneyOf(planned(lines[i]), view.currency), style: t.monoM),
                  SizedBox(width: 52, child: Text('${(planned(lines[i]) / (sum <= 0 ? 1 : sum) * 100).round()}%', textAlign: TextAlign.right, style: t.caption)),
                ]),
              ),
          ]),
        ),
      const SizedBox(height: ArivoSpace.s6),
      const SectionTitle('Tracking'),
      BudgetGauge(view: view),
      const SizedBox(height: ArivoSpace.s5),
      const SectionTitle('Spending by category'),
      BudgetPanel(trip: trip, showGauge: false),
    ]);
  }
}

class _Donut extends CustomPainter {
  _Donut(this.parts, this.track);
  final List<(double, Color)> parts;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 26.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    var start = -math.pi / 2;
    const gap = 0.025;
    for (final (share, color) in parts) {
      final sweep = share * math.pi * 2;
      if (sweep <= gap) continue;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Donut old) => true;
}

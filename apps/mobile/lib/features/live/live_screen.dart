import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';
import '../trip/trip_sheets.dart';

/// Arivo Live (ink): next stop, how to get there, time, weather, budget today, next booking. Glanceable, thumb-first.
class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider).value;
    final p = context.palette, t = context.type;
    if (trip == null) {
      return Scaffold(body: StateMessage(title: 'Live starts when your trip does', body: 'Plan a trip and Live becomes your heads-up guide on the day.', action: 'Plan a trip', onAction: () => context.go('/start')));
    }
    final dayIndex = ref.watch(selectedDayProvider).clamp(0, trip.days.length - 1);
    final day = trip.days[dayIndex];
    final now = tripNow(trip, ref.watch(demoClockProvider), dayIndex);
    final upcoming = day.items.where((i) => i.end.isAfter(now)).toList();
    final current = day.items.where((i) => !i.start.isAfter(now) && i.end.isAfter(now)).firstOrNull;
    final next = upcoming.where((i) => i.start.isAfter(now)).firstOrNull;
    final booking = trip.allItems.where((i) => i.isBooked && i.start.isAfter(now)).firstOrNull;
    final simulated = ref.watch(demoClockProvider) != null || !(DateTime.now().day == day.date.day && DateTime.now().month == day.date.month);

    return Scaffold(
      body: TopoBackground(
        child: SafeArea(
          child: PageWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s3, ArivoSpace.s4, 120), children: [
              Row(children: [
                const _LiveDot(),
                const SizedBox(width: ArivoSpace.s2),
                Text('LIVE TRIP', style: t.label.copyWith(color: p.signalText, letterSpacing: 1.2)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text('${simulated ? 'Simulating ' : ''}${hhmm(now)} · Day ${dayIndex + 1}', style: t.caption),
                  onPressed: () async {
                    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now), helpText: 'Simulate the time on this trip day');
                    if (tm != null) ref.read(demoClockProvider.notifier).set(DateTime(day.date.year, day.date.month, day.date.day, tm.hour, tm.minute));
                  },
                ),
              ]),
              const SizedBox(height: ArivoSpace.s4),
              if (next == null && current == null)
                StateMessage(title: 'All done for today', body: 'Day ${dayIndex + 1} is complete. Rest up — tomorrow is ready.', icon: Icons.nights_stay_outlined)
              else ...[
                Text(current != null ? 'Now' : 'Next stop', style: t.caption),
                Text((current ?? next)!.name, style: t.displayL),
                const SizedBox(height: ArivoSpace.s2),
                if (current != null && next != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ArivoSpace.s1),
                    child: Text('Then ${next.name}', style: t.titleM),
                  ),
                if (next != null && next.leg != null)
                  Row(children: [
                    Icon(next.leg!.isWalk ? Icons.directions_walk : Icons.train_outlined, color: p.signalText),
                    const SizedBox(width: ArivoSpace.s2),
                    Text('${next.leg!.minutes} min ${next.leg!.isWalk ? 'walk' : 'by transit'}', style: t.monoM),
                    ProvenanceTag(next.leg!.provenance, source: next.leg!.note),
                    const Spacer(),
                    Text('Arrive ${hhmm(next.start)}', style: t.monoM),
                  ]),
                const SizedBox(height: ArivoSpace.s4),
                Row(children: [
                  Expanded(
                    child: ArivoButton('Go', icon: Icons.navigation_outlined, expand: true, onPressed: () {
                      final target = next ?? current!;
                      launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${target.lat},${target.lon}&travelmode=${next?.leg?.isWalk == false ? 'transit' : 'walking'}'),
                          mode: LaunchMode.externalApplication);
                    }),
                  ),
                  const SizedBox(width: ArivoSpace.s2),
                  ArivoButton('Story', kind: ButtonKind.tonal, icon: Icons.auto_stories_outlined, onPressed: () {
                    final target = current ?? next!;
                    showStorySheet(context, ref, target.placeId, target.name);
                  }),
                ]),
              ],
              const SizedBox(height: ArivoSpace.s5),
              Row(children: [
                Expanded(child: _Tile(icon: Icons.wb_sunny_outlined, title: day.weather == null ? 'Forecast' : '${day.weather!['max_c']}°C', sub: day.weather == null ? 'Available closer to the date' : 'Rain ${day.weather!['max_precip_prob']}%', live: day.weather != null)),
                const SizedBox(width: ArivoSpace.s3),
                Expanded(child: _Tile(icon: Icons.account_balance_wallet_outlined, title: 'Budget', sub: 'Open Budget Brain', onTap: () => context.go('/you'))),
              ]),
              const SizedBox(height: ArivoSpace.s3),
              if (booking != null)
                _Tile(icon: Icons.confirmation_number_outlined, title: booking.name, sub: '${dayLabel(booking.start)} · ${hhmm(booking.start)} · ${booking.reason}', live: true),
              const SizedBox(height: ArivoSpace.s5),
              Text('Today', style: t.titleM),
              const SizedBox(height: ArivoSpace.s2),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: day.items.length,
                  separatorBuilder: (_, _) => Container(width: 18, alignment: Alignment.center, child: Container(height: 2, color: p.route(day.routeColor))),
                  itemBuilder: (_, i) {
                    final it = day.items[i];
                    final done = it.end.isBefore(now);
                    return Opacity(
                      opacity: done ? 0.5 : 1,
                      child: Container(
                        width: 130,
                        padding: const EdgeInsets.all(ArivoSpace.s3),
                        decoration: BoxDecoration(
                          color: p.raised,
                          borderRadius: BorderRadius.circular(ArivoRadius.s),
                          border: it.id == next?.id ? Border.all(color: p.signal, width: 2) : null,
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(hhmm(it.start), style: t.monoS),
                          Text(it.name, style: t.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: ArivoSpace.s5),
              Row(children: [
                Expanded(child: ArivoButton('Rescue my day', kind: ButtonKind.tonal, icon: Icons.auto_fix_high_outlined, onPressed: () => showRescueSheet(context, ref, trip, dayIndex))),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(child: ArivoButton('Scan receipt', kind: ButtonKind.tonal, icon: Icons.receipt_long_outlined, onPressed: () => context.push('/lens/receipt'))),
              ]),
              const SizedBox(height: ArivoSpace.s3),
              Text('Location is only used while Live is open and only if you allow it. Nothing is shared with your crew unless you turn on sharing.', style: t.caption),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.sub, this.onTap, this.live = false});
  final IconData icon;
  final String title, sub;
  final VoidCallback? onTap;
  final bool live;
  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Material(
      color: p.raised,
      borderRadius: BorderRadius.circular(ArivoRadius.s),
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: onTap == null,
        borderRadius: BorderRadius.circular(ArivoRadius.s),
        child: Padding(
          padding: const EdgeInsets.all(ArivoSpace.s3),
          child: Row(children: [
            Icon(icon, color: p.signalText),
            const SizedBox(width: ArivoSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(title, style: t.label, overflow: TextOverflow.ellipsis)), if (live) const ProvenanceTag(Provenance.live)]),
                Text(sub, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.reduceMotion ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.palette.signal;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => SizedBox.square(
        dimension: 18,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 6 + 12 * _c.value, height: 6 + 12 * _c.value, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.4 * (1 - _c.value)))),
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ]),
      ),
    );
  }
}

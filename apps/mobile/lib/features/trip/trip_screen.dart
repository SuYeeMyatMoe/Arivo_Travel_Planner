import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';
import 'trip_map.dart';
import 'trip_sheets.dart';

/// Loads the current trip and hands it to [builder]; calm states for loading, error and "no trip".
class _WithTrip extends ConsumerWidget {
  const _WithTrip({required this.title, required this.builder});
  final String title;
  final Widget Function(Trip trip) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(tripProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: StateMessage(title: "Couldn't load your trip", body: '$e', action: 'Try again', onAction: () => ref.invalidate(tripProvider), icon: Icons.cloud_off),
          ),
          data: (trip) => trip == null
              ? Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: StateMessage(title: 'No trip yet', body: 'Plan a trip first — it takes about a minute.', action: 'Plan a trip', onAction: () => context.go('/start')),
                )
              : builder(trip),
        );
  }
}

/// Horizontal "Day 1  2  3 …" selector.
class DayChips extends ConsumerWidget {
  const DayChips({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final sel = ref.watch(selectedDayProvider).clamp(0, trip.days.length - 1);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4),
        itemCount: trip.days.length,
        separatorBuilder: (_, _) => const SizedBox(width: ArivoSpace.s2),
        itemBuilder: (_, i) {
          final on = i == sel;
          return Semantics(
            button: true,
            selected: on,
            label: 'Day ${i + 1}, ${dayLabel(trip.days[i].date)}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => ref.read(selectedDayProvider.notifier).select(i),
              child: AnimatedContainer(
                duration: ArivoMotion.fast,
                padding: EdgeInsets.symmetric(horizontal: on ? ArivoSpace.s4 : ArivoSpace.s3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? p.volt : p.raised,
                  borderRadius: BorderRadius.circular(ArivoRadius.s),
                  border: Border.all(color: on ? p.volt : p.line),
                ),
                child: Text(on ? 'Day ${i + 1}' : '${i + 1}', style: t.label.copyWith(color: on ? p.onVolt : p.text)),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------- Day view

/// One day as a vertical timeline. Tap a stop for "Why this?", story, and details.
class ItineraryScreen extends StatelessWidget {
  const ItineraryScreen({super.key});

  @override
  Widget build(BuildContext context) => _WithTrip(title: 'Itinerary', builder: (trip) => _DayView(trip: trip));
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final dayIndex = ref.watch(selectedDayProvider).clamp(0, trip.days.length - 1);
    final day = trip.days[dayIndex];
    final weather = day.weather;
    return Scaffold(
      appBar: AppBar(
        title: Text('Itinerary', style: t.titleM.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Map', icon: const Icon(Icons.map_outlined), onPressed: () => context.push('/map')),
          IconButton(tooltip: 'Rescue my day', icon: const Icon(Icons.auto_fix_high_outlined), onPressed: () => showRescueSheet(context, ref, trip, dayIndex)),
        ],
      ),
      body: PageWidth(
        child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
          DayChips(trip: trip),
          Padding(
            padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s5, ArivoSpace.s4, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Day ${dayIndex + 1}', style: t.displayM),
              if (day.title.isNotEmpty) Text(day.title, style: t.titleM.copyWith(color: p.muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Wrap(spacing: ArivoSpace.s3, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(longDate(day.date), style: t.caption),
                Text('${day.items.where((i) => i.kind == 'sight').length} stops', style: t.caption),
                Text('${day.items.fold<int>(0, (a, i) => a + (i.leg?.minutes ?? 0))} min travelling', style: t.caption),
                if (weather != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wb_sunny_outlined, size: 14, color: p.lanternText),
                    const SizedBox(width: 4),
                    Text('${weather['min_c']}–${weather['max_c']}°C · rain ${weather['max_precip_prob']}%', style: t.caption),
                  ]),
              ]),
              const SizedBox(height: ArivoSpace.s5),
              for (var i = 0; i < day.items.length; i++)
                _TimelineRow(item: day.items[i], first: i == 0, last: i == day.items.length - 1, onTap: () => showWhySheet(context, ref, trip, day.items[i])),
              if (day.items.isEmpty) const StateMessage(title: 'A free day', body: 'Nothing planned — explore and add places you like.', icon: Icons.weekend_outlined),
              if (day.planB.isNotEmpty) ...[
                const SizedBox(height: ArivoSpace.s4),
                const SectionTitle('Plan B, ready'),
                for (final b in day.planB)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                    child: CleanCard(
                      padding: const EdgeInsets.all(ArivoSpace.s3),
                      onTap: () => showRescueSheet(context, ref, trip, dayIndex),
                      child: Row(children: [
                        IconWell(b.trigger == 'rain' ? Icons.umbrella_outlined : Icons.bedtime_outlined, size: 40),
                        const SizedBox(width: ArivoSpace.s3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.trigger == 'rain' ? 'If it rains' : 'If you get tired', style: t.label),
                            Text(b.summary, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: p.muted),
                      ]),
                    ),
                  ),
              ],
              const SizedBox(height: ArivoSpace.s4),
              ArivoButton('Rescue my day', kind: ButtonKind.outline, icon: Icons.auto_fix_high_outlined, expand: true, onPressed: () => showRescueSheet(context, ref, trip, dayIndex)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.first, required this.last, required this.onTap});
  final ItineraryItem item;
  final bool first, last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final sub = [
      duration(item.durationMin),
      if (item.cost != null) item.cost!.amountMinor == 0 ? 'Free' : money(item.cost!),
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 50, child: Padding(padding: const EdgeInsets.only(top: 14), child: Text(hhmm(item.start), style: t.monoS.copyWith(color: p.muted)))),
        SizedBox(
          width: 20,
          child: Column(children: [
            Container(width: 2, height: 16, color: first ? Colors.transparent : p.line),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: item.isBooked ? p.volt : p.raised, shape: BoxShape.circle, border: Border.all(color: p.volt, width: 2.5)),
            ),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent : p.line)),
          ]),
        ),
        const SizedBox(width: ArivoSpace.s2),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (item.leg != null && !first)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 2),
                  child: Row(children: [
                    Icon(item.leg!.isWalk ? Icons.directions_walk_rounded : Icons.train_outlined, size: 14, color: p.muted),
                    const SizedBox(width: 4),
                    Text(legLabel(item.leg!), style: t.caption),
                  ]),
                ),
              CleanCard(
                padding: const EdgeInsets.all(ArivoSpace.s3),
                onTap: onTap,
                child: Row(children: [
                  IconWell(categoryIcon(item.kind == 'sight' ? item.category : item.kind), size: 44),
                  const SizedBox(width: ArivoSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: t.label.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(item.reason.isEmpty ? sub : item.reason, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (item.reason.isNotEmpty) Text(sub, style: t.caption.copyWith(color: p.text)),
                      if (item.isBooked || item.status == 'closed' || item.status == 'done')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: StatusChip(item.isBooked ? ChipTone.booked : item.status == 'closed' ? ChipTone.closed : ChipTone.done),
                        ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------------------------------------------------- Map view

/// Full-screen map of the selected day with day chips on top and the stops in a swipeable strip.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) => _WithTrip(title: 'Map View', builder: (trip) => _MapView(trip: trip));
}

class _MapView extends ConsumerStatefulWidget {
  const _MapView({required this.trip});
  final Trip trip;
  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  ItineraryItem? _focus;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final p = context.palette, t = context.type;
    final dayIndex = ref.watch(selectedDayProvider).clamp(0, trip.days.length - 1);
    final day = trip.days[dayIndex];
    final stops = day.items.where((i) => i.lat != 0).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Map View', style: t.titleM.copyWith(fontWeight: FontWeight.w700))),
      body: Stack(children: [
        Positioned.fill(child: TripMap(day: day, focus: _focus, bottomPadding: 190)),
        Positioned(
          top: ArivoSpace.s2,
          left: 0,
          right: 0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DayChips(trip: trip),
            const Padding(padding: EdgeInsets.only(left: ArivoSpace.s4), child: MapCredit()),
          ]),
        ),
        if (stops.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: ArivoSpace.s4,
            child: SizedBox(
              height: 104,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.86),
                itemCount: stops.length,
                onPageChanged: (i) => setState(() => _focus = stops[i]),
                itemBuilder: (_, i) {
                  final s = stops[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s1),
                    child: CleanCard(
                      shadow: true,
                      padding: const EdgeInsets.all(ArivoSpace.s3),
                      onTap: () => showWhySheet(context, ref, trip, s),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: p.volt, shape: BoxShape.circle),
                          child: Text('${i + 1}', style: t.label.copyWith(color: p.onVolt)),
                        ),
                        const SizedBox(width: ArivoSpace.s3),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: t.label.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${hhmm(s.start)} · ${titleCase(s.category)} · ${duration(s.durationMin)}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Show on map',
                          icon: Icon(Icons.center_focus_strong_outlined, color: p.voltText),
                          onPressed: () => setState(() => _focus = s),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
      ]),
    );
  }
}

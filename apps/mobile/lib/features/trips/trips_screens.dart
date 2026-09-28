import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/destinations.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../guide/guide_sheet.dart';
import '../shell/app_shell.dart';

void _planNewTrip(BuildContext context, WidgetRef ref) {
  ref.read(setupDraftProvider.notifier).reset();
  context.push(ref.read(sessionProvider).interests.isEmpty ? '/setup/interests' : '/setup/where');
}

// -------------------------------------------------------------------------------------------------------- Saved trips

/// My Trips: Upcoming | Past, from GET /v1/trips. Tapping one makes it the current trip.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('My Trips', style: t.titleL),
          actions: [
            IconButton(tooltip: 'Plan a new trip', icon: const Icon(Icons.add_rounded), onPressed: () => _planNewTrip(context, ref)),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past')]),
        ),
        body: PageWidth(
          child: ref.watch(tripsListProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => StateMessage(title: "Couldn't load your trips", body: '$e', action: 'Try again', onAction: () => ref.invalidate(tripsListProvider), icon: Icons.cloud_off),
                data: (all) {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final upcoming = all.where((x) => !x.endDate.isBefore(today)).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
                  final past = all.where((x) => x.endDate.isBefore(today)).toList();
                  return TabBarView(children: [
                    _TripList(trips: upcoming, empty: 'No upcoming trips yet.'),
                    _TripList(trips: past, empty: 'Trips you have finished show up here.'),
                  ]);
                },
              ),
        ),
      ),
    );
  }
}

class _TripList extends ConsumerWidget {
  const _TripList({required this.trips, required this.empty});
  final List<TripSummary> trips;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final current = ref.watch(currentTripIdProvider);
    if (trips.isEmpty) {
      return StateMessage(title: empty, body: 'Plan a trip and it will be saved here.', action: 'Plan a trip', onAction: () => _planNewTrip(context, ref), icon: Icons.luggage_outlined);
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tripsListProvider),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s4, ArivoSpace.s4, 120),
        itemCount: trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: ArivoSpace.s3),
        itemBuilder: (_, i) {
          final x = trips[i];
          final isCurrent = x.id == current;
          return CleanCard(
            padding: const EdgeInsets.all(ArivoSpace.s3),
            onTap: () async {
              await ref.read(currentTripIdProvider.notifier).set(x.id);
              ref.read(selectedDayProvider.notifier).select(0);
              if (context.mounted) context.go('/trips/overview');
            },
            child: Row(children: [
              NetPhoto(photoForCities(x.cities), width: 96, height: 80, radius: ArivoRadius.s),
              const SizedBox(width: ArivoSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.title, style: t.titleM.copyWith(fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(dateRange(x.startDate, x.endDate), style: t.caption),
                  Text('${x.days} day${x.days == 1 ? '' : 's'}', style: t.caption),
                ]),
              ),
              if (isCurrent) TagPill('Current', color: p.voltText) else Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------ Trip overview

/// Trip Overview: destination, dates, photo, section shortcuts, highlights, days and estimated cost.
class TripOverviewScreen extends ConsumerWidget {
  const TripOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    return ref.watch(tripProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: StateMessage(title: "Couldn't load your trip", body: '$e', action: 'Try again', onAction: () => ref.invalidate(tripProvider), icon: Icons.cloud_off),
          ),
          data: (trip) {
            if (trip == null) {
              return Scaffold(
                appBar: AppBar(title: Text('Trip Overview', style: t.titleM)),
                body: StateMessage(
                  title: 'No trip yet',
                  body: 'Tell Ari where and when — routes, meals, budget and a Plan B are built for you.',
                  action: 'Plan a trip',
                  onAction: () => _planNewTrip(context, ref),
                ),
              );
            }
            return _Overview(trip: trip);
          },
        );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final end = trip.startDate.add(Duration(days: trip.days.length - 1));
    final city = destinationFor(trip.cities.first);
    final stops = trip.allItems.where((i) => i.kind == 'sight').length;
    final meals = trip.allItems.where((i) => i.kind == 'meal').length;
    final highlights = <(String, IconData, Color)>[
      for (final i in trip.interests.take(4)) (titleCase(i), _interestIcon(i), p.voltText),
      if (stops > 0) ('$stops places to see', Icons.place_outlined, const Color(0xFF059669)),
      if (meals > 0) ('$meals meals planned', Icons.restaurant_outlined, p.lanternText),
      if (trip.days.any((d) => d.planB.isNotEmpty)) ('Plan B ready', Icons.umbrella_outlined, p.voltText),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Trip Overview', style: t.titleM.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Ask Ari about this trip', icon: const Icon(Icons.auto_awesome_outlined), onPressed: () => showGuideSheet(context)),
        ],
      ),
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: () => ref.read(tripProvider.notifier).refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, 120), children: [
            Text(city == null ? trip.title : '${city.name}, ${city.country}', style: t.displayM),
            Text('${dateRange(trip.startDate, end)} · ${trip.days.length} days', style: t.bodyM.copyWith(color: p.muted)),
            const SizedBox(height: ArivoSpace.s4),
            AspectRatio(aspectRatio: 16 / 10, child: NetPhoto(photoForCities(trip.cities), radius: ArivoRadius.l)),
            const SizedBox(height: ArivoSpace.s4),
            Row(children: [
              _Shortcut(icon: Icons.dashboard_outlined, label: 'Overview', selected: true, onTap: () {}),
              _Shortcut(icon: Icons.view_timeline_outlined, label: 'Itinerary', onTap: () => context.go('/trips/overview/day')),
              _Shortcut(icon: Icons.map_outlined, label: 'Map', onTap: () => context.push('/map')),
              _Shortcut(icon: Icons.pie_chart_outline_rounded, label: 'Budget', onTap: () => context.push('/budget')),
            ]),
            const Divider(height: ArivoSpace.s8),
            if (highlights.isNotEmpty) ...[
              const SectionTitle('Trip Highlights'),
              Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
                for (final (label, icon, color) in highlights) TagPill(label, icon: icon, color: color),
              ]),
              const SizedBox(height: ArivoSpace.s6),
            ],
            CleanCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Estimated cost', style: t.caption),
                    const SizedBox(height: 2),
                    Text(trip.budgetTotal == null ? 'See breakdown' : money(trip.budgetTotal!), style: t.monoL),
                    Text(trip.crewSize > 1 ? 'for ${trip.crewSize} travellers' : 'for you', style: t.caption),
                  ]),
                ),
                TextButton(onPressed: () => context.push('/budget'), child: Text('View Breakdown', style: t.label.copyWith(color: p.voltText))),
              ]),
            ),
            const SizedBox(height: ArivoSpace.s6),
            const SectionTitle('Day by day'),
            for (final d in trip.days)
              Padding(
                padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                child: CleanCard(
                  padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4, vertical: ArivoSpace.s3),
                  onTap: () {
                    ref.read(selectedDayProvider.notifier).select(d.index);
                    context.go('/trips/overview/day');
                  },
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.voltSoft, borderRadius: BorderRadius.circular(ArivoRadius.s)),
                      child: Text('${d.index + 1}', style: t.titleM.copyWith(color: p.voltText)),
                    ),
                    const SizedBox(width: ArivoSpace.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.title.isEmpty ? 'Day ${d.index + 1}' : d.title, style: t.label.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${longDate(d.date)} · ${d.items.where((i) => i.kind == 'sight').length} stops', style: t.caption),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ]),
                ),
              ),
            const SizedBox(height: ArivoSpace.s4),
            const SectionTitle('Plan & book'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: ArivoSpace.s2,
              crossAxisSpacing: ArivoSpace.s2,
              childAspectRatio: 3,
              children: [
                _ToolTile(icon: Icons.flight_outlined, label: 'Flights', onTap: () => context.push('/book/flight')),
                _ToolTile(icon: Icons.hotel_outlined, label: 'Hotels', onTap: () => context.push('/book/stay')),
                _ToolTile(icon: Icons.local_activity_outlined, label: 'Activities', onTap: () => context.go('/explore')),
                _ToolTile(icon: Icons.luggage_outlined, label: 'Packing', onTap: () => context.push('/packing')),
                _ToolTile(icon: Icons.group_outlined, label: 'Crew', onTap: () => context.push('/crew')),
                _ToolTile(icon: Icons.near_me_outlined, label: 'Live mode', onTap: () => context.push('/live')),
              ],
            ),
            if (trip.warnings.isNotEmpty) ...[
              const SizedBox(height: ArivoSpace.s5),
              for (final w in trip.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 16, color: p.muted),
                    const SizedBox(width: ArivoSpace.s2),
                    Expanded(child: Text(w, style: t.caption)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

IconData _interestIcon(String i) => switch (i) {
      'food' => Icons.restaurant_outlined,
      'culture' || 'history' => Icons.temple_buddhist_outlined,
      'nature' => Icons.park_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      'nightlife' => Icons.nightlife_outlined,
      'photography' => Icons.photo_camera_outlined,
      'relaxation' => Icons.beach_access_outlined,
      'adventure' => Icons.terrain_outlined,
      _ => Icons.star_outline_rounded,
    };

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final c = selected ? p.voltText : p.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ArivoRadius.s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
          child: Column(children: [
            Icon(icon, color: c),
            const SizedBox(height: 4),
            Text(label, style: t.caption.copyWith(color: c, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CleanCard(
        padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s3),
        onTap: onTap,
        child: Row(children: [
          IconWell(icon, size: 34),
          const SizedBox(width: ArivoSpace.s2),
          Expanded(child: Text(label, style: context.type.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

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

/// Home: your trip at a glance, one-tap tools, and somewhere new to go.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final tripAsync = ref.watch(tripProvider);
    final trip = tripAsync.value;
    final p = context.palette, t = context.type;

    final actions = <(IconData, String, VoidCallback)>[
      (Icons.view_timeline_outlined, 'Itinerary', () => context.go('/trips/overview/day')),
      (Icons.map_outlined, 'Map', () => context.push('/map')),
      (Icons.flight_outlined, 'Flights', () => context.push('/book/flight')),
      (Icons.hotel_outlined, 'Hotels', () => context.push('/book/stay')),
      (Icons.local_activity_outlined, 'Activities', () => context.go('/explore')),
      (Icons.pie_chart_outline_rounded, 'Budget', () => context.push('/budget')),
      (Icons.luggage_outlined, 'Packing', () => context.push('/packing')),
      (Icons.near_me_outlined, 'Live', () => context.push('/live')),
      (Icons.train_outlined, 'Bus & train', () => context.push('/book/ground')),
      (Icons.group_outlined, 'Crew', () => context.push('/crew')),
      (Icons.receipt_long_outlined, 'Receipts', () => context.push('/lens/receipt')),
      (Icons.auto_awesome_outlined, 'Ask Ari', () => showGuideSheet(context)),
    ];

    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          child: RefreshIndicator(
            onRefresh: () => ref.read(tripProvider.notifier).refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, ArivoSpace.s4, ArivoSpace.s5, 120), children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hi, ${session.firstName}', style: t.bodyL.copyWith(color: p.muted)),
                    Text('Where to next?', style: t.displayM),
                  ]),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => _showNotifications(context, trip, session.notifications),
                  icon: Icon(Icons.notifications_none_rounded, color: p.text),
                ),
                const SizedBox(width: ArivoSpace.s1),
                GestureDetector(
                  onTap: () => context.go('/profile'),
                  child: Avatar(name: session.name, size: 40),
                ),
              ]),
              const SizedBox(height: ArivoSpace.s5),
              if (tripAsync.isLoading && trip == null)
                const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
              else if (trip == null)
                _PlanFirstTrip(onTap: () => _newTrip(context, ref))
              else
                TripHeroCard(trip: trip, onTap: () => context.go('/trips/overview')),
              if (trip != null) ...[
                const SizedBox(height: ArivoSpace.s3),
                ArivoButton('Plan a new trip', kind: ButtonKind.outline, icon: Icons.add_rounded, expand: true, onPressed: () => _newTrip(context, ref)),
              ],
              const SizedBox(height: ArivoSpace.s6),
              const SectionTitle('Quick actions'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: ArivoSpace.s4,
                crossAxisSpacing: ArivoSpace.s2,
                childAspectRatio: 0.82,
                children: [
                  for (final (icon, label, onTap) in actions)
                    InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(ArivoRadius.s),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconWell(icon, size: 52),
                        const SizedBox(height: ArivoSpace.s2),
                        Text(label, style: t.caption.copyWith(color: p.text, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: ArivoSpace.s6),
              SectionTitle('Popular destinations', action: 'See all', onAction: () => _newTrip(context, ref)),
              SizedBox(
                height: 170,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: destinations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: ArivoSpace.s3),
                  itemBuilder: (_, i) {
                    final d = destinations[i];
                    return SizedBox(
                      width: 130,
                      child: PhotoTile(
                        photo: d.photo,
                        label: d.name,
                        badge: d.supported ? null : 'Soon',
                        onTap: () {
                          if (!d.supported) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verified planning for ${d.name} is coming soon.')));
                            return;
                          }
                          ref.read(setupDraftProvider.notifier).update((x) => x.copyWith(destination: d, clearCustom: true));
                          context.push('/setup/when');
                        },
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

void _newTrip(BuildContext context, WidgetRef ref) {
  ref.read(setupDraftProvider.notifier).reset();
  context.push(ref.read(sessionProvider).interests.isEmpty ? '/setup/interests' : '/setup/where');
}

void _showNotifications(BuildContext context, Trip? trip, bool enabled) {
  final items = <(IconData, String, String)>[];
  if (trip != null) {
    final days = trip.startDate.difference(DateTime.now()).inDays;
    if (days >= 0) items.add((Icons.flight_takeoff_rounded, days == 0 ? 'Your trip starts today' : 'Your trip starts in $days day${days == 1 ? '' : 's'}', trip.title));
    for (final d in trip.days) {
      final rain = (d.weather?['max_precip_prob'] as num?) ?? 0;
      if (rain >= 50) items.add((Icons.umbrella_outlined, 'Rain likely on Day ${d.index + 1}', 'A Plan B is ready — open the day and tap Rescue my day.'));
    }
    for (final w in trip.warnings.take(2)) {
      items.add((Icons.info_outline_rounded, 'Heads-up', w));
    }
  }
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Notifications', style: ctx.type.titleL),
          const SizedBox(height: ArivoSpace.s3),
          if (!enabled) Text('Notifications are off. Turn them on in Profile → Notifications.', style: ctx.type.bodyM.copyWith(color: ctx.palette.muted)),
          if (enabled && items.isEmpty) Text("You're all caught up.", style: ctx.type.bodyM.copyWith(color: ctx.palette.muted)),
          if (enabled)
            for (final (icon, title, body) in items)
              ListTile(contentPadding: EdgeInsets.zero, leading: IconWell(icon, size: 40), title: Text(title), subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ),
  );
}

class _PlanFirstTrip extends StatelessWidget {
  const _PlanFirstTrip({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return ClipRRect(
      borderRadius: BorderRadius.circular(ArivoRadius.l),
      child: SizedBox(
        height: 220,
        child: Stack(fit: StackFit.expand, children: [
          NetPhoto(Photos.fuji),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x11000000), Color(0xCC000000)]))),
          Padding(
            padding: const EdgeInsets.all(ArivoSpace.s5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Plan your first trip', style: t.titleL.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text('Tell Ari where and when — get a full day-by-day plan in seconds.', style: t.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              const SizedBox(height: ArivoSpace.s3),
              SizedBox(width: 180, child: ArivoButton('Start planning', icon: Icons.auto_awesome_rounded, onPressed: onTap)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Photo card for the current trip: destination, dates, days, estimated cost.
class TripHeroCard extends StatelessWidget {
  const TripHeroCard({super.key, required this.trip, this.onTap, this.height = 220});
  final Trip trip;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final end = trip.startDate.add(Duration(days: trip.days.length - 1));
    return Semantics(
      button: onTap != null,
      label: '${trip.title}, ${dateRange(trip.startDate, end)}, ${trip.days.length} days',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ArivoRadius.l),
          child: SizedBox(
            height: height,
            child: Stack(fit: StackFit.expand, children: [
              NetPhoto(photoForCities(trip.cities)),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xD9000000)]))),
              Positioned(
                left: ArivoSpace.s4,
                top: ArivoSpace.s4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(ArivoRadius.pill)),
                  child: Text('Current trip', style: t.caption.copyWith(color: ArivoColors.textOnPaper, fontWeight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(ArivoSpace.s5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(trip.title, style: t.titleL.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${dateRange(trip.startDate, end)} · ${trip.days.length} days',
                          style: t.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                    ),
                    if (trip.budgetTotal != null) Text(money(trip.budgetTotal!), style: t.monoM.copyWith(color: Colors.white)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Initial-letter avatar in the brand tint.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.name, this.size = 40});
  final String? name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final letter = (name ?? '').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.voltSoft, shape: BoxShape.circle, border: Border.all(color: p.volt.withValues(alpha: 0.3))),
      child: Text(letter, style: context.type.titleM.copyWith(color: p.voltText, fontSize: size * 0.42)),
    );
  }
}

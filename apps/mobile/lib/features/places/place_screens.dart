import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/change_sheet.dart';
import '../shell/app_shell.dart';
import '../trip/trip_sheets.dart';

/// Add a place to the current trip: the planner proposes where it fits, you review the diff, nothing changes until Apply.
Future<void> addPlaceToTrip(BuildContext context, WidgetRef ref, String placeId) async {
  final trip = await ref.read(tripProvider.future);
  if (trip == null) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan a trip first, then add places to it.')));
    return;
  }
  try {
    final j = await ref.read(apiProvider).post('/v1/trips/${trip.id}/add-place', body: {'place_id': placeId}) as Map;
    final change = TripChange.fromJson(Map<String, dynamic>.from(j['change'] as Map));
    if (context.mounted) await showChangeSheet(context, ref, change, title: 'Add to your trip?');
  } on ApiError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

SavedPlace savedFrom(Place p) =>
    SavedPlace(id: p.id, name: p.name, city: p.city, category: p.category, photo: p.photo?['url'] as String?);

/// Heart toggle for saving a place on this device.
class SaveHeart extends ConsumerWidget {
  const SaveHeart({super.key, required this.place, this.onPhoto = false});
  final SavedPlace place;
  final bool onPhoto;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPlacesProvider).any((x) => x.id == place.id);
    final p = context.palette;
    final btn = IconButton(
      tooltip: saved ? 'Remove from saved' : 'Save',
      onPressed: () => ref.read(savedPlacesProvider.notifier).toggle(place),
      icon: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: saved ? p.emberText : (onPhoto ? p.text : p.muted)),
    );
    return onPhoto ? DecoratedBox(decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: btn) : btn;
  }
}

// ------------------------------------------------------------------------------------------------ Destination details

class PlaceDetailsScreen extends ConsumerWidget {
  const PlaceDetailsScreen({super.key, required this.placeId});
  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    return ref.watch(placeProvider(placeId)).when(
          loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: Text('Destination Details', style: t.titleM)),
            body: StateMessage(title: "Couldn't load this place", body: '$e', action: 'Try again', onAction: () => ref.invalidate(placeProvider(placeId)), icon: Icons.cloud_off),
          ),
          data: (place) => _Details(place: place),
        );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final saved = ref.watch(savedPlacesProvider).any((x) => x.id == place.id);
    final tags = <String>[
      titleCase(place.category),
      if (place.iconic >= 0.45) 'Iconic' else if (place.iconic < 0.2) 'Local find',
      titleCase(place.city.replaceAll('-', ' ')),
    ];
    final wiki = place.sources.where((s) => (s['url'] as String?)?.contains('wikipedia') ?? false).firstOrNull;
    final shareUrl = (wiki?['url'] ?? place.sources.firstOrNull?['url'] ?? 'https://www.openstreetmap.org/?mlat=${place.lat}&mlon=${place.lon}#map=17/${place.lat}/${place.lon}') as String;

    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ArivoRadius.s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
              child: Column(children: [Icon(icon, color: color ?? p.text), const SizedBox(height: 4), Text(label, style: t.caption.copyWith(color: p.text))]),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text('Destination Details', style: t.titleM.copyWith(fontWeight: FontWeight.w700))),
      body: PageWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s6), children: [
          AspectRatio(aspectRatio: 16 / 10, child: NetPhoto(place.photo?['url'] as String?, radius: ArivoRadius.l, icon: categoryIcon(place.category))),
          if (place.photo != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${place.photo!['credit']}', style: t.caption.copyWith(fontSize: 10.5))),
          const SizedBox(height: ArivoSpace.s4),
          Text(place.name, style: t.displayM),
          if (place.matchPct != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.star_rounded, size: 18, color: p.lantern),
                const SizedBox(width: 4),
                Text('${place.matchPct}% match for you', style: t.label),
              ]),
            ),
          const SizedBox(height: ArivoSpace.s3),
          Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [for (final tag in tags) TagPill(tag)]),
          if (place.summary != null) ...[
            const SizedBox(height: ArivoSpace.s4),
            Text(place.summary!, style: t.bodyM.copyWith(color: p.muted, height: 1.5)),
          ],
          const SizedBox(height: ArivoSpace.s4),
          CleanCard(
            padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s1),
            child: Row(children: [
              action(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, saved ? 'Saved' : 'Save',
                  () => ref.read(savedPlacesProvider.notifier).toggle(savedFrom(place)), color: saved ? p.emberText : null),
              action(Icons.directions_outlined, 'Directions',
                  () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lon}'), mode: LaunchMode.externalApplication)),
              action(Icons.auto_stories_outlined, 'Story', () => showStorySheet(context, ref, place.id, place.name)),
              action(Icons.share_outlined, 'Share', () async {
                await Clipboard.setData(ClipboardData(text: '${place.name} — $shareUrl'));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
              }),
            ]),
          ),
          const SizedBox(height: ArivoSpace.s4),
          _InfoRow(label: 'Opening hours', value: place.hoursRaw ?? 'Not listed', note: place.hoursRaw == null ? null : (place.hoursVerified ? 'From OpenStreetMap' : 'Unverified')),
          _InfoRow(label: 'Category', value: titleCase(place.category)),
          for (final e in place.why.take(3)) _InfoRow(label: 'Why it fits', value: e.text),
          if (place.sources.isNotEmpty) ...[
            const SizedBox(height: ArivoSpace.s2),
            Wrap(spacing: ArivoSpace.s2, children: [
              for (final s in place.sources.take(3))
                if (s['url'] != null)
                  ActionChip(
                    avatar: const Icon(Icons.link, size: 16),
                    label: Text('${s['name'] ?? s['kind'] ?? 'Source'}'),
                    onPressed: () => launchUrl(Uri.parse(s['url'] as String), mode: LaunchMode.externalApplication),
                  ),
            ]),
          ],
          const SizedBox(height: ArivoSpace.s6),
          ArivoButton('Add to Itinerary', icon: Icons.add_rounded, expand: true, onPressed: () => addPlaceToTrip(context, ref, place.id)),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.note});
  final String label, value;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: t.bodyM.copyWith(color: context.palette.muted))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: t.bodyM.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
            if (note != null) Text(note!, style: t.caption),
          ]),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------------------------------------------------- Saved tab

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPlacesProvider);
    final p = context.palette, t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text('Saved', style: t.titleL)),
      body: PageWidth(
        child: saved.isEmpty
            ? StateMessage(
                title: 'Nothing saved yet',
                body: 'Tap the heart on any place to keep it here for later.',
                action: 'Explore places',
                onAction: () => context.go('/explore'),
                icon: Icons.favorite_border_rounded,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, 120),
                itemCount: saved.length,
                separatorBuilder: (_, _) => const SizedBox(height: ArivoSpace.s3),
                itemBuilder: (_, i) {
                  final s = saved[i];
                  return CleanCard(
                    padding: const EdgeInsets.all(ArivoSpace.s3),
                    onTap: () => context.push('/place/${Uri.encodeComponent(s.id)}'),
                    child: Row(children: [
                      NetPhoto(s.photo, width: 80, height: 72, radius: ArivoRadius.s, icon: categoryIcon(s.category ?? '')),
                      const SizedBox(width: ArivoSpace.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: t.label.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text([if (s.category != null) titleCase(s.category!), if (s.city != null) titleCase(s.city!.replaceAll('-', ' '))].join(' · '), style: t.caption),
                        ]),
                      ),
                      SaveHeart(place: s),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

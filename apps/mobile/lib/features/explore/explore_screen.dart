import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ari/ari.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../common/change_sheet.dart';
import '../shell/app_shell.dart';

const _lanes = [('for_you', 'For you'), ('iconic', 'Iconic'), ('local', 'Local'), ('pulse', 'Pulse'), ('food', 'Food'), ('night', 'Night'), ('stay', 'Stay')];

final _cityProvider = NotifierProvider<_City, String>(_City.new);

class _City extends Notifier<String> {
  @override
  String build() => 'tokyo';
  void set(String c) => state = c;
}

final _laneProvider = NotifierProvider<_Lane, String>(_Lane.new);

class _Lane extends Notifier<String> {
  @override
  String build() => 'for_you';
  void set(String l) => state = l;
}

final _sliderProvider = NotifierProvider<_Slider, double>(_Slider.new);

class _Slider extends Notifier<double> {
  @override
  double build() => 0;
  void set(double v) => state = v;
}

final _resultsProvider = FutureProvider.autoDispose<(List<Place>, List<Json>)>((ref) async {
  final city = ref.watch(_cityProvider), lane = ref.watch(_laneProvider), slider = ref.watch(_sliderProvider);
  final api = ref.read(apiProvider);
  if (lane == 'pulse') {
    final j = await api.get('/v1/pulse', query: {'city': city}) as Map;
    return (const <Place>[], List<Json>.from((j['items'] as List).map((e) => Map<String, dynamic>.from(e as Map))));
  }
  final j = await api.get('/v1/places/search', query: {'city': city, 'lane': lane, 'iconic_local': slider.toStringAsFixed(2), 'limit': 24}) as Map;
  return ((j['results'] as List).map((e) => Place.fromJson(Map<String, dynamic>.from(e as Map))).toList(), const <Json>[]);
});

/// Explore: Iconic · Local · Pulse · For you — mixed on purpose, every card explains itself.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final lane = ref.watch(_laneProvider), city = ref.watch(_cityProvider);
    final results = ref.watch(_resultsProvider);
    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s4, ArivoSpace.s4, 0),
              sliver: SliverList.list(children: [
                Row(children: [
                  Expanded(child: Text('Explore', style: t.displayM)),
                  DropdownButton<String>(
                    value: city,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'tokyo', child: Text('Tokyo')),
                      DropdownMenuItem(value: 'kyoto', child: Text('Kyoto')),
                      DropdownMenuItem(value: 'kuala-lumpur', child: Text('Kuala Lumpur')),
                    ],
                    onChanged: (v) => v == null ? null : ref.read(_cityProvider.notifier).set(v),
                  ),
                ]),
                const SizedBox(height: ArivoSpace.s3),
                _SendToTrip(),
                const SizedBox(height: ArivoSpace.s3),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _lanes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: ArivoSpace.s2),
                    itemBuilder: (_, i) => ChoiceChip(
                      label: Text(_lanes[i].$2),
                      selected: lane == _lanes[i].$1,
                      onSelected: (_) => ref.read(_laneProvider.notifier).set(_lanes[i].$1),
                    ),
                  ),
                ),
                if (lane != 'pulse' && lane != 'stay') ...[
                  const SizedBox(height: ArivoSpace.s2),
                  Row(children: [
                    Text('Iconic', style: t.caption),
                    Expanded(
                      child: Slider(
                        value: ref.watch(_sliderProvider),
                        min: -1,
                        max: 1,
                        divisions: 4,
                        label: 'Iconic ← Balanced → Local',
                        onChanged: (v) => ref.read(_sliderProvider.notifier).set(v),
                      ),
                    ),
                    Text('Local', style: t.caption),
                  ]),
                ],
                if (lane == 'pulse') _PulseHeader(city: city),
                const SizedBox(height: ArivoSpace.s2),
              ]),
            ),
            results.when(
              loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))),
              error: (e, _) => SliverToBoxAdapter(child: StateMessage(title: 'Explore is unavailable', body: '$e', icon: Icons.cloud_off)),
              data: (r) {
                final (places, pulse) = r;
                if (lane == 'pulse') {
                  if (pulse.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: StateMessage(
                        title: 'No evidence yet',
                        body: 'Arivo Pulse only shows places with real signals (Wikipedia attention, news coverage, events). Refresh to collect them.',
                        icon: Icons.monitor_heart_outlined,
                      ),
                    );
                  }
                  return SliverList.builder(itemCount: pulse.length, itemBuilder: (_, i) => _PulseCard(item: pulse[i]));
                }
                if (places.isEmpty) return const SliverToBoxAdapter(child: StateMessage(title: 'No verified places here yet'));
                return SliverList.builder(itemCount: places.length, itemBuilder: (_, i) => _PlaceCard(place: places[i]));
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ]),
        ),
      ),
    );
  }
}

Future<void> _addToTrip(BuildContext context, WidgetRef ref, String placeId) async {
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

class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});
  final Place place;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s3),
      child: Material(
        color: p.raised,
        borderRadius: BorderRadius.circular(ArivoRadius.m),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PlacePhoto(photo: place.photo, fallbackColor: p.signal, height: place.photo == null ? 56 : 150),
          Padding(
            padding: const EdgeInsets.all(ArivoSpace.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(place.name, style: t.titleL)),
                if (place.matchPct != null) Text('${place.matchPct}%', style: t.monoL.copyWith(color: p.signalText)),
              ]),
              Text('${place.category.replaceAll('_', ' ')}${place.iconic >= 0.5 ? ' · iconic' : place.iconic < 0.2 ? ' · local find' : ''}', style: t.caption),
              if (place.summary != null) ...[const SizedBox(height: 6), Text(place.summary!, style: t.bodyM.copyWith(color: p.muted))],
              const SizedBox(height: ArivoSpace.s2),
              for (final e in place.why.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [Expanded(child: Text('• ${e.text}', style: t.caption.copyWith(color: p.text))), ProvenanceTag(e.provenance, source: e.source)]),
                ),
              const SizedBox(height: ArivoSpace.s2),
              Row(children: [
                ArivoButton('Add to trip', kind: ButtonKind.tonal, icon: Icons.add, onPressed: () => _addToTrip(context, ref, place.id)),
                const Spacer(),
                if (place.sources.isNotEmpty)
                  IconButton(
                    tooltip: 'Sources',
                    icon: const Icon(Icons.link),
                    onPressed: () => launchUrl(Uri.parse(place.sources.first['url'] as String)),
                  ),
              ]),
              if (place.photo != null) Text('${place.photo!['credit']}', style: t.caption.copyWith(fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PulseHeader extends ConsumerStatefulWidget {
  const _PulseHeader({required this.city});
  final String city;
  @override
  ConsumerState<_PulseHeader> createState() => _PulseHeaderState();
}

class _PulseHeaderState extends ConsumerState<_PulseHeader> {
  String? _status;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(top: ArivoSpace.s2),
      child: Row(children: [
        Expanded(child: Text(_status ?? 'Real signals only: Wikipedia attention, news coverage, events. No evidence, no badge.', style: t.caption)),
        ArivoButton('Refresh', kind: ButtonKind.quiet, onPressed: () async {
          try {
            final j = await ref.read(apiProvider).post('/v1/pulse/refresh', query: {'city': widget.city, 'limit': 12}) as Map;
            setState(() => _status = j['status'] == 'running'
                ? 'Already collecting evidence…'
                : 'Collecting evidence (~${j['estimated_seconds']} s — news sources are rate-limited). Pull to refresh.');
            Future.delayed(Duration(seconds: (j['estimated_seconds'] as num?)?.toInt() ?? 60), () => ref.invalidate(_resultsProvider));
          } on ApiError catch (e) {
            setState(() => _status = e.message);
          }
        }),
      ]),
    );
  }
}

class _PulseCard extends ConsumerWidget {
  const _PulseCard({required this.item});
  final Json item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final evidence = (item['evidence'] as List).map((e) => Evidence.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final comps = Map<String, dynamic>.from(item['components'] as Map);
    return Padding(
      padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s3),
      child: Container(
        decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(ArivoRadius.m), border: Border(top: BorderSide(color: p.lantern, width: 2))),
        padding: const EdgeInsets.all(ArivoSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['name'] as String, style: t.titleL),
          const SizedBox(height: ArivoSpace.s2),
          PulseBadge(score: item['score'] as num, label: (item['label'] as String?) ?? 'Signals collected'),
          const SizedBox(height: ArivoSpace.s3),
          Text('Why trending?', style: t.label),
          const SizedBox(height: 6),
          for (final (k, w) in const [('burst', 0.28), ('velocity', 0.20), ('recency', 0.16), ('source_diversity', 0.12), ('local_event', 0.10), ('local_relevance', 0.08), ('engagement_quality', 0.06)])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 130, child: Text(k.replaceAll('_', ' '), style: t.caption)),
                Expanded(child: ShareBar(value: ((comps[k] as num?) ?? 0).toDouble(), color: p.lantern)),
                SizedBox(width: 44, child: Text('×${w.toStringAsFixed(2)}', style: t.monoS, textAlign: TextAlign.right)),
              ]),
            ),
          const SizedBox(height: ArivoSpace.s2),
          for (final e in evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: e.url == null ? null : () => launchUrl(Uri.parse(e.url!)),
                child: Row(children: [Expanded(child: Text('• ${e.text}', style: t.bodyM)), ProvenanceTag(e.provenance, source: e.source)]),
              ),
            ),
          const SizedBox(height: ArivoSpace.s2),
          ArivoButton('Add to trip', kind: ButtonKind.tonal, icon: Icons.add, onPressed: () => _addToTrip(context, ref, item['place_id'] as String)),
        ]),
      ),
    );
  }
}

/// Send it to my trip: paste a public YouTube/TikTok/Vimeo link → the place it shows, with honest confidence.
class _SendToTrip extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SendToTrip> createState() => _SendToTripState();
}

class _SendToTripState extends ConsumerState<_SendToTrip> {
  final _url = TextEditingController();
  Json? _result;
  String? _error;
  bool _busy = false;

  Future<void> _resolve() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    ref.read(ariProvider.notifier).set(AriState.thinking);
    try {
      final j = await ref.read(apiProvider).post('/v1/pulse/resolve-url', body: {'url': _url.text.trim()});
      setState(() => _result = Map<String, dynamic>.from(j as Map));
      ref.read(ariProvider.notifier).say(_result!['note'] as String, as: AriState.pointing);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
      ref.read(ariProvider.notifier).set(AriState.idle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final place = _result?['place'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'Paste a travel video link to add its place',
          prefixIcon: const Icon(Icons.link),
          suffixIcon: _busy
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(tooltip: 'Find the place', icon: const Icon(Icons.arrow_forward), onPressed: _resolve),
        ),
        onSubmitted: (_) => _resolve(),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: t.caption.copyWith(color: p.emberText))),
      if (_result != null)
        Padding(
          padding: const EdgeInsets.only(top: ArivoSpace.s2),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_result!['note'] as String, style: t.bodyM),
                if (_result!['source_title'] != null) Text('From: ${_result!['source_title']}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (place != null) ArivoButton('Add', kind: ButtonKind.tonal, onPressed: () => _addToTrip(context, ref, place['id'] as String)),
          ]),
        ),
    ]);
  }
}

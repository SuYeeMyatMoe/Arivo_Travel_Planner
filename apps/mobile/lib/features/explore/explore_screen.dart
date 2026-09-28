import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ari/ari.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../places/place_screens.dart';
import '../shell/app_shell.dart';

const _lanes = [('for_you', 'All'), ('iconic', 'Iconic'), ('local', 'Local gems'), ('food', 'Food'), ('night', 'Nightlife'), ('stay', 'Stays'), ('pulse', 'Trending')];
const _cities = [('tokyo', 'Tokyo'), ('kyoto', 'Kyoto'), ('kuala-lumpur', 'Kuala Lumpur')];

/// Defaults to the current trip's first city; the picker overrides it.
final _cityProvider = NotifierProvider<_City, String>(_City.new);

class _City extends Notifier<String> {
  @override
  String build() {
    final c = ref.watch(tripProvider).value?.cities.firstOrNull;
    return _cities.any((x) => x.$1 == c) ? c! : 'tokyo';
  }

  void set(String c) => state = c;
}

final _laneProvider = NotifierProvider<_Lane, String>(_Lane.new);

class _Lane extends Notifier<String> {
  @override
  String build() => 'for_you';
  void set(String l) => state = l;
}

final _queryProvider = NotifierProvider<_Query, String>(_Query.new);

class _Query extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final _resultsProvider = FutureProvider.autoDispose<(List<Place>, List<Json>)>((ref) async {
  final city = ref.watch(_cityProvider), lane = ref.watch(_laneProvider), q = ref.watch(_queryProvider).trim();
  final api = ref.read(apiProvider);
  if (lane == 'pulse') {
    final j = await api.get('/v1/pulse', query: {'city': city}) as Map;
    return (const <Place>[], List<Json>.from((j['items'] as List).map((e) => Map<String, dynamic>.from(e as Map))));
  }
  final j = await api.get('/v1/places/search', query: {'city': city, 'lane': lane, if (q.length >= 2) 'q': q, 'limit': 30}) as Map;
  return ((j['results'] as List).map((e) => Place.fromJson(Map<String, dynamic>.from(e as Map))).toList(), const <Json>[]);
});

/// Explore / Activities: search, category chips, photo cards. Every card explains itself and can be saved or added.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(_queryProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _linkSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add from a video', style: ctx.type.titleL),
            const SizedBox(height: ArivoSpace.s2),
            Text('Paste a public YouTube, TikTok or Vimeo link — Ari finds the place it shows.', style: ctx.type.bodyM.copyWith(color: ctx.palette.muted)),
            const SizedBox(height: ArivoSpace.s4),
            _SendToTrip(),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final lane = ref.watch(_laneProvider), city = ref.watch(_cityProvider);
    final results = ref.watch(_resultsProvider);
    final cityName = _cities.firstWhere((c) => c.$1 == city).$2;
    return Scaffold(
      appBar: AppBar(
        title: Text('Explore', style: t.titleL),
        actions: [
          IconButton(tooltip: 'Add from a video link', icon: const Icon(Icons.add_link_rounded), onPressed: _linkSheet),
          PopupMenuButton<String>(
            tooltip: 'Change city',
            initialValue: city,
            onSelected: (v) => ref.read(_cityProvider.notifier).set(v),
            itemBuilder: (_) => [for (final (k, n) in _cities) PopupMenuItem(value: k, child: Text(n))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s3),
              child: Row(children: [
                Icon(Icons.place_outlined, size: 18, color: p.voltText),
                const SizedBox(width: 2),
                Text(cityName, style: t.label.copyWith(color: p.voltText)),
                Icon(Icons.expand_more_rounded, size: 18, color: p.voltText),
              ]),
            ),
          ),
        ],
      ),
      body: PageWidth(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, 0),
            sliver: SliverList.list(children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => ref.read(_queryProvider.notifier).set(v),
                decoration: InputDecoration(
                  hintText: 'Search activities in $cityName',
                  prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            ref.read(_queryProvider.notifier).set('');
                            setState(() {});
                          },
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ArivoSpace.s3),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _lanes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: ArivoSpace.s2),
                  itemBuilder: (_, i) => ChoiceChip(
                    showCheckmark: false,
                    label: Text(_lanes[i].$2),
                    selected: lane == _lanes[i].$1,
                    onSelected: (_) => ref.read(_laneProvider.notifier).set(_lanes[i].$1),
                  ),
                ),
              ),
              if (lane == 'pulse') _PulseHeader(city: city),
              const SizedBox(height: ArivoSpace.s3),
            ]),
          ),
          results.when(
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))),
            error: (e, _) => SliverToBoxAdapter(
              child: StateMessage(title: 'Explore is unavailable', body: '$e', action: 'Try again', onAction: () => ref.invalidate(_resultsProvider), icon: Icons.cloud_off),
            ),
            data: (r) {
              final (places, pulse) = r;
              if (lane == 'pulse') {
                if (pulse.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: StateMessage(
                      title: 'No evidence yet',
                      body: 'Trending only shows places with real signals (Wikipedia attention, news coverage, events). Refresh to collect them.',
                      icon: Icons.monitor_heart_outlined,
                    ),
                  );
                }
                return SliverList.builder(itemCount: pulse.length, itemBuilder: (_, i) => _PulseCard(item: pulse[i]));
              }
              if (places.isEmpty) return const SliverToBoxAdapter(child: StateMessage(title: 'No verified places match', icon: Icons.search_off_rounded));
              return SliverList.builder(itemCount: places.length, itemBuilder: (_, i) => _PlaceCard(place: places[i]));
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      ),
    );
  }
}

class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});
  final Place place;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    final kind = '${titleCase(place.category)}${place.iconic >= 0.45 ? ' · Iconic' : place.iconic < 0.2 ? ' · Local find' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s3),
      child: CleanCard(
        padding: const EdgeInsets.all(ArivoSpace.s3),
        onTap: () => context.push('/place/${Uri.encodeComponent(place.id)}'),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NetPhoto(place.photo?['url'] as String?, width: 96, height: 96, radius: ArivoRadius.s, icon: categoryIcon(place.category)),
          const SizedBox(width: ArivoSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name, style: t.label.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                if (place.matchPct != null) ...[
                  Icon(Icons.star_rounded, size: 15, color: p.lantern),
                  const SizedBox(width: 2),
                  Text('${place.matchPct}%', style: t.caption.copyWith(color: p.text, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                ],
                Flexible(child: Text(kind, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              if (place.summary != null) ...[
                const SizedBox(height: 4),
                Text(place.summary!, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ] else if (place.why.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place.why.first.text, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: ArivoSpace.s1),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => addPlaceToTrip(context, ref, place.id),
                  icon: Icon(Icons.add_rounded, size: 18, color: p.voltText),
                  label: Text('Add to trip', style: t.label.copyWith(color: p.voltText)),
                ),
              ),
            ]),
          ),
          SaveHeart(place: savedFrom(place)),
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
                : 'Collecting evidence (~${j['estimated_seconds']} s — news sources are rate-limited).');
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
      child: CleanCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['name'] as String, style: t.titleM),
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
          ArivoButton('Add to trip', kind: ButtonKind.outline, icon: Icons.add, onPressed: () => addPlaceToTrip(context, ref, item['place_id'] as String)),
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

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

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
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'https://…',
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
          padding: const EdgeInsets.only(top: ArivoSpace.s3),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_result!['note'] as String, style: t.bodyM),
                if (_result!['source_title'] != null) Text('From: ${_result!['source_title']}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (place != null) ArivoButton('Add', kind: ButtonKind.tonal, onPressed: () => addPlaceToTrip(context, ref, place['id'] as String)),
          ]),
        ),
    ]);
  }
}


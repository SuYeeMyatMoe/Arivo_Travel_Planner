import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../common/change_sheet.dart';
import '../shell/app_shell.dart';

final crewProvider = FutureProvider.autoDispose<Json?>((ref) async {
  final trip = await ref.watch(tripProvider.future);
  if (trip == null) return null;
  return Map<String, dynamic>.from(await ref.read(apiProvider).get('/v1/trips/${trip.id}/crew') as Map);
});

/// Arivo Crew: a constellation, not a Venn diagram. Fair shares, open votes, and proposals you review.
class CrewScreen extends ConsumerWidget {
  const CrewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider).value;
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: const Text('Crew')),
      body: trip == null
          ? StateMessage(title: 'No trip yet', body: 'Plan a trip, then invite your crew.', action: 'Plan a trip', onAction: () => context.go('/start'))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(crewProvider),
              child: PageWidth(
                child: ref.watch(crewProvider).when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => StateMessage(title: 'Crew unavailable', body: '$e', icon: Icons.cloud_off_outlined),
                      data: (crew) => ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s8), children: [
                        Text(trip.title, style: t.displayM),
                        Text('${trip.crew.length} of ${trip.crewSize} in the crew', style: t.caption),
                        const SizedBox(height: ArivoSpace.s3),
                        _Constellation(crew: crew!),
                        _InviteCard(trip: trip),
                        const SizedBox(height: ArivoSpace.s5),
                        _SharedAndConflicts(crew: crew),
                        const SizedBox(height: ArivoSpace.s5),
                        _Balance(crew: crew),
                        const SizedBox(height: ArivoSpace.s5),
                        _Suggestions(trip: trip, crew: crew),
                      ]),
                    ),
              ),
            ),
    );
  }
}

class _Constellation extends StatelessWidget {
  const _Constellation({required this.crew});
  final Json crew;
  @override
  Widget build(BuildContext context) {
    final members = (crew['members'] as List).cast<Map>();
    if (members.isEmpty) return const SizedBox.shrink();
    final ids = [for (final m in members) m['user_id'] as String];
    final names = [for (final m in members) m['name'] as String];
    final links = <(int, int, String, bool)>[];
    // Solid line: two people share a top interest. Dashed: they disagree on something (from the conflicts list).
    for (var a = 0; a < members.length; a++) {
      for (var b = a + 1; b < members.length; b++) {
        final shared = (members[a]['top'] as List).toSet().intersection((members[b]['top'] as List).toSet());
        if (shared.isNotEmpty) links.add((a, b, shared.first as String, false));
      }
    }
    for (final c in (crew['conflicts'] as List).cast<Map>()) {
      final fans = (c['fans'] as List).cast<String>().toSet();
      final a = names.indexWhere(fans.contains), b = names.indexWhere((n) => !fans.contains(n));
      if (a >= 0 && b >= 0 && !links.any((l) => {l.$1, l.$2}.containsAll({a, b}))) links.add((a < b ? a : b, a < b ? b : a, c['label'] as String, true));
    }
    return Semantics(
      label: 'Crew: ${names.join(', ')}. ${links.where((l) => !l.$4).length} shared interests, ${links.where((l) => l.$4).length} to balance.',
      child: CrewConstellation(names: [for (var i = 0; i < names.length; i++) ids[i] == ArivoConfig.devUser ? '${names[i]} (you)' : names[i]],
          colors: [for (final m in members) (m['color_index'] as num).toInt()], links: links.take(6).toList()),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.trip});
  final Trip trip;
  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  Json? _invite;
  String? _error;
  bool _busy = false;
  final _code = TextEditingController();

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      _invite = Map<String, dynamic>.from(await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/invites') as Map);
      _error = null;
    } on ApiError catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final token = _code.text.trim().split('/').last;
    if (token.isEmpty) return;
    try {
      final j = await ref.read(apiProvider).post('/v1/invites/$token/join') as Map;
      await ref.read(currentTripIdProvider.notifier).set(j['trip_id'] as String);
      ref.invalidate(crewProvider);
      _code.clear();
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final full = widget.trip.crew.length >= widget.trip.crewSize;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ArivoSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Invite your crew', style: t.titleM),
          const SizedBox(height: ArivoSpace.s2),
          if (_invite == null)
            ArivoButton(full ? 'Crew is full' : 'Create invite link', icon: Icons.link, busy: _busy, onPressed: full ? null : _create)
          else ...[
            SelectableText(_invite!['link'] as String, style: t.monoS),
            Text('Works ${_invite!['max_uses']} time(s) · expires ${(_invite!['expires_at'] as String).substring(0, 10)}', style: t.caption),
            const SizedBox(height: ArivoSpace.s2),
            ArivoButton('Copy link', kind: ButtonKind.tonal, icon: Icons.copy, onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _invite!['link'] as String));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link copied')));
            }),
          ],
          const Divider(height: ArivoSpace.s6),
          Row(children: [
            Expanded(child: TextField(controller: _code, decoration: const InputDecoration(labelText: 'Got a link? Paste it to join'))),
            IconButton(tooltip: 'Join', onPressed: _join, icon: const Icon(Icons.arrow_forward)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s2), child: Text(_error!, style: t.caption.copyWith(color: context.palette.emberText))),
        ]),
      ),
    );
  }
}

class _SharedAndConflicts extends StatelessWidget {
  const _SharedAndConflicts({required this.crew});
  final Json crew;
  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    final shared = (crew['shared'] as List).cast<Map>();
    final conflicts = (crew['conflicts'] as List).cast<Map>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Crew DNA', style: t.titleL),
      const SizedBox(height: ArivoSpace.s2),
      if (shared.isEmpty && conflicts.isEmpty)
        Text('Add your tastes in You → Taste DNA. Arivo builds the plan from everyone\'s picks, not an average.', style: t.bodyM),
      if (shared.isNotEmpty)
        Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
          for (final s in shared) Chip(avatar: Icon(Icons.favorite, size: 16, color: p.signalText), label: Text('${s['label']} · everyone')),
        ]),
      for (final c in conflicts)
        Container(
          margin: const EdgeInsets.only(top: ArivoSpace.s3),
          padding: const EdgeInsets.all(ArivoSpace.s3),
          decoration: BoxDecoration(border: Border.all(color: p.lantern), borderRadius: BorderRadius.circular(ArivoRadius.s)),
          child: Row(children: [
            Icon(Icons.call_split, color: p.lanternText),
            const SizedBox(width: ArivoSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['label']}${(c['fans'] as List).isEmpty ? '' : ' — ${(c['fans'] as List).join(', ')}'}', style: t.label),
                Text(c['note'] as String, style: t.caption),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.crew});
  final Json crew;
  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    final days = (crew['balance'] as List? ?? const []).cast<Map>();
    if (days.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Whose day is it?', style: t.titleL),
      Text('Share of each day\'s time that matches each person\'s tastes. A balance, not a score.', style: t.caption),
      const SizedBox(height: ArivoSpace.s3),
      for (final d in days)
        Padding(
          padding: const EdgeInsets.only(bottom: ArivoSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Day ${(d['day_index'] as num).toInt() + 1} · ${d['title']}', style: t.label),
            const SizedBox(height: ArivoSpace.s2),
            for (final m in (d['members'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 72, child: Text(m['name'] as String, style: t.caption, overflow: TextOverflow.ellipsis)),
                  Expanded(child: ShareBar(value: (m['share'] as num) / 100, color: p.crew((m['color_index'] as num).toInt()))),
                  SizedBox(width: 44, child: Text('${m['share']}%', style: t.monoS, textAlign: TextAlign.right)),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

class _Suggestions extends ConsumerStatefulWidget {
  const _Suggestions({required this.trip, required this.crew});
  final Trip trip;
  final Json crew;
  @override
  ConsumerState<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<_Suggestions> {
  final _text = TextEditingController();
  String _kind = 'nightlife';
  int _day = 0;

  Future<void> _add() async {
    if (_text.text.trim().length < 2) return;
    try {
      await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/crew/suggestions', body: {'text': _text.text.trim(), 'kind': _kind, 'day_index': _day});
      _text.clear();
      ref.invalidate(crewProvider);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _vote(Map s, int value) async {
    try {
      final j = Map<String, dynamic>.from(await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/crew/suggestions/${s['id']}/vote', body: {'value': value}) as Map);
      ref.invalidate(crewProvider);
      if (j['proposal'] != null && mounted) {
        await showChangeSheet(context, ref, TripChange.fromJson({...Map<String, dynamic>.from(j['proposal'] as Map), 'new_items': const []}),
            title: 'The crew voted yes');
      }
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final list = (widget.crew['suggestions'] as List? ?? const []).cast<Map>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Ideas & votes', style: t.titleL),
      Text('When most of the crew votes yes on a night out, Arivo proposes an evening change for you to review.', style: t.caption),
      const SizedBox(height: ArivoSpace.s3),
      TextField(controller: _text, maxLength: 200, decoration: const InputDecoration(hintText: 'e.g. Golden Gai bar crawl on day 2')),
      Wrap(spacing: ArivoSpace.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final k in const ['nightlife', 'food', 'place', 'other'])
          ChoiceChip(label: Text(k[0].toUpperCase() + k.substring(1)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
        DropdownButton<int>(
          value: _day,
          items: [for (var i = 0; i < widget.trip.days.length; i++) DropdownMenuItem(value: i, child: Text('Day ${i + 1}'))],
          onChanged: (v) => setState(() => _day = v!),
        ),
        ArivoButton('Suggest', kind: ButtonKind.tonal, onPressed: _add),
      ]),
      const SizedBox(height: ArivoSpace.s3),
      for (final s in list)
        Card(
          child: ListTile(
            title: Text(s['text'] as String, style: t.bodyM),
            subtitle: Text('${s['author']} · ${s['kind']}${s['day_index'] != null ? ' · Day ${(s['day_index'] as num).toInt() + 1}' : ''}'
                '${s['status'] == 'proposed' ? ' · change proposed' : ''}', style: t.caption),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Vote no', onPressed: () => _vote(s, -1), icon: const Icon(Icons.thumb_down_outlined)),
              Text('${s['score']}', style: t.monoM),
              IconButton(tooltip: 'Vote yes', onPressed: () => _vote(s, 1), icon: const Icon(Icons.thumb_up_outlined)),
            ]),
          ),
        ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ari/ari.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/trip_widgets.dart';
import '../../state/providers.dart';

/// Why this? — every reason behind a stop, with where each fact came from.
Future<void> showWhySheet(BuildContext context, WidgetRef ref, Trip trip, ItineraryItem item) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final p = ctx.palette, t = ctx.type;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow('${hhmm(item.start)} · ${duration(item.durationMin)} · ${titleCase(item.category)}'),
            const SizedBox(height: ArivoSpace.s2),
            Text(item.name, style: t.displayM),
            if (item.score != null) Text('${(item.score! * 100).round()}% match for your trip', style: t.monoM.copyWith(color: p.signalText)),
            const SizedBox(height: ArivoSpace.s4),
            Text('Why this?', style: t.titleM),
            const SizedBox(height: ArivoSpace.s2),
            for (final e in item.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 3), child: Icon(Icons.circle, size: 6, color: p.provenance(e.provenance.name))),
                  const SizedBox(width: ArivoSpace.s3),
                  Expanded(child: Text(e.text, style: t.bodyM)),
                  ProvenanceTag(e.provenance, source: e.source),
                ]),
              ),
            if (item.isBooked) Text('This is a booking — a fixed point Rescue never moves.', style: t.caption),
            const SizedBox(height: ArivoSpace.s4),
            Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
              if (!item.placeId.startsWith('booking') && !item.placeId.startsWith('transfer'))
                ArivoButton('Details', kind: ButtonKind.tonal, icon: Icons.info_outline_rounded, onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/place/${Uri.encodeComponent(item.placeId)}');
                }),
              if (!item.placeId.startsWith('booking') && !item.placeId.startsWith('transfer'))
                ArivoButton('Hear the story', kind: ButtonKind.tonal, icon: Icons.auto_stories_outlined, onPressed: () {
                  Navigator.pop(ctx);
                  showStorySheet(context, ref, item.placeId, item.name);
                }),
              if (!item.isBooked)
                ArivoButton('Not for me', kind: ButtonKind.quiet, onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final j = await ref.read(apiProvider).post('/v1/trips/${trip.id}/items/${item.id}', body: {'action': 'remove'});
                    ref.read(tripProvider.notifier).replace(Map<String, dynamic>.from(j as Map));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed ${item.name}. Arivo will learn from this.')));
                  } on ApiError catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Story Mode: sourced storytelling (Wikipedia), 30 s / 1 min / deep dive, read aloud on request.
Future<void> showStorySheet(BuildContext context, WidgetRef ref, String placeId, String name) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Theme(data: ArivoTheme.ink(), child: _StorySheet(placeId: placeId, name: name)),
  );
}

class _StorySheet extends ConsumerStatefulWidget {
  const _StorySheet({required this.placeId, required this.name});
  final String placeId, name;
  @override
  ConsumerState<_StorySheet> createState() => _StorySheetState();
}

class _StorySheetState extends ConsumerState<_StorySheet> {
  String _length = '1min';
  Map<String, dynamic>? _story;
  bool _loading = false;
  final _tts = FlutterTts();

  Future<void> _load() async {
    setState(() => _loading = true);
    ref.read(ariProvider.notifier).set(AriState.thinking);
    try {
      final j = await ref.read(apiProvider).post('/v1/places/${widget.placeId}/story', body: {'length': _length});
      setState(() => _story = Map<String, dynamic>.from(j as Map));
      ref.read(ariProvider.notifier).set(AriState.talking, revertAfter: const Duration(seconds: 8));
    } on ApiError catch (e) {
      setState(() => _story = {'status': 'error', 'message': e.message});
      ref.read(ariProvider.notifier).set(AriState.warning, revertAfter: const Duration(seconds: 4));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final text = _story?['text'] as String? ?? _story?['message'] as String?;
    final sources = (_story?['sources'] as List?)?.cast<Map>() ?? const [];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.name, style: t.displayM)),
              AriSprite(state: ref.watch(ariProvider).state, size: 72),
            ]),
            const SizedBox(height: ArivoSpace.s2),
            Text('Shall I tell you the story of this place?', style: t.bodyL.copyWith(color: p.muted)),
            const SizedBox(height: ArivoSpace.s4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '30s', label: Text('30 sec')),
                ButtonSegment(value: '1min', label: Text('1 min')),
                ButtonSegment(value: 'deep', label: Text('Deep dive')),
              ],
              selected: {_length},
              onSelectionChanged: (s) => setState(() => _length = s.first),
            ),
            const SizedBox(height: ArivoSpace.s4),
            ArivoButton(_story == null ? 'Start story' : 'Tell it again', icon: Icons.play_arrow_rounded, busy: _loading, onPressed: _load),
            if (text != null) ...[
              const SizedBox(height: ArivoSpace.s5),
              Text(text, style: t.bodyL),
              const SizedBox(height: ArivoSpace.s3),
              Row(children: [
                ArivoButton('Read aloud', kind: ButtonKind.tonal, icon: Icons.volume_up_outlined, onPressed: () => _tts.speak(text)),
                const SizedBox(width: ArivoSpace.s2),
                if (_story?['generated'] == false) Text('Verified summary · no AI rewrite', style: t.caption),
              ]),
              for (final s in sources)
                TextButton.icon(
                  onPressed: s['url'] == null ? null : () => launchUrl(Uri.parse(s['url'] as String)),
                  icon: const Icon(Icons.link, size: 16),
                  label: Text('${s['name']} · ${s['title'] ?? ''} (${s['license'] ?? ''})', style: t.caption),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Rescue My Day (ink): tell Arivo what happened, review exactly what changes, then decide.
Future<void> showRescueSheet(BuildContext context, WidgetRef ref, Trip trip, int dayIndex) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Theme(data: ArivoTheme.ink(), child: _RescueSheet(trip: trip, dayIndex: dayIndex)),
  );
}

class _RescueSheet extends ConsumerStatefulWidget {
  const _RescueSheet({required this.trip, required this.dayIndex});
  final Trip trip;
  final int dayIndex;
  @override
  ConsumerState<_RescueSheet> createState() => _RescueSheetState();
}

class _RescueSheetState extends ConsumerState<_RescueSheet> {
  TripChange? _change;
  String? _busy, _error;
  late DateTime _now = tripNow(widget.trip, ref.read(demoClockProvider), widget.dayIndex);

  static const _options = [
    ('rain', Icons.umbrella_outlined, "It's raining", 'Indoor swaps nearby'),
    ('late', Icons.alarm_outlined, 'Running late', 'Compress the day'),
    ('fatigue', Icons.bedtime_outlined, "We're tired", 'Slower, less walking'),
    ('budget', Icons.savings_outlined, 'Over budget', 'Free alternatives'),
    ('more_food', Icons.ramen_dining_outlined, 'More food', 'A food stop on the way'),
    ('skip_category', Icons.museum_outlined, 'Skip museums', 'Swap them out'),
  ];

  Future<void> _rescue(String trigger) async {
    setState(() {
      _busy = trigger;
      _error = null;
    });
    ref.read(ariProvider.notifier).set(AriState.thinking);
    try {
      final j = await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/rescue', body: {
        'trigger': trigger,
        'day_index': widget.dayIndex,
        'now': _now.toIso8601String().substring(0, 19),
        if (trigger == 'late') 'minutes_late': 90,
        if (trigger == 'skip_category') 'category': 'museum',
      }) as Map;
      if (j['status'] == 'proposed') {
        setState(() => _change = TripChange.fromJson(Map<String, dynamic>.from(j['change'] as Map)));
        ref.read(ariProvider.notifier).set(trigger == 'rain' ? AriState.warning : AriState.talking, revertAfter: const Duration(seconds: 5));
      } else {
        setState(() => _error = j['question'] as String?);
      }
    } on ApiError catch (e) {
      setState(() => _error = e.message);
      ref.read(ariProvider.notifier).set(AriState.warning, revertAfter: const Duration(seconds: 4));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _decide(bool apply) async {
    final c = _change!;
    setState(() => _busy = apply ? 'apply' : 'keep');
    try {
      final j = await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/changes/${c.id}/${apply ? 'apply' : 'reject'}') as Map;
      if (apply) {
        ref.read(tripProvider.notifier).replace(Map<String, dynamic>.from(j['trip'] as Map));
        ref.read(ariProvider.notifier).say('Done — your day is updated. Bookings stayed exactly where they were.', as: AriState.excited);
      }
      if (mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s8), children: [
        Row(children: [
          Expanded(child: Text(_change == null ? 'Rescue my day' : 'Plan updated', style: t.displayM)),
          AriSprite(state: ref.watch(ariProvider).state, size: 76),
        ]),
        if (_change == null) ...[
          Text("Tell me what's happening. I'll rebuild the rest of today — bookings stay put.", style: t.bodyL.copyWith(color: p.muted)),
          const SizedBox(height: ArivoSpace.s2),
          Row(children: [
            Icon(Icons.schedule, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Text('As of ${hhmm(_now)} · ${dayLabel(_now)}', style: t.caption),
            TextButton(
              onPressed: () async {
                final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_now));
                if (tm != null) setState(() => _now = DateTime(_now.year, _now.month, _now.day, tm.hour, tm.minute));
              },
              child: const Text('Change'),
            ),
          ]),
          const SizedBox(height: ArivoSpace.s3),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: ArivoSpace.s3,
            crossAxisSpacing: ArivoSpace.s3,
            childAspectRatio: 1.45,
            children: [
              for (final (key, icon, title, sub) in _options)
                Material(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(ArivoRadius.s),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(ArivoRadius.s),
                    onTap: _busy == null ? () => _rescue(key) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(ArivoSpace.s3),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        _busy == key ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: p.signal)) : Icon(icon, color: p.signalText),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.titleM), Text(sub, style: t.caption)]),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ] else ...[
          Text(_change!.explanation, style: t.bodyL),
          const SizedBox(height: ArivoSpace.s5),
          ChangeDiff(change: _change!),
          const SizedBox(height: ArivoSpace.s4),
          ArivoButton('Apply changes', expand: true, busy: _busy == 'apply', onPressed: () => _decide(true)),
          const SizedBox(height: ArivoSpace.s2),
          ArivoButton('Keep original', kind: ButtonKind.tonal, expand: true, onPressed: _busy == null ? () => _decide(false) : null),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s3), child: Text(_error!, style: t.bodyM.copyWith(color: p.lanternText))),
      ]),
    );
  }
}

/// Unused import guard for StopCard (used by callers that import this file).
typedef StopCardBuilder = StopCard Function(ItineraryItem);

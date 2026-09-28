import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/ari/ari.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/trip_widgets.dart';
import '../../state/providers.dart';
import '../common/change_sheet.dart';

Future<void> showGuideSheet(BuildContext context, {bool startListening = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Theme(data: ArivoTheme.ink(), child: _GuideSheet(startListening: startListening)),
  );
}

class _Msg {
  _Msg(this.fromUser, this.text, {this.cards = const [], this.proposals = const []});
  final bool fromUser;
  final String text;
  final List<Json> cards, proposals;
}

/// Arivo Guide: ask by text or voice. Ari can read, search and propose — you confirm; Ari never pays.
class _GuideSheet extends ConsumerStatefulWidget {
  const _GuideSheet({required this.startListening});
  final bool startListening;
  @override
  ConsumerState<_GuideSheet> createState() => _GuideSheetState();
}

class _GuideSheetState extends ConsumerState<_GuideSheet> {
  final _input = TextEditingController();
  final _msgs = <_Msg>[];
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _listening = false, _busy = false, _speak = true;
  final _done = <Json>{}; // proposals already confirmed: shown as done, never offered twice

  static const _prompts = ["What's next?", 'How much have we spent?', 'Find coffee near us', 'Move dinner later', 'Tell me the story of this place', 'It started raining'];

  @override
  void initState() {
    super.initState();
    if (widget.startListening) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    final ari = ref.read(ariProvider.notifier);
    final ok = await _stt.initialize(onError: (_) => setState(() => _listening = false));
    if (!ok) {
      setState(() => _msgs.add(_Msg(false, 'Voice needs microphone permission. You can type instead.')));
      return;
    }
    setState(() => _listening = true);
    ari.set(AriState.listening);
    await _stt.listen(onResult: (r) {
      _input.text = r.recognizedWords;
      if (r.finalResult) {
        setState(() => _listening = false);
        _send();
      }
    });
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty) return;
    final trip = await ref.read(tripProvider.future);
    if (trip == null) {
      setState(() => _msgs.add(_Msg(false, 'Plan a trip first and I can help with it.')));
      return;
    }
    _input.clear();
    setState(() {
      _msgs.add(_Msg(true, q));
      _busy = true;
    });
    final ari = ref.read(ariProvider.notifier);
    ari.set(AriState.thinking);
    try {
      final now = tripNow(trip, ref.read(demoClockProvider), ref.read(selectedDayProvider));
      final j = Map<String, dynamic>.from(await ref.read(apiProvider).post('/v1/trips/${trip.id}/guide', body: {'text': q, 'now': now.toIso8601String().substring(0, 19)}) as Map);
      final reply = j['reply'] as String;
      setState(() => _msgs.add(_Msg(false, reply,
          cards: List<Json>.from((j['cards'] as List).map((e) => Map<String, dynamic>.from(e as Map))),
          proposals: List<Json>.from((j['proposals'] as List).map((e) => Map<String, dynamic>.from(e as Map))))));
      final state = AriState.values.firstWhere((s) => s.name == j['ari_state'], orElse: () => AriState.talking);
      ari.set(state, revertAfter: const Duration(seconds: 6));
      if (_speak) await _tts.speak(reply);
    } on ApiError catch (e) {
      setState(() => _msgs.add(_Msg(false, e.message)));
      ari.set(e.isOffline ? AriState.offline : AriState.warning, revertAfter: const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(Json proposal) async {
    final kind = proposal['kind'] as String;
    final confirm = Map<String, dynamic>.from(proposal['confirm'] as Map);
    final api = ref.read(apiProvider);
    try {
      if (kind == 'trip_change') {
        final ch = Map<String, dynamic>.from((proposal['data'] as Map)['change'] as Map);
        final full = (await api.get('/v1/trips/${ch['trip_id']}/changes') as List).cast<Map>().firstWhere((c) => c['id'] == ch['id']);
        if (!mounted) return;
        final applied = await showChangeSheet(context, ref, TripChange.fromJson({...Map<String, dynamic>.from(full), 'new_items': const []}), title: 'Rescue my day');
        if (applied) setState(() => _done.add(proposal));
      } else if (kind == 'move_item') {
        final j = await api.post(confirm['path'] as String, body: confirm['body']);
        ref.read(tripProvider.notifier).replace(Map<String, dynamic>.from(j as Map));
        setState(() {
          _done.add(proposal);
          _msgs.add(_Msg(false, 'Done — moved.'));
        });
      } else if (kind == 'checkout') {
        final j = await api.post('/v1/trips/${confirm['trip_id']}/bookings', body: {'offer_id': confirm['offer_id'], 'travellers': 1}, idempotencyKey: ArivoApi.newIdempotencyKey());
        if (mounted) {
          Navigator.pop(context);
          context.push('/checkout/${(j as Map)['id']}');
        }
      }
    } on ApiError catch (e) {
      setState(() => _msgs.add(_Msg(false, e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final ari = ref.watch(ariProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s3, 0),
          child: Row(children: [
            AriSprite(state: ari.state, size: 64),
            const SizedBox(width: ArivoSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ari', style: t.titleL),
                Text(_listening ? "I'm listening…" : 'Ask anything about your trip.', style: t.caption),
              ]),
            ),
            IconButton(
              tooltip: _speak ? 'Mute replies' : 'Read replies aloud',
              icon: Icon(_speak ? Icons.volume_up_outlined : Icons.volume_off_outlined),
              onPressed: () => setState(() => _speak = !_speak),
            ),
          ]),
        ),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.all(ArivoSpace.s4), children: [
            if (_msgs.isEmpty)
              Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
                for (final q in _prompts) ActionChip(label: Text(q), onPressed: () => _send(q)),
              ]),
            for (final m in _msgs) _bubble(context, m),
            if (_busy) Padding(padding: const EdgeInsets.all(ArivoSpace.s3), child: Text('Ari is thinking…', style: t.caption)),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, ArivoSpace.s3 + MediaQuery.viewInsetsOf(context).bottom),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Ask anything…'),
                ),
              ),
              const SizedBox(width: ArivoSpace.s2),
              IconButton.filled(
                tooltip: _listening ? 'Stop listening' : 'Talk to Ari',
                style: IconButton.styleFrom(backgroundColor: _listening ? p.signal : p.volt, foregroundColor: p.onVolt, minimumSize: const Size(52, 52)),
                onPressed: _listening ? () => _stt.stop() : _listen,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(BuildContext context, _Msg m) {
    final p = context.palette, t = context.type;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.only(bottom: ArivoSpace.s3),
        padding: const EdgeInsets.all(ArivoSpace.s3),
        decoration: BoxDecoration(color: m.fromUser ? p.volt : p.sunken, borderRadius: BorderRadius.circular(ArivoRadius.m)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text, style: t.bodyM.copyWith(color: m.fromUser ? p.onVolt : p.text)),
          for (final c in m.cards) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s2), child: _card(context, c)),
          for (final pr in m.proposals)
            Padding(
              padding: const EdgeInsets.only(top: ArivoSpace.s3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pr['summary'] as String, style: t.caption.copyWith(color: p.text)),
                const SizedBox(height: ArivoSpace.s2),
                if (_done.contains(pr))
                  const StatusChip(ChipTone.done, label: 'Done')
                else
                  ArivoButton(switch (pr['kind']) { 'checkout' => 'Review & pay', 'trip_change' => 'Review changes', _ => 'Confirm' },
                      kind: ButtonKind.tonal, onPressed: () => _confirm(pr)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, Json c) {
    final t = context.type;
    switch (c['type']) {
      case 'stop':
        return StopCard(item: ItineraryItem.fromJson(Map<String, dynamic>.from(c['item'] as Map)), compact: true);
      case 'offer':
        return BoardingPassCard(offer: TravelOffer.fromJson(Map<String, dynamic>.from(c['offer'] as Map)));
      case 'budget':
        return BudgetGauge(view: BudgetView.fromJson(Map<String, dynamic>.from(c['budget'] as Map)));
      case 'place':
        return Row(children: [
          Expanded(child: Text('${c['name']}', style: t.label)),
          Text('${c['match']}%', style: t.monoS),
        ]);
      case 'story':
        final s = Map<String, dynamic>.from(c['story'] as Map);
        return Text((s['sources'] as List?)?.isNotEmpty == true ? 'Source: ${(s['sources'] as List).first['name']}' : '', style: t.caption);
      default:
        return const SizedBox.shrink();
    }
  }
}

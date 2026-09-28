import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ari/ari.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';

const _examples = [
  "I'm visiting Tokyo for five days with three friends. Around RM4,000 each. We love anime, food and photography but hate rushing.",
  'I live in Kuala Lumpur and have one free Saturday. Give me somewhere interesting under RM150.',
  'Kyoto for 3 days with my partner — temples, gardens and good food, not too packed.',
];

/// One sentence in, a whole trip out. Everything else is optional.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _text = TextEditingController();
  DateTime? _start;
  String? _crew;
  bool _busy = false;
  int _step = 0;
  String? _message;
  Timer? _steps;

  static const _stepLabels = ['Reading your request…', 'Finding verified places…', 'Checking opening hours…', 'Routing each day…', 'Balancing the budget…'];

  @override
  void dispose() {
    _steps?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final text = _text.text.trim();
    if (text.length < 3) {
      setState(() => _message = 'Tell me where — a city, a country, or "somewhere near KL".');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _step = 0;
    });
    ref.read(ariProvider.notifier).set(AriState.thinking);
    _steps = Timer.periodic(const Duration(milliseconds: 900), (_) => setState(() => _step = (_step + 1).clamp(0, _stepLabels.length - 1)));
    try {
      final quick = <String, dynamic>{
        if (_start != null) 'start_date': _start!.toIso8601String().substring(0, 10),
        if (_crew != null) 'crew_type': _crew,
        if (_crew == 'couple') 'crew_size': 2,
        if (_crew == 'solo') 'crew_size': 1,
      };
      final res = await ref.read(apiProvider).post('/v1/trips', body: {'text': text, 'quick': quick}) as Map;
      if (!mounted) return;
      switch (res['status']) {
        case 'ok':
          final trip = Map<String, dynamic>.from(res['trip'] as Map);
          await ref.read(currentTripIdProvider.notifier).set(trip['id'] as String);
          ref.read(ariProvider.notifier).say("Here's your trip. Tap any stop to see why it's there.", as: AriState.excited);
          if (mounted) context.go('/trip');
        case 'needs_input':
          setState(() => _message = (res['question'] as Map)['text'] as String);
          ref.read(ariProvider.notifier).set(AriState.listening);
        default:
          final err = Map<String, dynamic>.from(res['error'] as Map);
          final supported = (err['supported'] as List?)?.join(', ');
          setState(() => _message = supported == null ? '${err['message']}' : "${err['message']} I can plan $supported today.");
          ref.read(ariProvider.notifier).set(AriState.warning);
      }
    } on ApiError catch (e) {
      setState(() => _message = e.message);
      ref.read(ariProvider.notifier).set(e.isOffline ? AriState.offline : AriState.warning);
    } finally {
      _steps?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ArivoTheme.ink(),
      child: Builder(builder: (context) {
        final p = context.palette, t = context.type;
        final ari = ref.watch(ariProvider);
        final existing = ref.watch(currentTripIdProvider);
        return Scaffold(
          body: TopoBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, ArivoSpace.s4, ArivoSpace.s5, ArivoSpace.s8), children: [
                    Row(children: [
                      Text('Arivo', style: t.displayM.copyWith(fontSize: 28)),
                      const Spacer(),
                      if (existing != null) ArivoButton('My trip', kind: ButtonKind.quiet, onPressed: () => context.go('/trip')),
                    ]),
                    Ari3D(state: ari.state, height: 230),
                    Text('Where should we go?', style: t.displayL),
                    const SizedBox(height: ArivoSpace.s2),
                    Text("Tell me in one sentence. I'll handle the order, timing, budget — and what changes along the way.",
                        style: t.bodyL.copyWith(color: p.muted)),
                    const SizedBox(height: ArivoSpace.s5),
                    TextField(
                      controller: _text,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 600,
                      style: t.bodyL,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(hintText: '5 days in Tokyo with friends, about RM4,000 each…', counterText: ''),
                    ),
                    const SizedBox(height: ArivoSpace.s3),
                    Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
                      for (final c in const ['solo', 'couple', 'friends', 'family'])
                        ChoiceChip(
                          label: Text(c[0].toUpperCase() + c.substring(1)),
                          selected: _crew == c,
                          onSelected: (v) => setState(() => _crew = v ? c : null),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.event_outlined, size: 18),
                        label: Text(_start == null ? 'Dates' : '${_start!.day}/${_start!.month}/${_start!.year}'),
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 540)), initialDate: now.add(const Duration(days: 30)));
                          if (d != null) setState(() => _start = d);
                        },
                      ),
                    ]),
                    const SizedBox(height: ArivoSpace.s5),
                    ArivoButton(_busy ? _stepLabels[_step] : 'Build my trip', expand: true, busy: _busy, onPressed: _build, icon: Icons.arrow_forward_rounded),
                    if (_message != null) ...[
                      const SizedBox(height: ArivoSpace.s3),
                      Semantics(liveRegion: true, child: Text(_message!, style: t.bodyM.copyWith(color: p.lanternText))),
                    ],
                    const SizedBox(height: ArivoSpace.s6),
                    Eyebrow('Try'),
                    const SizedBox(height: ArivoSpace.s2),
                    for (final e in _examples)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(ArivoRadius.s),
                          onTap: () => setState(() => _text.text = e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.north_east_rounded, size: 16, color: p.signalText),
                              const SizedBox(width: ArivoSpace.s2),
                              Expanded(child: Text(e, style: t.bodyM.copyWith(color: p.muted))),
                            ]),
                          ),
                        ),
                      ),
                    const SizedBox(height: ArivoSpace.s6),
                    Text('Places: © OpenStreetMap contributors · Wikidata · Wikimedia Commons. Ari is derived from "Miibot" by itsmejhade (CC BY 4.0).',
                        style: t.caption),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

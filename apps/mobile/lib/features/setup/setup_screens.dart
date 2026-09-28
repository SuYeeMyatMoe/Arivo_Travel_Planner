import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ari/ari.dart';
import '../../core/data/destinations.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

// Setup wizard: interests → budget → where → when → who → generate → ready.
// Interests and budget are remembered on the device, so "Plan a new trip" later starts at "Where".

const _steps = 5;

// ---------------------------------------------------------------------------------------------------------- Interests

class InterestsStep extends ConsumerWidget {
  const InterestsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(sessionProvider).interests;
    void toggle(String k) =>
        ref.read(sessionProvider.notifier).setInterests(picked.contains(k) ? picked.where((x) => x != k).toList() : [...picked, k]);
    return StepScaffold(
      title: 'What interests you?',
      subtitle: 'Select a few to get better recommendations.',
      step: 1,
      steps: _steps,
      onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      onNext: picked.isEmpty ? null : () => context.push('/setup/budget'),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: ArivoSpace.s3,
          crossAxisSpacing: ArivoSpace.s3,
          childAspectRatio: 1.25,
          children: [
            for (final i in interests) PhotoTile(photo: i.photo, label: i.label, selected: picked.contains(i.key), onTap: () => toggle(i.key)),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------------------- Budget

class BudgetStep extends ConsumerWidget {
  const BudgetStep({super.key});

  static const _tiers = [('budget', 'Budget', '\$', 80.0), ('mid', 'Mid-range', '\$\$', 200.0), ('luxury', 'Luxury', '\$\$\$', 500.0)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final p = context.palette, t = context.type;
    final low = (s.dailyBudget * 0.6 / 10).round() * 10, high = (s.dailyBudget * 1.4 / 10).round() * 10;
    return StepScaffold(
      title: "What's your budget?",
      subtitle: 'This helps us create realistic recommendations.',
      step: 2,
      steps: _steps,
      onNext: () => context.push('/setup/where'),
      children: [
        Row(children: [
          for (final (key, label, sign, daily) in _tiers) ...[
            Expanded(
              child: Semantics(
                button: true,
                selected: s.budgetTier == key,
                label: label,
                child: GestureDetector(
                  onTap: () => ref.read(sessionProvider.notifier).setBudget(key, daily),
                  child: AnimatedContainer(
                    duration: ArivoMotion.fast,
                    padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s5),
                    decoration: BoxDecoration(
                      color: s.budgetTier == key ? p.voltSoft : p.raised,
                      borderRadius: BorderRadius.circular(ArivoRadius.m),
                      border: Border.all(color: s.budgetTier == key ? p.volt : p.line, width: s.budgetTier == key ? 2 : 1),
                    ),
                    child: Column(children: [
                      Text(label, style: t.caption.copyWith(color: s.budgetTier == key ? p.voltText : p.muted)),
                      const SizedBox(height: ArivoSpace.s2),
                      Text(sign, style: t.displayM.copyWith(color: s.budgetTier == key ? p.voltText : p.muted)),
                    ]),
                  ),
                ),
              ),
            ),
            if (key != 'luxury') const SizedBox(width: ArivoSpace.s3),
          ],
        ]),
        const SizedBox(height: ArivoSpace.s8),
        Text('Estimated budget per day', style: t.label),
        const SizedBox(height: ArivoSpace.s1),
        Text('\$$low – \$$high', style: t.displayM),
        Text('per person, excluding flights', style: t.caption),
        const SizedBox(height: ArivoSpace.s3),
        Slider(
          value: s.dailyBudget.clamp(50, 1000),
          min: 50,
          max: 1000,
          divisions: 95,
          label: '\$${s.dailyBudget.round()} / day',
          onChanged: (v) {
            final tier = v < 130 ? 'budget' : v < 380 ? 'mid' : 'luxury';
            ref.read(sessionProvider.notifier).setBudget(tier, v);
          },
        ),
        Row(children: [Text('\$50', style: t.caption), const Spacer(), Text('\$1,000', style: t.caption)]),
      ],
    );
  }
}

// -------------------------------------------------------------------------------------------------------------- Where

class WhereStep extends ConsumerStatefulWidget {
  const WhereStep({super.key});
  @override
  ConsumerState<WhereStep> createState() => _WhereStepState();
}

class _WhereStepState extends ConsumerState<WhereStep> {
  String _q = '';

  Future<void> _describe() async {
    final draft = ref.read(setupDraftProvider);
    final c = TextEditingController(text: draft.customText ?? '');
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Describe your trip', style: ctx.type.titleL),
          const SizedBox(height: ArivoSpace.s2),
          Text('One sentence is enough — Ari handles the order, timing and budget.', style: ctx.type.bodyM.copyWith(color: ctx.palette.muted)),
          const SizedBox(height: ArivoSpace.s4),
          TextField(
            controller: c,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            decoration: const InputDecoration(hintText: '5 days in Tokyo with three friends, about RM4,000 each. We love anime and food.'),
          ),
          const SizedBox(height: ArivoSpace.s3),
          ArivoButton('Use this', expand: true, onPressed: () => Navigator.pop(ctx, c.text.trim())),
        ]),
      ),
    );
    if (text == null || !mounted) return;
    ref.read(setupDraftProvider.notifier).update((d) => text.length < 3 ? d.copyWith(clearCustom: true) : d.copyWith(customText: text));
    if (text.length >= 3) context.push('/setup/when');
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(setupDraftProvider);
    final supported = ref.watch(supportedCitiesProvider).value ?? const {'tokyo', 'kyoto', 'kuala-lumpur'};
    final p = context.palette, t = context.type;
    final q = _q.trim().toLowerCase();
    final list = destinations
        .where((d) => q.isEmpty || d.name.toLowerCase().contains(q) || d.country.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => (supported.contains(b.key) ? 1 : 0) - (supported.contains(a.key) ? 1 : 0));
    return StepScaffold(
      title: 'Where do you want to go?',
      step: 3,
      steps: _steps,
      onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      onNext: draft.destination == null ? null : () => context.push('/setup/when'),
      footer: TextButton.icon(
        onPressed: _describe,
        icon: Icon(Icons.edit_note_rounded, color: p.voltText),
        label: Text(draft.customText == null ? 'Or describe it in your own words' : 'Edit your description', style: t.label.copyWith(color: p.voltText)),
      ),
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(hintText: 'Search destination (e.g. Japan, Tokyo…)', prefixIcon: Icon(Icons.search_rounded, color: p.muted)),
        ),
        const SizedBox(height: ArivoSpace.s5),
        Text('Popular Destinations', style: t.titleM.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: ArivoSpace.s3),
        if (list.isEmpty)
          Text('No match. Try "Tokyo", "Kyoto" or "Kuala Lumpur", or describe your trip in your own words below.', style: t.bodyM.copyWith(color: p.muted))
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: ArivoSpace.s2,
            crossAxisSpacing: ArivoSpace.s2,
            childAspectRatio: 0.9,
            children: [
              for (final d in list)
                PhotoTile(
                  photo: d.photo,
                  label: d.name,
                  selected: draft.destination?.key == d.key,
                  badge: supported.contains(d.key) ? null : 'Soon',
                  dimmed: !supported.contains(d.key),
                  onTap: () {
                    if (!supported.contains(d.key)) {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(content: Text('Verified planning for ${d.name} is coming soon. Try Tokyo, Kyoto or Kuala Lumpur today.')));
                      return;
                    }
                    ref.read(setupDraftProvider.notifier).update((x) => x.copyWith(destination: d, clearCustom: true));
                  },
                ),
            ],
          ),
      ],
    );
  }
}

// --------------------------------------------------------------------------------------------------------------- When

class WhenStep extends ConsumerWidget {
  const WhenStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(setupDraftProvider);
    final notifier = ref.read(setupDraftProvider.notifier);
    final p = context.palette, t = context.type;
    final now = DateTime.now();
    final start = draft.start ?? now.add(const Duration(days: 30));
    return StepScaffold(
      title: 'When are you traveling?',
      step: 4,
      steps: _steps,
      onNext: () => context.push('/setup/who'),
      children: [
        CleanCard(
          padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s2),
          child: CalendarDatePicker(
            initialDate: start,
            firstDate: DateTime(now.year, now.month, now.day),
            lastDate: now.add(const Duration(days: 540)),
            onDateChanged: (d) => notifier.update((x) => x.copyWith(start: d)),
          ),
        ),
        const SizedBox(height: ArivoSpace.s4),
        CleanCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trip duration', style: t.caption),
                Text('${draft.days} day${draft.days == 1 ? '' : 's'}', style: t.titleM),
              ]),
            ),
            _RoundIcon(icon: Icons.remove_rounded, label: 'Fewer days', onTap: draft.days > 1 ? () => notifier.update((x) => x.copyWith(days: x.days - 1)) : null),
            const SizedBox(width: ArivoSpace.s3),
            _RoundIcon(icon: Icons.add_rounded, label: 'More days', onTap: draft.days < 14 ? () => notifier.update((x) => x.copyWith(days: x.days + 1)) : null),
          ]),
        ),
        const SizedBox(height: ArivoSpace.s3),
        CleanCard(
          padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s2, ArivoSpace.s2),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Flexible dates', style: t.label),
                Text('Show cheaper options around these dates', style: t.caption),
              ]),
            ),
            Switch(value: draft.flexible, onChanged: (v) => notifier.update((x) => x.copyWith(flexible: v))),
          ]),
        ),
        if (draft.customText != null) ...[
          const SizedBox(height: ArivoSpace.s3),
          Text('Your description sets the length of the trip; the start date above is still used.', style: t.caption.copyWith(color: p.muted)),
        ],
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IconButton.outlined(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, color: onTap == null ? p.line : p.text),
      style: IconButton.styleFrom(side: BorderSide(color: p.line)),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------- Who

class WhoStep extends ConsumerWidget {
  const WhoStep({super.key});

  static const _options = [
    ('solo', 'Solo', 'Just me', Icons.person_outline_rounded),
    ('couple', 'Couple', 'Me and my partner', Icons.favorite_border_rounded),
    ('family', 'Family', 'With kids', Icons.family_restroom_rounded),
    ('friends', 'Friends', 'Group trip', Icons.groups_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crew = ref.watch(setupDraftProvider).crew;
    return StepScaffold(
      title: 'Who are you traveling with?',
      step: 5,
      steps: _steps,
      nextLabel: 'Generate my trip',
      onNext: () => context.push('/setup/generate'),
      children: [
        for (final (key, title, sub, icon) in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
            child: SelectCard(
              icon: icon,
              title: title,
              subtitle: sub,
              selected: crew == key,
              onTap: () => ref.read(setupDraftProvider.notifier).update((d) => d.copyWith(crew: key)),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------------------------------------- Generate

class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key});
  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  static const _labels = ['Analyzing your preferences…', 'Finding the best places…', 'Creating a personalized itinerary…', 'Checking prices and opening hours…'];
  int _step = 0;
  double _progress = 0.05;
  bool _busy = true;
  String? _error, _question;
  final _answer = TextEditingController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _run({String? extra}) async {
    setState(() {
      _busy = true;
      _error = null;
      _question = null;
      _step = 0;
      _progress = 0.05;
    });
    ref.read(ariProvider.notifier).set(AriState.thinking);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() {
        _step = (_step + 1).clamp(0, _labels.length - 1);
        _progress = (_progress + 0.12).clamp(0, 0.9);
      });
    });
    try {
      final r = ref.read(setupDraftProvider).request(ref.read(sessionProvider));
      final text = extra == null ? r.text : '${r.text} $extra';
      final res = await ref.read(apiProvider).post('/v1/trips', body: {'text': text, 'quick': r.quick}) as Map;
      if (!mounted) return;
      switch (res['status']) {
        case 'ok':
          final trip = Map<String, dynamic>.from(res['trip'] as Map);
          await ref.read(currentTripIdProvider.notifier).set(trip['id'] as String);
          ref.read(tripProvider.notifier).replace(trip);
          ref.read(selectedDayProvider.notifier).select(0);
          ref.read(ariProvider.notifier).set(AriState.excited);
          setState(() {
            _step = _labels.length;
            _progress = 1;
          });
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (mounted) context.go('/setup/ready');
        case 'needs_input':
          setState(() => _question = (res['question'] as Map)['text'] as String);
          ref.read(ariProvider.notifier).set(AriState.listening);
        default:
          final err = Map<String, dynamic>.from(res['error'] as Map);
          final supported = (err['supported'] as List?)?.join(', ');
          setState(() => _error = supported == null ? '${err['message']}' : "${err['message']} I can plan $supported today.");
          ref.read(ariProvider.notifier).set(AriState.warning);
      }
    } on ApiError catch (e) {
      setState(() => _error = e.message);
      ref.read(ariProvider.notifier).set(e.isOffline ? AriState.offline : AriState.warning);
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Scaffold(
      appBar: AppBar(
        leading: _busy ? null : IconButton(tooltip: 'Back', icon: Icon(Icons.arrow_back_rounded, color: p.volt), onPressed: () => context.pop()),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(ArivoSpace.s6), children: [
              const SizedBox(height: ArivoSpace.s6),
              Icon(Icons.auto_awesome_rounded, size: 56, color: p.volt),
              const SizedBox(height: ArivoSpace.s4),
              Text('Generate My Trip', textAlign: TextAlign.center, style: t.displayM),
              const SizedBox(height: ArivoSpace.s8),
              for (var i = 0; i < _labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: ArivoSpace.s4),
                  child: Row(children: [
                    AnimatedSwitcher(
                      duration: ArivoMotion.base,
                      child: i < _step || _progress >= 1
                          ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), color: const Color(0xFF10B981), size: 22)
                          : i == _step && _busy
                              ? SizedBox(key: const ValueKey('busy'), width: 22, height: 22, child: Padding(padding: const EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)))
                              : Icon(Icons.radio_button_unchecked_rounded, key: const ValueKey('todo'), color: p.line, size: 22),
                    ),
                    const SizedBox(width: ArivoSpace.s3),
                    Expanded(child: Text(_labels[i], style: t.bodyM.copyWith(color: i <= _step ? p.text : p.muted))),
                  ]),
                ),
              const SizedBox(height: ArivoSpace.s6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _progress),
                  duration: ArivoMotion.slow,
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8),
                ),
              ),
              const SizedBox(height: ArivoSpace.s2),
              Row(children: [
                Expanded(child: Text(_busy ? 'Crafting your perfect trip…' : (_error != null ? 'Something needs your attention' : ''), style: t.caption)),
                Text('${(_progress * 100).round()}%', style: t.monoS.copyWith(color: p.muted)),
              ]),
              if (_question != null) ...[
                const SizedBox(height: ArivoSpace.s6),
                Text(_question!, style: t.titleM),
                const SizedBox(height: ArivoSpace.s3),
                TextField(controller: _answer, autofocus: true, decoration: const InputDecoration(hintText: 'Your answer'), onSubmitted: (_) => _run(extra: _answer.text.trim())),
                const SizedBox(height: ArivoSpace.s3),
                ArivoButton('Continue', expand: true, onPressed: () => _run(extra: _answer.text.trim())),
              ],
              if (_error != null) ...[
                const SizedBox(height: ArivoSpace.s6),
                Container(
                  padding: const EdgeInsets.all(ArivoSpace.s4),
                  decoration: BoxDecoration(color: p.emberText.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(ArivoRadius.m)),
                  child: Text(_error!, style: t.bodyM.copyWith(color: p.emberText)),
                ),
                const SizedBox(height: ArivoSpace.s4),
                ArivoButton('Try again', expand: true, onPressed: () => _run()),
                const SizedBox(height: ArivoSpace.s2),
                ArivoButton('Change destination', kind: ButtonKind.outline, expand: true, onPressed: () => context.go('/setup/where')),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------------------------------------- Ready

class ReadyScreen extends ConsumerWidget {
  const ReadyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider).value;
    final p = context.palette, t = context.type;
    final city = trip == null ? null : destinationFor(trip.cities.first);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(ArivoSpace.s6), children: [
              const SizedBox(height: ArivoSpace.s6),
              Icon(Icons.celebration_rounded, size: 64, color: p.lanternText),
              const SizedBox(height: ArivoSpace.s4),
              Text('Your Trip is Ready!', textAlign: TextAlign.center, style: t.displayL),
              const SizedBox(height: ArivoSpace.s2),
              Text(
                trip == null
                    ? "We've created a personalized trip for you."
                    : "We've created a personalized ${trip.days.length}-day trip to ${city?.name ?? trip.title} for you.",
                textAlign: TextAlign.center,
                style: t.bodyL.copyWith(color: p.muted),
              ),
              const SizedBox(height: ArivoSpace.s6),
              AspectRatio(aspectRatio: 1.1, child: NetPhoto(trip == null ? Photos.fuji : photoForCities(trip.cities), radius: ArivoRadius.l)),
              const SizedBox(height: ArivoSpace.s6),
              ArivoButton('View Itinerary', expand: true, onPressed: () => context.go('/trips/overview')),
              const SizedBox(height: ArivoSpace.s3),
              ArivoButton('Customize', kind: ButtonKind.outline, expand: true, onPressed: () => context.go('/trips/overview/day')),
            ]),
          ),
        ),
      ),
    );
  }
}

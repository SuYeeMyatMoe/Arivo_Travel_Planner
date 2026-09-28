import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ari/ari.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../common/change_sheet.dart';
import '../../core/data/destinations.dart';
import '../../core/ui/clean.dart';
import '../../state/session.dart';
import '../home/home_screen.dart';
import '../shell/app_shell.dart';

const _dims = {
  'food': 'Food', 'anime': 'Anime', 'photography': 'Photography', 'culture': 'Culture', 'history': 'History', 'nature': 'Nature',
  'shopping': 'Shopping', 'nightlife': 'Nightlife', 'architecture': 'Architecture', 'adventure': 'Adventure', 'relaxation': 'Relaxation',
  'localDiscovery': 'Local finds',
};

/// Profile & Settings: who you are, travel preferences, notifications, currency, bookings, privacy, help, log out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final p = context.palette, t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text('Profile & Settings', style: t.titleL)),
      body: PageWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, 120), children: [
          Row(children: [
            Avatar(name: s.name, size: 60),
            const SizedBox(width: ArivoSpace.s4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((s.name ?? '').isEmpty ? 'Traveller' : s.name!, style: t.titleL),
                Text(s.email ?? '', style: t.bodyM.copyWith(color: p.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: ArivoSpace.s5),
          const Divider(),
          SettingsRow(icon: Icons.person_outline_rounded, title: 'Edit Profile', onTap: () => _editName(context, ref, s.name)),
          SettingsRow(icon: Icons.tune_rounded, title: 'Travel Preferences', onTap: () => context.push('/profile/preferences')),
          SettingsRow(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            trailing: Switch(value: s.notifications, onChanged: (v) => ref.read(sessionProvider.notifier).setNotifications(v)),
          ),
          SettingsRow(icon: Icons.payments_outlined, title: 'Currency', value: s.currency, onTap: () => _pickCurrency(context, ref, s.currency)),
          const SettingsRow(icon: Icons.language_rounded, title: 'Language', value: 'English'),
          const Divider(),
          SettingsRow(icon: Icons.confirmation_number_outlined, title: 'My Bookings', onTap: () => context.push('/bookings')),
          SettingsRow(icon: Icons.luggage_outlined, title: 'My Trips', onTap: () => context.go('/trips')),
          SettingsRow(
            icon: Icons.add_road_rounded,
            title: 'Plan a new trip',
            onTap: () {
              ref.read(setupDraftProvider.notifier).reset();
              context.push(s.interests.isEmpty ? '/setup/interests' : '/setup/where');
            },
          ),
          const Divider(),
          SettingsRow(icon: Icons.privacy_tip_outlined, title: 'Privacy', onTap: () => context.push('/profile/privacy')),
          SettingsRow(icon: Icons.help_outline_rounded, title: 'Help & About', onTap: () => context.push('/profile/about')),
          const Divider(),
          SettingsRow(
            icon: Icons.logout_rounded,
            title: 'Log Out',
            danger: true,
            onTap: () {
              ref.read(sessionProvider.notifier).signOut();
              context.go('/signin');
            },
          ),
        ]),
      ),
    );
  }
}

Future<void> _editName(BuildContext context, WidgetRef ref, String? current) async {
  final c = TextEditingController(text: current ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit Profile'),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Your name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) ref.read(sessionProvider.notifier).setName(name);
}

Future<void> _pickCurrency(BuildContext context, WidgetRef ref, String current) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (code, name) in const [('USD', 'US Dollar'), ('MYR', 'Malaysian Ringgit'), ('SGD', 'Singapore Dollar'), ('EUR', 'Euro'), ('JPY', 'Japanese Yen')])
          ListTile(
            title: Text('$code · $name'),
            trailing: code == current ? Icon(Icons.check_rounded, color: ctx.palette.volt) : null,
            onTap: () => Navigator.pop(ctx, code),
          ),
      ]),
    ),
  );
  if (picked != null) ref.read(sessionProvider.notifier).setCurrency(picked);
}

/// Scaffold for a simple pushed settings page.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title, style: context.type.titleM.copyWith(fontWeight: FontWeight.w700))),
        body: PageWidth(child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, ArivoSpace.s8), children: children)),
      );
}

class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final trip = ref.watch(tripProvider).value;
    final t = context.type;
    final sign = s.currency == 'USD' ? r'$' : '${s.currency} ';
    return _Page(title: 'Travel Preferences', children: [
      Text('Interests', style: t.titleM),
      const SizedBox(height: ArivoSpace.s2),
      Wrap(spacing: ArivoSpace.s2, runSpacing: ArivoSpace.s2, children: [
        for (final i in interests)
          FilterChip(
            label: Text(i.label),
            selected: s.interests.contains(i.key),
            onSelected: (on) => ref.read(sessionProvider.notifier).setInterests(on ? [...s.interests, i.key] : s.interests.where((x) => x != i.key).toList()),
          ),
      ]),
      const SizedBox(height: ArivoSpace.s5),
      Text('Budget per day', style: t.titleM),
      const SizedBox(height: ArivoSpace.s2),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: 'budget', label: Text('Budget')), ButtonSegment(value: 'mid', label: Text('Mid-range')), ButtonSegment(value: 'luxury', label: Text('Luxury'))],
        selected: {s.budgetTier},
        onSelectionChanged: (v) => ref.read(sessionProvider.notifier).setBudget(v.first, switch (v.first) { 'budget' => 80, 'luxury' => 500, _ => 200 }),
      ),
      const SizedBox(height: ArivoSpace.s1),
      Text('About $sign${s.dailyBudget.round()} per person per day. Used for new trips.', style: t.caption),
      const SizedBox(height: ArivoSpace.s6),
      if (trip != null) ...[
        Text('Taste DNA for this trip', style: t.titleM),
        const SizedBox(height: ArivoSpace.s2),
        TasteDnaSection(trip: trip),
      ],
    ]);
  }
}

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});
  @override
  Widget build(BuildContext context) => const _Page(title: 'My Bookings', children: [BookingsSection()]);
}

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Page(title: 'Privacy', children: [PrivacySection(trip: ref.watch(tripProvider).value)]);
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => const _Page(title: 'Help & About', children: [AboutSection()]);
}

// ------------------------------------------------------------------------------------------------------------ Budget

class BudgetPanel extends ConsumerWidget {
  const BudgetPanel({super.key, required this.trip, this.showGauge = true});
  final Trip trip;
  final bool showGauge;

  Future<void> _applySuggestion(BuildContext context, WidgetRef ref, Json s) async {
    try {
      final j = await ref.read(apiProvider).post('/v1/trips/${trip.id}/rescue', body: {'trigger': 'budget', 'day_index': s['day_index']}) as Map;
      if (j['status'] != 'proposed' || !context.mounted) return;
      final applied = await showChangeSheet(context, ref, TripChange.fromJson(Map<String, dynamic>.from(j['change'] as Map)), title: 'Save money');
      if (applied) ref.invalidate(budgetProvider);
    } on ApiError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette, t = context.type;
    return ref.watch(budgetProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(ArivoSpace.s5), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => StateMessage(title: 'Budget unavailable', body: '$e', icon: Icons.cloud_off_outlined),
          data: (b) {
            if (b == null) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showGauge) ...[BudgetGauge(view: b), const SizedBox(height: ArivoSpace.s4)],
              for (final l in b.lines.where((l) => (l['planned'] as num) > 0 || (l['spent'] as num) > 0 || (l['reserved'] as num) > 0))
                Semantics(
                  label: '${titleCase(l['category'] as String)}: ${moneyOf((l['spent'] as num).toDouble() + (l['reserved'] as num).toDouble(), b.currency)} '
                      'used of ${moneyOf((l['planned'] as num).toDouble(), b.currency)} planned, forecast ${moneyOf((l['forecast'] as num).toDouble(), b.currency)}',
                  excludeSemantics: true,
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(titleCase(l['category'] as String), style: t.label)),
                      Text('${moneyOf((l['spent'] as num).toDouble() + (l['reserved'] as num).toDouble(), b.currency)} / ${moneyOf((l['planned'] as num).toDouble(), b.currency)}', style: t.monoS),
                      ProvenanceTag(provenanceOf(l['provenance'] as String?)),
                    ]),
                    const SizedBox(height: 4),
                    ShareBar(
                      value: (l['planned'] as num) <= 0 ? 1 : ((l['spent'] as num) + (l['reserved'] as num)) / (l['planned'] as num),
                      color: (l['forecast'] as num) > (l['planned'] as num) * 1.05 ? p.ember : p.signal,
                    ),
                  ]),
                ),
                ),
              if (b.fx != null)
                Text('1 ${b.fx!['base']} = ${b.fx!['rate']} ${b.fx!['quote']} · ${b.fx!['source']} ${b.fx!['as_of']}', style: t.caption),
              for (final s in b.suggestions)
                Card(
                  margin: const EdgeInsets.only(top: ArivoSpace.s3),
                  child: ListTile(
                    leading: Icon(Icons.savings_outlined, color: p.lanternText),
                    title: Text(s['text'] as String, style: t.bodyM),
                    trailing: TextButton(onPressed: () => _applySuggestion(context, ref, s), child: const Text('Review')),
                  ),
                ),
              const SizedBox(height: ArivoSpace.s3),
              Row(children: [
                Expanded(child: ArivoButton('Add expense', kind: ButtonKind.tonal, icon: Icons.add, onPressed: () => addExpense(context, ref, trip))),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(child: ArivoButton('Scan receipt', kind: ButtonKind.tonal, icon: Icons.receipt_long_outlined, onPressed: () => context.push('/lens/receipt'))),
              ]),
            ]);
          },
        );
  }
}

Future<void> addExpense(BuildContext context, WidgetRef ref, Trip trip) async {
  final amount = TextEditingController();
  final merchant = TextEditingController();
  var category = 'food';
  var currency = trip.currency;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add expense', style: ctx.type.displayM),
          const SizedBox(height: ArivoSpace.s4),
          Row(children: [
            Expanded(
              child: TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
            ),
            const SizedBox(width: ArivoSpace.s3),
            DropdownButton<String>(
              value: currency,
              items: {trip.currency, trip.homeCurrency}.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => currency = v!),
            ),
          ]),
          const SizedBox(height: ArivoSpace.s3),
          TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Where (optional)')),
          const SizedBox(height: ArivoSpace.s3),
          Wrap(spacing: ArivoSpace.s2, children: [
            for (final c in const ['food', 'transport', 'activities', 'shopping', 'other'])
              ChoiceChip(label: Text(titleCase(c)), selected: category == c, onSelected: (_) => setState(() => category = c)),
          ]),
          const SizedBox(height: ArivoSpace.s4),
          ArivoButton('Save', expand: true, onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    ),
  );
  final value = double.tryParse(amount.text);
  if (ok != true || value == null || value <= 0) return;
  try {
    await ref.read(apiProvider).post('/v1/trips/${trip.id}/expenses', body: {
      'amount': value, 'currency': currency, 'category': category,
      if (merchant.text.trim().isNotEmpty) 'merchant': merchant.text.trim(), 'source': 'manual',
    });
    ref.invalidate(budgetProvider);
  } on ApiError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ---------------------------------------------------------------------------------------------------------- Bookings

class BookingsSection extends ConsumerWidget {
  const BookingsSection({super.key});

  Future<void> _cancel(BuildContext context, WidgetRef ref, BookingTxn txn) async {
    final api = ref.read(apiProvider);
    try {
      final q = Map<String, dynamic>.from(await api.post('/v1/bookings/${txn.id}/cancel-quote') as Map);
      if (!context.mounted) return;
      final refund = Money.fromJson(Map<String, dynamic>.from(q['refund'] as Map));
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this booking?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(txn.offer.title.isEmpty ? '${txn.offer.origin} → ${txn.offer.destination}' : txn.offer.title, style: ctx.type.label),
            const SizedBox(height: ArivoSpace.s3),
            Row(children: [Text('You get back ', style: ctx.type.bodyM), Text(money(refund), style: ctx.type.monoM), const ProvenanceTag(Provenance.live)]),
            const SizedBox(height: ArivoSpace.s2),
            Text(q['policy'] as String? ?? '', style: ctx.type.caption),
            if ((q['note'] as String?)?.isNotEmpty == true) Text(q['note'] as String, style: ctx.type.caption),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Cancel for ${money(refund)} refund')),
          ],
        ),
      );
      if (yes != true) return;
      await api.post('/v1/bookings/${txn.id}/cancel', body: {'accepted_refund_minor': refund.amountMinor});
      ref.invalidate(bookingsProvider);
      ref.invalidate(budgetProvider);
      ref.read(tripProvider.notifier).refresh();
    } on ApiError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    return ref.watch(bookingsProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(ArivoSpace.s5), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => StateMessage(title: 'Bookings unavailable', body: '$e', icon: Icons.cloud_off_outlined),
          data: (list) {
            final shown = list.where((b) => b.state != 'DRAFT' && b.state != 'SELECTED' && b.state != 'PRICE_CONFIRMED' && b.state != 'PRICE_CHANGED').toList();
            if (shown.isEmpty) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Nothing booked yet. Bookings you confirm become fixed points in your plan.', style: t.bodyM),
                const SizedBox(height: ArivoSpace.s3),
                Wrap(spacing: ArivoSpace.s2, children: [
                  ArivoButton('Flights', kind: ButtonKind.tonal, icon: Icons.flight_outlined, onPressed: () => context.push('/book/flight')),
                  ArivoButton('Stays', kind: ButtonKind.tonal, icon: Icons.hotel_outlined, onPressed: () => context.push('/book/stay')),
                  ArivoButton('Bus & train', kind: ButtonKind.tonal, icon: Icons.train_outlined, onPressed: () => context.push('/book/ground')),
                ]),
              ]);
            }
            return Column(children: [
              for (final b in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    BoardingPassCard(offer: b.offer, state: b.state, reference: b.bookingReference,
                        note: b.needsReconciliation ? 'We are double-checking this with the supplier.' : b.failureReason),
                    if (b.confirmed && b.offer.refundable)
                      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _cancel(context, ref, b), child: const Text('Cancel booking…'))),
                    if (b.confirmed && !b.offer.refundable)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('Non-refundable: ${b.offer.cancellationPolicy}', style: t.caption)),
                  ]),
                ),
            ]);
          },
        );
  }
}

// ---------------------------------------------------------------------------------------------------------- Taste DNA

class TasteDnaSection extends ConsumerStatefulWidget {
  const TasteDnaSection({super.key, required this.trip});
  final Trip trip;
  @override
  ConsumerState<TasteDnaSection> createState() => _TasteDnaSectionState();
}

class _TasteDnaSectionState extends ConsumerState<TasteDnaSection> {
  late Map<String, String> _votes = _fromTrip();
  bool _busy = false, _dirty = false;

  Map<String, String> _fromTrip() {
    final me = (widget.trip.raw['crew'] as List? ?? const []).cast<Map>().where((m) => m['user_id'] == ArivoConfig.devUser).firstOrNull;
    final dna = Map<String, dynamic>.from((me?['dna'] as Map?) ?? const {});
    return {
      for (final k in _dims.keys)
        k: switch ((dna[k] as num?)?.toDouble() ?? 0.5) { >= 0.8 => 'love', <= 0.25 => 'skip', _ => 'maybe' },
    };
  }

  @override
  void didUpdateWidget(TasteDnaSection old) {
    super.didUpdateWidget(old);
    if (!_dirty && old.trip.version != widget.trip.version) _votes = _fromTrip();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/v1/trips/${widget.trip.id}/crew/prefs', body: {'votes': _votes});
      _dirty = false;
      await ref.read(tripProvider.notifier).refresh();
      ref.read(ariProvider.notifier).say('Got it. New picks will lean your way.', as: AriState.excited);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Tell Ari what you love. This changes future suggestions for you and your crew — never your bookings.', style: t.bodyM),
      const SizedBox(height: ArivoSpace.s3),
      for (final e in _dims.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
          child: Row(children: [
            Expanded(child: Text(e.value, style: t.label)),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'love', label: Text('Love')),
                ButtonSegment(value: 'maybe', label: Text('Maybe')),
                ButtonSegment(value: 'skip', label: Text('Skip')),
              ],
              selected: {_votes[e.key]!},
              onSelectionChanged: (s) => setState(() {
                _votes = {..._votes, e.key: s.first};
                _dirty = true;
              }),
            ),
          ]),
        ),
      const SizedBox(height: ArivoSpace.s2),
      ArivoButton('Save my taste', kind: _dirty ? ButtonKind.primary : ButtonKind.tonal, busy: _busy, onPressed: _dirty ? _save : null),
    ]);
  }
}

// ------------------------------------------------------------------------------------------------------------ Privacy

class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key, required this.trip});
  final Trip? trip;
  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  bool? _private;

  Future<void> _setPrivate(bool v) async {
    setState(() => _private = v);
    try {
      await ref.read(apiProvider).post('/v1/trips/${widget.trip!.id}/crew/prefs', body: {'private': v});
    } on ApiError catch (e) {
      setState(() => _private = !v);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    final me = (widget.trip?.raw['crew'] as List? ?? const []).cast<Map>().where((m) => m['user_id'] == ArivoConfig.devUser).firstOrNull;
    final private = _private ?? (me?['private_prefs'] as bool? ?? false);
    Widget row(IconData i, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 20, color: p.signalText),
            const SizedBox(width: ArivoSpace.s3),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.label), Text(body, style: t.caption)])),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(Icons.shield_outlined, 'Ari never pays', 'Ari can search, compare and prepare a checkout. Only you can press Confirm & pay.'),
      row(Icons.masks_outlined, 'Personal details are masked', 'Names, passport numbers, booking references and phone numbers are replaced with placeholders before any AI sees them.'),
      row(Icons.location_off_outlined, 'Location, mic and camera are opt-in', 'Asked only when you use Live, voice or Receipt Lens. Receipt photos are read on your phone; only the text is sent.'),
      row(Icons.credit_card_off_outlined, 'No card numbers stored', 'Payments go through the payment provider. Arivo keeps only its reference.'),
      if (widget.trip != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Keep my tastes private from my crew', style: t.label),
          subtitle: Text('Crew still gets fair plans; they just don\'t see your top interests.', style: t.caption),
          value: private,
          onChanged: _setPrivate,
        ),
      const SizedBox(height: ArivoSpace.s2),
      ArivoButton('Start a new trip', kind: ButtonKind.tonal, icon: Icons.add_road, onPressed: () async {
        await ref.read(currentTripIdProvider.notifier).set(null);
        if (context.mounted) context.go('/start');
      }),
    ]);
  }
}

// -------------------------------------------------------------------------------------------------------------- About

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    Widget link(String label, String url) => InkWell(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(label, style: t.bodyM.copyWith(decoration: TextDecoration.underline)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Arivo 0.1 · Your trip isn\'t generated once. It travels with you.', style: t.bodyM),
      const SizedBox(height: ArivoSpace.s3),
      Text('Credits', style: t.label),
      link('Ari is based on "Miibot" by itsmejhade (CC BY 4.0), modified with travel gear', 'https://creativecommons.org/licenses/by/4.0/'),
      link('Places © OpenStreetMap contributors (ODbL)', 'https://www.openstreetmap.org/copyright'),
      link('Place facts from Wikidata (CC0) · photos from Wikimedia Commons (see each photo)', 'https://www.wikidata.org'),
      link('Map tiles by OpenFreeMap · OpenMapTiles', 'https://openfreemap.org'),
      link('Weather by Open-Meteo (CC BY 4.0)', 'https://open-meteo.com'),
      link('Exchange rates by Frankfurter (ECB reference rates)', 'https://frankfurter.dev'),
      link('Pulse signals: Wikipedia pageviews and GDELT', 'https://www.gdeltproject.org'),
      showLicensesButton(context),
    ]);
  }

  Widget showLicensesButton(BuildContext context) => TextButton(
        onPressed: () => showLicensePage(context: context, applicationName: 'Arivo', applicationVersion: '0.1.0'),
        child: const Text('Open-source licences'),
      );
}

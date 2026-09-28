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
import '../shell/app_shell.dart';

const _dims = {
  'food': 'Food', 'anime': 'Anime', 'photography': 'Photography', 'culture': 'Culture', 'history': 'History', 'nature': 'Nature',
  'shopping': 'Shopping', 'nightlife': 'Nightlife', 'architecture': 'Architecture', 'adventure': 'Adventure', 'relaxation': 'Relaxation',
  'localDiscovery': 'Local finds',
};

/// YOU: Taste DNA, Budget Brain, My Bookings, privacy and attributions.
class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider).value;
    final t = context.type;
    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s4, ArivoSpace.s4, 120), children: [
            Text('You', style: t.displayL),
            if (trip != null) Text(trip.title, style: t.caption),
            const SizedBox(height: ArivoSpace.s5),
            if (trip == null)
              StateMessage(title: 'No trip yet', body: 'Plan one and your budget, bookings and Taste DNA live here.', action: 'Plan a trip', onAction: () => context.go('/start'))
            else ...[
              _Section(title: 'Budget Brain', child: _BudgetPanel(trip: trip)),
              _Section(title: 'My bookings', child: const _Bookings()),
              _Section(title: 'Taste DNA', child: _TasteDna(trip: trip)),
            ],
            _Section(title: 'Privacy', child: _Privacy(trip: trip)),
            _Section(title: 'About', child: const _About()),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: ArivoSpace.s6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: context.type.titleL),
          const SizedBox(height: ArivoSpace.s3),
          child,
        ]),
      );
}

// ------------------------------------------------------------------------------------------------------------ Budget

class _BudgetPanel extends ConsumerWidget {
  const _BudgetPanel({required this.trip});
  final Trip trip;

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
              BudgetGauge(view: b),
              const SizedBox(height: ArivoSpace.s4),
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
                Expanded(child: ArivoButton('Add expense', kind: ButtonKind.tonal, icon: Icons.add, onPressed: () => _addExpense(context, ref, trip))),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(child: ArivoButton('Scan receipt', kind: ButtonKind.tonal, icon: Icons.receipt_long_outlined, onPressed: () => context.push('/lens/receipt'))),
              ]),
            ]);
          },
        );
  }
}

Future<void> _addExpense(BuildContext context, WidgetRef ref, Trip trip) async {
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

class _Bookings extends ConsumerWidget {
  const _Bookings();

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

class _TasteDna extends ConsumerStatefulWidget {
  const _TasteDna({required this.trip});
  final Trip trip;
  @override
  ConsumerState<_TasteDna> createState() => _TasteDnaState();
}

class _TasteDnaState extends ConsumerState<_TasteDna> {
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
  void didUpdateWidget(_TasteDna old) {
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

class _Privacy extends ConsumerStatefulWidget {
  const _Privacy({required this.trip});
  final Trip? trip;
  @override
  ConsumerState<_Privacy> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<_Privacy> {
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

class _About extends StatelessWidget {
  const _About();
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

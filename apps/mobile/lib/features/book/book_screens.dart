import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ari/ari.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/commerce_widgets.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';

/// Search → compare → select. The AI can explain options; only supplier inventory is ever bookable.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, required this.kind});
  final String kind; // flight | stay | ground
  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  List<TravelOffer>? _offers;
  List<String> _insights = const [];
  String? _error;
  bool _loading = false;
  String? _starting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final trip = await ref.read(tripProvider.future);
    if (trip == null) {
      setState(() => _error = 'Plan a trip first — searches use its dates, crew and route.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiProvider);
    final date = trip.startDate.toIso8601String().substring(0, 10);
    try {
      Map res;
      switch (widget.kind) {
        case 'flight':
          // Fly the evening before so day 1 isn't lost; landings after 10:00 on day 1 can't be "best fit".
          final dayBefore = trip.startDate.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
          res = await api.post('/v1/bookings/search/flights', body: {
            'origin': 'KUL', 'destination': trip.cities.first, 'depart': dayBefore, 'adults': trip.crewSize, 'arrive_by': '${date}T10:00:00',
          }) as Map;
          _insights = [if (res['insight'] != null) res['insight'] as String];
        case 'stay':
          res = await api.post('/v1/trips/${trip.id}/bookings/search/stays', body: {
            'check_in': date,
            'nights': (trip.days.length - 1).clamp(1, 30),
            'guests': trip.crewSize,
            'rooms': (trip.crewSize / 2).ceil(),
          }) as Map;
        default:
          final from = trip.cities.first, to = from == 'tokyo' ? 'kyoto' : from == 'kyoto' ? 'tokyo' : 'melaka';
          final depart = trip.days.length > 2 ? trip.days[trip.days.length - 2].date : trip.startDate;
          res = await api.post('/v1/bookings/search/ground', body: {'origin': from, 'destination': to, 'depart': depart.toIso8601String().substring(0, 10), 'passengers': trip.crewSize}) as Map;
          _insights = List<String>.from(res['insights'] as List? ?? const []);
      }
      setState(() => _offers = (res['offers'] as List).map((e) => TravelOffer.fromJson(Map<String, dynamic>.from(e as Map))).toList());
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(TravelOffer o) async {
    final trip = await ref.read(tripProvider.future);
    if (trip == null) return;
    setState(() => _starting = o.offerId);
    try {
      final travellers = o.type == 'stay' ? 1 : trip.crewSize;
      final j = await ref.read(apiProvider).post('/v1/trips/${trip.id}/bookings',
          body: {'offer_id': o.offerId, 'travellers': travellers}, idempotencyKey: ArivoApi.newIdempotencyKey());
      final txn = BookingTxn.fromJson(Map<String, dynamic>.from(j as Map));
      if (mounted) context.push('/checkout/${txn.id}');
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final title = switch (widget.kind) { 'flight' => 'Flights', 'stay' => 'Hotels', _ => 'Train · Bus' };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PageWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, 0, ArivoSpace.s4, ArivoSpace.s8), children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'flight', label: Text('Flights')),
              ButtonSegment(value: 'stay', label: Text('Hotels')),
              ButtonSegment(value: 'ground', label: Text('Bus & train')),
            ],
            selected: {widget.kind},
            onSelectionChanged: (s) => context.pushReplacement('/book/${s.first}'),
          ),
          const SizedBox(height: ArivoSpace.s3),
          if (_offers?.any((o) => o.sandbox) ?? false)
            Container(
              padding: const EdgeInsets.all(ArivoSpace.s3),
              decoration: BoxDecoration(border: Border.all(color: p.lanternText), borderRadius: BorderRadius.circular(ArivoRadius.s)),
              child: Row(children: [
                const StatusChip(ChipTone.sandbox),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(child: Text('Sandbox inventory: real places, test prices. No real booking or payment happens.', style: t.caption)),
              ]),
            ),
          for (final s in _insights)
            Padding(
              padding: const EdgeInsets.only(top: ArivoSpace.s3),
              child: Row(children: [
                AriSprite(state: AriState.talking, size: 44),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(child: Text(s, style: t.bodyM)),
                const ProvenanceTag(Provenance.est),
              ]),
            ),
          const SizedBox(height: ArivoSpace.s3),
          if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (_error != null) StateMessage(title: 'Search unavailable', body: _error, action: 'Try again', onAction: _search, icon: Icons.cloud_off),
          for (final o in _offers ?? const <TravelOffer>[])
            Padding(
              padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                BoardingPassCard(offer: o, onTap: _starting == null ? () => _select(o) : null),
                if (o.type == 'stay' && o.locationFit != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, 0),
                    child: LocationFitMeter(score: o.locationFit!, sentence: o.meta['fit_sentence'] as String?),
                  ),
                if (o.meta['door_to_door_min'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s2, ArivoSpace.s4, 0),
                    child: Text('Door-to-door ${duration((o.meta['door_to_door_min'] as num).toInt())} · from ${o.meta['departure_station']}', style: t.caption),
                  ),
                if (_starting == o.offerId) const LinearProgressIndicator(),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Traveller · Details · Payment · Review → "Confirm & pay (amount)". Revalidated price only; changes need reconfirmation.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.txnId});
  final String txnId;
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  BookingTxn? _txn;
  int _step = 0;
  final List<(TextEditingController, TextEditingController)> _names = [];
  final _email = TextEditingController();
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final j = await ref.read(apiProvider).post('/v1/bookings/${widget.txnId}/revalidate');
    final txn = BookingTxn.fromJson(Map<String, dynamic>.from(j as Map));
    setState(() {
      _txn = txn;
      while (_names.length < txn.travellersCount) {
        _names.add((TextEditingController(), TextEditingController()));
      }
    });
  }

  Future<void> _pay() async {
    final txn = _txn!;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final j = await ref.read(apiProvider).post('/v1/bookings/${txn.id}/confirm', body: {
        'accepted_total_minor': txn.offer.price.amountMinor,
        'travellers': [
          for (final (g, f) in _names) {'given_name': g.text.trim(), 'family_name': f.text.trim(), if (_email.text.trim().isNotEmpty) 'email': _email.text.trim()}
        ],
      });
      final done = BookingTxn.fromJson(Map<String, dynamic>.from(j as Map));
      if (done.confirmed) {
        ref.invalidate(tripProvider);
        ref.invalidate(bookingsProvider);
        ref.read(ariProvider.notifier).say('Booked! I added it to your trip as a fixed point.', as: AriState.excited);
        if (mounted) context.pushReplacement('/booked/${done.id}');
      } else if (done.state == 'SUPPLIER_PENDING') {
        setState(() => _error = 'Confirming with the supplier. We never re-book automatically — check My Bookings shortly.');
      } else {
        setState(() => _error = done.failureReason ?? 'Booking failed. Nothing was charged.');
      }
    } on ApiError catch (e) {
      if (e.code == 'price_changed') {
        await _load();
        setState(() => _step = 3);
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  bool get _namesOk => _names.every((n) => n.$1.text.trim().isNotEmpty && n.$2.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    final txn = _txn;
    if (txn == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final changedFrom = txn.priceChanged ? txn.oldPriceNote?.replaceFirst('price ', '') : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: PageWidth(
        child: Stepper(
          currentStep: _step,
          onStepTapped: (i) => setState(() => _step = i),
          controlsBuilder: (context, d) => Padding(
            padding: const EdgeInsets.only(top: ArivoSpace.s4),
            child: _step < 3
                ? Align(alignment: Alignment.centerLeft, child: ArivoButton('Next', kind: ButtonKind.tonal, onPressed: _step == 0 && !_namesOk ? null : d.onStepContinue))
                : const SizedBox.shrink(),
          ),
          onStepContinue: () => setState(() => _step = (_step + 1).clamp(0, 3)),
          steps: [
            Step(
              title: Text('Traveller${txn.travellersCount > 1 ? 's' : ''}', style: t.label),
              isActive: _step >= 0,
              content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < _names.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
                    child: LayoutBuilder(builder: (context, box) {
                      final given = TextField(
                        controller: _names[i].$1,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: i == 0 ? const [AutofillHints.givenName] : null,
                        decoration: InputDecoration(labelText: 'Given name', hintText: 'as on passport'),
                        onChanged: (_) => setState(() {}),
                      );
                      final family = TextField(
                        controller: _names[i].$2,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: i == 0 ? const [AutofillHints.familyName] : null,
                        decoration: const InputDecoration(labelText: 'Family name'),
                        onChanged: (_) => setState(() {}),
                      );
                      // Side by side only when both fields can show their labels; stacked on narrow phones.
                      final fields = box.maxWidth >= 360
                          ? Row(children: [Expanded(child: given), const SizedBox(width: ArivoSpace.s2), Expanded(child: family)])
                          : Column(children: [given, const SizedBox(height: ArivoSpace.s2), family]);
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_names.length > 1) Padding(padding: const EdgeInsets.only(bottom: ArivoSpace.s1), child: Text('Traveller ${i + 1}', style: t.label)),
                        fields,
                      ]);
                    }),
                  ),
                Text('Names as on passport. Stored only in the protected booking vault — never shared with AI.', style: t.caption),
              ]),
            ),
            Step(
              title: Text('Details', style: t.label),
              isActive: _step >= 1,
              content: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Email for the confirmation (optional)')),
            ),
            Step(
              title: Text('Payment', style: t.label),
              isActive: _step >= 2,
              content: Row(children: [
                Icon(Icons.lock_outline, color: p.muted),
                const SizedBox(width: ArivoSpace.s2),
                Expanded(
                  child: Text(txn.offer.sandbox
                      ? 'Sandbox payment: a test authorisation is held, then captured only if the supplier confirms. No real money moves.'
                      : 'Card details go straight to the payment provider. Arivo never sees or stores them.', style: t.bodyM),
                ),
              ]),
            ),
            Step(
              title: Text('Review', style: t.label),
              isActive: _step >= 3,
              content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                BoardingPassCard(offer: txn.offer),
                const SizedBox(height: ArivoSpace.s4),
                PriceBreakdown(offer: txn.offer, changedFrom: changedFrom),
                const SizedBox(height: ArivoSpace.s2),
                Text('${txn.travellersCount} traveller${txn.travellersCount > 1 ? 's' : ''}: ${_names.map((n) => '${n.$1.text} ${n.$2.text}'.trim()).join(', ')}', style: t.caption),
                const SizedBox(height: ArivoSpace.s4),
                ArivoButton('Confirm & pay ${money(txn.offer.price)}', expand: true, busy: _paying, onPressed: _namesOk ? _pay : null),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s3), child: Text(_error!, style: t.bodyM.copyWith(color: p.emberText))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingSuccessScreen extends ConsumerWidget {
  const BookingSuccessScreen({super.key, required this.txnId});
  final String txnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(apiProvider).get('/v1/bookings/$txnId'),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final txn = BookingTxn.fromJson(Map<String, dynamic>.from(snap.data as Map));
        final o = txn.offer;
        final t = context.type;
        return Scaffold(
          body: SafeArea(
            child: PageWidth(
              child: ListView(padding: const EdgeInsets.all(ArivoSpace.s5), children: [
                const Ari3D(state: AriState.excited, height: 200),
                Text('Booked', style: t.displayL),
                const SizedBox(height: ArivoSpace.s2),
                Text(o.type == 'stay' ? o.title : '${o.origin} → ${o.destination}', style: t.monoL),
                if (o.departure != null) Text('${dayLabel(o.departure!)} · ${hhmm(o.departure!)}', style: t.bodyL),
                const SizedBox(height: ArivoSpace.s4),
                BoardingPassCard(offer: o, state: txn.state, reference: txn.bookingReference),
                const SizedBox(height: ArivoSpace.s3),
                Text('Added to your trip as a fixed point — nothing will be scheduled before you can get there.', style: t.bodyM),
                const SizedBox(height: ArivoSpace.s5),
                ArivoButton('See it in my trip', expand: true, onPressed: () => context.go('/trip')),
                const SizedBox(height: ArivoSpace.s2),
                ArivoButton('My bookings', kind: ButtonKind.outline, expand: true, onPressed: () => context.go('/bookings')),
              ]),
            ),
          ),
        );
      },
    );
  }
}

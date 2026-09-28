import 'package:arivo/core/format.dart';
import 'package:arivo/core/models/models.dart';
import 'package:arivo/core/theme/arivo_theme.dart';
import 'package:arivo/core/ui/commerce_widgets.dart';
import 'package:arivo/core/ui/primitives.dart';
import 'package:arivo/core/ui/trip_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _host(Widget child, {bool ink = false}) => MaterialApp(
      theme: ink ? ArivoTheme.ink() : ArivoTheme.paper(),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    );

Json _offer({bool sandbox = true, bool refundable = true}) => {
      'offer_id': 'off_1', 'provider': 'sandbox-air', 'type': 'flight', 'origin': 'KUL', 'destination': 'NRT',
      'departure': '2026-10-12T09:30:00', 'arrival': '2026-10-12T17:35:00', 'duration_min': 425,
      'segments': [
        {'origin': 'KUL', 'destination': 'NRT', 'departure': '2026-10-12T09:30:00', 'arrival': '2026-10-12T17:35:00', 'carrier': 'Sandbox Air', 'number': 'SX 88'},
      ],
      'price': {'amount_minor': 123450, 'currency': 'MYR'},
      'lines': [
        {'label': 'Fare', 'amount': {'amount_minor': 100000, 'currency': 'MYR'}},
        {'label': 'Taxes & fees', 'amount': {'amount_minor': 23450, 'currency': 'MYR'}},
      ],
      'refundable': refundable, 'changeable': false, 'cancellation_policy': 'Refundable minus RM 150 fee', 'change_policy': '',
      'sandbox': sandbox, 'title': 'KUL → NRT', 'subtitle': 'Sandbox Air', 'badges': ['Best fit'],
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('money', () {
    test('keeps cents on payable amounts, even large ones', () {
      expect(moneyOf(1234.5, 'MYR'), 'RM 1,234.50');
      expect(moneyOf(4000, 'MYR'), 'RM 4,000');
    });
    test('zero-decimal currencies never show cents', () {
      expect(money(const Money(4653, 'JPY')), '¥4,653');
    });
    test('negative and signed values', () {
      expect(signedMoney(const Money(-15000, 'MYR')), '−RM 150');
      expect(signedMoney(const Money(2500, 'MYR')), '+RM 25');
    });
  });

  testWidgets('ProvenanceTag shows where a number came from', (tester) async {
    await tester.pumpWidget(_host(const Row(children: [ProvenanceTag(Provenance.live), ProvenanceTag(Provenance.est), ProvenanceTag(Provenance.you)])));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('EST.'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
  });

  testWidgets('BoardingPassCard labels sandbox inventory and shows the exact total', (tester) async {
    await tester.pumpWidget(_host(BoardingPassCard(offer: TravelOffer.fromJson(_offer()))));
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.text('RM 1,234.50'), findsOneWidget);
    expect(find.text('total · refundable'), findsOneWidget);
  });

  testWidgets('BoardingPassCard for a confirmed booking shows its reference instead of a price', (tester) async {
    await tester.pumpWidget(_host(BoardingPassCard(offer: TravelOffer.fromJson(_offer(sandbox: false)), state: 'CONFIRMED', reference: 'ABC123')));
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('SANDBOX'), findsNothing);
  });

  testWidgets('PriceBreakdown warns when the price changed and says nothing was charged', (tester) async {
    await tester.pumpWidget(_host(PriceBreakdown(offer: TravelOffer.fromJson(_offer()), changedFrom: 'price RM 1,180.00 → RM 1,234.50')));
    expect(find.text('Price changed'), findsOneWidget);
    expect(find.textContaining('Nothing has been charged'), findsOneWidget);
    expect(find.text('Fare'), findsOneWidget);
    expect(find.text('RM 1,234.50'), findsOneWidget);
  });

  testWidgets('ChangeDiff groups kept, moved, removed and added, and shows the saving', (tester) async {
    final change = TripChange.fromJson({
      'id': 'chg_1', 'trip_id': 'trp_1', 'day_index': 1, 'trigger': 'rain', 'status': 'proposed', 'explanation': 'Rain from 14:00',
      'kept': [{'item_id': 'a', 'name': 'Flight KUL → NRT'}],
      'moved': [{'item_id': 'b', 'name': 'Ramen lunch', 'from_time': '12:00', 'to_time': '12:30'}],
      'removed': [{'item_id': 'c', 'name': 'Yoyogi Park', 'reason': 'outdoor, rain 80%'}],
      'added': [{'item_id': 'd', 'name': 'teamLab Planets'}],
      'time_delta_min': -30, 'budget_delta': {'amount_minor': -4000, 'currency': 'MYR'},
    });
    await tester.pumpWidget(_host(ChangeDiff(change: change)));
    for (final label in ['KEPT', 'MOVED', 'REMOVED', 'ADDED']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('12:00 → 12:30'), findsOneWidget);
    expect(find.text('−RM 40'), findsOneWidget);
    final removed = tester.widget<Text>(find.text('Yoyogi Park'));
    expect(removed.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('BudgetGauge states over budget in words, not only colour', (tester) async {
    final view = BudgetView.fromJson({
      'currency': 'MYR', 'total': 16000, 'spent': 9000, 'reserved': 6000, 'forecast': 17200, 'remaining': 1000, 'state': 'over',
      'lines': const [], 'suggestions': const [],
    });
    await tester.pumpWidget(_host(BudgetGauge(view: view), ink: true));
    expect(find.text('Over budget'), findsOneWidget);
    expect(find.text('RM 1,000'), findsOneWidget);
  });

  testWidgets('StatusChip always pairs colour with text', (tester) async {
    await tester.pumpWidget(_host(const Wrap(children: [StatusChip(ChipTone.pending), StatusChip(ChipTone.failed), StatusChip(ChipTone.sandbox)])));
    expect(find.text('Confirming'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
  });
}

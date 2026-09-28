import 'package:arivo/app.dart';
import 'package:arivo/core/data/destinations.dart';
import 'package:arivo/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Map<String, String?> local) => ProviderScope(overrides: [initialLocalStateProvider.overrideWithValue(local)], child: const ArivoApp());

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SetupDraft.request', () {
    const session = Session(interests: ['food', 'culture'], budgetTier: 'mid', dailyBudget: 150, currency: 'USD');

    test('composes one sentence and exact quick controls from the wizard', () {
      final draft = SetupDraft(destination: destinationFor('kyoto'), start: DateTime(2026, 11, 3), days: 4, crew: 'friends');
      final r = draft.request(session);
      expect(r.text, 'Kyoto for 4 days with friends. We love food and local culture.');
      expect(r.quick, {
        'start_date': '2026-11-03',
        'days': 4,
        'crew_type': 'friends',
        'crew_size': 3,
        'budget_amount': 600.0, // per person: $150/day × 4 days
        'budget_currency': 'USD',
      });
    });

    test('a free-text description is sent as-is and keeps its own length and budget', () {
      const draft = SetupDraft(customText: '3 days in Tokyo, RM2,000 each', crew: 'couple');
      final r = draft.request(session);
      expect(r.text, '3 days in Tokyo, RM2,000 each');
      expect(r.quick.containsKey('days'), isFalse);
      expect(r.quick.containsKey('budget_amount'), isFalse);
      expect(r.quick['crew_size'], 2);
    });
  });

  testWidgets('a first launch lands on the welcome screen', (tester) async {
    await tester.pumpWidget(_app(const {}));
    await tester.pump();
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('a returning, signed-out traveller lands on Sign In', (tester) async {
    await tester.pumpWidget(_app({SessionNotifier.storageKey: '{"onboardingSeen": true}'}));
    await tester.pump();
    expect(find.text('Welcome back!\nSign in to continue your journey.'), findsOneWidget);
  });

  testWidgets('sign-in validates the form before continuing', (tester) async {
    await tester.pumpWidget(_app({SessionNotifier.storageKey: '{"onboardingSeen": true}'}));
    await tester.pump();
    await tester.tap(find.widgetWithText(Material, 'Sign In').last);
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsOneWidget);
  });
}

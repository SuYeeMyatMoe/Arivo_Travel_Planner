import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/providers.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the current trip, the session and saved places before the first frame, so the first route
  // (signed in or not) and deep links (/book, /live…) never see a false "no trip" or "signed out".
  String? tripId;
  final local = <String, String?>{};
  try {
    final prefs = await SharedPreferences.getInstance();
    tripId = prefs.getString(CurrentTrip.storageKey);
    for (final k in [SessionNotifier.storageKey, SavedPlacesNotifier.storageKey]) {
      local[k] = prefs.getString(k);
    }
  } catch (_) {/* storage unavailable: start fresh */}
  runApp(ProviderScope(
    overrides: [
      initialTripIdProvider.overrideWithValue(tripId),
      initialLocalStateProvider.overrideWithValue(local),
    ],
    child: const ArivoApp(),
  ));
}

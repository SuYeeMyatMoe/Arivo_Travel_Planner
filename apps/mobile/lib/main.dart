import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the current trip before the first frame so deep links (/book, /live…) never see a false "no trip".
  String? tripId;
  try {
    tripId = (await SharedPreferences.getInstance()).getString(CurrentTrip.storageKey);
  } catch (_) {/* storage unavailable: start fresh */}
  runApp(ProviderScope(overrides: [initialTripIdProvider.overrideWithValue(tripId)], child: const ArivoApp()));
}

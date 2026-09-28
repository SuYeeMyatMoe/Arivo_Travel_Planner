import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/models.dart';
import '../core/net/api.dart';

final apiProvider = Provider<ArivoApi>((ref) => ArivoApi());

/// The trip the app is focused on (persisted so a relaunch lands back in the trip).
/// Trip id restored from storage in main() before the first frame.
final initialTripIdProvider = Provider<String?>((ref) => null);

class CurrentTrip extends Notifier<String?> {
  static const storageKey = 'arivo.currentTrip';
  static const _key = storageKey;

  @override
  String? build() => ref.read(initialTripIdProvider);

  Future<void> set(String? id) async {
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      id == null ? await prefs.remove(_key) : await prefs.setString(_key, id);
    } catch (_) {}
  }
}

final currentTripIdProvider = NotifierProvider<CurrentTrip, String?>(CurrentTrip.new);

class TripNotifier extends AsyncNotifier<Trip?> {
  @override
  Future<Trip?> build() async {
    final id = ref.watch(currentTripIdProvider);
    if (id == null) return null;
    try {
      final j = await ref.read(apiProvider).get('/v1/trips/$id');
      return Trip.fromJson(Map<String, dynamic>.from(j as Map));
    } on ApiError catch (e) {
      // Trip deleted, or no longer shared with you: forget it instead of showing an error forever.
      if (e.status == 404 || e.status == 403) {
        Future.microtask(() => ref.read(currentTripIdProvider.notifier).set(null));
        return null;
      }
      rethrow;
    }
  }

  void replace(Json tripJson) => state = AsyncData(Trip.fromJson(tripJson));
  Future<void> refresh() async => ref.invalidateSelf();
}

final tripProvider = AsyncNotifierProvider<TripNotifier, Trip?>(TripNotifier.new);

final budgetProvider = FutureProvider.autoDispose<BudgetView?>((ref) async {
  final trip = await ref.watch(tripProvider.future);
  if (trip == null) return null;
  final j = await ref.read(apiProvider).get('/v1/trips/${trip.id}/budget');
  return BudgetView.fromJson(Map<String, dynamic>.from(j as Map));
});

final bookingsProvider = FutureProvider.autoDispose<List<BookingTxn>>((ref) async {
  final trip = await ref.watch(tripProvider.future);
  if (trip == null) return const [];
  final j = await ref.read(apiProvider).get('/v1/trips/${trip.id}/bookings');
  return (j as List).map((e) => BookingTxn.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Summary row from GET /v1/trips.
class TripSummary {
  TripSummary.fromJson(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        startDate = DateTime.parse(j['start_date'] as String),
        days = (j['days'] as num).toInt(),
        cities = List<String>.from(j['cities'] as List? ?? const []);
  final String id, title;
  final DateTime startDate;
  final int days;
  final List<String> cities;
  DateTime get endDate => startDate.add(Duration(days: days - 1));
}

final tripsListProvider = FutureProvider.autoDispose<List<TripSummary>>((ref) async {
  ref.watch(currentTripIdProvider); // a new trip → refresh the list
  final j = await ref.read(apiProvider).get('/v1/trips');
  final list = (j as List).map((e) => TripSummary.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  list.sort((a, b) => b.startDate.compareTo(a.startDate));
  return list;
});

final placeProvider = FutureProvider.autoDispose.family<Place, String>((ref, id) async {
  final j = await ref.read(apiProvider).get('/v1/places/$id');
  return Place.fromJson(Map<String, dynamic>.from(j as Map));
});

/// City keys with verified place data (GET /v1/cities). Falls back to the seeded three when offline.
final supportedCitiesProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final j = await ref.read(apiProvider).get('/v1/cities');
    return {for (final c in j as List) (c as Map)['key'] as String};
  } catch (_) {
    return const {'tokyo', 'kyoto', 'kuala-lumpur'};
  }
});

/// Which day the Trip tab is showing.
class SelectedDay extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

final selectedDayProvider = NotifierProvider<SelectedDay, int>(SelectedDay.new);

/// Demo clock: planning happens before the trip, so Live/Rescue can simulate "now" on a trip day.
class DemoClock extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void set(DateTime? t) => state = t;
}

final demoClockProvider = NotifierProvider<DemoClock, DateTime?>(DemoClock.new);

DateTime tripNow(Trip trip, DateTime? demo, int dayIndex) {
  if (demo != null) return demo;
  final now = DateTime.now();
  final day = trip.days[dayIndex.clamp(0, trip.days.length - 1)];
  final sameDay = now.year == day.date.year && now.month == day.date.month && now.day == day.date.day;
  return sameDay ? now : DateTime(day.date.year, day.date.month, day.date.day, 12, 30);
}

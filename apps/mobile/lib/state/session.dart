import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/destinations.dart';

// Local, on-device state: the traveller's profile and preferences, the setup wizard draft, saved places and packing.
// Sign-in is UI-only for now (no Supabase yet): the profile lives here and API calls keep using the dev identity.

Future<void> _save(String key, Object value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  } catch (_) {/* storage unavailable (private window): keep working in memory */}
}

Map<String, dynamic>? _decode(String? raw) {
  if (raw == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------------------------------------------------------------ Session

class Session {
  const Session({
    this.onboardingSeen = false,
    this.name,
    this.email,
    this.interests = const [],
    this.budgetTier = 'mid',
    this.dailyBudget = 200,
    this.currency = 'USD',
    this.notifications = true,
  });

  final bool onboardingSeen, notifications;
  final String? name, email;
  final List<String> interests;
  final String budgetTier; // budget | mid | luxury
  final double dailyBudget; // per person per day, in [currency]
  final String currency;

  bool get signedIn => email != null;
  String get firstName => (name ?? '').trim().isEmpty ? 'Traveller' : name!.trim().split(' ').first;

  Session copyWith({
    bool? onboardingSeen,
    String? name,
    String? email,
    bool clearProfile = false,
    List<String>? interests,
    String? budgetTier,
    double? dailyBudget,
    String? currency,
    bool? notifications,
  }) =>
      Session(
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
        name: clearProfile ? null : (name ?? this.name),
        email: clearProfile ? null : (email ?? this.email),
        interests: interests ?? this.interests,
        budgetTier: budgetTier ?? this.budgetTier,
        dailyBudget: dailyBudget ?? this.dailyBudget,
        currency: currency ?? this.currency,
        notifications: notifications ?? this.notifications,
      );

  Map<String, dynamic> toJson() => {
        'onboardingSeen': onboardingSeen,
        'name': name,
        'email': email,
        'interests': interests,
        'budgetTier': budgetTier,
        'dailyBudget': dailyBudget,
        'currency': currency,
        'notifications': notifications,
      };

  factory Session.fromJson(Map<String, dynamic>? j) => j == null
      ? const Session()
      : Session(
          onboardingSeen: j['onboardingSeen'] as bool? ?? false,
          name: j['name'] as String?,
          email: j['email'] as String?,
          interests: List<String>.from(j['interests'] as List? ?? const []),
          budgetTier: j['budgetTier'] as String? ?? 'mid',
          dailyBudget: (j['dailyBudget'] as num?)?.toDouble() ?? 200,
          currency: j['currency'] as String? ?? 'USD',
          notifications: j['notifications'] as bool? ?? true,
        );
}

/// Raw stored values, read in main() before the first frame so the router's first redirect is already right.
final initialLocalStateProvider = Provider<Map<String, String?>>((ref) => const {});

class SessionNotifier extends Notifier<Session> {
  static const storageKey = 'arivo.session';

  @override
  Session build() => Session.fromJson(_decode(ref.read(initialLocalStateProvider)[storageKey]));

  void _set(Session s) {
    state = s;
    _save(storageKey, s.toJson());
  }

  void finishIntro() => _set(state.copyWith(onboardingSeen: true));
  void signIn({required String email, String? name}) => _set(state.copyWith(onboardingSeen: true, email: email, name: name ?? state.name));
  void signOut() => _set(state.copyWith(clearProfile: true));
  void setName(String name) => _set(state.copyWith(name: name));
  void setInterests(List<String> v) => _set(state.copyWith(interests: v));
  void setBudget(String tier, double daily) => _set(state.copyWith(budgetTier: tier, dailyBudget: daily));
  void setCurrency(String c) => _set(state.copyWith(currency: c));
  void setNotifications(bool v) => _set(state.copyWith(notifications: v));
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

// ------------------------------------------------------------------------------------------------------ Setup draft

class SetupDraft {
  const SetupDraft({this.destination, this.customText, this.start, this.days = 5, this.flexible = false, this.crew = 'couple'});
  final Destination? destination;
  final String? customText; // "Describe it yourself" — sent as-is instead of the composed sentence
  final DateTime? start;
  final int days;
  final bool flexible;
  final String crew; // solo | couple | family | friends

  SetupDraft copyWith({Destination? destination, String? customText, bool clearCustom = false, DateTime? start, int? days, bool? flexible, String? crew}) => SetupDraft(
        destination: destination ?? this.destination,
        customText: clearCustom ? null : (customText ?? this.customText),
        start: start ?? this.start,
        days: days ?? this.days,
        flexible: flexible ?? this.flexible,
        crew: crew ?? this.crew,
      );

  int get crewSize => switch (crew) { 'solo' => 1, 'couple' => 2, 'family' => 4, _ => 3 };

  /// One natural sentence for the planner (it also parses interests from it), plus exact quick controls.
  ({String text, Map<String, dynamic> quick}) request(Session s) {
    final picked = interests.where((i) => s.interests.contains(i.key)).map((i) => _phrase[i.key] ?? i.label.toLowerCase()).toList();
    final who = switch (crew) { 'solo' => 'on my own', 'couple' => 'with my partner', 'family' => 'with my family', _ => 'with friends' };
    final likes = picked.isEmpty ? '' : ' We love ${_join(picked)}.';
    final pace = switch (s.budgetTier) { 'budget' => ' Keep it affordable.', 'luxury' => ' We like comfort and nice places.', _ => '' };
    final text = customText?.trim().isNotEmpty == true
        ? customText!.trim()
        : '${destination?.name ?? 'Tokyo'} for $days days $who.$likes$pace';
    return (
      text: text,
      quick: {
        if (start != null) 'start_date': start!.toIso8601String().substring(0, 10),
        if (customText == null) 'days': days,
        'crew_type': crew,
        'crew_size': crewSize,
        if (customText == null) 'budget_amount': (s.dailyBudget * days).roundToDouble(),
        if (customText == null) 'budget_currency': s.currency,
      },
    );
  }

  static const _phrase = {
    'relaxation': 'relaxing and beaches',
    'nature': 'nature and mountain views',
    'architecture': 'city architecture',
    'food': 'food',
    'culture': 'culture and temples',
    'adventure': 'adventure',
  };

  static String _join(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
}

class SetupDraftNotifier extends Notifier<SetupDraft> {
  @override
  SetupDraft build() => SetupDraft(start: DateTime.now().add(const Duration(days: 30)));
  void update(SetupDraft Function(SetupDraft) f) => state = f(state);
  void reset() => state = build();
}

final setupDraftProvider = NotifierProvider<SetupDraftNotifier, SetupDraft>(SetupDraftNotifier.new);

// ------------------------------------------------------------------------------------------------------ Saved places

class SavedPlace {
  const SavedPlace({required this.id, required this.name, this.city, this.category, this.photo});
  final String id, name;
  final String? city, category, photo;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'city': city, 'category': category, 'photo': photo};
  factory SavedPlace.fromJson(Map<String, dynamic> j) =>
      SavedPlace(id: j['id'] as String, name: j['name'] as String, city: j['city'] as String?, category: j['category'] as String?, photo: j['photo'] as String?);
}

class SavedPlacesNotifier extends Notifier<List<SavedPlace>> {
  static const storageKey = 'arivo.saved';

  @override
  List<SavedPlace> build() {
    final raw = ref.read(initialLocalStateProvider)[storageKey];
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  bool has(String id) => state.any((p) => p.id == id);

  void toggle(SavedPlace p) {
    state = has(p.id) ? state.where((x) => x.id != p.id).toList() : [p, ...state];
    _save(storageKey, state.map((e) => e.toJson()).toList());
  }
}

final savedPlacesProvider = NotifierProvider<SavedPlacesNotifier, List<SavedPlace>>(SavedPlacesNotifier.new);

// ------------------------------------------------------------------------------------------------------------ Packing

class PackingItem {
  const PackingItem(this.label, {this.done = false, this.custom = false});
  final String label;
  final bool done, custom;
  PackingItem toggled() => PackingItem(label, done: !done, custom: custom);
  Map<String, dynamic> toJson() => {'label': label, 'done': done, 'custom': custom};
  factory PackingItem.fromJson(Map<String, dynamic> j) => PackingItem(j['label'] as String, done: j['done'] as bool? ?? false, custom: j['custom'] as bool? ?? false);
}

/// Suggested items from the trip's shape; checked state and custom items are kept per trip.
List<PackingItem> suggestedPacking({required int days, required bool international, required bool rainy, required bool warm, required bool beach}) => [
      if (international) const PackingItem('Passport'),
      const PackingItem('Travel insurance'),
      const PackingItem('Credit card / cash'),
      const PackingItem('Phone & charger'),
      if (international) const PackingItem('Travel adapter'),
      const PackingItem('Comfortable shoes'),
      PackingItem('Clothes for $days days'),
      const PackingItem('Toiletries'),
      const PackingItem('Medication'),
      if (warm || beach) const PackingItem('Sunscreen'),
      if (beach) const PackingItem('Swimsuit'),
      if (rainy) const PackingItem('Umbrella or rain jacket'),
      if (!warm) const PackingItem('Warm layer'),
      const PackingItem('Reusable water bottle'),
    ];

class PackingNotifier extends Notifier<List<PackingItem>?> {
  PackingNotifier(this.tripId);
  final String tripId;
  String get _key => 'arivo.packing.$tripId';

  bool _loaded = false;
  List<PackingItem>? _pendingSeed;

  @override
  List<PackingItem>? build() {
    _load();
    return null; // null = still loading from storage
  }

  Future<void> _load() async {
    List<PackingItem>? stored;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) stored = (jsonDecode(raw) as List).map((e) => PackingItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {}
    _loaded = true;
    if (stored != null) {
      state = stored;
    } else if (_pendingSeed != null) {
      _set(_pendingSeed!);
    }
  }

  void _set(List<PackingItem> items) {
    state = items;
    _save(_key, items.map((e) => e.toJson()).toList());
  }

  /// Suggested items for a trip with no saved list. Safe to call before storage has loaded.
  void seed(List<PackingItem> items) {
    if (!_loaded) {
      _pendingSeed = items;
    } else if (state == null) {
      _set(items);
    }
  }

  void toggle(int i) => _set([...state!]..[i] = state![i].toggled());
  void add(String label) => _set([...state ?? const [], PackingItem(label, custom: true)]);
  void remove(int i) => _set([...state!]..removeAt(i));
}

final packingProvider = NotifierProvider.family<PackingNotifier, List<PackingItem>?, String>(PackingNotifier.new);

// Client models mirror the backend's normalized shapes. Supplier payloads never reach the app.

typedef Json = Map<String, dynamic>;

List<T> _list<T>(dynamic v, T Function(Json) f) => (v as List? ?? const []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String);

enum Provenance { live, est, you }

Provenance provenanceOf(String? v) => switch (v) { 'live' => Provenance.live, 'you' => Provenance.you, _ => Provenance.est };

const _minorUnits = {'JPY': 0, 'KRW': 0, 'VND': 0, 'IDR': 0};

class Money {
  const Money(this.amountMinor, this.currency);
  factory Money.fromJson(Json j) => Money((j['amount_minor'] as num).toInt(), j['currency'] as String);
  final int amountMinor;
  final String currency;

  int get digits => _minorUnits[currency] ?? 2;
  double get amount => amountMinor / _pow10(digits);
  static int _pow10(int d) => d == 0 ? 1 : 100;
  Json toJson() => {'amount_minor': amountMinor, 'currency': currency};
}

class Evidence {
  Evidence(this.text, this.provenance, this.source, this.url, this.updatedAt);
  factory Evidence.fromJson(Json j) =>
      Evidence(j['text'] as String, provenanceOf(j['provenance'] as String?), j['source'] as String?, j['url'] as String?, _dt(j['updated_at']));
  final String text;
  final Provenance provenance;
  final String? source;
  final String? url;
  final DateTime? updatedAt;
}

class Leg {
  Leg(this.mode, this.minutes, this.distanceM, this.provenance, this.note);
  factory Leg.fromJson(Json j) =>
      Leg(j['mode'] as String, (j['minutes'] as num).toInt(), (j['distance_m'] as num).toInt(), provenanceOf(j['provenance'] as String?), j['note'] as String?);
  final String mode;
  final int minutes;
  final int distanceM;
  final Provenance provenance;
  final String? note;
  bool get isWalk => mode == 'walk';
}

class ItineraryItem {
  ItineraryItem.fromJson(Json j)
      : id = j['id'] as String,
        placeId = j['place_id'] as String,
        name = j['name'] as String,
        category = j['category'] as String,
        lat = (j['lat'] as num).toDouble(),
        lon = (j['lon'] as num).toDouble(),
        start = DateTime.parse(j['start'] as String),
        durationMin = (j['duration_min'] as num).toInt(),
        leg = j['leg'] == null ? null : Leg.fromJson(Map<String, dynamic>.from(j['leg'] as Map)),
        legCost = j['leg_cost'] == null ? null : Money.fromJson(Map<String, dynamic>.from(j['leg_cost'] as Map)),
        cost = j['cost'] == null ? null : Money.fromJson(Map<String, dynamic>.from(j['cost'] as Map)),
        costProvenance = provenanceOf(j['cost_provenance'] as String?),
        reason = (j['reason'] as String?) ?? '',
        evidence = _list(j['evidence'], Evidence.fromJson),
        score = (j['score'] as num?)?.toDouble(),
        status = j['status'] as String,
        locked = j['locked'] as bool? ?? false,
        bookingId = j['booking_id'] as String?,
        indoor = j['indoor'] as bool? ?? false,
        kind = j['kind'] as String,
        lane = j['lane'] as String?;

  final String id, placeId, name, category, status, kind, reason;
  final double lat, lon;
  final DateTime start;
  final int durationMin;
  final Leg? leg;
  final Money? legCost, cost;
  final Provenance costProvenance;
  final List<Evidence> evidence;
  final double? score;
  final bool locked, indoor;
  final String? bookingId, lane;

  DateTime get end => start.add(Duration(minutes: durationMin));
  bool get isBooked => locked || status == 'booked';
}

class PlanB {
  PlanB.fromJson(Json j)
      : trigger = j['trigger'] as String,
        summary = j['summary'] as String? ?? '',
        items = _list(j['items'], ItineraryItem.fromJson),
        timeDeltaMin = (j['time_delta_min'] as num?)?.toInt() ?? 0;
  final String trigger, summary;
  final List<ItineraryItem> items;
  final int timeDeltaMin;
}

class ItineraryDay {
  ItineraryDay.fromJson(Json j)
      : index = (j['index'] as num).toInt(),
        date = DateTime.parse(j['date'] as String),
        zone = j['zone'] as String? ?? '',
        title = j['title'] as String? ?? '',
        routeColor = (j['route_color'] as num?)?.toInt() ?? 0,
        items = _list(j['items'], ItineraryItem.fromJson),
        planB = _list(j['plan_b'], PlanB.fromJson),
        weather = j['weather'] == null ? null : Map<String, dynamic>.from(j['weather'] as Map);
  final int index, routeColor;
  final DateTime date;
  final String zone, title;
  final List<ItineraryItem> items;
  final List<PlanB> planB;
  final Json? weather;
}

class BudgetLine {
  BudgetLine.fromJson(Json j)
      : category = j['category'] as String,
        planned = Money.fromJson(Map<String, dynamic>.from(j['planned'] as Map)),
        reserved = Money.fromJson(Map<String, dynamic>.from(j['reserved'] as Map)),
        spent = Money.fromJson(Map<String, dynamic>.from(j['spent'] as Map));
  final String category;
  final Money planned, reserved, spent;
}

class CrewMember {
  CrewMember.fromJson(Json j)
      : userId = j['user_id'] as String,
        name = j['display_name'] as String,
        role = j['role'] as String,
        colorIndex = (j['color_index'] as num?)?.toInt() ?? 0;
  final String userId, name, role;
  final int colorIndex;
}

class Trip {
  Trip.fromJson(Json j)
      : id = j['id'] as String,
        ownerId = j['owner_id'] as String,
        title = j['title'] as String,
        cities = List<String>.from(j['cities'] as List),
        startDate = DateTime.parse(j['start_date'] as String),
        timezone = j['timezone'] as String,
        currency = j['currency'] as String,
        homeCurrency = j['home_currency'] as String? ?? 'MYR',
        crewSize = ((j['intent'] as Map)['crew_size'] as num).toInt(),
        crewType = (j['intent'] as Map)['crew_type'] as String,
        interests = List<String>.from(((j['intent'] as Map)['interests'] as List?) ?? const []),
        pace = (j['intent'] as Map)['pace'] as String,
        parser = (j['intent'] as Map)['parser'] as String? ?? 'heuristic',
        days = _list(j['days'], ItineraryDay.fromJson),
        crew = _list(j['crew'], CrewMember.fromJson),
        budgetTotal = j['budget'] == null ? null : Money.fromJson(Map<String, dynamic>.from((j['budget'] as Map)['total'] as Map)),
        budgetLines = j['budget'] == null ? const [] : _list((j['budget'] as Map)['lines'], BudgetLine.fromJson),
        hotelPlaceId = j['hotel_place_id'] as String?,
        mode = j['mode'] as String? ?? 'planner',
        version = (j['version'] as num).toInt(),
        warnings = List<String>.from(j['warnings'] as List? ?? const []),
        raw = j;

  final String id, ownerId, title, timezone, currency, homeCurrency, crewType, pace, parser, mode;
  final List<String> cities, interests, warnings;
  final DateTime startDate;
  final int crewSize, version;
  final List<ItineraryDay> days;
  final List<CrewMember> crew;
  final Money? budgetTotal;
  final List<BudgetLine> budgetLines;
  final String? hotelPlaceId;
  final Json raw;

  Iterable<ItineraryItem> get allItems => days.expand((d) => d.items);
}

class DiffEntry {
  DiffEntry.fromJson(Json j)
      : itemId = j['item_id'] as String,
        name = j['name'] as String,
        fromTime = j['from_time'] as String?,
        toTime = j['to_time'] as String?,
        reason = j['reason'] as String?,
        detail = j['detail'] as String?;
  final String itemId, name;
  final String? fromTime, toTime, reason, detail;
}

class TripChange {
  TripChange.fromJson(Json j)
      : id = j['id'] as String,
        tripId = j['trip_id'] as String,
        dayIndex = (j['day_index'] as num).toInt(),
        trigger = j['trigger'] as String,
        kept = _list(j['kept'], DiffEntry.fromJson),
        moved = _list(j['moved'], DiffEntry.fromJson),
        removed = _list(j['removed'], DiffEntry.fromJson),
        added = _list(j['added'], DiffEntry.fromJson),
        timeDeltaMin = (j['time_delta_min'] as num?)?.toInt() ?? 0,
        budgetDelta = j['budget_delta'] == null ? null : Money.fromJson(Map<String, dynamic>.from(j['budget_delta'] as Map)),
        explanation = j['explanation'] as String? ?? '',
        status = j['status'] as String,
        newItems = _list(j['new_items'], ItineraryItem.fromJson);
  final String id, tripId, trigger, explanation, status;
  final int dayIndex, timeDeltaMin;
  final List<DiffEntry> kept, moved, removed, added;
  final Money? budgetDelta;
  final List<ItineraryItem> newItems;
}

class BudgetView {
  BudgetView.fromJson(Json j)
      : currency = j['currency'] as String,
        total = (j['total'] as num).toDouble(),
        spent = (j['spent'] as num).toDouble(),
        reserved = (j['reserved'] as num).toDouble(),
        forecast = (j['forecast'] as num).toDouble(),
        remaining = (j['remaining'] as num).toDouble(),
        state = j['state'] as String,
        lines = List<Json>.from((j['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map))),
        suggestions = List<Json>.from((j['suggestions'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map))),
        fx = j['fx'] == null ? null : Map<String, dynamic>.from(j['fx'] as Map);
  final String currency, state;
  final double total, spent, reserved, forecast, remaining;
  final List<Json> lines, suggestions;
  final Json? fx;
}

class Segment {
  Segment.fromJson(Json j)
      : origin = j['origin'] as String,
        destination = j['destination'] as String,
        departure = DateTime.parse(j['departure'] as String),
        arrival = DateTime.parse(j['arrival'] as String),
        carrier = j['carrier'] as String,
        number = j['number'] as String?;
  final String origin, destination, carrier;
  final String? number;
  final DateTime departure, arrival;
}

class PriceLine {
  PriceLine.fromJson(Json j) : label = j['label'] as String, amount = Money.fromJson(Map<String, dynamic>.from(j['amount'] as Map));
  final String label;
  final Money amount;
}

class TravelOffer {
  TravelOffer.fromJson(Json j)
      : offerId = j['offer_id'] as String,
        provider = j['provider'] as String,
        type = j['type'] as String,
        origin = j['origin'] as String?,
        destination = j['destination'] as String?,
        departure = _dt(j['departure']),
        arrival = _dt(j['arrival']),
        durationMin = (j['duration_min'] as num?)?.toInt(),
        segments = _list(j['segments'], Segment.fromJson),
        price = Money.fromJson(Map<String, dynamic>.from(j['price'] as Map)),
        lines = _list(j['lines'], PriceLine.fromJson),
        baggage = j['baggage'] as String?,
        refundable = j['refundable'] as bool? ?? false,
        changeable = j['changeable'] as bool? ?? false,
        cancellationPolicy = j['cancellation_policy'] as String? ?? '',
        changePolicy = j['change_policy'] as String? ?? '',
        sandbox = j['sandbox'] as bool? ?? false,
        title = j['title'] as String? ?? '',
        subtitle = j['subtitle'] as String? ?? '',
        badges = List<String>.from(j['badges'] as List? ?? const []),
        locationFit = (j['location_fit'] as num?)?.toInt(),
        placeId = j['place_id'] as String?,
        meta = Map<String, dynamic>.from(j['meta'] as Map? ?? const {});
  final String offerId, provider, type, cancellationPolicy, changePolicy, title, subtitle;
  final String? origin, destination, baggage, placeId;
  final DateTime? departure, arrival;
  final int? durationMin, locationFit;
  final List<Segment> segments;
  final Money price;
  final List<PriceLine> lines;
  final bool refundable, changeable, sandbox;
  final List<String> badges;
  final Json meta;
}

class BookingTxn {
  BookingTxn.fromJson(Json j)
      : id = j['id'] as String,
        state = j['state'] as String,
        offer = TravelOffer.fromJson(Map<String, dynamic>.from(j['offer'] as Map)),
        travellersCount = (j['travellers_count'] as num).toInt(),
        bookingReference = j['booking_reference'] as String?,
        failureReason = j['failure_reason'] as String?,
        needsReconciliation = j['needs_reconciliation'] as bool? ?? false,
        events = List<Json>.from((j['events'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  final String id, state;
  final TravelOffer offer;
  final int travellersCount;
  final String? bookingReference, failureReason;
  final bool needsReconciliation;
  final List<Json> events;

  bool get priceChanged => state == 'PRICE_CHANGED';
  bool get confirmed => state == 'CONFIRMED';
  String? get oldPriceNote => events.map((e) => e['note'] as String? ?? '').lastWhere((n) => n.startsWith('price '), orElse: () => '');
}

class Place {
  Place.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        category = j['category'] as String,
        lat = (j['lat'] as num).toDouble(),
        lon = (j['lon'] as num).toDouble(),
        city = j['city'] as String,
        iconic = (j['iconic'] as num?)?.toDouble() ?? 0,
        summary = j['summary'] as String?,
        photo = j['photo'] == null ? null : Map<String, dynamic>.from(j['photo'] as Map),
        matchPct = (j['match_pct'] as num?)?.toInt(),
        why = _list(j['why'], Evidence.fromJson),
        hoursVerified = (j['hours'] as Map?)?['verified'] as bool? ?? false,
        hoursRaw = (j['hours'] as Map?)?['raw'] as String?,
        sources = List<Json>.from((j['sources'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  final String id, name, category, city;
  final double lat, lon, iconic;
  final String? summary, hoursRaw;
  final Json? photo;
  final int? matchPct;
  final List<Evidence> why;
  final bool hoursVerified;
  final List<Json> sources;
}

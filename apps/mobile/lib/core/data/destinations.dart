/// Curated destinations and interest imagery for onboarding, Home and trip headers.
///
/// Only cities with seeded, verified place data (`supported`) can be planned today; the rest are shown as
/// "Coming soon" so the grid stays honest. Photos are Unsplash (Unsplash License).
library;

String unsplash(String id, {int w = 900}) => 'https://images.unsplash.com/photo-$id?auto=format&fit=crop&w=$w&q=80';

abstract final class Photos {
  static final hero = unsplash('1464822759023-fed622ff2c3b', w: 1400);
  static final tokyo = unsplash('1540959733332-eab4deabeeaf');
  static final kyoto = unsplash('1478436127897-769e1b3f0f36');
  static final kualaLumpur = unsplash('1596422846543-75c6fc197f07');
  static final fuji = unsplash('1493976040374-85c8e12f0c0e');
  static final bali = unsplash('1537996194471-e657df975ab4');
  static final amalfi = unsplash('1533105079780-92b9be482077');
  static final food = unsplash('1519984388953-d2406bc725e1');
  static final paris = unsplash('1502602898657-3e91760cbb34');
  static final singapore = unsplash('1525625293386-3f8f99389edd');
  static final seoul = unsplash('1538485399081-7191377e8241');
  static final bangkok = unsplash('1508009603885-50cf7c579365');
  static final rome = unsplash('1552832230-c0197dd311b5');
  static final dubai = unsplash('1512453979798-5ea266f8880c');
  static final london = unsplash('1513635269975-59663e0ac1ad');
  static final newYork = unsplash('1496442226666-8d4d0e62e6e9');
  static final santorini = unsplash('1570077188670-e3a8d69ac5ff');
  static final beach = unsplash('1507525428034-b723cf961d3e');
  static final mountains = unsplash('1464822759023-fed622ff2c3b');
  static final adventure = unsplash('1551632811-561732d1e306');
}

class Destination {
  const Destination(this.key, this.name, this.country, this.photo, {this.supported = false, this.blurb = ''});
  final String key, name, country, photo, blurb;
  final bool supported;
}

final destinations = <Destination>[
  Destination('tokyo', 'Tokyo', 'Japan', Photos.tokyo, supported: true, blurb: 'Neon streets, quiet shrines and the best food on earth.'),
  Destination('kyoto', 'Kyoto', 'Japan', Photos.kyoto, supported: true, blurb: 'Temples, gardens and lantern-lit lanes.'),
  Destination('kuala-lumpur', 'Kuala Lumpur', 'Malaysia', Photos.kualaLumpur, supported: true, blurb: 'Markets, skyline and a food culture that brings the city together.'),
  Destination('bali', 'Bali', 'Indonesia', Photos.bali),
  Destination('paris', 'Paris', 'France', Photos.paris),
  Destination('singapore', 'Singapore', 'Singapore', Photos.singapore),
  Destination('seoul', 'Seoul', 'South Korea', Photos.seoul),
  Destination('bangkok', 'Bangkok', 'Thailand', Photos.bangkok),
  Destination('rome', 'Rome', 'Italy', Photos.rome),
  Destination('dubai', 'Dubai', 'UAE', Photos.dubai),
  Destination('london', 'London', 'UK', Photos.london),
  Destination('new-york', 'New York', 'USA', Photos.newYork),
  Destination('santorini', 'Santorini', 'Greece', Photos.santorini),
];

Destination? destinationFor(String? cityKey) {
  if (cityKey == null) return null;
  final k = cityKey.toLowerCase();
  for (final d in destinations) {
    if (d.key == k || d.name.toLowerCase() == k) return d;
  }
  return null;
}

/// Best photo for a trip header: the first city we know, else a scenic default.
String photoForCities(List<String> cities) {
  for (final c in cities) {
    final d = destinationFor(c);
    if (d != null) return d.photo;
  }
  return Photos.fuji;
}

class Interest {
  const Interest(this.key, this.label, this.photo);
  final String key, label, photo;
}

/// Onboarding interests. `key` matches the backend's Taste DNA dimensions where one exists.
final interests = <Interest>[
  Interest('relaxation', 'Beaches', Photos.beach),
  Interest('nature', 'Mountains', Photos.mountains),
  Interest('architecture', 'Cities', Photos.newYork),
  Interest('food', 'Food', Photos.food),
  Interest('culture', 'Culture', Photos.kyoto),
  Interest('adventure', 'Adventure', Photos.adventure),
];

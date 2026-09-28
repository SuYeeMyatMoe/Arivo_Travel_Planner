import 'package:intl/intl.dart';

import 'models/models.dart';

final _nf0 = NumberFormat('#,##0', 'en_US');
final _nf2 = NumberFormat('#,##0.00', 'en_US');

String money(Money m) => moneyOf(m.amount, m.currency);

String moneyOf(double amount, String currency) {
  final sym = switch (currency) { 'MYR' => 'RM ', 'JPY' => '¥', 'USD' => '\$', 'EUR' => '€', 'SGD' => 'S\$', _ => '$currency ' };
  // Exact cents whenever they exist: a price the traveller pays is never rounded for looks.
  final whole = const {'JPY', 'KRW', 'VND', 'IDR'}.contains(currency) || amount == amount.roundToDouble();
  final s = (whole ? _nf0 : _nf2).format(amount.abs());
  return '${amount < 0 ? '−' : ''}$sym$s';
}

String signedMoney(Money m) => '${m.amountMinor > 0 ? '+' : ''}${money(m)}';

String hhmm(DateTime t) => DateFormat('HH:mm').format(t);
String dayLabel(DateTime d) => DateFormat('EEE d MMM').format(d);

/// "Apr 12 – Apr 18, 2025" (year shown once, on the end date).
String dateRange(DateTime a, DateTime b) =>
    a.year == b.year ? '${DateFormat('MMM d').format(a)} – ${DateFormat('MMM d, y').format(b)}' : '${DateFormat('MMM d, y').format(a)} – ${DateFormat('MMM d, y').format(b)}';

String longDate(DateTime d) => DateFormat('EEE, MMM d, y').format(d);

String duration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String legLabel(Leg leg) => '${leg.isWalk ? 'Walk' : 'Transit'} · ${leg.minutes} min';

String titleCase(String s) => s.isEmpty ? s : s.split(RegExp(r'[_\s]+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

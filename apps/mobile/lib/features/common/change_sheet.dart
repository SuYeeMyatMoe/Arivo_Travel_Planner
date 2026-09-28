import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ari/ari.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/trip_widgets.dart';
import '../../state/providers.dart';

/// Any proposed change (Explore add, Guide, Crew vote) goes through the same review → Apply | Keep original.
Future<bool> showChangeSheet(BuildContext context, WidgetRef ref, TripChange change, {String title = 'Review the change'}) async {
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ChangeSheet(change: change, title: title),
  );
  return applied ?? false;
}

class _ChangeSheet extends ConsumerStatefulWidget {
  const _ChangeSheet({required this.change, required this.title});
  final TripChange change;
  final String title;
  @override
  ConsumerState<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends ConsumerState<_ChangeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _decide(bool apply) async {
    setState(() => _busy = true);
    try {
      final c = widget.change;
      final j = await ref.read(apiProvider).post('/v1/trips/${c.tripId}/changes/${c.id}/${apply ? 'apply' : 'reject'}') as Map;
      if (apply) {
        ref.read(tripProvider.notifier).replace(Map<String, dynamic>.from(j['trip'] as Map));
        ref.read(ariProvider.notifier).say('Updated. Your bookings stayed put.', as: AriState.excited);
      }
      if (mounted) Navigator.pop(context, apply);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, 0, ArivoSpace.s5, ArivoSpace.s5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: t.displayM),
          const SizedBox(height: ArivoSpace.s2),
          Text(widget.change.explanation, style: t.bodyL),
          const SizedBox(height: ArivoSpace.s4),
          ChangeDiff(change: widget.change),
          ArivoButton('Apply changes', expand: true, busy: _busy, onPressed: () => _decide(true)),
          const SizedBox(height: ArivoSpace.s2),
          ArivoButton('Keep original', kind: ButtonKind.tonal, expand: true, onPressed: _busy ? null : () => _decide(false)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s3), child: Text(_error!, style: t.bodyM.copyWith(color: context.palette.emberText))),
        ]),
      ),
    );
  }
}

/// Small helper for places with licensed photos (Commons) and an honest fallback tile.
class PlacePhoto extends StatelessWidget {
  const PlacePhoto({super.key, this.photo, required this.fallbackColor, this.height = 140});
  final Json? photo;
  final Color fallbackColor;
  final double height;
  @override
  Widget build(BuildContext context) {
    final url = photo?['url'] as String?;
    final fallback = Container(
      height: height,
      decoration: BoxDecoration(color: fallbackColor.withValues(alpha: 0.18)),
      child: TopoBackground(seed: height.toInt(), child: const SizedBox.expand()),
    );
    if (url == null) return fallback;
    return Image.network(url, height: height, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback,
        semanticLabel: 'Photo: ${photo?['credit'] ?? 'Wikimedia Commons'}');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../shell/app_shell.dart';

/// Packing Checklist: Suggested (from the trip's length, weather and destination) and Custom. Saved per trip on device.
class PackingScreen extends ConsumerWidget {
  const PackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final trip = ref.watch(tripProvider).value;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Packing Checklist', style: t.titleM)),
        body: StateMessage(title: 'No trip yet', body: 'Plan a trip and get a packing list made for it.', action: 'Plan a trip', onAction: () => context.go('/start')),
      );
    }
    return _Checklist(trip: trip);
  }
}

List<PackingItem> _suggest(Trip trip) {
  final maxC = trip.days.map((d) => (d.weather?['max_c'] as num?)?.toDouble()).whereType<double>();
  final rain = trip.days.map((d) => (d.weather?['max_precip_prob'] as num?)?.toDouble() ?? 0);
  return suggestedPacking(
    days: trip.days.length,
    // The planner treats trips outside Malaysia as international; a different local currency is the same signal on the client.
    international: trip.currency != 'MYR',
    rainy: rain.any((r) => r >= 40),
    warm: maxC.isEmpty ? true : maxC.reduce((a, b) => a > b ? a : b) >= 22,
    beach: trip.interests.contains('relaxation'),
  );
}

class _Checklist extends ConsumerStatefulWidget {
  const _Checklist({required this.trip});
  final Trip trip;
  @override
  ConsumerState<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends ConsumerState<_Checklist> {
  @override
  void initState() {
    super.initState();
    // Used only when nothing is stored for this trip yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(packingProvider(widget.trip.id).notifier).seed(_suggest(widget.trip));
    });
  }

  Future<void> _add() async {
    final c = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add item'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'e.g. Camera'), onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) ref.read(packingProvider(widget.trip.id).notifier).add(label);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final items = ref.watch(packingProvider(widget.trip.id));
    final notifier = ref.read(packingProvider(widget.trip.id).notifier);
    Widget list(bool custom) {
      if (items == null) return const Center(child: CircularProgressIndicator());
      final idx = [for (var i = 0; i < items.length; i++) if (items[i].custom == custom) i];
      return ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s4, ArivoSpace.s3, ArivoSpace.s4, 120), children: [
        if (idx.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s6),
            child: Text(custom ? 'Add anything else you want to remember.' : 'Nothing suggested.', textAlign: TextAlign.center, style: t.bodyM.copyWith(color: p.muted)),
          ),
        for (final i in idx)
          Dismissible(
            key: ValueKey('${items[i].label}-$i'),
            direction: custom ? DismissDirection.endToStart : DismissDirection.none,
            onDismissed: (_) => notifier.remove(i),
            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: ArivoSpace.s4), child: Icon(Icons.delete_outline, color: p.emberText)),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: items[i].done,
              onChanged: (_) => notifier.toggle(i),
              title: Text(items[i].label, style: t.bodyL.copyWith(color: items[i].done ? p.muted : p.text, decoration: items[i].done ? TextDecoration.lineThrough : null)),
            ),
          ),
        const SizedBox(height: ArivoSpace.s4),
        ArivoButton('Add Item', kind: ButtonKind.outline, icon: Icons.add_rounded, expand: true, onPressed: _add),
      ]);
    }

    final done = items?.where((i) => i.done).length ?? 0, total = items?.length ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Packing Checklist', style: t.titleM.copyWith(fontWeight: FontWeight.w700)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(78),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4),
                child: Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 6),
                    ),
                  ),
                  const SizedBox(width: ArivoSpace.s3),
                  Text('$done / $total packed', style: t.caption),
                ]),
              ),
              const TabBar(tabs: [Tab(text: 'Suggested'), Tab(text: 'Custom')]),
            ]),
          ),
        ),
        body: PageWidth(child: TabBarView(children: [list(false), list(true)])),
      ),
    );
  }
}

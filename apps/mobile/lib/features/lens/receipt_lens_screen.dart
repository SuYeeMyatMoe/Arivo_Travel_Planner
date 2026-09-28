import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ari/ari.dart';
import '../../core/format.dart';
import '../../core/models/models.dart';
import '../../core/net/api.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/primitives.dart';
import '../../state/providers.dart';
import '../shell/app_shell.dart';

/// Labelled sample for web previews, where on-device OCR is not available. Never saved unless you confirm.
const _sample = '''居酒屋 とりまる 新宿店
2026/09/26 19:42
生ビール x3   1,950
焼き鳥盛り合わせ   1,280
枝豆   420
だし巻き玉子   580
小計   4,230
消費税   423
合計   ¥4,653
VISA ************4242''';

/// Receipt Lens: photo → on-device text recognition → draft → you confirm → Budget Brain.
/// The photo never leaves the phone; only recognised text is sent, card digits are masked server-side.
class ReceiptLensScreen extends ConsumerStatefulWidget {
  const ReceiptLensScreen({super.key});
  @override
  ConsumerState<ReceiptLensScreen> createState() => _ReceiptLensScreenState();
}

class _ReceiptLensScreenState extends ConsumerState<ReceiptLensScreen> {
  final _raw = TextEditingController();
  final _merchant = TextEditingController();
  final _total = TextEditingController();
  Json? _draft;
  String _category = 'food';
  String? _error;
  bool _busy = false, _usedSample = false;

  Future<void> _scan(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000);
    if (file == null) return;
    setState(() => _busy = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
      _raw.text = text.text;
      _usedSample = false;
      await _parse();
    } catch (e) {
      setState(() => _error = 'Could not read that photo. Try again in better light, or type the total.');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _parse() async {
    if (_raw.text.trim().length < 3) return;
    final trip = ref.read(tripProvider).value;
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(ariProvider.notifier).set(AriState.thinking);
    try {
      final j = Map<String, dynamic>.from(await ref.read(apiProvider).post('/v1/lens/receipt', body: {'text': _raw.text, 'currency_hint': trip?.currency}) as Map);
      final d = Map<String, dynamic>.from(j['draft'] as Map);
      setState(() {
        _draft = d;
        _merchant.text = d['merchant'] as String? ?? '';
        _total.text = d['total'] == null ? '' : '${d['total']}';
        _category = d['category'] as String? ?? 'food';
      });
      ref.read(ariProvider.notifier).set(AriState.pointing, revertAfter: const Duration(seconds: 3));
    } on ApiError catch (e) {
      setState(() => _error = e.message);
      ref.read(ariProvider.notifier).set(AriState.warning, revertAfter: const Duration(seconds: 4));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final trip = ref.read(tripProvider).value;
    final amount = double.tryParse(_total.text.replaceAll(',', ''));
    if (trip == null || amount == null || amount <= 0) {
      setState(() => _error = 'Check the total before adding it.');
      return;
    }
    setState(() => _busy = true);
    try {
      final j = Map<String, dynamic>.from(await ref.read(apiProvider).post('/v1/trips/${trip.id}/expenses', body: {
        'amount': amount, 'currency': _draft!['currency'], 'category': _category,
        if (_merchant.text.trim().isNotEmpty) 'merchant': _merchant.text.trim(), 'source': 'receipt_lens',
      }) as Map);
      ref.invalidate(budgetProvider);
      final b = BudgetView.fromJson(Map<String, dynamic>.from(j['budget'] as Map));
      ref.read(ariProvider.notifier).say('Added. ${moneyOf(b.remaining, b.currency)} left in the budget.', as: AriState.excited);
      if (mounted) context.pop();
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type, p = context.palette;
    final d = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Lens')),
      body: PageWidth(
        child: ListView(padding: const EdgeInsets.all(ArivoSpace.s4), children: [
          Text('Snap a receipt. Ari reads it on your phone, you check it, then it goes into the budget.', style: t.bodyL),
          const SizedBox(height: ArivoSpace.s4),
          if (!kIsWeb)
            Row(children: [
              Expanded(child: ArivoButton('Take photo', icon: Icons.photo_camera_outlined, busy: _busy, onPressed: () => _scan(ImageSource.camera))),
              const SizedBox(width: ArivoSpace.s2),
              Expanded(child: ArivoButton('From gallery', kind: ButtonKind.tonal, icon: Icons.photo_library_outlined, onPressed: _busy ? null : () => _scan(ImageSource.gallery))),
            ])
          else
            Container(
              padding: const EdgeInsets.all(ArivoSpace.s3),
              decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(ArivoRadius.s)),
              child: Text('Camera text recognition runs on Android and iOS. In this web preview, paste receipt text or load the sample.', style: t.caption),
            ),
          const SizedBox(height: ArivoSpace.s4),
          TextField(
            controller: _raw,
            minLines: 4,
            maxLines: 10,
            maxLength: 8000,
            style: t.monoS,
            decoration: const InputDecoration(labelText: 'Receipt text', alignLabelWithHint: true),
          ),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.science_outlined),
              label: const Text('Load sample receipt'),
              onPressed: () => setState(() {
                _raw.text = _sample;
                _usedSample = true;
              }),
            ),
            const Spacer(),
            ArivoButton('Read receipt', kind: ButtonKind.tonal, busy: _busy && d == null, onPressed: _parse),
          ]),
          if (_usedSample) const Align(alignment: Alignment.centerLeft, child: StatusChip(ChipTone.sandbox, label: 'SAMPLE RECEIPT')),
          if (d != null) ...[
            const Divider(height: ArivoSpace.s6),
            Row(children: [
              Text('Check before adding', style: t.titleL),
              const Spacer(),
              Text('${((d['confidence'] as num) * 100).round()}% sure', style: t.monoS),
            ]),
            const SizedBox(height: ArivoSpace.s3),
            for (final l in (d['lines'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text('${l['name']}${(l['qty'] as num) > 1 ? ' ×${l['qty']}' : ''}', style: t.bodyM)),
                  Text(moneyOf((l['amount'] as num).toDouble(), d['currency'] as String), style: t.monoS),
                ]),
              ),
            const SizedBox(height: ArivoSpace.s3),
            TextField(controller: _merchant, decoration: const InputDecoration(labelText: 'Merchant')),
            const SizedBox(height: ArivoSpace.s3),
            TextField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: 'Total', suffixText: d['currency'] as String),
            ),
            if (d['total_matches_lines'] == true)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Total matches the items.', style: t.caption.copyWith(color: p.signalText))),
            for (final w in (d['warnings'] as List).cast<String>())
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(w, style: t.caption.copyWith(color: p.lanternText))),
            const SizedBox(height: ArivoSpace.s3),
            Wrap(spacing: ArivoSpace.s2, children: [
              for (final c in const ['food', 'transport', 'activities', 'shopping', 'other'])
                ChoiceChip(label: Text(titleCase(c)), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
            ]),
            const SizedBox(height: ArivoSpace.s4),
            ArivoButton('Add to budget', expand: true, busy: _busy, onPressed: _confirm),
            const SizedBox(height: ArivoSpace.s2),
            ArivoButton('Discard', kind: ButtonKind.quiet, expand: true, onPressed: () => setState(() => _draft = null)),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: ArivoSpace.s3), child: Text(_error!, style: t.bodyM.copyWith(color: p.emberText))),
        ]),
      ),
    );
  }
}

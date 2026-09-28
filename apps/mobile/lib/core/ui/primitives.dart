import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';

enum ButtonKind { primary, outline, tonal, quiet, danger }

/// Rounded button. One blue `primary` per screen; `outline` is the blue-bordered secondary ("Customize").
/// On the last checkout step the label states the amount.
class ArivoButton extends StatelessWidget {
  const ArivoButton(this.label, {super.key, this.onPressed, this.kind = ButtonKind.primary, this.icon, this.expand = false, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool expand, busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, border) = switch (kind) {
      ButtonKind.primary => (p.volt, p.onVolt, null),
      ButtonKind.outline => (p.raised, p.voltText, p.volt),
      ButtonKind.tonal => (p.raised, p.text, p.line),
      ButtonKind.quiet => (Colors.transparent, p.voltText, null),
      ButtonKind.danger => (p.emberText, ArivoColors.textOnVolt, null),
    };
    final big = kind == ButtonKind.primary || kind == ButtonKind.outline || kind == ButtonKind.danger;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (busy || icon != null) const SizedBox(width: ArivoSpace.s2),
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis,
              style: context.type.label.copyWith(color: fg, fontSize: big ? 15 : 14)),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      label: busy ? '$label, working' : label,
      excludeSemantics: true,
      onTap: busy ? null : onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArivoRadius.s),
            side: border == null ? BorderSide.none : BorderSide(color: border, width: kind == ButtonKind.outline ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: big ? 52 : ArivoSize.touchMin - 4),
              child: Padding(padding: EdgeInsets.symmetric(horizontal: kind == ButtonKind.quiet ? ArivoSpace.s3 : ArivoSpace.s6), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// LIVE · EST. · YOU — where a number came from. Every price/time/distance/score shows one.
class ProvenanceTag extends StatelessWidget {
  const ProvenanceTag(this.kind, {super.key, this.source});
  final Provenance kind;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, spoken) = switch (kind) {
      Provenance.live => ('LIVE', 'live data'),
      Provenance.est => ('EST.', 'Arivo estimate'),
      Provenance.you => ('YOU', 'your input'),
    };
    final color = p.provenance(kind.name);
    return Tooltip(
      message: source == null ? spoken : '$spoken · $source',
      child: Semantics(
        label: source == null ? spoken : '$spoken from $source',
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: context.type.monoS.copyWith(color: color, fontSize: 10.5, height: 1.3)),
        ),
      ),
    );
  }
}

enum ChipTone { confirmed, pending, failed, cancelled, sandbox, offline, closed, booked, done }

/// Status = icon + word, never colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip(this.tone, {super.key, this.label});
  final ChipTone tone;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, text, color) = switch (tone) {
      ChipTone.confirmed => (Icons.check_rounded, 'Confirmed', p.signalText),
      ChipTone.pending => (Icons.schedule_rounded, 'Confirming', p.lanternText),
      ChipTone.failed => (Icons.error_outline_rounded, 'Failed', p.emberText),
      ChipTone.cancelled => (Icons.remove_rounded, 'Cancelled', p.emberText),
      ChipTone.sandbox => (Icons.science_outlined, 'SANDBOX', p.lanternText),
      ChipTone.offline => (Icons.lock_outline_rounded, 'Saved offline', p.muted),
      ChipTone.closed => (Icons.warning_amber_rounded, 'Closed today', p.emberText),
      ChipTone.booked => (Icons.lock_outline_rounded, 'Booked', p.voltText),
      ChipTone.done => (Icons.check_rounded, 'Done', p.signalText),
    };
    final outline = tone == ChipTone.sandbox;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : p.sunken,
        border: outline ? Border.all(color: color, width: 1.5) : null,
        borderRadius: BorderRadius.circular(ArivoRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label ?? text, style: context.type.caption.copyWith(color: color, fontWeight: FontWeight.w600, letterSpacing: outline ? 0.8 : null)),
      ]),
    );
  }
}

/// Faint topographic contours for ink surfaces ("night map", not flat black).
class TopoBackground extends StatelessWidget {
  const TopoBackground({super.key, required this.child, this.seed = 3});
  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TopoPainter(context.palette.line.withValues(alpha: 0.35), seed), child: child);
  }
}

class _TopoPainter extends CustomPainter {
  _TopoPainter(this.color, this.seed);
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rnd = math.Random(seed);
    final cx = size.width * (0.55 + rnd.nextDouble() * 0.3), cy = size.height * (0.2 + rnd.nextDouble() * 0.2);
    for (var i = 1; i <= 9; i++) {
      final r = i * 46.0;
      final path = Path();
      for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 36) {
        final wobble = 1 + 0.08 * math.sin(a * 3 + i) + 0.05 * math.cos(a * 5 - i * 0.7);
        final x = cx + math.cos(a) * r * wobble * 1.25, y = cy + math.sin(a) * r * wobble;
        a == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopoPainter old) => old.color != color || old.seed != seed;
}

/// Section label ("KEPT", "DAY 2 · TUE 17 NOV").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.dot});
  final String text;
  final Color? color, dot;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (dot != null) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 8)],
      Text(text.toUpperCase(), style: context.type.label.copyWith(color: color ?? context.palette.muted, letterSpacing: 1.1)),
    ]);
  }
}

/// A calm inline message for empty/offline/error states (never a stack trace).
class StateMessage extends StatelessWidget {
  const StateMessage({super.key, required this.title, this.body, this.action, this.onAction, this.icon = Icons.explore_outlined});
  final String title;
  final String? body, action;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ArivoSpace.s6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 32, color: context.palette.muted),
        const SizedBox(height: ArivoSpace.s3),
        Text(title, style: context.type.titleM, textAlign: TextAlign.center),
        if (body != null) ...[const SizedBox(height: ArivoSpace.s2), Text(body!, style: context.type.bodyM.copyWith(color: context.palette.muted), textAlign: TextAlign.center)],
        if (action != null) ...[const SizedBox(height: ArivoSpace.s4), ArivoButton(action!, kind: ButtonKind.tonal, onPressed: onAction)],
      ]),
    );
  }
}

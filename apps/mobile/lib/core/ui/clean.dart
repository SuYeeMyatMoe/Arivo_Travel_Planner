import 'package:flutter/material.dart';

import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';
import 'primitives.dart';

/// Building blocks of the "Clean Blue" screens: photo tiles, selectable cards, the setup-step scaffold,
/// settings rows. Keep screens composed from these so every page reads the same.

/// Icon for a place / itinerary category (OSM-style keys from the backend).
IconData categoryIcon(String category) => switch (category) {
      'restaurant' || 'food_court' || 'fast_food' || 'meal' => Icons.restaurant_rounded,
      'cafe' => Icons.local_cafe_rounded,
      'bar' || 'pub' || 'nightclub' => Icons.nightlife_rounded,
      'market' || 'shopping' => Icons.storefront_rounded,
      'museum' || 'gallery' => Icons.museum_rounded,
      'temple' || 'shrine' || 'mosque' => Icons.temple_buddhist_rounded,
      'park' || 'garden' => Icons.park_rounded,
      'viewpoint' => Icons.landscape_rounded,
      'hotel' || 'hostel' || 'guest_house' || 'stay' || 'lodging' => Icons.hotel_rounded,
      'flight' || 'airport' => Icons.flight_rounded,
      'transfer' || 'rail' || 'train' || 'bus' => Icons.train_rounded,
      'theme_park' || 'zoo' || 'aquarium' => Icons.attractions_rounded,
      _ => Icons.place_rounded,
    };

/// Network photo with a calm gradient fallback (offline, blocked, or no photo at all).
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.url, {super.key, this.height, this.width, this.radius = 0, this.fit = BoxFit.cover, this.icon = Icons.landscape_outlined});
  final String? url;
  final double? height, width;
  final double radius;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [p.voltSoft, p.sunken], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Center(child: Icon(icon, color: p.volt.withValues(alpha: 0.5), size: 28)),
    );
    final img = url == null
        ? fallback
        : Image.network(
            url!,
            height: height,
            width: width,
            fit: fit,
            errorBuilder: (_, _, _) => fallback,
            frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : fallback,
          );
    return radius == 0 ? img : ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

/// Photo with a label in the corner and an optional check badge (interests, destinations).
class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.photo, required this.label, this.selected = false, this.onTap, this.badge, this.dimmed = false});
  final String? photo;
  final String label;
  final bool selected, dimmed;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: ArivoMotion.fast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ArivoRadius.m),
            border: Border.all(color: selected ? p.volt : Colors.transparent, width: 2.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ArivoRadius.m - 2),
            child: Stack(fit: StackFit.expand, children: [
              Opacity(opacity: dimmed ? 0.55 : 1, child: NetPhoto(photo)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x99000000)]),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.label.copyWith(color: Colors.white, fontSize: 14)),
              ),
              if (badge != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(ArivoRadius.pill)),
                    child: Text(badge!, style: t.caption.copyWith(fontSize: 10, color: p.text, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: p.volt, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bordered choice card: icon · title · subtitle, blue ring + dot when selected.
class SelectCard extends StatelessWidget {
  const SelectCard({super.key, required this.icon, required this.title, this.subtitle, this.selected = false, this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.voltSoft : p.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArivoRadius.m),
          side: BorderSide(color: selected ? p.volt : p.line, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4, vertical: ArivoSpace.s4),
            child: Row(children: [
              Icon(icon, color: selected ? p.volt : p.muted, size: 26),
              const SizedBox(width: ArivoSpace.s4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.titleM.copyWith(fontSize: 16)),
                  if (subtitle != null) Text(subtitle!, style: t.caption),
                ]),
              ),
              ?trailing,
              if (trailing == null)
                AnimatedOpacity(
                  duration: ArivoMotion.fast,
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: p.volt, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One setup step: back arrow, big title, subtitle, scrollable body, sticky blue "Next".
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.onNext,
    this.nextLabel = 'Next',
    this.busy = false,
    this.step,
    this.steps,
    this.onBack,
    this.footer,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool busy;
  final int? step, steps;
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: onBack != null || canPop
            ? IconButton(
                tooltip: 'Back',
                icon: Icon(Icons.arrow_back_rounded, color: p.volt),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null,
        title: step != null && steps != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: step! / steps!, minHeight: 5, semanticsLabel: 'Step $step of $steps'),
              )
            : null,
        titleSpacing: 0,
        actions: const [SizedBox(width: 56)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, ArivoSpace.s2, ArivoSpace.s5, ArivoSpace.s5), children: [
                  Text(title, style: t.displayL),
                  if (subtitle != null) ...[
                    const SizedBox(height: ArivoSpace.s2),
                    Text(subtitle!, style: t.bodyM.copyWith(color: p.muted)),
                  ],
                  const SizedBox(height: ArivoSpace.s5),
                  ...children,
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(ArivoSpace.s5, ArivoSpace.s2, ArivoSpace.s5, ArivoSpace.s4),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ArivoButton(nextLabel, expand: true, busy: busy, onPressed: onNext),
                  ?footer,
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Popular destinations" + optional "See all" link.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: ArivoSpace.s3),
      child: Row(children: [
        Expanded(child: Text(title, style: t.titleM.copyWith(fontWeight: FontWeight.w700))),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!, style: t.label.copyWith(color: context.palette.voltText))),
      ]),
    );
  }
}

/// White card with a hairline border; tappable when [onTap] is set.
class CleanCard extends StatelessWidget {
  const CleanCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(ArivoSpace.s4), this.shadow = false});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(ArivoRadius.m), boxShadow: shadow ? ArivoElevation.raised : null),
      child: Material(
        color: p.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ArivoRadius.m), side: BorderSide(color: p.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Pale rounded square holding an icon (quick actions, settings rows).
class IconWell extends StatelessWidget {
  const IconWell(this.icon, {super.key, this.size = 44, this.color, this.background});
  final IconData icon;
  final double size;
  final Color? color, background;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? p.voltSoft, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: color ?? p.volt, size: size * 0.5),
    );
  }
}

/// Settings list row: icon · title · value · chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.icon, required this.title, this.value, this.onTap, this.danger = false, this.trailing});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final color = danger ? p.emberText : p.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: ArivoSpace.s1),
        child: Row(children: [
          Icon(icon, size: 22, color: danger ? p.emberText : p.muted),
          const SizedBox(width: ArivoSpace.s4),
          Expanded(child: Text(title, style: t.bodyL.copyWith(color: color, fontWeight: FontWeight.w500))),
          if (value != null) Text(value!, style: t.bodyM.copyWith(color: p.muted)),
          if (trailing != null)
            trailing!
          else if (!danger && onTap != null) ...[
            const SizedBox(width: ArivoSpace.s2),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ]),
      ),
    );
  }
}

/// Soft coloured pill with an icon ("Beautiful beaches", "Budget friendly").
class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.voltText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(ArivoRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(label, style: context.type.caption.copyWith(color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Simple modal-less page header used by pushed screens that want a big title under the app bar.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: ArivoSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: context.type.displayM),
          if (subtitle != null) Text(subtitle!, style: context.type.bodyM.copyWith(color: context.palette.muted)),
        ]),
      );
}

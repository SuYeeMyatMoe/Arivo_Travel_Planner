import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ari/ari.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../guide/guide_sheet.dart';

/// Four areas — Explore · Trip · Live · You — with Ari always one tap away.
/// Live is ink (you're in the trip); the others are paper (planning).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = shell.currentIndex == 2;
    return Theme(
      data: ink ? ArivoTheme.ink() : ArivoTheme.paper(),
      child: Builder(builder: (context) {
        return Scaffold(
          body: shell,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
            child: GuideFab(
              onTap: () => showGuideSheet(context),
              onLongPress: () => showGuideSheet(context, startListening: true),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
              NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Trip'),
              NavigationDestination(icon: Icon(Icons.radio_button_checked_outlined), selectedIcon: Icon(Icons.radio_button_checked), label: 'Live'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'You'),
            ],
          ),
        );
      }),
    );
  }
}

/// Wraps a paper screen body in the same max width on tablets/web so it never stretches edge to edge.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
      );
}

extension PaletteShortcut on BuildContext {
  ArivoPalette get p => palette;
}

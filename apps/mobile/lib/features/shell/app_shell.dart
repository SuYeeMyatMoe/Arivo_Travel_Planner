import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ari/ari.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../guide/guide_sheet.dart';

/// Five areas — Home · Trips · Explore · Saved · Profile — with Ari always one tap away.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      body: shell,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: ArivoSpace.s2),
        child: GuideFab(
          onTap: () => showGuideSheet(context),
          onLongPress: () => showGuideSheet(context, startListening: true),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.luggage_outlined), selectedIcon: Icon(Icons.luggage_rounded), label: 'Trips'),
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Explore'),
            NavigationDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Saved'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

/// Wraps a screen body in the same max width on tablets/web so it never stretches edge to edge.
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

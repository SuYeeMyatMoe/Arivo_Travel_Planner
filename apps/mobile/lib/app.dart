import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/arivo_theme.dart';
import 'features/book/book_screens.dart';
import 'features/crew/crew_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/lens/receipt_lens_screen.dart';
import 'features/live/live_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/trip/trip_screen.dart';
import 'features/you/you_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/trip', builder: (_, _) => const TripScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/live', builder: (_, _) => const LiveScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/you', builder: (_, _) => const YouScreen())]),
        ],
      ),
      GoRoute(parentNavigatorKey: _rootKey, path: '/book/:kind', builder: (_, s) => BookScreen(kind: s.pathParameters['kind']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/checkout/:txn', builder: (_, s) => CheckoutScreen(txnId: s.pathParameters['txn']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/booked/:txn', builder: (_, s) => BookingSuccessScreen(txnId: s.pathParameters['txn']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/crew', builder: (_, _) => const CrewScreen()),
      GoRoute(parentNavigatorKey: _rootKey, path: '/lens/receipt', builder: (_, _) => const ReceiptLensScreen()),
    ],
  );
});

class ArivoApp extends ConsumerWidget {
  const ArivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Arivo',
      debugShowCheckedModeBanner: false,
      theme: ArivoTheme.paper(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

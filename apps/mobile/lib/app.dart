import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/arivo_theme.dart';
import 'features/book/book_screens.dart';
import 'features/budget/budget_screen.dart';
import 'features/crew/crew_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lens/receipt_lens_screen.dart';
import 'features/live/live_screen.dart';
import 'features/packing/packing_screen.dart';
import 'features/places/place_screens.dart';
import 'features/setup/setup_screens.dart';
import 'features/shell/app_shell.dart';
import 'features/trip/trip_screen.dart';
import 'features/trips/trips_screens.dart';
import 'features/welcome/welcome_screens.dart';
import 'features/you/you_screen.dart';
import 'state/session.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Screens you can see without an account.
const _public = {'/welcome', '/welcome/intro', '/signin', '/signup'};

/// Older paths (links inside screens, deep links) → where they live now.
const _aliases = {'/': '/home', '/trip': '/trips/overview', '/you': '/profile', '/start': '/setup/where', '/activities': '/explore'};

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when the session changes (sign in/out) without rebuilding the router.
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(parentNavigatorKey: _rootKey, path: path, builder: (_, s) => build(s));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final alias = _aliases[loc];
      if (alias != null) return alias;
      final s = ref.read(sessionProvider);
      if (_public.contains(loc)) return s.signedIn ? '/home' : null;
      if (!s.signedIn) return s.onboardingSeen ? '/signin' : '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/welcome/intro', builder: (_, _) => const IntroScreen()),
      GoRoute(path: '/signin', builder: (_, _) => const AuthScreen(signUp: false)),
      GoRoute(path: '/signup', builder: (_, _) => const AuthScreen(signUp: true)),
      GoRoute(path: '/setup/interests', builder: (_, _) => const InterestsStep()),
      GoRoute(path: '/setup/budget', builder: (_, _) => const BudgetStep()),
      GoRoute(path: '/setup/where', builder: (_, _) => const WhereStep()),
      GoRoute(path: '/setup/when', builder: (_, _) => const WhenStep()),
      GoRoute(path: '/setup/who', builder: (_, _) => const WhoStep()),
      GoRoute(path: '/setup/generate', builder: (_, _) => const GenerateScreen()),
      GoRoute(path: '/setup/ready', builder: (_, _) => const ReadyScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/trips', builder: (_, _) => const TripsScreen(), routes: [
              GoRoute(path: 'overview', builder: (_, _) => const TripOverviewScreen(), routes: [
                GoRoute(path: 'day', builder: (_, _) => const ItineraryScreen()),
              ]),
            ]),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/saved', builder: (_, _) => const SavedScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      page('/map', (_) => const MapScreen()),
      page('/budget', (_) => const BudgetScreen()),
      page('/packing', (_) => const PackingScreen()),
      page('/live', (_) => const LiveScreen()),
      page('/place/:id', (s) => PlaceDetailsScreen(placeId: s.pathParameters['id']!)),
      page('/bookings', (_) => const BookingsPage()),
      page('/profile/preferences', (_) => const PreferencesPage()),
      page('/profile/privacy', (_) => const PrivacyPage()),
      page('/profile/about', (_) => const AboutPage()),
      page('/book/:kind', (s) => BookScreen(kind: s.pathParameters['kind']!)),
      page('/checkout/:txn', (s) => CheckoutScreen(txnId: s.pathParameters['txn']!)),
      page('/booked/:txn', (s) => BookingSuccessScreen(txnId: s.pathParameters['txn']!)),
      page('/crew', (_) => const CrewScreen()),
      page('/lens/receipt', (_) => const ReceiptLensScreen()),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../camera_explorer/camera_explorer_screen.dart';
import '../memories/memories_screen.dart';
import '../friends/friends_screen.dart';
import '../sharing/shared_walks.dart';
import '../accounts/account_library_screens.dart';
import '../just_walking/just_walking_screen.dart';
import '../active_roam/active_roam_controller.dart';
import '../preferences/preferences_controller.dart';
import '../on_device_ai/rover_ai_diagnostics_screen.dart';
import '../shell/rover_shell.dart';
import '../ui/placeholder_screens.dart';

GoRouter createRoverRouter(
  PreferencesController preferencesController, {
  String initialLocation = '/welcome',
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  final planNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'plan');
  final routesNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'routes');
  final roamsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'roams');
  final profileNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: preferencesController,
    errorBuilder: (context, state) {
      final error = state.error;
      if (error is GoException) {
        return RoverNotFoundScreen(error: error);
      }

      return RoverErrorScreen(error: error);
    },
    routes: [
      GoRoute(
        path: '/shared-walks',
        builder: (context, state) => const SharedWalksScreen(),
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsScreen(),
      ),
      GoRoute(
        path: '/invite',
        builder: (context, state) =>
            FriendsScreen(invitation: state.uri.queryParameters['code']),
      ),
      GoRoute(
        path: '/memories',
        builder: (context, state) => const MemoriesScreen(),
      ),
      GoRoute(path: '/explore', redirect: (context, state) => '/home'),
      GoRoute(
        path: '/roams',
        redirect: (context, state) => '/profile/saved-walks',
      ),
      GoRoute(
        path: '/roams/history',
        redirect: (context, state) => '/profile/history',
      ),
      GoRoute(
        path: '/roams/saved-discoveries',
        redirect: (context, state) => '/profile/saved-discoveries',
      ),
      GoRoute(
        path: '/just-walking',
        builder: (context, state) => const JustWalkingScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        redirect: (context, state) =>
            preferencesController.preferences.completedOnboarding
            ? '/home'
            : null,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/camera-explorer',
        name: 'camera-explorer',
        builder: (context, state) => const CameraExplorerScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/account',
        name: 'account',
        builder: (context, state) => const WalkaboutAccountScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'account-create',
            builder: (context, state) => const WalkaboutAccountScreen(),
          ),
          GoRoute(
            path: 'sign-in',
            name: 'account-sign-in',
            builder: (context, state) => const WalkaboutAccountScreen(),
          ),
          GoRoute(
            path: 'verify-email',
            name: 'account-verify-email',
            builder: (context, state) => const WalkaboutAccountScreen(),
          ),
          GoRoute(
            path: 'forgot-password',
            name: 'account-forgot-password',
            builder: (context, state) => const WalkaboutAccountScreen(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return WalkaboutJourneyHost(
            child: RoverShell(navigationShell: navigationShell),
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const WalkaboutWalkScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const HomeScreen(),
                  ),
                  GoRoute(
                    path: 'adventure-request',
                    name: 'adventure-request',
                    builder: (context, state) => const AdventureRequestScreen(),
                  ),
                  GoRoute(
                    path: 'route-preview',
                    name: 'route-preview',
                    redirect: (context, state) {
                      final session = ActiveRoamScope.of(context).session;
                      return session.apiWalkSessionId == null ||
                              session.roam.stops.isEmpty
                          ? '/home'
                          : null;
                    },
                    builder: (context, state) => const RoutePreviewScreen(),
                  ),
                  GoRoute(
                    path: 'active-roam',
                    name: 'active-roam',
                    builder: (context, state) => const WalkaboutWalkScreen(),
                  ),
                  GoRoute(
                    path: 'stop-details',
                    name: 'stop-details',
                    builder: (context, state) => const StopDetailsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: planNavigatorKey,
            routes: [
              GoRoute(
                path: '/plan',
                builder: (context, state) => const WalkaboutPlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: roamsNavigatorKey,
            routes: [
              GoRoute(
                path: '/stories',
                builder: (context, state) => const WalkaboutStoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: routesNavigatorKey,
            routes: [
              GoRoute(
                path: '/routes',
                builder: (context, state) => const WalkaboutRoutesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'stops',
                    builder: (context, state) =>
                        const WalkaboutStopListScreen(),
                    routes: [
                      GoRoute(
                        path: ':stopId',
                        builder: (context, state) => WalkaboutStopScreen(
                          stopId: state.pathParameters['stopId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const WalkHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'saved-discoveries',
                    builder: (context, state) => const SavedDiscoveriesScreen(),
                  ),
                  GoRoute(
                    path: 'saved-walks',
                    builder: (context, state) =>
                        const PersonalLibraryScreen(kind: 'walks'),
                  ),
                  GoRoute(
                    path: 'walking-profiles',
                    builder: (context, state) =>
                        const PersonalLibraryScreen(kind: 'profiles'),
                  ),
                  GoRoute(
                    path: 'settings',
                    name: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'beta-diagnostics',
                        name: 'beta-diagnostics',
                        builder: (context, state) =>
                            const BetaDiagnosticsScreen(),
                      ),
                      GoRoute(
                        path: 'report-problem',
                        name: 'report-problem',
                        builder: (context, state) =>
                            const ReportProblemScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'account',
                    name: 'account-settings',
                    builder: (context, state) => const WalkaboutAccountScreen(),
                  ),
                  GoRoute(
                    path: 'voice-test',
                    name: 'voice-test',
                    builder: (context, state) => const VoiceTestScreen(),
                  ),
                  GoRoute(
                    path: 'on-device-ai',
                    name: 'on-device-ai-diagnostics',
                    builder: (context, state) =>
                        const RoverAiDiagnosticsScreen(),
                  ),
                  GoRoute(
                    path: 'walk-feedback',
                    name: 'walk-feedback',
                    builder: (context, state) => const PostWalkFeedbackScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

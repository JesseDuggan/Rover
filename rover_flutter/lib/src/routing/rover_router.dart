import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../camera_explorer/camera_explorer_screen.dart';
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
  final exploreNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'explore');
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
        path: '/welcome',
        name: 'welcome',
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
        builder: (context, state) => const AccountChoiceScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'account-create',
            builder: (context, state) => const CreateAccountScreen(),
          ),
          GoRoute(
            path: 'sign-in',
            name: 'account-sign-in',
            builder: (context, state) => const SignInScreen(),
          ),
          GoRoute(
            path: 'verify-email',
            name: 'account-verify-email',
            builder: (context, state) => const VerifyEmailScreen(),
          ),
          GoRoute(
            path: 'forgot-password',
            name: 'account-forgot-password',
            builder: (context, state) => const ForgotPasswordScreen(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return RoverShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'adventure-request',
                    name: 'adventure-request',
                    builder: (context, state) => const AdventureRequestScreen(),
                  ),
                  GoRoute(
                    path: 'route-preview',
                    name: 'route-preview',
                    builder: (context, state) => const RoutePreviewScreen(),
                  ),
                  GoRoute(
                    path: 'active-roam',
                    name: 'active-roam',
                    builder: (context, state) => const ActiveRoamScreen(),
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
            navigatorKey: exploreNavigatorKey,
            routes: [
              GoRoute(
                path: '/explore',
                name: 'explore',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: roamsNavigatorKey,
            routes: [
              GoRoute(
                path: '/roams',
                name: 'saved-roams',
                builder: (context, state) => const SavedRoamsScreen(),
                routes: [
                  GoRoute(
                    path: 'history',
                    name: 'walk-history',
                    builder: (context, state) => const WalkHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'saved-discoveries',
                    name: 'saved-discoveries',
                    builder: (context, state) => const SavedDiscoveriesScreen(),
                  ),
                ],
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
                    builder: (context, state) => const AccountSettingsScreen(),
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

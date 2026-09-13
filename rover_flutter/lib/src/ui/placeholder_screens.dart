import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../adaptive_stories/adaptive_route_story_controller.dart';
import '../adaptive_stories/rover_phase16_flags.dart';
import '../adaptive_stories/route_story_question_dialog.dart';
import '../adventure/adventure_request.dart';
import '../adventure/adventure_request_controller.dart';
import '../adventure/roam.dart';
import '../api/adaptation_models.dart';
import '../api/beta_models.dart';
import '../api/local_discovery_options.dart';
import '../api/location_story_models.dart';
import '../api/offline_problem_report_queue.dart';
import '../api/problem_details.dart';
import '../api/profile_models.dart';
import '../api/rover_api_client.dart';
import '../api/walk_repository.dart';
import '../diagnostics/field_diagnostics.dart';
import '../diagnostics/performance_diagnostics.dart';
import '../location/location_controller.dart';
import '../location/rover_location.dart';
import '../maps/rover_map_view.dart';
import '../maps/rover_map_provider.dart';
import '../on_device_ai/rover_on_device_ai_scope.dart';
import '../preferences/preferences_controller.dart';
import '../preferences/rover_preferences.dart';
import '../profile/installation_id_repository.dart';
import '../voice/rover_premium_voice.dart';
import '../voice/rover_voice_controller.dart';
import '../voice/rover_voice_state.dart';

const _phase15Enabled = bool.fromEnvironment(
  'ROVER_PHASE15_ENABLED',
  defaultValue: false,
);

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'ROVER',
      subtitle: 'You bring the time. ROVER creates the adventure.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/onboarding'),
          child: const Text('Get Started'),
        ),
        TextButton(
          onPressed: () async {
            await PreferencesScope.of(context).continueAsGuest();
            if (context.mounted) {
              context.go('/home');
            }
          },
          child: const Text('Continue as Guest'),
        ),
      ],
      child: const RileyPlaceholder(),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class AccountChoiceScreen extends StatelessWidget {
  const AccountChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'ROVER account',
      subtitle: 'Save your walks, discoveries, and preferences across devices.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/account/create'),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Create account'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/account/sign-in'),
          icon: const Icon(Icons.login),
          label: const Text('Sign in'),
        ),
        TextButton(
          onPressed: () async {
            await PreferencesScope.of(context).continueAsGuest();
            if (context.mounted) {
              context.go('/home');
            }
          },
          child: const Text('Continue as guest'),
        ),
      ],
      child: const PlaceholderPanel(
        icon: Icons.cloud_sync_outlined,
        label: 'Account sync is ready for Cognito staging configuration.',
      ),
    );
  }
}

class CreateAccountScreen extends StatelessWidget {
  const CreateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Create account',
      subtitle: 'Use Cognito PKCE in staging to preserve guest Rover data.',
      primaryLabel: 'Continue to email verification',
      primaryIcon: Icons.mark_email_read_outlined,
      onPrimary: () => context.go('/account/verify-email'),
      secondaryLabel: 'Already have an account?',
      onSecondary: () => context.go('/account/sign-in'),
    );
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Sign in',
      subtitle: 'Restore saved walks, discoveries, and preferences.',
      primaryLabel: 'Sign in',
      primaryIcon: Icons.login,
      onPrimary: () => context.go('/profile/account'),
      secondaryLabel: 'Forgot password?',
      onSecondary: () => context.go('/account/forgot-password'),
    );
  }
}

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Verify email',
      subtitle: 'Enter the verification code from Cognito staging.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/profile/account'),
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Confirm'),
        ),
      ],
      child: const TextField(
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Verification code'),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Forgot password',
      subtitle: 'Cognito staging will send a password reset email.',
      primaryLabel: 'Send reset email',
      primaryIcon: Icons.lock_reset,
      onPrimary: () => context.go('/account/sign-in'),
      secondaryLabel: 'Back to sign in',
      onSecondary: () => context.go('/account/sign-in'),
    );
  }
}

class _AccountFormScaffold extends StatelessWidget {
  const _AccountFormScaffold({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: title,
      subtitle: subtitle,
      actions: [
        FilledButton.icon(
          onPressed: onPrimary,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
        TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
      ],
      child: const Column(
        children: [
          TextField(
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email'),
          ),
          SizedBox(height: 12),
          TextField(
            obscureText: true,
            decoration: InputDecoration(labelText: 'Password'),
          ),
        ],
      ),
    );
  }
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _firstNameController = TextEditingController();
  final _mobilityController = TextEditingController();

  late Set<String> _interests;
  late String _walkingPace;
  late String _availableTime;
  late String _contentDepth;
  late String _storyDensity;
  late String _audioPreference;
  late String _notifications;
  late String _distanceUnit;
  late String _language;

  int _step = 0;
  bool _seeded = false;

  static const _interestOptions = [
    'history',
    'food',
    'architecture',
    'nature',
    'art',
    'movies',
    'current events',
    'hidden gems',
    'culture',
    'notable people',
    'film and television',
    'unusual facts',
    'events',
    'weather',
  ];
  static const _paceOptions = ['easy', 'steady', 'brisk'];
  static const _timeOptions = [
    '30 minutes',
    '60 minutes',
    '90 minutes',
    '2+ hours',
  ];
  static const _depthOptions = ['quick highlights', 'deeper stories'];
  static const _storyDensityOptions = ['Quiet', 'Highlights', 'Story-Rich'];
  static const _audioOptions = ['prefer audio', 'text is fine'];
  static const _notificationOptions = ['helpful nudges', 'quiet mode'];
  static const _distanceOptions = ['miles', 'kilometers'];
  static const _languageOptions = ['English', 'Spanish', 'French'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }

    final preferences = PreferencesScope.of(context).preferences;
    _firstNameController.text = preferences.firstName;
    _mobilityController.text = preferences.mobility;
    _interests = preferences.interests.toSet();
    _walkingPace = preferences.walkingPace;
    _availableTime = preferences.availableTime;
    _contentDepth = preferences.contentDepth;
    _storyDensity = preferences.storyDensity;
    _audioPreference = preferences.audioPreference;
    _notifications = preferences.notifications;
    _distanceUnit = preferences.distanceUnit;
    _language = preferences.language;
    _seeded = true;
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _OnboardingStep(
        title: 'What should Riley call you?',
        subtitle:
            'A first name helps ROVER make the adventure feel like yours.',
        child: TextField(
          controller: _firstNameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'First name',
            helperText: 'Optional',
          ),
        ),
      ),
      _OnboardingStep(
        title: 'What catches your eye?',
        subtitle: 'Pick any mix. Riley will use these as hints, not homework.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final interest in _interestOptions)
              FilterChip(
                label: Text(interest),
                selected: _interests.contains(interest),
                onSelected: (selected) {
                  setState(() {
                    selected
                        ? _interests.add(interest)
                        : _interests.remove(interest);
                  });
                },
              ),
          ],
        ),
      ),
      _OnboardingStep(
        title: 'How should the day move?',
        subtitle:
            'Choose what you know. Anything can be skipped and edited later.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChoiceGroup(
              label: 'Preferred walking pace',
              value: _walkingPace,
              options: _paceOptions,
              onChanged: (value) => setState(() => _walkingPace = value),
            ),
            const SizedBox(height: 20),
            _ChoiceGroup(
              label: 'Typical available time',
              value: _availableTime,
              options: _timeOptions,
              onChanged: (value) => setState(() => _availableTime = value),
            ),
          ],
        ),
      ),
      _OnboardingStep(
        title: 'Anything Riley should plan around?',
        subtitle: 'Share mobility or accessibility notes in your own words, or skip for now.',
        child: TextField(
          controller: _mobilityController,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Accessibility and mobility considerations',
            helperText: 'Optional',
            alignLabelWithHint: true,
          ),
        ),
      ),
      _OnboardingStep(
        title: 'How should ROVER tell the story?',
        subtitle: 'A few preference switches keep future ROAMs tuned to you.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChoiceGroup(
              label: 'Content depth',
              value: _contentDepth,
              options: _depthOptions,
              onChanged: (value) => setState(() => _contentDepth = value),
            ),
            const SizedBox(height: 20),
            if (_phase15Enabled) ...[
              _ChoiceGroup(
                label: 'Story frequency',
                value: _storyDensity,
                options: _storyDensityOptions,
                onChanged: (value) => setState(() => _storyDensity = value),
              ),
              const SizedBox(height: 20),
            ],
            _ChoiceGroup(
              label: 'Audio preference',
              value: _audioPreference,
              options: _audioOptions,
              onChanged: (value) => setState(() => _audioPreference = value),
            ),
          ],
        ),
      ),
      _OnboardingStep(
        title: 'Last little trail markers',
        subtitle: 'Rover uses your location to guide your walk and recognize when you arrive at each stop.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChoiceGroup(
              label: 'Notification preference',
              value: _notifications,
              options: _notificationOptions,
              onChanged: (value) => setState(() => _notifications = value),
            ),
            const SizedBox(height: 20),
            _ChoiceGroup(
              label: 'Distance units',
              value: _distanceUnit,
              options: _distanceOptions,
              onChanged: (value) => setState(() => _distanceUnit = value),
            ),
            const SizedBox(height: 20),
            _ChoiceGroup(
              label: 'Language',
              value: _language,
              options: _languageOptions,
              onChanged: (value) => setState(() => _language = value),
            ),
          ],
        ),
      ),
    ];

    final current = steps[_step];
    final isLast = _step == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riley setup'),
        actions: [TextButton(onPressed: _finish, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Semantics(
              label: 'Onboarding progress',
              value: 'Step ${_step + 1} of ${steps.length}',
              child: LinearProgressIndicator(value: (_step + 1) / steps.length),
            ),
            const SizedBox(height: 24),
            Text(
              current.title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              current.subtitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            current.child,
            const SizedBox(height: 32),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step -= 1),
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: isLast
                        ? _finish
                        : () => setState(() => _step += 1),
                    child: Text(isLast ? 'Save preferences' : 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    final preferences = RoverPreferences(
      firstName: _firstNameController.text.trim(),
      interests: _interests.toList()..sort(),
      walkingPace: _walkingPace,
      availableTime: _availableTime,
      mobility: _mobilityController.text.trim(),
      contentDepth: _contentDepth,
      storyDensity: _storyDensity,
      audioPreference: _audioPreference,
      notifications: _notifications,
      distanceUnit: _distanceUnit,
      language: _language,
      completedOnboarding: true,
    );

    await PreferencesScope.of(context).save(preferences);
    if (mounted) {
      context.go('/profile/settings');
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _mobilityController.dispose();
    super.dispose();
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option),
                  selected: value == option,
                  onSelected: (_) => onChanged(value == option ? '' : option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DestinationScaffold(
      title: 'Home',
      subtitle: 'What do you want to do?',
      children: [
        Text(
          'I have 90 minutes. Take me for a walk.',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Tell Riley the shape of your day and ROVER will mock up a starter adventure.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.timer_outlined),
              label: const Text('I have 30 minutes'),
              onPressed: () => context.go('/home/adventure-request?minutes=30'),
            ),
            ActionChip(
              avatar: const Icon(Icons.timer_outlined),
              label: const Text('I have 60 minutes'),
              onPressed: () => context.go('/home/adventure-request?minutes=60'),
            ),
            ActionChip(
              avatar: const Icon(Icons.timer_outlined),
              label: const Text('I have 90 minutes'),
              onPressed: () => context.go('/home/adventure-request?minutes=90'),
            ),
            ActionChip(
              avatar: const Icon(Icons.near_me_outlined),
              label: const Text('Show me what\'s nearby'),
              onPressed: () =>
                  context.go('/home/adventure-request?nearby=true'),
            ),
            ActionChip(
              avatar: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Surprise me'),
              onPressed: () =>
                  context.go('/home/adventure-request?surprise=true'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FeatureCard(
          title: 'Build an adventure request',
          subtitle: 'Set time, starting point, route style, and mood.',
          icon: Icons.add_location_alt_outlined,
          onTap: () => context.go('/home/adventure-request'),
        ),
        FeatureCard(
          title: 'Route preview',
          subtitle: 'Review a sample route before starting.',
          icon: Icons.map_outlined,
          onTap: () => context.go('/home/route-preview'),
        ),
        FeatureCard(
          title: 'Active ROAM',
          subtitle: 'Resume today\'s placeholder adventure.',
          icon: Icons.near_me_outlined,
          onTap: () => context.go('/home/active-roam'),
        ),
      ],
    );
  }
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DestinationScaffold(
      title: 'Explore',
      subtitle: 'Browse sample ideas for future ROVER adventures.',
      children: [
        FeatureCard(
          title: 'Camera Explorer',
          subtitle: 'Raise your phone and let Rover describe nearby places.',
          icon: Icons.photo_camera_outlined,
          onTap: () => context.push('/camera-explorer'),
        ),
        const PlaceholderPanel(
          icon: Icons.coffee_outlined,
          label: 'Cozy cafe crawl',
        ),
        const PlaceholderPanel(
          icon: Icons.palette_outlined,
          label: 'Tiny gallery loop',
        ),
        const PlaceholderPanel(
          icon: Icons.park_outlined,
          label: 'Fresh-air reset',
        ),
      ],
    );
  }
}

class AdventureRequestScreen extends StatefulWidget {
  const AdventureRequestScreen({super.key});

  @override
  State<AdventureRequestScreen> createState() => _AdventureRequestScreenState();
}

class _AdventureRequestScreenState extends State<AdventureRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _minutesController = TextEditingController();
  final _naturalRequestController = TextEditingController();

  late Set<String> _interests;
  late String _routeMode;
  late String _pace;
  late String _routeShape;
  late String _companions;
  late String _environment;
  late String _budget;
  late bool _surpriseMe;
  bool _seeded = false;

  static const _interestOptions = [
    'history',
    'food',
    'architecture',
    'nature',
    'art',
    'movies',
    'current events',
    'hidden gems',
  ];
  static const _routeModes = ['Walking', 'Accessible route'];
  static const _paces = ['Easy', 'Steady', 'Brisk'];
  static const _routeShapes = ['Loop route', 'Different destination'];
  static const _companionOptions = ['Solo', 'Couple', 'Family', 'Group'];
  static const _environments = ['Indoor', 'Outdoor', 'Either'];
  static const _budgets = ['Free-only', 'Include paid attractions'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }

    final saved = AdventureRequestScope.of(context).request;
    final preferences = PreferencesScope.of(context).preferences;
    final request = saved ?? _requestFromPreferences(preferences);
    final uri = GoRouterState.of(context).uri;
    final minutes = uri.queryParameters['minutes'];
    final cameraPlace = uri.queryParameters['cameraPlace']?.trim();

    _minutesController.text = minutes ?? request.availableMinutes.toString();
    _naturalRequestController.text = cameraPlace == null || cameraPlace.isEmpty
        ? request.naturalRequest
        : 'I have ${minutes ?? request.availableMinutes} minutes. Build a walk that visits $cameraPlace.';
    _interests = {
      ...request.interests,
      if (cameraPlace != null && cameraPlace.isNotEmpty) 'hidden gems',
    };
    _routeMode = request.routeMode;
    _pace = request.pace;
    _routeShape = request.routeShape;
    _companions = request.companions;
    _environment = request.environment;
    _budget = request.budget;
    _surpriseMe = uri.queryParameters['surprise'] == 'true'
        ? true
        : request.surpriseMe;
    _seeded = true;
  }

  AdventureRequest _requestFromPreferences(RoverPreferences preferences) {
    final minutes = _minutesFromPreference(preferences.availableTime);
    final interests =
        preferences.interests
            .map((interest) => interest.trim().toLowerCase())
            .where((interest) => interest.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final mobility = preferences.mobility.trim();

    return AdventureRequest.empty.copyWith(
      availableMinutes: minutes,
      routeMode: _routeModeFromPreference(mobility),
      interests: interests,
      pace: _paceFromPreference(preferences.walkingPace),
      budget: preferences.contentDepth.toLowerCase().contains('paid')
          ? 'Include paid attractions'
          : AdventureRequest.empty.budget,
      naturalRequest: interests.isEmpty
          ? 'I have $minutes minutes. Take me for a walk.'
          : 'I have $minutes minutes. Build a ${interests.join(', ')} walk.',
    );
  }

  int _minutesFromPreference(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) {
      return AdventureRequest.empty.availableMinutes;
    }

    final parsed = int.tryParse(match.group(0)!);
    if (parsed == null) {
      return AdventureRequest.empty.availableMinutes;
    }

    return value.toLowerCase().contains('hour') ? parsed * 60 : parsed;
  }

  String _paceFromPreference(String value) {
    return switch (value.toLowerCase()) {
      'easy' => 'Easy',
      'brisk' => 'Brisk',
      'steady' => 'Steady',
      _ => AdventureRequest.empty.pace,
    };
  }

  String _routeModeFromPreference(String mobility) {
    final value = mobility.toLowerCase();
    if (value.contains('access') ||
        value.contains('wheelchair') ||
        value.contains('stairs') ||
        value.contains('mobility')) {
      return 'Accessible route';
    }

    return AdventureRequest.empty.routeMode;
  }

  @override
  Widget build(BuildContext context) {
    final locationController = LocationScope.of(context);
    final location = locationController.location;
    final failure = locationController.failure;

    return Scaffold(
      appBar: AppBar(title: const Text('Adventure request')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                'What do you want to do?',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Start casual. Riley will build the walk from your current device location.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _naturalRequestController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Natural request',
                  helperText: 'Example: I have 90 minutes. Take me for a walk.',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Available time',
                  suffixText: 'minutes',
                ),
                validator: _validateMinutes,
              ),
              const SizedBox(height: 16),
              _LocationRequestPanel(
                location: location,
                failure: failure,
                isLoading: locationController.isLoading,
                onRetry: _retryDeviceLocation,
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Walking or accessible route',
                value: _routeMode,
                options: _routeModes,
                onChanged: (value) => setState(() => _routeMode = value),
              ),
              const SizedBox(height: 20),
              _InterestPicker(
                interests: _interests,
                options: _interestOptions,
                surpriseMe: _surpriseMe,
                onChanged: (interest, selected) {
                  setState(() {
                    selected
                        ? _interests.add(interest)
                        : _interests.remove(interest);
                  });
                },
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Desired pace',
                value: _pace,
                options: _paces,
                onChanged: (value) => setState(() => _pace = value),
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Route shape',
                value: _routeShape,
                options: _routeShapes,
                onChanged: (value) => setState(() => _routeShape = value),
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Who is roaming?',
                value: _companions,
                options: _companionOptions,
                onChanged: (value) => setState(() => _companions = value),
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Indoor/outdoor preference',
                value: _environment,
                options: _environments,
                onChanged: (value) => setState(() => _environment = value),
              ),
              const SizedBox(height: 20),
              _ChoiceGroup(
                label: 'Attraction budget',
                value: _budget,
                options: _budgets,
                onChanged: (value) => setState(() => _budget = value),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Surprise me'),
                subtitle: const Text(
                  'Let Riley fill in the gaps with playful mock suggestions.',
                ),
                value: _surpriseMe,
                onChanged: (value) => setState(() => _surpriseMe = value),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: locationController.isLoading ? null : _save,
                child: const Text('Create My Walk'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateMinutes(String? value) {
    final minutes = int.tryParse(value?.trim() ?? '');
    if (minutes == null) {
      return 'How many minutes can Riley plan around?';
    }

    final request = AdventureRequest.empty.copyWith(
      availableMinutes: minutes,
      startingPoint: 'check',
      interests: const ['check'],
    );
    final timeMessage = request.validate().where(
      (message) => message.contains('minutes') || message.contains('hours'),
    );

    return timeMessage.isEmpty ? null : timeMessage.first;
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final locationController = LocationScope.of(context);
    final locationResult = await locationController.ensureDeviceLocation();
    if (!mounted) {
      return;
    }
    if (!locationResult.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ROVER needs device location to create this walk.'),
        ),
      );
      return;
    }

    final request = AdventureRequest(
      availableMinutes: int.parse(_minutesController.text.trim()),
      startingPoint: 'Current device location',
      routeMode: _routeMode,
      interests: _interests.toList()..sort(),
      pace: _pace,
      routeShape: _routeShape,
      companions: _companions,
      environment: _environment,
      budget: _budget,
      surpriseMe: _surpriseMe,
      naturalRequest: _naturalRequestController.text.trim(),
    );
    final messages = request.validate();
    if (messages.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(messages.first)));
      return;
    }

    AdventureRequestScope.of(context).save(request);
    context.go('/home/route-preview');
  }

  Future<void> _retryDeviceLocation() async {
    await LocationScope.of(context).ensureDeviceLocation(forceRefresh: true);
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _naturalRequestController.dispose();
    super.dispose();
  }
}

class _LocationRequestPanel extends StatelessWidget {
  const _LocationRequestPanel({
    required this.location,
    required this.failure,
    required this.isLoading,
    required this.onRetry,
  });

  final RoverLatLng? location;
  final LocationFailure? failure;
  final bool isLoading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  location == null
                      ? Icons.location_searching
                      : Icons.location_on,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Starting location',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isLoading
                  ? 'Finding your device location...'
                  : location == null
                  ? 'Device location is required and will be used automatically.'
                  : 'Device location active: $location',
            ),
            if (failure != null) ...[
              const SizedBox(height: 8),
              Text(
                '${failure!.message} ${failure!.recovery}',
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (!isLoading && location == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry device location'),
              ),
            ],
            if (isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _InterestPicker extends StatelessWidget {
  const _InterestPicker({
    required this.interests,
    required this.options,
    required this.surpriseMe,
    required this.onChanged,
  });

  final Set<String> interests;
  final List<String> options;
  final bool surpriseMe;
  final void Function(String interest, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Interests',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Interests', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            surpriseMe
                ? 'Surprise mode can work without interests.'
                : 'Pick at least one interest, or turn on Surprise me.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final interest in options)
                FilterChip(
                  label: Text(interest),
                  selected: interests.contains(interest),
                  onSelected: (selected) => onChanged(interest, selected),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RoutePreviewScreen extends StatefulWidget {
  const RoutePreviewScreen({super.key});

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  final _routeService = const MockRouteGenerationService();
  RoverRoam? _roam;
  AdventureRequest? _request;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final request = AdventureRequestScope.of(context).request;
    if (request != _request) {
      _request = request;
      _roam = request == null ? null : _routeService.generate(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) {
      return DetailScaffold(
        title: 'Route preview',
        subtitle: 'Riley needs an adventure request before making suggestions.',
        actions: [
          FilledButton(
            onPressed: () => context.go('/home/adventure-request'),
            child: const Text('Create request'),
          ),
        ],
        child: const PlaceholderPanel(
          icon: Icons.edit_location_alt_outlined,
          label: 'No adventure request yet',
        ),
      );
    }

    final roam = _roam ?? _routeService.generate(request);
    final location = LocationScope.of(context).location;
    final activeController = ActiveRoamScope.of(context);
    final overBudget = !roam.fitsBudget(request.availableMinutes);

    return DetailScaffold(
      title: 'Route preview',
      subtitle: roam.summary,
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/home/adventure-request'),
          child: const Text('Edit request'),
        ),
        OutlinedButton(onPressed: _refresh, child: const Text('Refresh')),
        OutlinedButton(onPressed: _regenerate, child: const Text('Regenerate')),
        FilledButton(
          onPressed: _isSubmitting
              ? null
              : () => _createMiddlewareWalk(activeController, request),
          child: Text(_isSubmitting ? 'Creating walk...' : 'Create My Walk'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) ...[
            _ErrorPanel(
              message: _errorMessage!,
              onRetry: () => _createMiddlewareWalk(activeController, request),
            ),
            const SizedBox(height: 12),
          ],
          if (_isSubmitting) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          _RoamSummaryCard(
            roam: roam,
            availableMinutes: request.availableMinutes,
          ),
          if (overBudget) ...[
            const SizedBox(height: 12),
            Text(
              'This route is over your time budget. Remove or replace a stop to bring it back in range.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          RoverMapView(
            currentLocation: location,
            orderedStops: roam.orderedStops,
            routeGeometry: roam.routeGeometry,
            height: 340,
          ),
          const SizedBox(height: 16),
          Text('Itinerary', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roam.orderedStops.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final orderedStop = roam.orderedStops[index];
              return _ItineraryStopCard(
                key: ValueKey(orderedStop.stop.id),
                orderedStop: orderedStop,
                onRemove: () => _remove(orderedStop.stop),
                onReplace: () => _replace(orderedStop.stop),
              );
            },
          ),
        ],
      ),
    );
  }

  void _refresh() {
    setState(() {
      _roam = _roam?.copyWith();
    });
  }

  void _regenerate() {
    setState(() {
      final roam = _roam;
      if (roam != null) {
        _roam = _routeService.regenerate(roam);
      }
    });
  }

  void _remove(RoverStop stop) {
    setState(() {
      _roam = _roam?.removeStop(stop.id);
    });
  }

  void _replace(RoverStop stop) {
    setState(() {
      _roam = _roam?.replaceStop(stop.id, _routeService.replacementFor(stop));
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _roam = _roam?.reorderStop(oldIndex, newIndex);
    });
  }

  Future<void> _createMiddlewareWalk(
    ActiveRoamController controller,
    AdventureRequest request,
  ) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final locationController = LocationScope.of(context);
    final locationResult = await locationController.ensureDeviceLocation(
      forceRefresh: true,
    );
    if (!mounted) {
      return;
    }
    final location = locationResult.location;
    if (location == null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'ROVER needs an active device location to create a live walk. '
            'Check Location Services and location permission, then try again.';
      });
      return;
    }

    await controller.createWalk(request: request, location: location);

    if (!mounted) {
      return;
    }

    final error = controller.session.errorMessage;
    setState(() {
      _isSubmitting = false;
      _errorMessage = error;
    });

    if (error == null && controller.session.apiWalkSessionId != null) {
      context.go('/home/active-roam');
    }
  }
}

class _RoamSummaryCard extends StatelessWidget {
  const _RoamSummaryCard({required this.roam, required this.availableMinutes});

  final RoverRoam roam;
  final int availableMinutes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roam.title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(roam.summary),
            const SizedBox(height: 12),
            _PreferenceRow(
              label: 'Total estimated time',
              value:
                  '${roam.totalEstimatedMinutes} of $availableMinutes minutes',
            ),
            _PreferenceRow(
              label: 'Walking time',
              value: '${roam.walkingMinutes} minutes',
            ),
            _PreferenceRow(
              label: 'Content time',
              value: '${roam.contentMinutes} minutes',
            ),
            _PreferenceRow(
              label: 'Distance',
              value: '${roam.distanceMiles.toStringAsFixed(1)} miles',
            ),
            _PreferenceRow(label: 'Starting point', value: roam.startingPoint),
            _PreferenceRow(
              label: 'Accessibility notes',
              value: roam.accessibilityNotes.join(' '),
            ),
            _PreferenceRow(
              label: 'Warnings',
              value: roam.warnings.isEmpty
                  ? 'No weather or closure warnings available.'
                  : roam.warnings.join(' '),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItineraryStopCard extends StatelessWidget {
  const _ItineraryStopCard({
    required this.orderedStop,
    required this.onRemove,
    required this.onReplace,
    super.key,
  });

  final OrderedRoverStop orderedStop;
  final VoidCallback onRemove;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final stop = orderedStop.stop;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Text(orderedStop.sequence.toString())),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${stop.category} - ${stop.estimatedVisitMinutes} min',
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                height: 88,
                width: double.infinity,
                child: Center(
                  child: Text(
                    stop.image,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(stop.shortDescription),
            if (stop.attributionLabel case final attribution?) ...[
              const SizedBox(height: 6),
              Text(
                'Source: $attribution',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 6),
            Text('Coordinates: ${stop.coordinates}'),
            if (stop.audio != null) Text('Optional audio: ${stop.audio}'),
            const SizedBox(height: 6),
            Text('Why Rover selected it: ${stop.whySelected}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onReplace,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Replace'),
                ),
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AdventureRequestSummary extends StatelessWidget {
  const AdventureRequestSummary({required this.request, super.key});

  final AdventureRequest request;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PreferenceRow(label: 'Request', value: request.naturalRequest),
        _PreferenceRow(
          label: 'Available time',
          value: '${request.availableMinutes} minutes',
        ),
        _PreferenceRow(label: 'Starting point', value: request.startingPoint),
        _PreferenceRow(label: 'Route mode', value: request.routeMode),
        _PreferenceRow(label: 'Interests', value: request.interests.join(', ')),
        _PreferenceRow(label: 'Pace', value: request.pace),
        _PreferenceRow(label: 'Route shape', value: request.routeShape),
        _PreferenceRow(label: 'Companions', value: request.companions),
        _PreferenceRow(label: 'Indoor/outdoor', value: request.environment),
        _PreferenceRow(label: 'Budget', value: request.budget),
        _PreferenceRow(
          label: 'Surprise me',
          value: request.surpriseMe ? 'Yes' : 'No',
        ),
      ],
    );
  }
}

class ActiveRoamScreen extends StatefulWidget {
  const ActiveRoamScreen({super.key});

  @override
  State<ActiveRoamScreen> createState() => _ActiveRoamScreenState();
}

class _ActiveRoamScreenState extends State<ActiveRoamScreen> {
  late final RoverVoiceController _voiceController;
  late final AdaptiveRouteStoryController _routeStoryController;
  bool _voiceControllerInitialized = false;
  RoamSession? _lastSyncedSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_voiceControllerInitialized) {
      final walkRepository = HttpWalkRepository();
      final installationIds = InstallationIdRepository();
      final activeRoamController = ActiveRoamScope.of(context);
      final phase16Flags = RoverPhase16Flags.fromEnvironment();
      _voiceController = RoverVoiceController(
        walkRepository: walkRepository,
        premiumVoice: RoverPremiumVoiceCoordinator(
          walkRepository: walkRepository,
        ),
        onDeviceAiCoordinator: RoverOnDeviceAiScope.of(context),
        preferencesController: PreferencesScope.of(context),
        onArrivalNarrated: activeRoamController.markArrivalNarrated,
        adaptiveRouteStoriesEnabled: phase16Flags.enabled,
        interactionProfileIdResolver: () async {
          final installationId = await installationIds.loadOrCreate();
          final profile = await walkRepository.createOrGetGuestProfile(
            installationId,
          );
          return profile.profileId;
        },
      );
      _routeStoryController = AdaptiveRouteStoryController(
        repository: walkRepository,
        flags: phase16Flags,
      );
      _voiceControllerInitialized = true;
    }
  }

  @override
  void dispose() {
    if (_voiceControllerInitialized) {
      _voiceController.dispose();
      _routeStoryController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ActiveRoamScope.of(context);
    final session = controller.session;
    if (!identical(_lastSyncedSession, session)) {
      _lastSyncedSession = session;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(() async {
            await _voiceController.syncWithSession(session);
            if (mounted) {
              await _routeStoryController.syncWithSession(
                session,
                _voiceController,
              );
            }
          }());
        }
      });
    }
    final nextStop = session.nextStop;
    final status = session.status;
    final isRunning = status == RoamSessionStatus.active;
    final isApiWalk = session.apiWalkSessionId != null;
    final hasEnded =
        status == RoamSessionStatus.completed ||
        status == RoamSessionStatus.ended;
    final allStopsArrived =
        isApiWalk &&
        session.completedStopIds.length >= session.roam.stops.length;

    return DetailScaffold(
      title: 'Active ROAM',
      subtitle: isApiWalk
          ? 'Connected to the local Rover middleware with foreground location during active navigation.'
          : 'Create a live walk from your current location to start navigation.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.push('/camera-explorer'),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Camera Explorer'),
        ),
        if (status == RoamSessionStatus.notStarted ||
            status == RoamSessionStatus.ended)
          FilledButton.icon(
            onPressed: controller.isBusy
                ? null
                : isApiWalk
                ? controller.startApiWalk
                : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(isApiWalk ? 'Start walk' : 'Create live walk first'),
          ),
        if (isRunning)
          OutlinedButton.icon(
            onPressed: controller.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
        if (status == RoamSessionStatus.paused)
          FilledButton.icon(
            onPressed: controller.resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        if (!hasEnded && status != RoamSessionStatus.notStarted)
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : isApiWalk
                ? () => _confirmCancel(context, controller)
                : controller.end,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(isApiWalk ? 'Cancel walk' : 'End ROAM'),
          ),
        if (allStopsArrived && status == RoamSessionStatus.active)
          FilledButton.icon(
            onPressed: controller.isBusy ? null : controller.completeApiWalk,
            icon: const Icon(Icons.flag_circle_outlined),
            label: const Text('Complete walk'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SafetyBanner(screenAwake: session.screenAwake),
          if (isApiWalk && controller.locationFailure != null) ...[
            const SizedBox(height: 12),
            _LocationPermissionPanel(
              failure: controller.locationFailure!,
              onRetry: controller.startLocationTracking,
              onOpenSettings: controller.openLocationSettings,
            ),
          ],
          if (session.errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorPanel(
              message: session.errorMessage!,
              onRetry: () => context.go('/home/route-preview'),
            ),
          ],
          const SizedBox(height: 12),
          if (session.navigationGuidance != null) ...[
            _NavigationGuidancePanel(guidance: session.navigationGuidance!),
            const SizedBox(height: 12),
          ],
          RoverMapView(
            currentLocation: session.simulatedLocation,
            orderedStops: session.orderedStops,
            routeGeometry: session.roam.routeGeometry,
            currentStopIndex: session.currentStopIndex,
            completedStopIds: session.completedStopIds,
            arrivalDebug: RoverArrivalDebugInfo(
              currentGpsAccuracyMeters: session.currentGpsAccuracyMeters,
              distanceToNextStopMeters: session.distanceToNextStopMeters,
              arrivalRadiusMeters: session.currentStop.arrivalRadiusMeters,
              arrivalCandidateReadingCount:
                  session.arrivalCandidateReadingCount,
              arrivalCandidateStopId: session.arrivalCandidateStopId,
            ),
            currentHeadingDegrees: session.currentHeadingDegrees,
            mapProvider: RoverMapProvider(
              routingProvider: session.roam.routeProvider,
            ),
            height: 460,
          ),
          const SizedBox(height: 16),
          if (session.recentNarrationStop != null) ...[
            PlaceholderPanel(
              icon: Icons.place_outlined,
              label:
                  'You have arrived at this location called ${session.recentNarrationStop!.name}.',
            ),
            const SizedBox(height: 12),
          ],
          LinearProgressIndicator(value: session.progress),
          const SizedBox(height: 8),
          Text(
            '${(session.progress * 100).round()}% complete - ${session.status.name}',
          ),
          if (session.timeRemainingMinutes != null) ...[
            const SizedBox(height: 4),
            Text('${session.timeRemainingMinutes} minutes remaining'),
          ],
          const SizedBox(height: 16),
          _CurrentStopPanel(session: session),
          if (nextStop != null) ...[
            const SizedBox(height: 12),
            _NextUpPanel(stop: nextStop),
          ],
          const SizedBox(height: 12),
          _NavigationStats(session: session),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            _PerformanceDiagnosticsPanel(
              session: session,
              voiceController: _voiceController,
            ),
          ],
          const SizedBox(height: 12),
          _WalkItineraryPanel(session: session),
          if (_routeStoryController.enabled && isApiWalk) ...[
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: Listenable.merge([
                _routeStoryController,
                _voiceController,
              ]),
              builder: (context, _) => _AdaptiveRouteStoryPanel(
                session: session,
                controller: _routeStoryController,
                voiceController: _voiceController,
              ),
            ),
          ],
          if (session.isOffRoute) ...[
            const SizedBox(height: 12),
            PlaceholderPanel(
              icon: Icons.alt_route,
              label: 'You appear to be off the planned route. Recenter or review the route before continuing.',
            ),
          ],
          if (isApiWalk && isRunning) ...[
            const SizedBox(height: 12),
            _AdaptationPanel(controller: controller, session: session),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isApiWalk) ...[
                OutlinedButton.icon(
                  onPressed: controller.isTrackingLocation
                      ? null
                      : controller.startLocationTracking,
                  icon: const Icon(Icons.gps_fixed),
                  label: Text(
                    controller.isTrackingLocation
                        ? 'Live GPS on'
                        : 'Start live GPS',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      hasEnded ||
                          !isRunning ||
                          allStopsArrived ||
                          session.arrivedAtCurrentStop ||
                          controller.isBusy
                      ? null
                      : controller.manualArriveAtCurrentStop,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('I\'m Here'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _voiceController,
            builder: (context, _) => _VoiceNarrationPanel(
              session: session,
              voiceController: _voiceController,
              isApiWalk: isApiWalk,
            ),
          ),
          const SizedBox(height: 16),
          _FullStopDetails(stop: session.currentStop),
          if (status == RoamSessionStatus.completed) ...[
            const SizedBox(height: 16),
            const PlaceholderPanel(
              icon: Icons.flag_circle_outlined,
              label:
                  'ROAM complete. Nice work getting Riley all the way through.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/profile/walk-feedback'),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Share beta feedback'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    ActiveRoamController controller,
  ) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this walk?'),
        content: const Text(
          'This will stop the active middleware walk session on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep walking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel walk'),
          ),
        ],
      ),
    );

    if (cancel == true) {
      await controller.cancelApiWalk();
    }
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.screenAwake});

  final bool screenAwake;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Walking safety reminder',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Stay aware of traffic, crossings, surfaces, and people around you. Screen awake: ${screenAwake ? 'on' : 'off'}.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentStopPanel extends StatelessWidget {
  const _CurrentStopPanel({required this.session});

  final RoamSession session;

  @override
  Widget build(BuildContext context) {
    final stop = session.currentStop;
    return PlaceholderPanel(
      icon: session.arrivedAtCurrentStop
          ? Icons.place
          : Icons.navigation_outlined,
      label:
          'Current stop: ${stop.name} - ${session.arrivedAtCurrentStop ? 'arrived' : 'on the way'}${stop.attributionLabel == null ? '' : '\nSource: ${stop.attributionLabel}'}',
    );
  }
}

class _NavigationGuidancePanel extends StatelessWidget {
  const _NavigationGuidancePanel({required this.guidance});

  final RoverNavigationGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label:
          '${guidance.maneuver.instruction}, ${guidance.distanceMeters} meters',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _maneuverIcon(guidance.maneuver.maneuverType),
              color: scheme.onPrimaryContainer,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guidance.maneuver.instruction,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    guidance.distanceMeters <= 12
                        ? 'Now'
                        : 'In ${guidance.distanceMeters} m',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _maneuverIcon(String maneuverType) {
    final type = maneuverType.toUpperCase();
    if (type.contains('U_TURN')) return Icons.u_turn_left;
    if (type.contains('LEFT')) return Icons.turn_left;
    if (type.contains('RIGHT')) return Icons.turn_right;
    if (type.contains('ROUNDABOUT')) return Icons.roundabout_left;
    return Icons.straight;
  }
}

class _NextUpPanel extends StatelessWidget {
  const _NextUpPanel({required this.stop});

  final RoverStop stop;

  @override
  Widget build(BuildContext context) {
    return PlaceholderPanel(
      icon: Icons.flag_outlined,
      label:
          'Next Up: ${stop.name} - ${stop.shortDescription}${stop.attributionLabel == null ? '' : '\nSource: ${stop.attributionLabel}'}',
    );
  }
}

class _NavigationStats extends StatelessWidget {
  const _NavigationStats({required this.session});

  final RoamSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PreferenceRow(
          label: 'Distance to next stop',
          value: session.distanceToNextStopMeters == null
              ? '${session.distanceMilesToNext.toStringAsFixed(2)} miles'
              : '${session.distanceToNextStopMeters!.round()} meters',
        ),
        _PreferenceRow(
          label: 'Estimated time to next stop',
          value: session.timeRemainingMinutes == null
              ? '${session.estimatedMinutesToNext} minutes'
              : '${session.timeRemainingMinutes} minutes remaining',
        ),
        _PreferenceRow(
          label: 'Route status',
          value: session.isOffRoute
              ? 'Off route by ${session.distanceFromRouteMeters.round()} meters'
              : session.arrivalCandidate
              ? 'Arriving at stop'
              : 'On planned route',
        ),
      ],
    );
  }
}

class _PerformanceDiagnosticsPanel extends StatelessWidget {
  const _PerformanceDiagnosticsPanel({
    required this.session,
    required this.voiceController,
  });

  final RoamSession session;
  final RoverVoiceController voiceController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PerformanceDiagnostics.instance,
        FieldDiagnostics.instance,
        voiceController,
      ]),
      builder: (context, _) {
        final diagnostics = PerformanceDiagnostics.instance;
        final fieldDiagnostics = FieldDiagnostics.instance;
        final last = diagnostics.lastOperation;
        final slow = diagnostics.lastSlowOperation;
        final journey = voiceController.lastJourneyNarration;
        final routeQuality = session.routeQuality;
        final lifecycle = session.lifecycleConsistency;
        final fieldLog = fieldDiagnostics.entries.reversed
            .take(5)
            .map((entry) => entry.summary)
            .join(' | ');
        return PlaceholderPanel(
          icon: Icons.speed,
          label: [
            'Performance: last ${last?.summary ?? 'none'}',
            'slow ${slow?.summary ?? 'none'}',
            if (journey != null) journey.summary,
            if (session.geofenceEntryDebug != null) session.geofenceEntryDebug!,
            if (fieldLog.isNotEmpty) 'Field log: $fieldLog',
            if (routeQuality != null)
              'Route quality: ${routeQuality.estimatedExperienceTimeMinutes} min, utilization ${(routeQuality.availableTimeUtilization * 100).round()}%, backtrack ${routeQuality.backtrackingEstimateMeters} m',
            if (lifecycle != null)
              'Lifecycle: ${lifecycle.isConsistent ? 'ok' : 'warning'} rev ${lifecycle.routeRevision}',
          ].join('; '),
        );
      },
    );
  }
}

class _WalkItineraryPanel extends StatelessWidget {
  const _WalkItineraryPanel({required this.session});

  final RoamSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stops = session.orderedStops;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.format_list_numbered),
        title: const Text('Itinerary'),
        subtitle: Text('${stops.length} stops on this walk'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final orderedStop in stops)
            _ItineraryRow(
              orderedStop: orderedStop,
              status: _statusFor(session, orderedStop),
            ),
        ],
      ),
    );
  }

  static _ItineraryStatus _statusFor(
    RoamSession session,
    OrderedRoverStop orderedStop,
  ) {
    if (session.completedStopIds.contains(orderedStop.stop.id)) {
      return _ItineraryStatus.visited;
    }
    if (orderedStop.sequence - 1 == session.currentStopIndex) {
      return _ItineraryStatus.current;
    }
    if (orderedStop.sequence - 1 < session.currentStopIndex) {
      return _ItineraryStatus.skipped;
    }
    return _ItineraryStatus.upcoming;
  }
}

class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({required this.orderedStop, required this.status});

  final OrderedRoverStop orderedStop;
  final _ItineraryStatus status;

  @override
  Widget build(BuildContext context) {
    final stop = orderedStop.stop;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Stop ${orderedStop.sequence}, ${stop.name}, ${status.label}, ${stop.estimatedVisitMinutes} minute visit',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _colorForStop(stop, scheme).withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: _colorForStop(stop, scheme)),
              ),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _iconForStop(stop),
                      color: _colorForStop(stop, scheme),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: Center(
                            child: Text(
                              orderedStop.sequence.toString(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${status.label} - ${stop.category} - ${stop.estimatedVisitMinutes} min',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (stop.shortDescription.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      stop.shortDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (stop.attributionLabel case final attribution?) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Source: $attribution',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                  if (stop.distanceFromPreviousStopMeters > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${stop.distanceFromPreviousStopMeters} m from previous stop',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForStop(RoverStop stop) {
    final category = '${stop.category} ${stop.contentType}'.toLowerCase();
    if (category.contains('burger')) return Icons.lunch_dining;
    if (category.contains('coffee') || category.contains('cafe')) {
      return Icons.coffee;
    }
    if (category.contains('tea')) return Icons.emoji_food_beverage;
    if (category.contains('bakery') || category.contains('cake')) {
      return Icons.cake;
    }
    if (category.contains('history') ||
        category.contains('architecture') ||
        category.contains('landmark')) {
      return Icons.account_balance;
    }
    return Icons.place;
  }

  Color _colorForStop(RoverStop stop, ColorScheme scheme) {
    final category = '${stop.category} ${stop.contentType}'.toLowerCase();
    if (stop.isSponsored) return Colors.amber.shade800;
    if (category.contains('burger')) return Colors.deepOrange.shade700;
    if (category.contains('coffee') || category.contains('cafe')) {
      return Colors.brown.shade700;
    }
    if (category.contains('tea')) return Colors.green.shade700;
    if (category.contains('bakery') || category.contains('cake')) {
      return Colors.pink.shade700;
    }
    if (category.contains('history') ||
        category.contains('architecture') ||
        category.contains('landmark')) {
      return Colors.indigo.shade700;
    }
    return scheme.primary;
  }
}

enum _ItineraryStatus {
  visited('Visited'),
  current('Current'),
  upcoming('Upcoming'),
  skipped('Skipped');

  const _ItineraryStatus(this.label);

  final String label;
}

class _LocationPermissionPanel extends StatelessWidget {
  const _LocationPermissionPanel({
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LocationFailure failure;
  final VoidCallback onRetry;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied =
        failure.kind == LocationFailureKind.permanentlyDenied;
    return PlaceholderPanel(
      icon: Icons.location_off_outlined,
      label:
          'Rover uses your location during an active walk to show your route, guide you to the next stop and detect when you arrive. ${failure.recovery}',
      action: permanentlyDenied
          ? OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            )
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Location'),
            ),
    );
  }
}

class _AdaptationPanel extends StatefulWidget {
  const _AdaptationPanel({required this.controller, required this.session});

  final ActiveRoamController controller;
  final RoamSession session;

  @override
  State<_AdaptationPanel> createState() => _AdaptationPanelState();
}

class _AdaptationPanelState extends State<_AdaptationPanel> {
  static const double _optionsRefreshDistanceMeters = 500;

  final WalkRepository _walkRepository = HttpWalkRepository();
  LocalDiscoveryOptionsResult? _optionsResult;
  String? _optionsError;
  bool _loadingOptions = false;
  RoverLatLng? _lastOptionsLocation;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOptions());
  }

  @override
  void didUpdateWidget(covariant _AdaptationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _lastOptionsLocation;
    final current = widget.session.simulatedLocation;
    if (previous == null ||
        previous.distanceTo(current) > _optionsRefreshDistanceMeters) {
      unawaited(_refreshOptions());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = widget.session;
    final proposal = session.pendingAdaptation;
    final optionsResult = _optionsResult;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Route options',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('Rev ${session.routeRevision}'),
              ],
            ),
            const SizedBox(height: 10),
            if (proposal == null) ...[
              if (_loadingOptions)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              if (_optionsError != null) ...[
                Text(
                  _optionsError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ] else if (optionsResult != null) ...[
                Text(
                  optionsResult.hasEnabledOptions
                      ? 'Live nearby options are available from the Rover API.'
                      : 'No live nearby route options found here yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DiscoveryChip(
                    label: 'Coffee',
                    icon: Icons.coffee,
                    option: optionsResult?.optionFor('coffee'),
                    onPressed: _canRequest('coffee')
                        ? () => _chooseDiscovery('coffee')
                        : null,
                  ),
                  _DiscoveryChip(
                    label: 'Tea',
                    icon: Icons.emoji_food_beverage_outlined,
                    option: optionsResult?.optionFor('tea'),
                    onPressed: _canRequest('tea')
                        ? () => _chooseDiscovery('tea')
                        : null,
                  ),
                  _DiscoveryChip(
                    label: 'Cakes',
                    icon: Icons.cake_outlined,
                    option: optionsResult?.optionFor('cakes'),
                    onPressed: _canRequest('cakes')
                        ? () => _chooseDiscovery('cakes')
                        : null,
                  ),
                  _DiscoveryChip(
                    label: 'Burgers',
                    icon: Icons.lunch_dining_outlined,
                    option: optionsResult?.optionFor('burgers'),
                    onPressed: _canRequest('burgers')
                        ? () => _chooseDiscovery('burgers')
                        : null,
                  ),
                  _DiscoveryChip(
                    label: 'Sites',
                    icon: Icons.account_balance_outlined,
                    option: optionsResult?.optionFor('interesting sites'),
                    onPressed: _canRequest('interesting sites')
                        ? () => _chooseDiscovery('interesting sites')
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'AddDiscovery',
                              userRequest: 'Find something nearby',
                            ),
                          ),
                    icon: const Icon(Icons.explore),
                    label: const Text('Find Nearby'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'SkipStop',
                              userRequest: 'Skip the next stop',
                            ),
                          ),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip Next'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'ShortenWalk',
                              userRequest: 'Shorten the walk',
                            ),
                          ),
                    icon: const Icon(Icons.compress),
                    label: const Text('Shorten'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'ExtendWalk',
                              userRequest: 'Make the walk longer',
                            ),
                          ),
                    icon: const Icon(Icons.add_road),
                    label: const Text('Extend'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'ExtendWalk',
                              availableMinutes:
                                  session.roam.totalEstimatedMinutes + 12,
                              userRequest: 'Add about 12 minutes',
                            ),
                          ),
                    icon: const Icon(Icons.more_time),
                    label: const Text('Add 12 min'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'ExtendWalk',
                              proposedDiscoveryId:
                                  'discovery-sponsored-walking-shop',
                              userRequest: 'Show sponsored extend option',
                            ),
                          ),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Sponsored extend'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'RejoinRoute',
                              userRequest: 'Rejoin the route',
                            ),
                          ),
                    icon: const Icon(Icons.u_turn_left),
                    label: const Text('Rejoin'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.evaluateAdaptation(
                              requestedType: 'ReturnToStart',
                              userRequest: 'Take me back',
                            ),
                          ),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Return'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                proposal.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(proposal.explanation),
              if (proposal.addedStops.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...proposal.proposedStops
                    .where((stop) => proposal.addedStops.contains(stop.stopId))
                    .map(
                      (stop) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.add_location_alt_outlined),
                        title: Text(stop.name),
                        subtitle: Text(
                          [
                            stop.category,
                            '${stop.distanceFromPreviousStopMeters} m away',
                            stop.contentSourceLabel,
                            if (stop.address != null) stop.address!,
                            if (stop.phoneNumber != null) stop.phoneNumber!,
                            if (stop.websiteUrl != null) stop.websiteUrl!,
                            if (stop.menuUrl != null) 'Menu: ${stop.menuUrl!}',
                          ].join(' - '),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 10),
              _AdaptationActions(controller: controller, proposal: proposal),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(proposal.type)),
                  Chip(
                    label: Text(
                      '${proposal.estimatedAddedMinutes >= 0 ? '+' : ''}${proposal.estimatedAddedMinutes} min',
                    ),
                  ),
                  Chip(label: Text(proposal.distanceLabel)),
                  if (proposal.isSponsored)
                    const Chip(label: Text('Sponsored')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Affected stops: ${proposal.affectedStops.isEmpty ? 'None' : proposal.affectedStops.join(', ')}',
              ),
              Text(
                'Added: ${proposal.addedStops.isEmpty ? 'None' : proposal.addedStops.join(', ')}',
              ),
              Text(
                'Removed: ${proposal.removedStops.isEmpty ? 'None' : proposal.removedStops.join(', ')}',
              ),
              Text(
                'New order: ${proposal.reorderedStops.isEmpty ? 'Unchanged' : proposal.reorderedStops.join(' > ')}',
              ),
              Text(
                'Proposed route: ${proposal.proposedRoute.durationMinutes} min, ${(proposal.proposedRoute.distanceMeters / 1609.344).toStringAsFixed(1)} mi',
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _requestDiscovery(String interest, {String? proposedDiscoveryId}) {
    unawaited(
      widget.controller.evaluateAdaptation(
        requestedType: 'AddDiscovery',
        interest: interest,
        proposedDiscoveryId: proposedDiscoveryId,
        userRequest: 'Find $interest nearby',
      ),
    );
  }

  void _chooseDiscovery(String interest) {
    final option = _optionsResult?.optionFor(interest);
    final samples = option?.samples ?? const <LocalDiscoverySample>[];
    if (samples.isEmpty) {
      _requestDiscovery(interest);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                option?.label ?? interest,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${samples.length} named nearby options'),
              const SizedBox(height: 8),
              for (final sample in samples)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: Text(sample.name),
                  subtitle: Text(
                    [
                      sample.category,
                      '${sample.distanceMeters} m away',
                      if (sample.address != null) sample.address!,
                      if (sample.phoneNumber != null) sample.phoneNumber!,
                      if (sample.websiteUrl != null) sample.websiteUrl!,
                      if (sample.menuUrl != null) 'Menu: ${sample.menuUrl!}',
                    ].join(' - '),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _requestDiscovery(
                      interest,
                      proposedDiscoveryId: sample.stopId,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  bool _canRequest(String option) {
    if (widget.controller.isBusy || _loadingOptions) {
      return false;
    }

    final result = _optionsResult;
    if (result == null) {
      return false;
    }

    return result.optionFor(option)?.hasSelectableSamples ?? false;
  }

  Future<void> _refreshOptions() async {
    if (_loadingOptions) {
      return;
    }

    final location = widget.session.simulatedLocation;
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });

    try {
      final result = await _walkRepository.getLocalDiscoveryOptions(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _optionsResult = result;
        _lastOptionsLocation = location;
        _optionsError = result.discoveryError;
      });
    } on RoverApiException catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() => _optionsError = exception.message);
    } finally {
      if (mounted) {
        setState(() => _loadingOptions = false);
      }
    }
  }
}

class _AdaptationActions extends StatelessWidget {
  const _AdaptationActions({required this.controller, required this.proposal});

  final ActiveRoamController controller;
  final WalkAdaptationProposal proposal;

  @override
  Widget build(BuildContext context) {
    final canCycle =
        proposal.type == 'AddDiscovery' || proposal.type == 'ExtendWalk';
    final acceptLabel = switch (proposal.type) {
      'AddDiscovery' => 'Add to Walk',
      'ExtendWalk' => 'Extend Walk',
      'SkipStop' => 'Skip Stop',
      'ShortenWalk' => 'Shorten Walk',
      'ReturnToStart' => 'Return',
      'RejoinRoute' => 'Rejoin Route',
      _ => 'Apply Change',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: controller.isBusy
              ? null
              : () => unawaited(_acceptAndConfirm(context)),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(acceptLabel),
        ),
        OutlinedButton.icon(
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.rejectPendingAdaptation()),
          icon: const Icon(Icons.route),
          label: const Text('Continue Current Walk'),
        ),
        OutlinedButton.icon(
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.savePendingAdaptationForLater()),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Save for Later'),
        ),
        if (canCycle)
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => unawaited(controller.requestNextAdaptationOption()),
            icon: const Icon(Icons.navigate_next),
            label: const Text('Next Option'),
          ),
        OutlinedButton.icon(
          onPressed: controller.isBusy
              ? null
              : () => unawaited(
                  controller.rejectPendingAdaptation(dismissDiscovery: true),
                ),
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Text('Dismiss'),
        ),
      ],
    );
  }

  Future<void> _acceptAndConfirm(BuildContext context) async {
    final addedNames = proposal.proposedStops
        .where((stop) => proposal.addedStops.contains(stop.stopId))
        .map((stop) => stop.name)
        .toList();
    await controller.acceptPendingAdaptation();
    if (!context.mounted) {
      return;
    }

    final placeText = addedNames.isEmpty
        ? _acceptedRouteOptionText(proposal)
        : addedNames.length == 1
        ? addedNames.first
        : addedNames.join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_acceptedRouteOptionMessage(proposal, placeText))),
    );
  }

  String _acceptedRouteOptionText(WalkAdaptationProposal proposal) {
    return switch (proposal.type) {
      'SkipStop' => 'That stop',
      'ExtendWalk' => 'The walk extension',
      'ShortenWalk' => 'The shorter route',
      'ReturnToStart' => 'The return route',
      'RejoinRoute' => 'The rejoin route',
      _ => 'Route option',
    };
  }

  String _acceptedRouteOptionMessage(
    WalkAdaptationProposal proposal,
    String placeText,
  ) {
    return switch (proposal.type) {
      'AddDiscovery' => '$placeText has been added to your walk and map.',
      'SkipStop' => '$placeText has been skipped.',
      'ExtendWalk' => '$placeText has been added to your walk.',
      'ShortenWalk' => '$placeText is now active.',
      'ReturnToStart' => '$placeText is now active.',
      'RejoinRoute' => '$placeText is now active.',
      _ => '$placeText is now active.',
    };
  }
}

class _DiscoveryChip extends StatelessWidget {
  const _DiscoveryChip({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.option,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final LocalDiscoveryOption? option;

  @override
  Widget build(BuildContext context) {
    final count = option?.selectableCount;
    final text = count == null || count == 0 ? label : '$label ($count)';
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(text),
      onPressed: onPressed,
    );
  }
}

class _AdaptiveRouteStoryPanel extends StatelessWidget {
  const _AdaptiveRouteStoryPanel({
    required this.session,
    required this.controller,
    required this.voiceController,
  });

  final RoamSession session;
  final AdaptiveRouteStoryController controller;
  final RoverVoiceController voiceController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selection = controller.currentSelection;
    final pack = controller.pack;
    final speaking = voiceController.state == RoverAudioState.speakingAnswer;
    final paused = voiceController.state == RoverAudioState.narrationPaused;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_stories_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Route stories',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(controller.readinessLabel)),
                IconButton(
                  tooltip: 'Refresh route stories',
                  onPressed: controller.isBusy
                      ? null
                      : () => unawaited(controller.refreshPack(session)),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              pack == null
                  ? 'Preparing stories for this route.'
                  : '${pack.stories.length} grounded stories - ${controller.usingOfflinePack
                        ? 'downloaded offline pack'
                        : controller.offlineEligible
                        ? 'downloaded for offline use'
                        : 'online sources'}',
            ),
            Text(controller.researchStatus),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () => _askAboutRoute(context),
              icon: const Icon(Icons.question_answer_outlined),
              label: const Text('Ask about route'),
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (selection != null) ...[
              const SizedBox(height: 12),
              Text(
                selection.story.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${selection.story.intent} - ${selection.variant.estimatedDurationSeconds} sec',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(selection.variant.narration),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: controller.isBusy || speaking
                        ? null
                        : () => unawaited(
                            controller.playCurrent(session, voiceController),
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                  OutlinedButton.icon(
                    onPressed: speaking
                        ? () => unawaited(
                            controller.pauseCurrent(session, voiceController),
                          )
                        : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                  OutlinedButton.icon(
                    onPressed: paused
                        ? () => unawaited(
                            controller.resumeCurrent(session, voiceController),
                          )
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(controller.skipCurrent(session)),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.tellMore(session, voiceController),
                          ),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Tell Me More'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(controller.saveCurrent(session)),
                    icon: const Icon(Icons.bookmark_border),
                    label: const Text('Save'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selection.story.sources.isEmpty
                        ? null
                        : () => _showSources(context),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Sources'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showSources(BuildContext context) async {
    final selection = controller.currentSelection;
    if (selection == null) return;
    unawaited(controller.recordSourcesViewed(session));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              'Sources for ${selection.story.title}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final source in selection.story.sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(source.title ?? source.providerName),
                trailing: source.url == null
                    ? null
                    : IconButton(
                        tooltip: 'Open source',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () async {
                          final uri = Uri.tryParse(source.url!);
                          var opened = false;
                          try {
                            if (uri != null &&
                                uri.hasAuthority &&
                                (uri.scheme == 'https' ||
                                    uri.scheme == 'http')) {
                              opened = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          } catch (_) {
                            // Show the same recoverable message for unavailable browser handlers.
                          }
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open this source.'),
                              ),
                            );
                          }
                        },
                      ),
                subtitle: Text(
                  [
                    source.attribution,
                    if (source.url != null) source.url!,
                  ].join('\n'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _askAboutRoute(BuildContext context) async {
    final question = await showRouteStoryQuestionDialog(context);
    if (!context.mounted) return;
    if (question == null || question.trim().isEmpty) return;
    await controller.askAboutRoute(session, voiceController, question);
  }
}

class _VoiceNarrationPanel extends StatelessWidget {
  const _VoiceNarrationPanel({
    required this.session,
    required this.voiceController,
    required this.isApiWalk,
  });

  final RoamSession session;
  final RoverVoiceController voiceController;
  final bool isApiWalk;

  @override
  Widget build(BuildContext context) {
    final state = voiceController.state;
    final turn = voiceController.lastTurn;
    final hasNarration = session.currentStop.narration?.isNotEmpty ?? false;
    final canAsk = isApiWalk && voiceController.canAsk;
    final activeController = ActiveRoamScope.of(context);
    return Semantics(
      label: 'Rover voice narration and Ask Rover controls',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.record_voice_over_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rover voice',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Chip(label: Text(state.name)),
                ],
              ),
              const SizedBox(height: 10),
              if (voiceController.voiceStatusMessage != null) ...[
                Text(voiceController.voiceStatusMessage!),
                const SizedBox(height: 10),
              ],
              if (voiceController.premiumProvider != null) ...[
                Text(
                  [
                    'Premium provider: ${voiceController.premiumProvider}',
                    'cache: ${voiceController.premiumCacheStatus ?? 'unknown'}',
                    'fallback: ${voiceController.premiumUsedFallback == true ? 'yes' : 'no'}',
                    'bytes: ${voiceController.premiumAudioBytes ?? 0}',
                  ].join(' - '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (voiceController.premiumPlaybackError != null)
                  Text(
                    'Playback error: ${voiceController.premiumPlaybackError}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 10),
              ],
              if (state == RoverAudioState.listening)
                const PlaceholderPanel(
                  icon: Icons.mic,
                  label:
                      'Listening. Rover listens only after you tap Ask Rover.',
                ),
              if (voiceController.errorMessage != null)
                PlaceholderPanel(
                  icon: Icons.error_outline,
                  label: voiceController.errorMessage!,
                  action: OutlinedButton.icon(
                    onPressed: openRoverMicrophoneSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                ),
              if (voiceController.captionText.isNotEmpty) ...[
                Text('Caption', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(voiceController.captionText),
                const SizedBox(height: 10),
              ],
              if (voiceController.transcriptText.isNotEmpty) ...[
                Text(
                  'Transcript',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(voiceController.transcriptText),
                const SizedBox(height: 10),
              ],
              if (turn != null) ...[
                Text('Answer', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(turn.answerText),
                if (turn.safetyNotice != null) Text(turn.safetyNotice!),
                Text('Provider: ${turn.provider}'),
                if (_canReviewVoiceSuggestion(turn)) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: activeController.isBusy
                        ? null
                        : () =>
                              unawaited(_reviewVoiceSuggestion(context, turn)),
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Review Route Change'),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Text('Rate'),
                  Expanded(
                    child: Slider(
                      value: voiceController.speechRate,
                      min: 0.3,
                      max: 0.65,
                      divisions: 7,
                      label: voiceController.speechRate.toStringAsFixed(2),
                      onChanged: (value) =>
                          unawaited(voiceController.setSpeechRate(value)),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: hasNarration
                        ? () => unawaited(
                            voiceController.playNarration(session.currentStop),
                          )
                        : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Play'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state == RoverAudioState.speakingNarration
                        ? () => unawaited(voiceController.pauseNarration())
                        : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Pause'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state == RoverAudioState.narrationPaused
                        ? () => unawaited(voiceController.resumeNarration())
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                  OutlinedButton.icon(
                    onPressed: hasNarration
                        ? () => unawaited(
                            voiceController.replayNarration(
                              session.currentStop,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.replay),
                    label: const Text('Replay'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(voiceController.stopAll()),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canAsk
                        ? () => unawaited(_startAskRover(context))
                        : null,
                    icon: const Icon(Icons.mic),
                    label: const Text('Ask Rover'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canAsk
                        ? () => unawaited(_askNearbyContext(context))
                        : null,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Tell Me Nearby'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canAsk
                        ? () => unawaited(_typeAskRover(context))
                        : null,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Type Question'),
                  ),
                  OutlinedButton.icon(
                    onPressed: turn == null
                        ? null
                        : () => unawaited(voiceController.replayAnswer()),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('Replay Answer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: voiceController.hasNarration
                        ? () => unawaited(voiceController.continueNarration())
                        : null,
                    icon: const Icon(Icons.subdirectory_arrow_right),
                    label: const Text('Continue Narration'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canReviewVoiceSuggestion(RoverVoiceTurn turn) {
    return turn.suggestedAction != 'Informational';
  }

  Future<void> _reviewVoiceSuggestion(
    BuildContext context,
    RoverVoiceTurn turn,
  ) async {
    final controller = ActiveRoamScope.of(context);
    final action = turn.suggestedAction;
    final interest = _interestFromQuestion(turn.questionText);
    await controller.evaluateAdaptation(
      requestedType: action,
      interest: interest,
      userRequest: turn.questionText,
    );
  }

  String? _interestFromQuestion(String question) {
    final text = question.toLowerCase();
    if (text.contains('coffee')) return 'coffee';
    if (text.contains('tea')) return 'tea';
    if (text.contains('cake') || text.contains('dessert')) return 'cakes';
    if (text.contains('burger')) return 'burgers';
    if (text.contains('architecture')) return 'architecture';
    if (text.contains('art')) return 'public art';
    return null;
  }

  Future<void> _startAskRover(BuildContext context) async {
    if (voiceController.privacyAccepted) {
      await voiceController.askRover(session);
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask Rover'),
        content: const Text(
          'Rover listens only after you tap Ask Rover. Your question is transcribed and sent to Rover to provide an answer about your current walk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await voiceController.acceptPrivacyAndAsk(session);
    }
  }

  Future<void> _askNearbyContext(BuildContext context) async {
    String? selectedPlaceId;
    try {
      final contextResult = await voiceController.walkRepository
          .getLocationContext(
            latitude: session.simulatedLocation.latitude,
            longitude: session.simulatedLocation.longitude,
            radiusMeters: 1500,
            routeId: session.apiWalkSessionId,
          );
      if (context.mounted && contextResult.rankedPlaces.isNotEmpty) {
        selectedPlaceId = await _showNearbyDiscoveries(context, contextResult);
      }
    } on RoverApiException {
      // The voice controller shows the location-story error if this retry fails.
    }

    await voiceController.tellNearbyStory(
      session,
      selectedPlaceId: selectedPlaceId,
    );
  }

  Future<String?> _showNearbyDiscoveries(
    BuildContext context,
    LocationStoryContext locationContext,
  ) {
    final places = locationContext.rankedPlaces.take(5).toList();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text(
                'Nearby discoveries',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final place in places)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.travel_explore),
                  title: Text(place.name),
                  subtitle: Text(
                    [
                      if (place.distanceFromUserMeters != null)
                        '${place.distanceFromUserMeters!.round()} m ${place.directionFromUser ?? ''}'
                            .trim(),
                      if (place.storyWorthinessReasons.isNotEmpty)
                        place.storyWorthinessReasons.take(2).join(' - '),
                      if (place.sourceReferences.isNotEmpty)
                        'Source: ${place.sourceReferences.map((source) => source.providerName).toSet().join(', ')}',
                    ].join('\n'),
                  ),
                  onTap: () => Navigator.of(context).pop(place.canonicalId),
                ),
              if (locationContext.sourceWarnings.isNotEmpty) ...[
                const Divider(),
                Text(
                  locationContext.sourceWarnings.take(2).join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.auto_stories),
                label: const Text('Use Best Story'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _typeAskRover(BuildContext context) async {
    final controller = TextEditingController(
      text: voiceController.transcriptText,
    );
    try {
      final question = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ask Rover'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Question',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              Navigator.of(context).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Ask'),
            ),
          ],
        ),
      );

      if (question != null && question.trim().isNotEmpty) {
        await voiceController.submitEditedQuestion(session, question);
      }
    } finally {
      controller.dispose();
    }
  }
}

class _FullStopDetails extends StatelessWidget {
  const _FullStopDetails({required this.stop});

  final RoverStop stop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stop details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _PreferenceRow(label: 'Name', value: stop.name),
            _PreferenceRow(label: 'Category', value: stop.category),
            _PreferenceRow(
              label: 'Content source',
              value: stop.contentSource ?? 'Rover editorial',
            ),
            _PreferenceRow(
              label: 'Content type',
              value: stop.contentType ?? stop.category,
            ),
            if (stop.sponsoredDisclosure != null)
              _PreferenceRow(
                label: 'Sponsored disclosure',
                value: stop.sponsoredDisclosure!,
              ),
            _PreferenceRow(
              label: 'Estimated visit time',
              value: '${stop.estimatedVisitMinutes} minutes',
            ),
            _PreferenceRow(
              label: 'Coordinates',
              value: stop.coordinates.toString(),
            ),
            _PreferenceRow(label: 'Image', value: stop.image),
            _PreferenceRow(
              label: 'Optional audio',
              value: stop.audio ?? 'No audio for this stop yet.',
            ),
            _PreferenceRow(label: 'Description', value: stop.shortDescription),
            _PreferenceRow(
              label: 'Why Rover selected it',
              value: stop.whySelected,
            ),
            if (stop.narration != null)
              _PreferenceRow(label: 'Narration', value: stop.narration!),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection issue',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(message, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class StopDetailsScreen extends StatelessWidget {
  const StopDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DetailScaffold(
      title: 'Stop details',
      subtitle:
          'A friendly placeholder for why this stop belongs in the adventure.',
      child: PlaceholderPanel(
        icon: Icons.place_outlined,
        label: 'Pocket park - quiet bench - nearby pastries',
      ),
    );
  }
}

class SavedRoamsScreen extends StatelessWidget {
  const SavedRoamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DestinationScaffold(
      title: 'My ROAMs',
      subtitle: 'Saved placeholder adventures live here.',
      children: [
        const PlaceholderPanel(
          icon: Icons.bookmark_border_rounded,
          label: 'Sunday wander - 3 stops',
        ),
        FeatureCard(
          title: 'Walk history',
          subtitle: 'Completed and intentionally ended walks.',
          icon: Icons.history,
          onTap: () => context.go('/roams/history'),
        ),
        FeatureCard(
          title: 'Saved discoveries',
          subtitle: 'Stops, discoveries, and stories saved for later.',
          icon: Icons.bookmarks_outlined,
          onTap: () => context.go('/roams/saved-discoveries'),
        ),
        FeatureCard(
          title: 'Start another',
          subtitle: 'Create a fresh placeholder adventure.',
          icon: Icons.add_road_rounded,
          onTap: () => context.go('/home/adventure-request'),
        ),
      ],
    );
  }
}

class WalkHistoryScreen extends StatelessWidget {
  const WalkHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    final finished =
        session.status == RoamSessionStatus.completed ||
        session.status == RoamSessionStatus.ended;

    return DetailScaffold(
      title: 'Walk history',
      subtitle: 'Walk recaps appear after a ROAM is completed or intentionally ended.',
      child: finished
          ? _PreferenceRow(
              label: session.status == RoamSessionStatus.completed
                  ? 'Completed ROAM'
                  : 'Ended ROAM',
              value:
                  '${session.completedStopIds.length} stops visited - ${session.roam.distanceMiles.toStringAsFixed(1)} mi planned',
            )
          : const PlaceholderPanel(
              icon: Icons.history,
              label: 'No completed walk recap is available yet.',
            ),
    );
  }
}

class SavedDiscoveriesScreen extends StatelessWidget {
  const SavedDiscoveriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DetailScaffold(
      title: 'Saved discoveries',
      subtitle: 'Saved items persist through the Phase 7 guest profile API when the middleware is reachable.',
      child: _ProfileSyncPanel(showSavedOnly: true),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = PreferencesScope.of(context).preferences;
    final greeting = preferences.firstName.isEmpty
        ? 'Guest rover'
        : '${preferences.firstName}\'s ROVER';

    return DestinationScaffold(
      title: 'Profile',
      subtitle: preferences.completedOnboarding
          ? 'Your adventure preferences are saved locally.'
          : 'Set up Riley so future ROAMs feel more like you.',
      children: [
        PlaceholderPanel(icon: Icons.account_circle_outlined, label: greeting),
        FeatureCard(
          title: 'Review preferences',
          subtitle: 'Edit or reset your local personalization.',
          icon: Icons.settings_outlined,
          onTap: () => context.go('/profile/settings'),
        ),
        FeatureCard(
          title: 'Account',
          subtitle: 'Sign in, sync across devices, export data, or delete account data.',
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => context.go('/profile/account'),
        ),
        FeatureCard(
          title: 'Legal notices',
          subtitle: 'Review application, map, and open-source licenses.',
          icon: Icons.policy_outlined,
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'ROVER',
            applicationVersion: '1.0.0',
          ),
        ),
        if (kDebugMode)
          FeatureCard(
            title: 'Voice test',
            subtitle: 'Check premium Rover voice and fallback behavior.',
            icon: Icons.graphic_eq,
            onTap: () => context.go('/profile/voice-test'),
          ),
        if (kDebugMode)
          FeatureCard(
            title: 'On-device AI',
            subtitle: 'View the Android capability snapshot.',
            icon: Icons.memory_outlined,
            onTap: () => context.go('/profile/on-device-ai'),
          ),
        const _ProfileSyncPanel(),
      ],
    );
  }
}

class VoiceTestScreen extends StatefulWidget {
  const VoiceTestScreen({super.key});

  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  late final RoverPremiumVoiceCoordinator _premiumVoice;
  String _status = 'Ready';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _premiumVoice = RoverPremiumVoiceCoordinator(
      walkRepository: HttpWalkRepository(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const RoverNotFoundScreen();
    }

    return DetailScaffold(
      title: 'Voice test',
      subtitle: 'Development-only premium voice and device fallback checks.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceholderPanel(icon: Icons.graphic_eq, label: _status),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _play(
                          'StopNarration',
                          'Union Square has always been a stage for San Francisco street life.',
                        ),
                      ),
                icon: const Icon(Icons.place_outlined),
                label: const Text('Stop sample'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _play(
                          'AskRoverAnswer',
                          'Rover thinks the best next move is a short architecture detour.',
                        ),
                      ),
                icon: const Icon(Icons.question_answer_outlined),
                label: const Text('Ask sample'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _play(
                          'WalkIntroduction',
                          'Welcome to your Rover walk. Keep your eyes up and your pace comfortable.',
                        ),
                      ),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Intro sample'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_premiumVoice.pause()),
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_premiumVoice.resume()),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_premiumVoice.stop()),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _play(String purpose, String text) async {
    setState(() {
      _busy = true;
      _status = 'Loading premium voice.';
    });

    final premium = await _premiumVoice.speak(text: text, purpose: purpose);
    if (mounted) {
      setState(() {
        _busy = false;
        _status = premium ? _premiumVoice.statusMessage : 'Using device voice.';
      });
    }
  }
}

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Account settings',
      subtitle:
          'Private beta controls for sync, export, sign out, and deletion.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/account'),
          icon: const Icon(Icons.login),
          label: const Text('Sign in or create account'),
        ),
      ],
      child: Column(
        children: [
          const PlaceholderPanel(
            icon: Icons.cloud_done_outlined,
            label: 'Guest-to-account conversion preserves guest Rover data after Cognito is configured.',
          ),
          const SizedBox(height: 12),
          _AccountActionRow(
            icon: Icons.download_outlined,
            label: 'Download my Rover data',
            onPressed: () {},
          ),
          _AccountActionRow(
            icon: Icons.history_toggle_off,
            label: 'Delete walk history',
            onPressed: () {},
          ),
          _AccountActionRow(
            icon: Icons.psychology_alt_outlined,
            label: 'Reset learned preferences',
            onPressed: () {},
          ),
          _AccountActionRow(
            icon: Icons.bookmark_remove_outlined,
            label: 'Delete saved discoveries',
            onPressed: () {},
          ),
          _AccountActionRow(
            icon: Icons.logout,
            label: 'Sign out',
            onPressed: () => context.go('/welcome'),
          ),
          _AccountActionRow(
            icon: Icons.delete_forever_outlined,
            label: 'Delete account',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onPressed,
    );
  }
}

class _ProfileSyncPanel extends StatefulWidget {
  const _ProfileSyncPanel({this.showSavedOnly = false});

  final bool showSavedOnly;

  @override
  State<_ProfileSyncPanel> createState() => _ProfileSyncPanelState();
}

class _ProfileSyncPanelState extends State<_ProfileSyncPanel> {
  final _installationIds = InstallationIdRepository();
  final _repository = HttpWalkRepository();
  GuestProfile? _profile;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final installationId = await _installationIds.loadOrCreate();
      final profile = await _repository.createOrGetGuestProfile(installationId);
      final synced = await _syncLocalPreferences(profile);
      if (mounted) {
        setState(() => _profile = synced);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Profile API is unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<GuestProfile> _syncLocalPreferences(GuestProfile profile) async {
    if (widget.showSavedOnly) {
      return profile;
    }

    final preferences = PreferencesScope.of(context).preferences;
    if (!preferences.completedOnboarding && preferences.interests.isEmpty) {
      return profile;
    }

    return _repository.updateProfilePreferences(
      profile.profileId,
      UpdateProfilePreferencesRequest(
        interests: preferences.interests,
        walkingPace: preferences.walkingPace.isEmpty
            ? null
            : preferences.walkingPace,
        accessibilityNeeds: preferences.mobility.trim().isEmpty
            ? const []
            : [preferences.mobility.trim()],
        distanceUnits: preferences.distanceUnit.isEmpty
            ? null
            : preferences.distanceUnit,
        directionVoiceEnabled: preferences.audioPreference != 'text is fine',
        narrationEnabled: preferences.audioPreference != 'text is fine',
        premiumVoiceEnabled: preferences.audioPreference != 'text is fine',
        askRoverVoiceEnabled: preferences.audioPreference != 'text is fine',
        autoPlayNarrationOnArrival: true,
        resumeNarrationAfterNavigation: true,
        deviceVoiceFallbackEnabled: true,
        preferredNarrationLength: preferences.contentDepth.isEmpty
            ? null
            : preferences.contentDepth,
        storyDensity: preferences.storyDensity,
        excludedStoryCategories: preferences.excludedStoryCategories,
      ),
    );
  }

  Future<void> _enableLearning(bool enabled) async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final updated = await _repository.updateProfilePreferences(
      profile.profileId,
      UpdateProfilePreferencesRequest(improveRecommendations: enabled),
    );
    setState(() => _profile = updated);
  }

  Future<void> _deleteProfile() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    await _repository.deleteProfile(profile.profileId);
    setState(() => _profile = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const PlaceholderPanel(
        icon: Icons.sync,
        label: 'Loading guest profile.',
      );
    }

    if (_error != null) {
      return PlaceholderPanel(
        icon: Icons.cloud_off_outlined,
        label: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return PlaceholderPanel(
        icon: Icons.delete_outline,
        label: 'Guest profile deleted from the API.',
        action: OutlinedButton(onPressed: _load, child: const Text('Recreate')),
      );
    }

    if (widget.showSavedOnly) {
      return Column(
        children: [
          if (profile.savedDiscoveries.isEmpty)
            const PlaceholderPanel(
              icon: Icons.bookmarks_outlined,
              label: 'No saved discoveries yet.',
            )
          else
            for (final item in profile.savedDiscoveries)
              _PreferenceRow(
                label: item.name,
                value: '${item.category} - ${item.source}',
              ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreferenceRow(label: 'Guest profile', value: profile.profileId),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Improve recommendations'),
          subtitle: const Text('Uses limited, explainable signals only.'),
          value: profile.preferences.improveRecommendations,
          onChanged: (value) => unawaited(_enableLearning(value)),
        ),
        _PreferenceRow(
          label: 'Learned interests',
          value: profile.learnedPreferences.isEmpty
              ? 'None yet'
              : profile.learnedPreferences
                    .map((item) => '${item.topic}: ${item.score}')
                    .join(', '),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_deleteProfile()),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Profile Data'),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PreferencesScope.of(context);
    final preferences = controller.preferences;

    return DetailScaffold(
      title: 'Preferences',
      subtitle: 'Riley keeps these on this device for now. No account or backend is connected.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/onboarding'),
          child: const Text('Edit preferences'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/profile/settings/beta-diagnostics'),
          icon: const Icon(Icons.health_and_safety_outlined),
          label: const Text('Beta diagnostics'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/profile/settings/report-problem'),
          icon: const Icon(Icons.report_problem_outlined),
          label: const Text('Report a problem'),
        ),
        OutlinedButton(
          onPressed: () async {
            await controller.reset();
            if (context.mounted) {
              context.go('/welcome');
            }
          },
          child: const Text('Reset onboarding'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_phase15Enabled) ...[
            _StoryPreferenceControls(controller: controller),
            const SizedBox(height: 16),
          ],
          PreferencesSummary(preferences: preferences),
        ],
      ),
    );
  }
}

class _StoryPreferenceControls extends StatelessWidget {
  const _StoryPreferenceControls({required this.controller});

  static const categories = [
    'history',
    'architecture',
    'food',
    'culture',
    'notable people',
    'film and television',
    'nature',
    'unusual facts',
    'events',
    'weather',
  ];

  final PreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final preferences = controller.preferences;
    final selectedDensity =
        {'Quiet', 'Highlights', 'Story-Rich'}.contains(preferences.storyDensity)
        ? preferences.storyDensity
        : 'Highlights';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Story frequency', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Quiet', label: Text('Quiet')),
            ButtonSegment(value: 'Highlights', label: Text('Highlights')),
            ButtonSegment(value: 'Story-Rich', label: Text('Story-Rich')),
          ],
          selected: {selectedDensity},
          onSelectionChanged: (selection) => unawaited(
            controller.save(
              preferences.copyWith(storyDensity: selection.single),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Story interests', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories)
              FilterChip(
                label: Text(category),
                selected:
                    preferences.interests.contains(category) &&
                    !preferences.excludedStoryCategories.contains(category),
                onSelected: (selected) {
                  final interests = preferences.interests.toSet();
                  final excluded = preferences.excludedStoryCategories.toSet();
                  if (selected) {
                    interests.add(category);
                    excluded.remove(category);
                  } else {
                    interests.remove(category);
                    excluded.add(category);
                  }
                  unawaited(
                    controller.save(
                      preferences.copyWith(
                        interests: interests.toList()..sort(),
                        excludedStoryCategories: excluded.toList()..sort(),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class BetaDiagnosticsScreen extends StatefulWidget {
  const BetaDiagnosticsScreen({super.key});

  @override
  State<BetaDiagnosticsScreen> createState() => _BetaDiagnosticsScreenState();
}

class _BetaDiagnosticsScreenState extends State<BetaDiagnosticsScreen> {
  final _client = RoverApiClient();
  late final Future<(BetaConfigurationStatus, BetaDiagnosticsReport)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadDiagnostics();
  }

  Future<(BetaConfigurationStatus, BetaDiagnosticsReport)>
  _loadDiagnostics() async {
    final configuration = await _client.getBetaConfiguration();
    final diagnostics = await _client.getBetaDiagnostics();
    return (configuration, diagnostics);
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Beta diagnostics',
      subtitle: 'Private-beta status without secrets, tokens, emails, or precise location history.',
      child: FutureBuilder<(BetaConfigurationStatus, BetaDiagnosticsReport)>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return PlaceholderPanel(
              icon: Icons.cloud_off_outlined,
              label:
                  'Diagnostics unavailable. API: ${_client.config.normalizedBaseUrl}',
            );
          }

          final (configuration, diagnostics) = snapshot.data!;
          final report = diagnostics.toRedactedText();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DiagnosticRow(
                label: 'App version',
                value: diagnostics.appVersion,
              ),
              _DiagnosticRow(
                label: 'Build number',
                value: diagnostics.buildNumber,
              ),
              _DiagnosticRow(
                label: 'API environment',
                value: diagnostics.apiEnvironment,
              ),
              _DiagnosticRow(label: 'API health', value: diagnostics.apiHealth),
              _DiagnosticRow(
                label: 'API base URL',
                value: _client.config.normalizedBaseUrl,
              ),
              _DiagnosticRow(
                label: 'Beta build',
                value: configuration.isBeta ? 'yes' : 'no',
              ),
              _DiagnosticRow(
                label: 'Map configured',
                value: diagnostics.mapboxConfigured ? 'yes' : 'no',
              ),
              _DiagnosticRow(
                label: 'ElevenLabs enabled',
                value: diagnostics.elevenLabsEnabled ? 'yes' : 'no',
              ),
              _DiagnosticRow(
                label: 'ElevenLabs configured',
                value: diagnostics.elevenLabsConfigured ? 'yes' : 'no',
              ),
              _DiagnosticRow(label: 'Storage', value: diagnostics.storageMode),
              _DiagnosticRow(
                label: 'Routing provider',
                value: diagnostics.routingMode,
              ),
              _DiagnosticRow(
                label: 'Discovery provider',
                value: diagnostics.discoveryMode,
              ),
              _DiagnosticRow(
                label: 'Local discovery',
                value: diagnostics.localDiscoveryMode,
              ),
              _DiagnosticRow(
                label: 'API requests',
                value: '${diagnostics.apiRequestCount}',
              ),
              _DiagnosticRow(
                label: 'Location updates',
                value: '${diagnostics.locationUpdateCount}',
              ),
              _DiagnosticRow(
                label: 'Audio bytes',
                value: '${diagnostics.downloadedAudioBytes}',
              ),
              if (configuration.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                PlaceholderPanel(
                  icon: Icons.warning_amber_outlined,
                  label: configuration.warnings.join('\n'),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Diagnostics copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy diagnostics'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  static const _categories = [
    'Map issue',
    'Wrong directions',
    'Arrival not detected',
    'Narration issue',
    'ASK ROVER issue',
    'Login or account issue',
    'Walk content issue',
    'Application crash or freeze',
    'Other',
  ];

  final _client = RoverApiClient();
  final _queue = OfflineProblemReportQueue();
  final _descriptionController = TextEditingController();
  String _category = _categories.first;
  bool _preciseLocationAttached = false;
  String _status = 'Attach precise location only if you choose to.';
  bool _busy = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    return DetailScaffold(
      title: 'Report a problem',
      subtitle: 'Send beta feedback with privacy-safe technical context.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: _categories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _category = value ?? _category),
            decoration: const InputDecoration(labelText: 'Issue type'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            enabled: !_busy,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Optional description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _preciseLocationAttached,
            onChanged: _busy
                ? null
                : (value) => setState(() => _preciseLocationAttached = value),
            title: const Text('Attach precise current location'),
            subtitle: const Text(
              'Use only when the problem depends on exactly where you are.',
            ),
          ),
          const SizedBox(height: 12),
          PlaceholderPanel(icon: Icons.info_outline, label: _status),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _submit(session),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit report'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(RoamSession session) async {
    setState(() => _busy = true);
    final request = ProblemReportRequest(
      category: _category,
      description: _descriptionController.text,
      walkSessionId: session.apiWalkSessionId,
      stopId: session.currentStop.id,
      connectivityState: 'unknown',
      preciseLocationAttached: _preciseLocationAttached,
    );
    try {
      final receipt = await _client.submitProblemReport(request);
      setState(
        () => _status = 'Report received. Severity: ${receipt.severity}.',
      );
    } on RoverApiException {
      await _queue.enqueue(request);
      setState(
        () => _status = 'API unavailable. Report queued on this device.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class PostWalkFeedbackScreen extends StatefulWidget {
  const PostWalkFeedbackScreen({super.key});

  @override
  State<PostWalkFeedbackScreen> createState() => _PostWalkFeedbackScreenState();
}

class _PostWalkFeedbackScreenState extends State<PostWalkFeedbackScreen> {
  final _client = RoverApiClient();
  final _commentsController = TextEditingController();
  int _rating = 5;
  bool? _directionsEasy = true;
  bool? _stopsDetected = true;
  bool? _narrationEnjoyable = true;
  bool? _askUseful = true;
  bool? _rightLength = true;
  bool? _again = true;
  String _status = 'A few quick beta notes help harden Rover.';
  bool _busy = false;

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    return DetailScaffold(
      title: 'Walk feedback',
      subtitle: 'Skippable private-beta feedback for this completed walk.',
      actions: [
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text('Skip'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Slider(
            value: _rating.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$_rating',
            onChanged: _busy
                ? null
                : (value) => setState(() => _rating = value.round()),
          ),
          _FeedbackToggle(
            label: 'Directions were easy to follow',
            value: _directionsEasy,
            onChanged: (value) => setState(() => _directionsEasy = value),
          ),
          _FeedbackToggle(
            label: 'Stops were detected correctly',
            value: _stopsDetected,
            onChanged: (value) => setState(() => _stopsDetected = value),
          ),
          _FeedbackToggle(
            label: 'Narration was enjoyable',
            value: _narrationEnjoyable,
            onChanged: (value) => setState(() => _narrationEnjoyable = value),
          ),
          _FeedbackToggle(
            label: 'ASK ROVER was useful',
            value: _askUseful,
            onChanged: (value) => setState(() => _askUseful = value),
          ),
          _FeedbackToggle(
            label: 'Walk length felt right',
            value: _rightLength,
            onChanged: (value) => setState(() => _rightLength = value),
          ),
          _FeedbackToggle(
            label: 'I would take another Rover walk',
            value: _again,
            onChanged: (value) => setState(() => _again = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentsController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Optional comments',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          PlaceholderPanel(icon: Icons.rate_review_outlined, label: _status),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || session.apiWalkSessionId == null
                ? null
                : () => _submit(session.apiWalkSessionId!),
            icon: const Icon(Icons.check),
            label: const Text('Submit feedback'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(String walkSessionId) async {
    setState(() => _busy = true);
    try {
      await _client.submitPostWalkFeedback(
        walkSessionId,
        PostWalkFeedbackRequest(
          overallRating: _rating,
          directionsEasyToFollow: _directionsEasy,
          stopsDetectedCorrectly: _stopsDetected,
          narrationEnjoyable: _narrationEnjoyable,
          askRoverUseful: _askUseful,
          walkRightLength: _rightLength,
          wouldTakeAnotherWalk: _again,
          comments: _commentsController.text,
        ),
      );
      setState(() => _status = 'Feedback saved for this walk.');
    } on RoverApiException catch (error) {
      setState(() => _status = error.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _FeedbackToggle extends StatelessWidget {
  const _FeedbackToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value ?? false,
      onChanged: onChanged,
      title: Text(label),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _PreferenceRow(label: label, value: value);
  }
}

class PreferencesSummary extends StatelessWidget {
  const PreferencesSummary({required this.preferences, super.key});

  final RoverPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saved Rover preferences',
      child: Column(
        children: [
          _PreferenceRow(label: 'First name', value: preferences.firstName),
          _PreferenceRow(
            label: 'Interests',
            value: preferences.interests.join(', '),
          ),
          _PreferenceRow(label: 'Walking pace', value: preferences.walkingPace),
          _PreferenceRow(
            label: 'Available time',
            value: preferences.availableTime,
          ),
          _PreferenceRow(
            label: 'Accessibility and mobility',
            value: preferences.mobility,
          ),
          _PreferenceRow(
            label: 'Content depth',
            value: preferences.contentDepth,
          ),
          if (_phase15Enabled)
            _PreferenceRow(
              label: 'Story frequency',
              value: preferences.storyDensity,
            ),
          _PreferenceRow(label: 'Audio', value: preferences.audioPreference),
          _PreferenceRow(
            label: 'Notifications',
            value: preferences.notifications,
          ),
          _PreferenceRow(
            label: 'Distance units',
            value: preferences.distanceUnit,
          ),
          _PreferenceRow(label: 'Language', value: preferences.language),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = value.trim().isEmpty ? 'Skipped for now' : value;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(displayValue, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class RoverNotFoundScreen extends StatelessWidget {
  const RoverNotFoundScreen({this.error, super.key});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'ROAM not found',
      subtitle: 'That path wandered off. Let\'s get you back to the trailhead.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('Go Home'),
        ),
      ],
      child: PlaceholderPanel(
        icon: Icons.travel_explore_rounded,
        label: error?.toString() ?? 'Unknown route',
      ),
    );
  }
}

class RoverErrorScreen extends StatelessWidget {
  const RoverErrorScreen({this.error, super.key});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'ROVER hit a bump',
      subtitle: 'Something unexpected happened, but your adventure can restart safely.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('Go Home'),
        ),
      ],
      child: PlaceholderPanel(
        icon: Icons.error_outline_rounded,
        label: error?.toString() ?? 'Unknown navigation error',
      ),
    );
  }
}

class BrandedScaffold extends StatelessWidget {
  const BrandedScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  const SizedBox(height: 36),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    for (final action in actions) ...[
                      action,
                      if (action != actions.last) const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DestinationScaffold extends StatelessWidget {
  const DestinationScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(subtitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          for (final child in children) ...[
            child,
            if (child != children.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(subtitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          if (actions.isNotEmpty) ...[
            for (final action in actions) ...[
              action,
              if (action != actions.last) const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
          ],
          child,
        ],
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    required this.icon,
    required this.label,
    this.action,
    super.key,
  });

  final IconData icon;
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

class RileyPlaceholder extends StatelessWidget {
  const RileyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Temporary Riley mascot placeholder',
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_rounded,
                size: 56,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(height: 12),
              Text(
                'Riley mascot placeholder',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

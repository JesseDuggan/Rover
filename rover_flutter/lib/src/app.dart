import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'active_roam/active_roam_controller.dart';
import 'active_roam/active_roam_repository.dart';
import 'active_roam/screen_awake_controller.dart';
import 'adventure/adventure_request_controller.dart';
import 'api/walk_repository.dart';
import 'api/rover_api_config.dart';
import 'location/location_controller.dart';
import 'location/rover_location.dart';
import 'on_device_ai/rover_ai_provider.dart';
import 'on_device_ai/rover_ai_provider_factory.dart';
import 'on_device_ai/rover_offline_intelligence.dart';
import 'on_device_ai/rover_on_device_ai_coordinator.dart';
import 'on_device_ai/rover_on_device_ai_scope.dart';
import 'on_device_ai/rover_phase13_flags.dart';
import 'preferences/preferences_controller.dart';
import 'preferences/preferences_repository.dart';
import 'routing/rover_router.dart';

class RoverApp extends StatefulWidget {
  const RoverApp({
    this.preferencesRepository,
    this.activeRoamRepository,
    this.walkRepository,
    this.roverAiProvider,
    this.phase13Flags,
    super.key,
  });

  final PreferencesRepository? preferencesRepository;
  final ActiveRoamRepository? activeRoamRepository;
  final WalkRepository? walkRepository;
  final RoverAiProvider? roverAiProvider;
  final RoverPhase13Flags? phase13Flags;

  @override
  State<RoverApp> createState() => _RoverAppState();
}

class _RoverAppState extends State<RoverApp> {
  late final PreferencesController _preferencesController;
  late final AdventureRequestController _adventureRequestController;
  late final LocationController _locationController;
  late final ActiveRoamController _activeRoamController;
  late final RoverOnDeviceAiCoordinator _roverAiCoordinator;
  late final RoverOfflineIntelligence _offlineIntelligence;
  late final Future<void> _preferencesLoad;
  late final Future<void> _activeRoamLoad;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final phase13Flags =
        widget.phase13Flags ?? RoverPhase13Flags.fromEnvironment();
    _offlineIntelligence = RoverOfflineIntelligence.instance;
    _offlineIntelligence.configure(
      enabled: phase13Flags.enabled && phase13Flags.offlineIntelligence,
    );
    _adventureRequestController = AdventureRequestController();
    _locationController = LocationController();
    unawaited(_locationController.ensureDeviceLocation());
    _activeRoamController = ActiveRoamController(
      repository: widget.activeRoamRepository,
      walkRepository: widget.walkRepository,
    );
    _preferencesController = PreferencesController(
      widget.preferencesRepository ?? FilePreferencesRepository(),
    );
    _router = createRoverRouter(_preferencesController);
    _roverAiCoordinator = RoverOnDeviceAiCoordinator(
      flags: phase13Flags,
      provider: widget.roverAiProvider ?? createPlatformRoverAiProvider(),
    );
    _activeRoamController.addListener(_syncPhase13Situation);
    _offlineIntelligence.addListener(_syncPhase13Situation);
    _preferencesLoad = _loadPreferences();
    _activeRoamLoad = _activeRoamController.load();
  }

  Future<void> _loadPreferences() async {
    await _preferencesController.load();
    RoverApiConfig.setDevelopmentOverride(
      _preferencesController.preferences.developmentApiBaseUrl,
    );
  }

  void _syncPhase13Situation() {
    if (!_activeRoamController.isLoaded) {
      return;
    }
    _roverAiCoordinator.observeSituation(
      session: _activeRoamController.session,
      reading: _activeRoamController.latestLocationReading,
      connectivityState: _offlineIntelligence.connectivityState,
      offlineCacheState: _offlineIntelligence.cacheState,
    );
    unawaited(
      _offlineIntelligence.preloadJourney(_activeRoamController.session),
    );
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2D6CDF);

    return FutureBuilder<void>(
      future: _preferencesLoad,
      builder: (context, snapshot) {
        final app = MaterialApp.router(
          title: 'ROVER',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          routerConfig: _router,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            ),
            splashFactory: NoSplash.splashFactory,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            splashFactory: NoSplash.splashFactory,
            useMaterial3: true,
          ),
        );

        return FutureBuilder<void>(
          future: _activeRoamLoad,
          builder: (context, activeSnapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                activeSnapshot.connectionState != ConnectionState.done) {
              return MaterialApp(
                title: 'ROVER',
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(seedColor: seed),
                  splashFactory: NoSplash.splashFactory,
                  useMaterial3: true,
                ),
                home: const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            return PreferencesScope(
              controller: _preferencesController,
              child: AdventureRequestScope(
                controller: _adventureRequestController,
                child: LocationScope(
                  controller: _locationController,
                  child: ActiveRoamScope(
                    controller: _activeRoamController,
                    child: RoverOnDeviceAiScope(
                      coordinator: _roverAiCoordinator,
                      child: app,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _activeRoamController.removeListener(_syncPhase13Situation);
    _offlineIntelligence.removeListener(_syncPhase13Situation);
    _router.dispose();
    unawaited(_roverAiCoordinator.dispose());
    _activeRoamController.dispose();
    _locationController.dispose();
    _adventureRequestController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }
}

class RoverTestApp extends StatefulWidget {
  const RoverTestApp({
    required this.preferencesRepository,
    this.activeRoamRepository,
    this.walkRepository,
    this.roverAiProvider,
    this.phase13Flags,
    this.locationProvider,
    this.initialLocation = '/welcome',
    super.key,
  });

  final PreferencesRepository preferencesRepository;
  final ActiveRoamRepository? activeRoamRepository;
  final WalkRepository? walkRepository;
  final RoverAiProvider? roverAiProvider;
  final RoverPhase13Flags? phase13Flags;
  final RoverLocationProvider? locationProvider;
  final String initialLocation;

  @override
  State<RoverTestApp> createState() => _RoverTestAppState();
}

class _RoverTestAppState extends State<RoverTestApp> {
  late final PreferencesController _preferencesController;
  late final AdventureRequestController _adventureRequestController;
  late final LocationController _locationController;
  late final ActiveRoamController _activeRoamController;
  late final RoverOnDeviceAiCoordinator _roverAiCoordinator;
  late final RoverOfflineIntelligence _offlineIntelligence;
  late final Future<void> _preferencesLoad;
  late final Future<void> _activeRoamLoad;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final phase13Flags = widget.phase13Flags ?? const RoverPhase13Flags();
    _offlineIntelligence = RoverOfflineIntelligence.instance;
    _offlineIntelligence.configure(
      enabled: phase13Flags.enabled && phase13Flags.offlineIntelligence,
    );
    _preferencesController = PreferencesController(
      widget.preferencesRepository,
    );
    _router = createRoverRouter(
      _preferencesController,
      initialLocation: widget.initialLocation,
    );
    _adventureRequestController = AdventureRequestController();
    _locationController = LocationController(
      realProvider: widget.locationProvider,
    );
    _activeRoamController = ActiveRoamController(
      repository: widget.activeRoamRepository ?? MemoryActiveRoamRepository(),
      walkRepository: widget.walkRepository,
      screenAwakeController: MemoryScreenAwakeController(),
    );
    _roverAiCoordinator = RoverOnDeviceAiCoordinator(
      flags: phase13Flags,
      provider: widget.roverAiProvider ?? const DisabledRoverAiProvider(),
    );
    _activeRoamController.addListener(_syncPhase13Situation);
    _offlineIntelligence.addListener(_syncPhase13Situation);
    _preferencesLoad = _loadPreferences();
    _activeRoamLoad = _activeRoamController.load();
  }

  Future<void> _loadPreferences() async {
    await _preferencesController.load();
    RoverApiConfig.setDevelopmentOverride(
      _preferencesController.preferences.developmentApiBaseUrl,
    );
  }

  void _syncPhase13Situation() {
    if (!_activeRoamController.isLoaded) {
      return;
    }
    _roverAiCoordinator.observeSituation(
      session: _activeRoamController.session,
      reading: _activeRoamController.latestLocationReading,
      connectivityState: _offlineIntelligence.connectivityState,
      offlineCacheState: _offlineIntelligence.cacheState,
    );
    unawaited(
      _offlineIntelligence.preloadJourney(_activeRoamController.session),
    );
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2D6CDF);

    return FutureBuilder<void>(
      future: _preferencesLoad,
      builder: (context, snapshot) {
        return FutureBuilder<void>(
          future: _activeRoamLoad,
          builder: (context, activeSnapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                activeSnapshot.connectionState != ConnectionState.done) {
              return const MaterialApp(
                home: Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            return PreferencesScope(
              controller: _preferencesController,
              child: AdventureRequestScope(
                controller: _adventureRequestController,
                child: LocationScope(
                  controller: _locationController,
                  child: ActiveRoamScope(
                    controller: _activeRoamController,
                    child: RoverOnDeviceAiScope(
                      coordinator: _roverAiCoordinator,
                      child: MaterialApp.router(
                        routerConfig: _router,
                        theme: ThemeData(
                          colorScheme: ColorScheme.fromSeed(seedColor: seed),
                          splashFactory: NoSplash.splashFactory,
                          useMaterial3: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _activeRoamController.removeListener(_syncPhase13Situation);
    _offlineIntelligence.removeListener(_syncPhase13Situation);
    _router.dispose();
    unawaited(_roverAiCoordinator.dispose());
    _activeRoamController.dispose();
    _locationController.dispose();
    _adventureRequestController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }
}

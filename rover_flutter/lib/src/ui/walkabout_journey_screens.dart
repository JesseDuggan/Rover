part of 'placeholder_screens.dart';

/// Audio belongs to the journey, not to a tab or a camera view.
class WalkaboutJourneyHost extends StatefulWidget {
  const WalkaboutJourneyHost({required this.child, super.key});
  final Widget child;
  @override
  State<WalkaboutJourneyHost> createState() => _WalkaboutJourneyHostState();
}

class _WalkaboutJourneyHostState extends State<WalkaboutJourneyHost> {
  RoverVoiceController? _voice;
  AdaptiveRouteStoryController? _stories;
  RoamSession? _lastSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = ActiveRoamScope.of(context);
    if (_voice == null) {
      final repository = active.walkRepository;
      final storyRepository = repository is AdaptiveRouteStoryRepository
          ? repository as AdaptiveRouteStoryRepository
          : HttpWalkRepository();
      final flags = repository is AdaptiveRouteStoryRepository
          ? RoverPhase16Flags.fromEnvironment()
          : const RoverPhase16Flags(enabled: false);
      final installationIds = InstallationIdRepository();
      _voice = RoverVoiceController(
        walkRepository: repository,
        premiumVoice: RoverPremiumVoiceCoordinator(walkRepository: repository),
        onDeviceAiCoordinator: RoverOnDeviceAiScope.of(context),
        preferencesController: PreferencesScope.of(context),
        onArrivalNarrated: active.markArrivalNarrated,
        adaptiveRouteStoriesEnabled: flags.enabled,
        interactionProfileIdResolver: () async {
          final id = await installationIds.loadOrCreate();
          return (await repository.createOrGetGuestProfile(id)).profileId;
        },
      );
      _stories = AdaptiveRouteStoryController(
        repository: storyRepository,
        flags: flags,
      );
      _stories!.startPolling(
        session: () => active.session,
        voiceController: _voice!,
        isForeground: () =>
            mounted &&
            (supportsBackgroundWalking ||
                WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed),
      );
    }
    final session = active.session;
    if (!identical(_lastSession, session)) {
      _lastSession = session;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(active.session, session)) return;
        unawaited(_syncSession(active, session));
      });
    }
  }

  Future<void> _syncSession(
    ActiveRoamController active,
    RoamSession session,
  ) async {
    try {
      await _voice!.syncWithSession(session);
      if (mounted && identical(active.session, session)) {
        await _stories!.syncWithSession(session, _voice!);
      }
    } catch (_) {
      FieldDiagnostics.instance.record(
        'journey',
        'Session audio sync failed; retrying on the next update.',
      );
    }
  }

  @override
  void dispose() {
    _stories?.dispose();
    _voice?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WalkaboutJourneyScope(
    voice: _voice!,
    stories: _stories!,
    child: widget.child,
  );
}

class WalkaboutJourneyScope extends InheritedWidget {
  const WalkaboutJourneyScope({
    required this.voice,
    required this.stories,
    required super.child,
    super.key,
  });
  final RoverVoiceController voice;
  final AdaptiveRouteStoryController stories;
  static WalkaboutJourneyScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WalkaboutJourneyScope>()!;
  @override
  bool updateShouldNotify(WalkaboutJourneyScope oldWidget) =>
      voice != oldWidget.voice || stories != oldWidget.stories;
}

class WalkaboutMic extends StatelessWidget {
  const WalkaboutMic({super.key});
  @override
  Widget build(BuildContext context) => FloatingActionButton(
    heroTag: null,
    tooltip: 'Walkabout AI',
    onPressed: () => showWalkaboutVoice(context),
    child: const Icon(Icons.mic_none, size: 24),
  );
}

Future<void> showWalkaboutVoice(BuildContext context) async {
  final router = GoRouter.of(context);
  final journey = WalkaboutJourneyScope.of(context);
  final active = ActiveRoamScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AnimatedBuilder(
      animation: journey.voice,
      builder: (context, _) {
        final voice = journey.voice;
        final session = active.session;
        final canAsk =
            session.apiWalkSessionId != null &&
            session.roam.stops.isNotEmpty &&
            voice.canAsk;
        final actions = _VoiceNarrationPanel(
          session: session,
          voiceController: voice,
          isApiWalk: session.apiWalkSessionId != null,
        );
        final status = switch (voice.state) {
          RoverAudioState.listening => 'Listening',
          RoverAudioState.transcribing => 'Transcribing',
          RoverAudioState.thinking => 'Thinking',
          RoverAudioState.preparingNarration => 'Preparing audio',
          RoverAudioState.speakingAnswer ||
          RoverAudioState.speakingNarration => 'Speaking',
          RoverAudioState.narrationPaused => 'Paused',
          RoverAudioState.error => 'Voice unavailable',
          RoverAudioState.idle => 'What would you like to discover?',
        };
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              0,
              22,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: WalkHeading('Walkabout AI')),
                        IconButton(
                          tooltip: 'Close voice panel',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Icon(
                      Icons.graphic_eq,
                      color: WalkaboutColors.teal,
                      size: 24,
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(status, textAlign: TextAlign.center),
                    ),
                    if (voice.errorMessage case final error?) ...[
                      const SizedBox(height: 12),
                      Text(error),
                      TextButton.icon(
                        onPressed: openRoverMicrophoneSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Microphone settings'),
                      ),
                    ],
                    if (voice.transcriptText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(voice.transcriptText),
                    ],
                    if (voice.lastTurn case final turn?) ...[
                      const SizedBox(height: 12),
                      Text(turn.answerText),
                      if (turn.safetyNotice != null) Text(turn.safetyNotice!),
                      if (actions._canReviewVoiceSuggestion(turn))
                        TextButton.icon(
                          onPressed: active.isBusy
                              ? null
                              : () async {
                                  await actions._reviewVoiceSuggestion(
                                    context,
                                    turn,
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  if (active.session.pendingAdaptation !=
                                      null) {
                                    router.go('/routes');
                                  }
                                },
                          icon: const Icon(Icons.alt_route),
                          label: const Text('Review route change'),
                        ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: WalkaboutColors.pink,
                      ),
                      onPressed: canAsk
                          ? () => actions._startAskRover(context)
                          : null,
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Ask Walkabout AI'),
                    ),
                    TextButton.icon(
                      onPressed: canAsk
                          ? () => actions._typeAskRover(context)
                          : null,
                      icon: const Icon(Icons.keyboard_outlined),
                      label: const Text('Type a question'),
                    ),
                    if (session.apiWalkSessionId == null)
                      const Text(
                        'Create a walk to ask about your route.',
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class WalkaboutWalkScreen extends StatefulWidget {
  const WalkaboutWalkScreen({super.key});
  @override
  State<WalkaboutWalkScreen> createState() => _WalkaboutWalkScreenState();
}

class _WalkaboutWalkScreenState extends State<WalkaboutWalkScreen> with WidgetsBindingObserver {
  bool _camera = false;
  bool _memoriesOpen = false;
  ActiveRoamController? _active;

  Future<void> _reviewDirection(ActiveRoamController controller) async {
    final proposal = controller.session.pendingAdaptation;
    if (proposal == null || controller.isBusy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(proposal.title),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(proposal.explanation),
            const SizedBox(height: 12),
            Text('${proposal.estimatedNewTotalMinutes} minutes remaining'),
            for (final stop in proposal.proposedStops) Text(stop.name),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current route')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Follow new direction')),
        ],
      ),
    );
    if (!mounted || controller.session.pendingAdaptation?.adaptationId != proposal.adaptationId) return;
    if (accepted == true) {
      await controller.acceptPendingAdaptation();
    } else {
      await controller.rejectPendingAdaptation();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() {});
    if (state != AppLifecycleState.resumed) _active?.setMapVisible(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active?.setMapVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ActiveRoamScope.of(context);
    _active = controller;
    final mapVisible = !_camera && !_memoriesOpen && TickerMode.valuesOf(context).enabled &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.setMapVisible(mapVisible);
    });
    final session = controller.session;
    if (session.apiWalkSessionId != null &&
        session.status == RoamSessionStatus.notStarted) {
      return const WalkPreviewScreen();
    }
    if (session.apiWalkSessionId == null ||
        session.roam.stops.isEmpty ||
        session.status == RoamSessionStatus.ended ||
        session.status == RoamSessionStatus.completed) {
      return const WalkHomeScreen();
    }
    final journey = WalkaboutJourneyScope.of(context);
    final guidance = session.navigationGuidance;
    final visible = TickerMode.valuesOf(context).enabled;
    final next = session.arrivedAtCurrentStop
        ? session.nextStop
        : session.currentStop;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: Column(
            children: [
              SizedBox(width: double.infinity, child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.map_outlined),
                  label: Text('Map'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.photo_camera_outlined),
                  label: Text('Camera'),
                ),
              ],
              selected: {_camera},
              onSelectionChanged: (v) => setState(() => _camera = v.first),
              )),
              Row(children: [
              Expanded(child: Row(children: [
                Switch(
                  value: controller.recordGpsTrail,
                  onChanged: controller.setRecordGpsTrail,
                ),
                const Flexible(child: Text('Record GPS trail')),
              ])),
              IconButton(
                tooltip: 'View recorded GPS trail',
                icon: const Icon(Icons.timeline),
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => WalkTrailScreen(sessionId: session.apiWalkSessionId!,
                    store: controller.trailStore,
                    beforeDelete: () => controller.setRecordGpsTrail(false)),
                )),
              ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Expanded(child: TextButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Tell me about here'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => TellHereScreen(voice: journey.voice,
                    repository: controller.walkRepository, location: LocationScope.of(context),
                    interests: PreferencesScope.of(context).preferences.interests))),
              )),
              IconButton(
                tooltip: 'Capture a memory',
                icon: const Icon(Icons.add_a_photo_outlined),
                onPressed: _memoriesOpen ? null : () async {
                  setState(() => _memoriesOpen = true);
                  controller.setMapVisible(false);
                  try {
                    await journey.voice.stopAll();
                    if (!context.mounted) return;
                    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                      builder: (_) => MemoryCaptureScreen(store: MemoryStore(), journey: MemoryJourney(
                        id: session.apiWalkSessionId!, route: session.roam))));
                  } finally {
                    if (mounted) setState(() => _memoriesOpen = false);
                  }
                },
              ),
              IconButton(
                tooltip: 'Save walk',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: () => context.push('/profile/saved-walks'),
              ),
              IconButton(
                tooltip: 'Walk memories',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _memoriesOpen ? null : () async {
                  setState(() => _memoriesOpen = true);
                  controller.setMapVisible(false);
                  try {
                    await journey.voice.stopAll();
                    if (!context.mounted) return;
                    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                      builder: (_) => MemoriesScreen(stories: journey.stories.pack?.stories ?? const [], journey: MemoryJourney(
                        id: session.apiWalkSessionId!, route: session.roam))));
                  } finally {
                    if (mounted) setState(() => _memoriesOpen = false);
                  }
                },
              ),
              ]),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight < 430 ||
                  MediaQuery.textScalerOf(context).scale(16) > 24;
              final panelHeight = (constraints.maxHeight * .32).clamp(
                48.0,
                180.0,
              );
              return IndexedStack(
                index: _camera ? 1 : 0,
                children: [
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      RoverMapView(
                        active: mapVisible,
                        key: ValueKey(
                          'journey-map-${session.apiWalkSessionId}',
                        ),
                        currentLocation: session.simulatedLocation,
                        orderedStops: session.orderedStops,
                        routeGeometry: session.roam.routeGeometry,
                        currentStopIndex: session.currentStopIndex,
                        completedStopIds: session.completedStopIds,
                        currentHeadingDegrees: session.currentHeadingDegrees,
                        mapProvider: RoverMapProvider(
                          routingProvider: session.roam.routeProvider,
                        ),
                        enableExpand: false,
                        height: constraints.maxHeight,
                        viewportPadding: EdgeInsets.only(
                          top: compact ? panelHeight + 16 : 140,
                          bottom: compact ? panelHeight + 16 : 180,
                        ),
                        onStopTap: (ordered) =>
                            _openStop(context, ordered.stop.id),
                      ),
                      Positioned(
                        top: 8,
                        left: 20,
                        right: 20,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: panelHeight),
                          child: SingleChildScrollView(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      session.isOffRoute
                                          ? Icons.alt_route
                                          : Icons.navigation_outlined,
                                      color: WalkaboutColors.blue,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            session.status ==
                                                    RoamSessionStatus.paused
                                                ? 'Walk paused'
                                                : session.isOffRoute
                                                ? 'You are off the planned route'
                                                : guidance
                                                          ?.maneuver
                                                          .instruction ??
                                                      'Continue to ${next?.name ?? 'the end of your walk'}',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (session.pendingAdaptation?.type == 'FollowDirection')
                                            TextButton.icon(
                                              onPressed: controller.isBusy ? null : () => _reviewDirection(controller),
                                              icon: const Icon(Icons.alt_route),
                                              label: const Text('Follow your new direction?'),
                                            ),
                                          if (guidance != null)
                                            Text(
                                              '${guidance.distanceMeters} m',
                                            ),
                                          if (controller.locationFailure !=
                                              null)
                                            TextButton(
                                              onPressed: controller
                                                  .startLocationTracking,
                                              child: const Text(
                                                'Restore location',
                                              ),
                                            ),
                                          if (session.errorMessage != null)
                                            Text(
                                              session.errorMessage!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 20,
                        right: 94,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: panelHeight),
                          child: SingleChildScrollView(
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: next == null
                                    ? null
                                    : () => _openStop(context, next.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Next stop',
                                        style: TextStyle(
                                          color: WalkaboutColors.teal,
                                        ),
                                      ),
                                      Text(
                                        next?.name ?? 'Walk complete',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (next != null)
                                        Text(
                                          _distanceLabel(
                                            context,
                                            session.distanceToNextStopMeters ??
                                                session.distanceMilesToNext *
                                                    1609.344,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 12,
                        right: 20,
                        child: WalkaboutMic(),
                      ),
                    ],
                  ),
                  if (_camera && visible && !_memoriesOpen)
                    CameraExplorerScreen(
                      embedded: true,
                      voiceController: journey.voice,
                      onVoice: () => showWalkaboutVoice(context),
                    )
                  else
                    const SizedBox.expand(),
                ],
              );
            },
          ),
        ),
        if (!_camera)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .24,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: AnimatedBuilder(
                animation: journey.stories,
                builder: (context, _) {
                  final pack =
                      journey.stories.pack?.walkSessionId ==
                          session.apiWalkSessionId
                      ? journey.stories.pack
                      : null;
                  final stop = session.arrivedAtCurrentStop
                      ? session.recentNarrationStop ?? session.currentStop
                      : session.currentStop;
                  return StoryImages(
                    compact: true,
                    nearbyLocation: stop.coordinates,
                    sourceUrls: [
                      if (stop.sourceUrl != null) stop.sourceUrl!,
                      for (final story
                          in pack?.stories ?? <AdaptiveRouteStory>[])
                        for (final source in story.sources)
                          if (source.url != null) source.url!,
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

String _distanceLabel(BuildContext context, double meters) {
  if (PreferencesScope.of(context).preferences.distanceUnit == 'miles') {
    return meters < 160.9344
        ? '${(meters * 3.28084).round()} ft'
        : '${(meters / 1609.344).toStringAsFixed(1)} mi';
  }
  return meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
}

void _openStop(BuildContext context, String id) =>
    context.go('/profile/stops/${Uri.encodeComponent(id)}');

class WalkaboutPlanScreen extends StatelessWidget {
  const WalkaboutPlanScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final active = ActiveRoamScope.of(context);
    final session = active.session;
    final stops = session.roam.stops;
    return Scaffold(
      floatingActionButton: const WalkaboutMic(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 96),
        children: [
          const WalkHeading('Your itinerary'),
          const SizedBox(height: 12),
          if (stops.isEmpty)
            const _JourneyEmpty(
              message: 'Your itinerary will appear after you create a walk.',
            )
          else ...[
            Text(session.roam.summary),
            if (session.apiWalkSessionId != null &&
                session.status != RoamSessionStatus.completed &&
                session.status != RoamSessionStatus.ended)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/home/create?placeMode=stop'),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add a stop or destination'),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('${stops.length} stops')),
                Chip(
                  label: Text(
                    '${session.roam.totalEstimatedMinutes} min total',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < stops.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openStop(context, stops[i].id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                session.completedStopIds.contains(stops[i].id)
                                ? const Color(0xFFDFF3F4)
                                : const Color(0xFFE8F2FF),
                            child:
                                session.completedStopIds.contains(stops[i].id)
                                ? const Icon(
                                    Icons.check,
                                    color: WalkaboutColors.teal,
                                  )
                                : Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: WalkaboutColors.blue,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stops[i].name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(stops[i].category),
                                Text(
                                  session.completedStopIds.contains(stops[i].id)
                                      ? 'Visited'
                                      : session.skippedStopIds.contains(
                                          stops[i].id,
                                        )
                                      ? 'Skipped'
                                      : i == session.currentStopIndex
                                      ? 'Next stop'
                                      : 'Upcoming',
                                  style: const TextStyle(
                                    color: WalkaboutColors.teal,
                                  ),
                                ),
                                if (i == session.currentStopIndex &&
                                    session.distanceToNextStopMeters != null)
                                  Text(
                                    '${_distanceLabel(context, session.distanceToNextStopMeters!)} from you',
                                  ),
                                if (i != session.currentStopIndex &&
                                    stops[i].distanceFromPreviousStopMeters > 0)
                                  Text(
                                    '${_distanceLabel(context, stops[i].distanceFromPreviousStopMeters.toDouble())} from previous stop',
                                  ),
                                Text(
                                  '${stops[i].estimatedVisitMinutes} min visit',
                                ),
                                if (i == session.currentStopIndex &&
                                    session.apiWalkSessionId != null &&
                                    session.status ==
                                        RoamSessionStatus.active &&
                                    i < stops.length - 1)
                                  TextButton.icon(
                                    icon: const Icon(Icons.skip_next),
                                    label: const Text('Skip and replace'),
                                    onPressed: active.isBusy
                                        ? null
                                        : () async {
                                            await active.evaluateAdaptation(
                                              requestedType: 'SkipStop',
                                              userRequest: 'Skip the next stop and find a matching replacement ahead',
                                            );
                                            if (context.mounted) {
                                              context.go('/routes');
                                            }
                                          },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _JourneyEmpty extends StatelessWidget {
  const _JourneyEmpty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.go('/home/create'),
          icon: const Icon(Icons.add),
          label: const Text('Create a walk'),
        ),
      ],
    ),
  );
}

class WalkaboutStoriesScreen extends StatelessWidget {
  const WalkaboutStoriesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    final journey = WalkaboutJourneyScope.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([journey.stories, journey.voice]),
      builder: (context, _) {
        final stories = journey.stories;
        final voice = journey.voice;
        final pack = stories.pack?.walkSessionId == session.apiWalkSessionId
            ? stories.pack
            : null;
        final selection = pack == null ? null : stories.currentSelection;
        final playing =
            selection != null && voice.activeStoryId == selection.story.storyId;
        final paused =
            selection != null &&
            voice.hasInterruptedAdaptiveStory(selection.story.storyId);
        final details = _AdaptiveRouteStoryPanel(
          session: session,
          controller: stories,
          voiceController: voice,
        );
        return Scaffold(
          floatingActionButton: const WalkaboutMic(),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 96),
            children: [
              Row(
                children: [
                  const Expanded(child: WalkHeading('Walk stories')),
                  IconButton(
                    tooltip: 'Refresh route stories',
                    onPressed:
                        session.apiWalkSessionId == null ||
                            stories.isBusy ||
                            stories.isRefreshing
                        ? null
                        : () => stories.refreshPack(session),
                    icon: stories.isRefreshing
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (session.roam.stops.isEmpty)
                const _JourneyEmpty(
                  message: 'Stories belong to your current walk.',
                )
              else ...[
                Text('${pack?.stories.length ?? 0} stories on this walk'),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(stories.listeningStatus(session)),
                ),
                if (stories.usingOfflinePack)
                  const Text('Downloaded stories - offline'),
                if (stories.errorMessage case final error?)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (stories.isBusy && selection == null)
                  const LinearProgressIndicator(),
                if (selection != null) ...[
                  const SizedBox(height: 18),
                  Card(
                    color: WalkaboutColors.navy,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: DefaultTextStyle(
                        style: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              voice.state == RoverAudioState.speakingNarration
                                  ? 'Story waiting for stop information'
                                  : 'Current story',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              selection.story.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'About ${selection.variant.estimatedDurationSeconds} sec',
                            ),
                            Wrap(
                              children: [
                                IconButton.filled(
                                  tooltip: playing
                                      ? 'Pause story'
                                      : paused
                                      ? 'Resume story'
                                      : 'Play story',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: WalkaboutColors.navy,
                                  ),
                                  onPressed: stories.isBusy && !playing
                                      ? null
                                      : () => playing
                                            ? stories.pauseCurrent(
                                                session,
                                                voice,
                                              )
                                            : paused
                                            ? stories.resumeCurrent(
                                                session,
                                                voice,
                                              )
                                            : stories.playCurrent(
                                                session,
                                                voice,
                                              ),
                                  icon: Icon(
                                    playing ? Icons.pause : Icons.play_arrow,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Skip story',
                                  color: Colors.white,
                                  onPressed: stories.isBusy
                                      ? null
                                      : () => stories.skipCurrent(session),
                                  icon: const Icon(Icons.skip_next),
                                ),
                                IconButton(
                                  tooltip: 'Save story',
                                  color: Colors.white,
                                  onPressed: () => stories.saveCurrent(session),
                                  icon: const Icon(Icons.bookmark_border),
                                ),
                                IconButton(
                                  tooltip: 'Share story with friends',
                                  color: Colors.white,
                                  icon: const Icon(Icons.share_outlined),
                                  onPressed: () async {
                                    await voice.stopAll();
                                    if (!context.mounted) return;
                                    await Navigator.push(context, MaterialPageRoute<void>(
                                      builder: (_) => ShareWalkScreen(
                                        journey: session.apiWalkSessionId == null ? null : MemoryJourney(
                                          id: session.apiWalkSessionId!, route: session.roam),
                                        stories: [{
                                          'title': selection.story.title,
                                          'narration': selection.variant.narration,
                                          'notice': [
                                            if (selection.story.sensitivityNotice != null) selection.story.sensitivityNotice!,
                                            ...selection.story.uncertainClaims,
                                          ].join('\n'),
                                          'sources': selection.story.sources.map((s) => s.url)
                                              .whereType<String>().where((url) => Uri.tryParse(url)?.scheme == 'https').take(20).toList(),
                                          'location': {
                                            'latitude': selection.story.latitude,
                                            'longitude': selection.story.longitude,
                                          },
                                        }],
                                      ),
                                    ));
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Story sources',
                                  color: Colors.white,
                                  onPressed: () =>
                                      details._showSources(context),
                                  icon: const Icon(Icons.fact_check_outlined),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Story text and pictures'),
                    children: [
                      if (selection.story.sensitivityNotice case final notice?)
                        Text(notice),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(selection.variant.narration),
                      ),
                      if (selection.story.uncertainClaims.isNotEmpty)
                        Text(
                          'Source uncertainty: ${selection.story.uncertainClaims.join(' ')}',
                        ),
                      StoryImages(
                        key: ValueKey('pictures-${selection.story.storyId}'),
                        sourceUrls: selection.story.sources
                            .map((s) => s.url)
                            .whereType<String>()
                            .toList(),
                      ),
                      TextButton.icon(
                        onPressed: stories.isBusy
                            ? null
                            : () => stories.tellMore(session, voice),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Tell me more'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                for (final story
                    in pack?.stories ?? const <AdaptiveRouteStory>[])
                  if (story.storyId != selection?.story.storyId)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: const Icon(
                            Icons.headphones_outlined,
                            color: WalkaboutColors.teal,
                          ),
                          title: Text(story.title),
                          subtitle: Text(
                            [
                              if (story.geographicArea != null)
                                story.geographicArea!,
                              stories.automaticStoryStatus(story, session),
                              if (story.variants.isNotEmpty)
                                'About ${story.variants.first.estimatedDurationSeconds} sec',
                            ].join('\n'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: stories.isBusy
                              ? null
                              : () =>
                                    stories.selectStory(story.storyId, session),
                        ),
                      ),
                    ),
                OutlinedButton.icon(
                  onPressed: () => details._askAboutRoute(context),
                  icon: const Icon(Icons.question_answer_outlined),
                  label: const Text('Ask about route'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class WalkaboutStopListScreen extends StatelessWidget {
  const WalkaboutStopListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final stops = ActiveRoamScope.of(context).session.roam.stops;
    return Scaffold(
      appBar: AppBar(title: const Text('Stop details')),
      floatingActionButton: const WalkaboutMic(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 96),
        children: [
          if (stops.isEmpty)
            const _JourneyEmpty(message: 'No stops in your current walk.'),
          for (var i = 0; i < stops.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  leading: Text('${i + 1}'),
                  title: Text(stops[i].name),
                  subtitle: Text(stops[i].category),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openStop(context, stops[i].id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WalkaboutStopScreen extends StatelessWidget {
  const WalkaboutStopScreen({required this.stopId, super.key});
  final String stopId;
  @override
  Widget build(BuildContext context) {
    final session = ActiveRoamScope.of(context).session;
    final index = session.roam.stops.indexWhere((s) => s.id == stopId);
    if (index < 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stop details')),
        body: const Padding(
          padding: EdgeInsets.all(22),
          child: Text('This stop is no longer on your route.'),
        ),
      );
    }
    final stop = session.roam.stops[index];
    final journey = WalkaboutJourneyScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stop details')),
      floatingActionButton: const WalkaboutMic(),
      body: AnimatedBuilder(
        animation: journey.stories,
        builder: (context, _) {
          final related =
              journey.stories.pack?.stories
                  .where(
                    (story) =>
                        story.placeId == stop.id ||
                        (stop.providerPlaceId != null &&
                            story.placeId == stop.providerPlaceId),
                  )
                  .toList() ??
              [];
          final imageUri = Uri.tryParse(stop.image);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 96),
            children: [
              Text(
                'Stop ${index + 1} of ${session.roam.stops.length} - ${stop.category}',
                style: const TextStyle(color: WalkaboutColors.teal),
              ),
              const SizedBox(height: 12),
              WalkHeading(stop.name),
              const SizedBox(height: 18),
              if (imageUri?.scheme == 'https')
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    stop.image,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    semanticLabel: stop.name,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 80,
                      child: Center(child: Text('Photo unavailable')),
                    ),
                  ),
                ),
              if (stop.attributionLabel != null) Text(stop.attributionLabel!),
              const SizedBox(height: 18),
              Text(stop.shortDescription),
              if (stop.address != null) ...[
                const SizedBox(height: 12),
                Text(stop.address!),
              ],
              if (stop.sponsoredDisclosure != null) ...[
                const SizedBox(height: 12),
                Text(stop.sponsoredDisclosure!),
              ],
              if (stop.narration?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                StopNarrationControls(stop: stop, voice: journey.voice),
              ],
              const SizedBox(height: 20),
              for (final story in related)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.headphones_outlined),
                  title: Text(story.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    journey.stories.selectStory(story.storyId, session);
                    context.go('/stories');
                  },
                ),
              if (related.isEmpty)
                const Text('No linked story for this stop yet.'),
              StoryImages(
                nearbyLocation: stop.coordinates,
                sourceUrls: [
                  if (stop.sourceUrl != null) stop.sourceUrl!,
                  for (final story in related)
                    for (final source in story.sources)
                      if (source.url != null) source.url!,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class WalkaboutRoutesScreen extends StatefulWidget {
  const WalkaboutRoutesScreen({super.key});
  @override
  State<WalkaboutRoutesScreen> createState() => _WalkaboutRoutesScreenState();
}

class _WalkaboutRoutesScreenState extends State<WalkaboutRoutesScreen> {
  int? _minutes;
  bool _returnToStart = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final active = ActiveRoamScope.of(context);
    final session = active.session;
    final preferences = PreferencesScope.of(context);
    final p = preferences.preferences;
    final requestController = AdventureRequestScope.of(context);
    final request = requestController.request ?? AdventureRequest.empty;
    final minutes = _minutes ?? request.availableMinutes.clamp(20, 240);
    final live =
        session.apiWalkSessionId != null &&
        session.status == RoamSessionStatus.active;
    Future<void> save(AdventureRequest next, RoverPreferences prefs) async {
      try {
        requestController.save(next);
        await preferences.save(prefs);
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'Could not save route preferences.');
        }
      }
    }

    return Scaffold(
      floatingActionButton: const WalkaboutMic(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 96),
        children: [
          const WalkHeading('Route options'),
          const SizedBox(height: 20),
          Text('Time available: $minutes min'),
          Slider(
            value: minutes.toDouble(),
            min: 20,
            max: 240,
            divisions: 44,
            label: '$minutes min',
            onChanged: active.isBusy
                ? null
                : (v) {
                    setState(() => _minutes = v.round());
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(p.walkingPace),
            initialValue: ['easy', 'steady', 'brisk'].contains(p.walkingPace)
                ? p.walkingPace
                : 'easy',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Walking pace for new walks',
            ),
            items: [
              for (final pace in ['easy', 'steady', 'brisk'])
                DropdownMenuItem(
                  value: pace,
                  child: Text(
                    '${pace[0].toUpperCase()}${pace.substring(1)} pace',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                unawaited(
                  save(
                    request.copyWith(
                      pace: '${value[0].toUpperCase()}${value.substring(1)}',
                    ),
                    p.copyWith(walkingPace: value),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.trailing,
            title: const Text('Return to starting point now'),
            value: _returnToStart,
            onChanged: live && !active.isBusy
                ? (v) => setState(() => _returnToStart = v!)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accessible paths for new walks'),
            value: p.mobility.contains('Accessible'),
            onChanged: (v) => unawaited(
              save(
                request.copyWith(routeMode: v ? 'Accessible route' : 'Walking'),
                p.copyWith(mobility: v ? 'Accessible route' : ''),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avoid stairs for new walks'),
            value: p.mobility.toLowerCase().contains('stairs'),
            onChanged: (value) => unawaited(
              save(
                request.copyWith(routeMode: value ? 'Avoid stairs' : 'Walking'),
                p.copyWith(mobility: value ? 'Avoid stairs' : ''),
              ),
            ),
          ),
          if (live)
            const Text('Pace and accessibility changes apply to new walks.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: active.isBusy
                ? null
                : () async {
                    setState(() => _error = null);
                    try {
                      requestController.save(
                        request.copyWith(availableMinutes: minutes),
                      );
                      if (!live) {
                        if (context.mounted) context.go('/home/create');
                        return;
                      }
                      await active.evaluateAdaptation(
                        requestedType: _returnToStart
                            ? 'ReturnToStart'
                            : minutes <
                                  (session.timeRemainingMinutes ??
                                      session.roam.totalEstimatedMinutes)
                            ? 'ShortenWalk'
                            : 'ExtendWalk',
                        availableMinutes: minutes,
                        userRequest: _returnToStart
                            ? 'Return to the starting point'
                            : 'I have $minutes minutes available',
                      );
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'Route update failed. Your current route has been kept.',
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text(live ? 'Update my route' : 'Create a walk'),
          ),
          if (_error != null) Text(_error!),
          if (session.errorMessage != null) Text(session.errorMessage!),
          if (live) ...[
            const SizedBox(height: 24),
            _AdaptationPanel(controller: active, session: session),
          ],
        ],
      ),
    );
  }
}

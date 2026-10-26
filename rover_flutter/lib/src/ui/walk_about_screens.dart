import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../adventure/adventure_request.dart';
import '../adventure/adventure_request_controller.dart';
import '../api/walk_place_models.dart';
import '../api/problem_details.dart';
import '../location/location_controller.dart';
import '../maps/rover_map_view.dart';
import '../preferences/preferences_controller.dart';
import '../preferences/rover_preferences.dart';
import 'walk_about_theme.dart';
import 'placeholder_screens.dart' show WalkaboutJourneyScope;
import 'tell_here_screen.dart';
import '../drives/scenic_drive.dart';
import '../drives/scenic_drive_screen.dart';
import '../drives/drive_narration.dart';

const walkInterests = [
  'history',
  'coffee',
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
String _label(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

class WalkHomeScreen extends StatefulWidget {
  const WalkHomeScreen({this.fineTune = false, super.key});
  final bool fineTune;
  @override
  State<WalkHomeScreen> createState() => _WalkHomeScreenState();
}

class _WalkHomeScreenState extends State<WalkHomeScreen> {
  final _prompt = TextEditingController();
  AdventureRequest? _draft;
  bool _busy = false;
  String? _error;
  String _placeMode = 'Discover';
  WalkPlaceOption? _selectedPlace;
  List<WalkPlaceOption> _placeResults = [];

  bool get _usesPlace => _placeMode != 'Discover';

  Future<void> _searchPlaces() async {
    if (_busy) return;
    final query = _prompt.text.trim();
    if (query.isEmpty || query.length > 256) {
      setState(() => _error = 'Enter a place name of up to 256 characters.');
      return;
    }
    final repository = ActiveRoamScope.of(context).walkRepository;
    if (repository is! WalkPlaceRepository) {
      setState(() => _error = 'Place search is unavailable.');
      return;
    }
    final location = LocationScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _selectedPlace = null;
      _placeResults = [];
    });
    try {
      final fix = await location.ensureDeviceLocation(forceRefresh: true);
      if (!mounted) return;
      if (fix.location == null) {
        setState(() => _error = 'Allow location access to find nearby places.');
        return;
      }
      final result = await (repository as WalkPlaceRepository).searchWalkPlaces(
        query: query,
        latitude: fix.location!.latitude,
        longitude: fix.location!.longitude,
      );
      if (!mounted) return;
      setState(() {
        _placeResults = result.places;
        if (result.places.isEmpty) {
          _error = result.warnings.isEmpty
              ? 'No matching places nearby. Try the full name and town.'
              : 'Place search is temporarily unavailable. Please try again.';
        }
      });
    } on RoverApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not search for places. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saved = AdventureRequestScope.of(context).request;
    if (_draft != null) {
      if (saved != null && saved != _draft) {
        _draft = saved;
        _prompt.text = saved.naturalRequest;
      }
      return;
    }
    final p = PreferencesScope.of(context).preferences;
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['placeMode'] == 'stop') _placeMode = 'Add stop';
    final queryMinutes = int.tryParse(uri.queryParameters['minutes'] ?? '');
    final minutes = int.tryParse(
      RegExp(r'\d+').firstMatch(p.availableTime)?.group(0) ?? '',
    );
    _draft =
        saved ??
        AdventureRequest.empty.copyWith(
          naturalRequest: '',
          availableMinutes:
              queryMinutes?.clamp(20, 240) ??
              (minutes == null
                  ? 90
                  : (p.availableTime.contains('hour') ? minutes * 60 : minutes)
                        .clamp(20, 240)),
          startingPoint: 'Current device location',
          pace: p.walkingPace.isEmpty ? 'Easy' : _label(p.walkingPace),
          routeMode: p.mobility.isEmpty ? 'Walking' : p.mobility,
          budget: p.includePaidAttractions
              ? 'Include paid attractions'
              : 'Free-only',
        );
    final cameraPlace = uri.queryParameters['cameraPlace'];
    if (cameraPlace != null) {
      _draft = _draft!.copyWith(
        naturalRequest: 'Include $cameraPlace in my walk.',
      );
    }
    _prompt.text = _draft!.naturalRequest;
  }

  void _update(AdventureRequest request) {
    _draft = request;
    AdventureRequestScope.of(context).save(request);
    setState(() {});
  }

  Future<void> _create() async {
    if (_busy || ActiveRoamScope.of(context).isBusy) return;
    final controller = ActiveRoamScope.of(context);
    if (_usesPlace && _selectedPlace == null) {
      await _searchPlaces();
      return;
    }
    final selectedPlace = _usesPlace
        ? WalkPlaceSelection(
            query: _prompt.text.trim(),
            placeId: _selectedPlace!.placeId,
            isDestination: _placeMode == 'End here',
          )
        : null;
    final changingWalk =
        selectedPlace != null &&
        controller.session.apiWalkSessionId != null &&
        controller.session.status != RoamSessionStatus.completed &&
        controller.session.status != RoamSessionStatus.ended;
    if (!changingWalk &&
        (controller.session.status == RoamSessionStatus.active ||
            controller.session.status == RoamSessionStatus.paused)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('You have a walk in progress'),
          content: const Text('End that walk before creating another?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep walking'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End and create'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
      await controller.cancelApiWalk();
      if (!mounted) return;
      if (controller.session.errorMessage != null) {
        setState(() => _error = controller.session.errorMessage);
        return;
      }
    }
    final p = PreferencesScope.of(context).preferences;
    final request = _draft!.copyWith(
      naturalRequest: _prompt.text.trim(),
      interests: p.interests,
      pace: p.walkingPace.isEmpty ? 'Easy' : _label(p.walkingPace),
      routeMode: p.mobility.isEmpty ? 'Walking' : p.mobility,
      budget: p.includePaidAttractions
          ? 'Include paid attractions'
          : 'Free-only',
      surpriseMe: _draft!.surpriseMe || p.interests.isEmpty,
      startingPoint: 'Current device location',
    );
    final errors = request.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.first);
      return;
    }
    final locationController = LocationScope.of(context);
    final drafts = AdventureRequestScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await locationController.ensureDeviceLocation(
        forceRefresh: true,
      );
      if (!mounted) return;
      if (result.location == null) {
        setState(
          () => _error = 'Allow location access to create a walk from here.',
        );
        return;
      }
      drafts.save(request);
      if (changingWalk) {
        await controller.evaluateAdaptation(
          requestedType: selectedPlace.isDestination
              ? 'SetDestination'
              : 'AddDiscovery',
          selectedPlace: selectedPlace,
          location: result.location!,
          availableMinutes: request.availableMinutes,
        );
        if (!mounted) return;
        if (controller.session.errorMessage != null) {
          setState(() => _error = controller.session.errorMessage);
          return;
        }
        final proposal = controller.session.pendingAdaptation;
        if (proposal == null) {
          setState(
            () => _error = 'No route change was returned. Please try again.',
          );
          return;
        }
        final accept = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(proposal.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(proposal.explanation),
                  const SizedBox(height: 12),
                  Text(
                    '${proposal.estimatedNewTotalMinutes} minutes remaining',
                  ),
                  for (final stop in proposal.proposedStops) Text(stop.name),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep current route'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Apply route'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (accept != true) {
          await controller.rejectPendingAdaptation();
          return;
        }
        await controller.acceptPendingAdaptation();
      } else {
        await controller.createWalk(
          request: request,
          location: result.location!,
          selectedPlace: selectedPlace,
        );
      }
      if (!mounted) return;
      if (controller.session.errorMessage != null) {
        setState(() => _error = controller.session.errorMessage);
        return;
      }
      if (controller.session.apiWalkSessionId != null &&
          controller.session.roam.stops.isNotEmpty) {
        context.go(
          changingWalk &&
                  controller.session.status != RoamSessionStatus.notStarted
              ? '/home/active-roam'
              : '/home/route-preview',
        );
      } else {
        setState(() => _error = 'No route was returned. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create your walk. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duration() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _DurationDialog(minutes: _draft!.availableMinutes),
    );
    if (value != null && mounted) {
      _update(_draft!.copyWith(availableMinutes: value));
    }
  }

  void _openDrive() {
    final active = ActiveRoamScope.of(context);
    final journey = WalkaboutJourneyScope.of(context);
    final location = LocationScope.of(context);
    final interests = PreferencesScope.of(context).preferences.interests;
    final narration = DeviceDriveNarration(active.walkRepository);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (driveContext) => ScenicDriveScreen(
        repository: HttpScenicDriveRepository(), location: location,
        narration: narration,
        beforeNavigate: () async {
          final ready = await showDialog<bool>(context: driveContext, builder: (dialogContext) => AlertDialog(
            title: const Text('Ready for driving directions?'),
            content: const Text('Set up navigation while parked. Any active walk will be paused. With automatic stories on, Walkabout prepares audio and keeps location active beside Google Maps. Do not use the screen while driving.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Open Google Maps')),
            ],
          ));
          if (ready != true || !driveContext.mounted) return false;
          if (active.session.status == RoamSessionStatus.active) await active.pause();
          await journey.voice.stopAll();
          return true;
        },
        tellHere: () => Navigator.of(driveContext).push(MaterialPageRoute<void>(
          builder: (_) => TellHereScreen(voice: journey.voice, repository: active.walkRepository,
            location: location, interests: interests))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft!;
    final session = ActiveRoamScope.of(context).session;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const WalkHeading('Create your walk'),
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
                onPressed: _busy ? null : _openDrive,
                icon: const Icon(Icons.directions_car_outlined),
                label: const Text('Scenic Drive'),
              )),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                icon: const Icon(Icons.my_location), label: const Text('Tell me about here'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => TellHereScreen(voice: WalkaboutJourneyScope.of(context).voice,
                    repository: ActiveRoamScope.of(context).walkRepository,
                    location: LocationScope.of(context),
                    interests: PreferencesScope.of(context).preferences.interests))),
              )),
              const SizedBox(height: 24),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'Discover', label: Text('Discover')),
                  ButtonSegment(value: 'Add stop', label: Text('Add stop')),
                  ButtonSegment(value: 'End here', label: Text('End here')),
                ],
                selected: {_placeMode},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _placeMode = value.single;
                        _selectedPlace = null;
                        _placeResults = [];
                        _error = null;
                      }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _prompt,
                minLines: 3,
                maxLines: 5,
                enabled: !_busy,
                onChanged: (_) {
                  if (_selectedPlace != null || _placeResults.isNotEmpty) {
                    setState(() {
                      _selectedPlace = null;
                      _placeResults = [];
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: 'What would you like to discover?',
                  hintText: _usesPlace
                      ? 'Place name or address'
                      : 'Optional request',
                  alignLabelWithHint: true,
                ),
              ),
              if (_usesPlace) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _searchPlaces,
                    icon: const Icon(Icons.search),
                    label: const Text('Find place'),
                  ),
                ),
                for (final place in _placeResults)
                  ListTile(
                    selected: _selectedPlace?.placeId == place.placeId,
                    leading: Icon(
                      _selectedPlace?.placeId == place.placeId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(place.name),
                    subtitle: Text(
                      [place.address, place.attribution]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join('\n'),
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() {
                            _selectedPlace = place;
                            _error = null;
                          }),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text('Time available'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in [30, 60, 90])
                    ChoiceChip(
                      label: Text('$minutes min'),
                      selected: draft.availableMinutes == minutes,
                      onSelected: _busy
                          ? null
                          : (_) => _update(
                              draft.copyWith(availableMinutes: minutes),
                            ),
                    ),
                  ActionChip(
                    label: Text(
                      [30, 60, 90].contains(draft.availableMinutes)
                          ? 'Custom'
                          : '${draft.availableMinutes} min',
                    ),
                    onPressed: _busy ? null : _duration,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(
                  _busy
                      ? 'Please wait...'
                      : _usesPlace && _selectedPlace == null
                      ? 'Find place'
                      : _usesPlace &&
                            session.apiWalkSessionId != null &&
                            session.status != RoamSessionStatus.completed &&
                            session.status != RoamSessionStatus.ended
                      ? 'Review route change'
                      : 'Create my walk',
                ),
              ),
              if (session.apiWalkSessionId != null &&
                  session.roam.stops.isNotEmpty &&
                  session.status != RoamSessionStatus.completed &&
                  session.status != RoamSessionStatus.ended)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => context.go(
                          session.status == RoamSessionStatus.notStarted
                              ? '/home/route-preview'
                              : '/home/active-roam',
                        ),
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Continue your walk'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }
}

class WalkChoice extends StatelessWidget {
  const WalkChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: option == value,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    ),
  );
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({required this.minutes});
  final int minutes;
  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _input = TextEditingController(text: '${widget.minutes}');
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Walk duration'),
    content: TextField(
      controller: _input,
      keyboardType: TextInputType.number,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'Minutes',
        helperText: '20 to 240 minutes',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          final value = int.tryParse(_input.text);
          if (value == null || value < 20 || value > 240) {
            setState(() => _error = 'Enter 20 to 240 minutes');
          } else {
            Navigator.pop(context, value);
          }
        },
        child: const Text('Done'),
      ),
    ],
  );
}

class WalkPreviewScreen extends StatefulWidget {
  const WalkPreviewScreen({super.key});
  @override
  State<WalkPreviewScreen> createState() => _WalkPreviewScreenState();
}

class _WalkPreviewScreenState extends State<WalkPreviewScreen> {
  bool _starting = false;
  @override
  Widget build(BuildContext context) {
    final controller = ActiveRoamScope.of(context);
    final session = controller.session;
    final route = session.roam;
    if (session.apiWalkSessionId == null ||
        route.stops.isEmpty ||
        session.status == RoamSessionStatus.completed ||
        session.status == RoamSessionStatus.ended) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your walk')),
        body: Center(
          child: TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Create a walk first'),
          ),
        ),
      );
    }
    final miles =
        PreferencesScope.of(context).preferences.distanceUnit == 'miles';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your walk'),
        actions: [
          IconButton(
            tooltip: 'Save walk',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => context.push('/profile/saved-walks'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'YOUR ROUTE IS READY',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                WalkHeading(route.stops.first.name),
                const SizedBox(height: 8),
                Text(route.summary),
                const SizedBox(height: 20),
                RoverMapView(
                  currentLocation: session.simulatedLocation,
                  orderedStops: route.orderedStops,
                  routeGeometry: route.routeGeometry,
                  height: 250,
                  overview: true,
                  enableExpand: true,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('${route.walkingMinutes} min'),
                    Text(
                      '${(miles ? route.distanceMiles : route.distanceMiles * 1.609344).toStringAsFixed(1)} ${miles ? 'mi' : 'km'}',
                    ),
                    Text('${route.stops.length} stops'),
                  ],
                ),
                for (final warning in [
                  ...route.accessibilityNotes,
                  ...route.warnings,
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(warning),
                  ),
                const SizedBox(height: 16),
                for (var i = 0; i < route.stops.length; i++) ...[
                  const Divider(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route.stops[i].name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(route.stops[i].shortDescription),
                            if (route.stops[i].attributionLabel != null)
                              Text(
                                route.stops[i].attributionLabel!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (session.errorMessage != null)
                  Text(
                    session.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    _starting
                        ? 'Starting...'
                        : session.status == RoamSessionStatus.active ||
                              session.status == RoamSessionStatus.paused
                        ? 'Continue walking'
                        : 'Start walking',
                  ),
                  onPressed: _starting || controller.isBusy
                      ? null
                      : () async {
                          setState(() => _starting = true);
                          try {
                            if (session.status ==
                                RoamSessionStatus.notStarted) {
                              await controller.startApiWalk();
                            } else if (session.status ==
                                RoamSessionStatus.paused) {
                              await controller.resume();
                            }
                            if (context.mounted &&
                                controller.session.status ==
                                    RoamSessionStatus.active) {
                              context.go('/home/active-roam');
                            }
                          } finally {
                            if (mounted) setState(() => _starting = false);
                          }
                        },
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: _starting
                        ? null
                        : () => context.go('/home/adventure-request'),
                    child: const Text('Adjust'),
                  ),
                  TextButton(
                    onPressed: _starting
                        ? null
                        : () => context.go('/home/create'),
                    child: const Text('Try another'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalkProfileScreen extends StatelessWidget {
  const WalkProfileScreen({
    this.extra = const [],
    this.floatingActionButton,
    super.key,
  });
  final List<Widget> extra;
  final Widget? floatingActionButton;
  Future<void> _save(BuildContext context, RoverPreferences p) async {
    try {
      await PreferencesScope.of(context).save(p);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save preferences. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PreferencesScope.of(context).preferences;
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 96),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 26,
                    child: Text(
                      p.firstName.isEmpty ? 'W' : p.firstName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    p.firstName.isEmpty
                        ? 'Your walks'
                        : "${p.firstName}'s walks",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Your profile'),
                ),
                const SizedBox(height: 28),
                const WalkHeading('Your interests'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final interest in {
                      ...walkInterests,
                      ...p.interests.map((e) => e.toLowerCase()),
                    })
                      FilterChip(
                        label: Text(_label(interest)),
                        selected: p.interests.any(
                          (e) => e.toLowerCase() == interest,
                        ),
                        onSelected: (selected) {
                          final values = p.interests
                              .map((e) => e.toLowerCase())
                              .toSet();
                          if (selected) {
                            values.add(interest);
                          } else {
                            values.remove(interest);
                          }
                          final excluded = p.excludedStoryCategories.toSet();
                          if (selected) {
                            excluded.remove(interest);
                          } else {
                            excluded.add(interest);
                          }
                          _save(
                            context,
                            p.copyWith(
                              interests: values.toList()..sort(),
                              excludedStoryCategories: excluded.toList()
                                ..sort(),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'How you like to walk',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                WalkChoice(
                  label: 'Your usual pace',
                  value: p.walkingPace.isEmpty ? 'Easy' : _label(p.walkingPace),
                  options: const ['Easy', 'Steady', 'Brisk'],
                  onChanged: (v) =>
                      _save(context, p.copyWith(walkingPace: v.toLowerCase())),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prefer accessible paths'),
                  value: p.mobility.isNotEmpty,
                  onChanged: (v) => _save(
                    context,
                    p.copyWith(mobility: v ? 'Accessible route' : ''),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include paid attractions'),
                  value: p.includePaidAttractions,
                  onChanged: (v) =>
                      _save(context, p.copyWith(includePaidAttractions: v)),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Stop details'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/stops'),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Walking profiles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile/walking-profiles'),
                ),
                ListTile(
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: const Text('Saved walks'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile/saved-walks'),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Walk history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/history'),
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark_border),
                  title: const Text('Saved discoveries'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/saved-discoveries'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Voice and narration'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/settings'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/profile/account'),
                ),
                ...extra,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

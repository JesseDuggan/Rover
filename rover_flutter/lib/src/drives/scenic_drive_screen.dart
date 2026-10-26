import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/problem_details.dart';
import '../location/location_controller.dart';
import '../maps/rover_map_view.dart';
import 'scenic_drive.dart';
import 'drive_settings.dart';
import 'drive_interests_screen.dart';
import 'drive_narration.dart';

class ScenicDriveScreen extends StatefulWidget {
  const ScenicDriveScreen({
    required this.repository,
    required this.location,
    required this.beforeNavigate,
    required this.tellHere,
    this.launchDirections,
    this.settingsStore,
    this.narration,
    super.key,
  });
  final ScenicDriveRepository repository;
  final DriveSettingsStore? settingsStore;
  final DriveNarration? narration;
  final LocationController location;
  final Future<bool> Function() beforeNavigate;
  final VoidCallback tellHere;
  final Future<bool> Function(Uri)? launchDirections;
  @override
  State<ScenicDriveScreen> createState() => _ScenicDriveScreenState();
}

class _ScenicDriveScreenState extends State<ScenicDriveScreen>
    with WidgetsBindingObserver {
  bool _automaticStories = true, _driveActive = false;
  Map<String, String> _storyStatus = {};
  String? _preparing;
  final _query = TextEditingController();
  final _interests = <String>{'scenic', 'history'};
  late final DriveSettingsStore _settingsStore =
      widget.settingsStore ?? FileDriveSettingsStore();
  Future<void> _saving = Future.value();
  bool _localRoads = true,
      _avoidTolls = false,
      _restStops = false,
      _chargingStops = false;
  int _maxDetour = 15;
  DrivePreferences get _preferences => DrivePreferences(
    preferLocalRoads: _localRoads,
    avoidTolls: _avoidTolls,
    maxDetourMinutes: _maxDetour,
    includeRestStops: _restStops,
    includeChargingStops: _chargingStops,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final saved = await _settingsStore.load();
      if (!mounted) return;
      setState(() {
        _interests
          ..clear()
          ..addAll(saved.interests);
        _localRoads = saved.preferences.preferLocalRoads;
        _avoidTolls = saved.preferences.avoidTolls;
        _restStops = saved.preferences.includeRestStops;
        _chargingStops = saved.preferences.includeChargingStops;
        _maxDetour = saved.preferences.maxDetourMinutes;
      });
    } catch (_) {
      // Defaults remain usable when preferences cannot be read.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remember() {
    final saved = DriveSettings(
      interests: {..._interests},
      preferences: _preferences,
    );
    _saving = _saving.then((_) => _settingsStore.save(saved)).catchError((
      Object _,
    ) {
      if (mounted) {
        setState(
          () => _error = 'Your choices could not be remembered on this device.',
        );
      }
    });
  }

  Future<void> _chooseInterests() async {
    final chosen = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => DriveInterestsScreen(selected: _interests),
      ),
    );
    if (chosen != null && mounted) {
      _change(() {
        _interests
          ..clear()
          ..addAll(chosen);
      });
      _remember();
    }
  }

  String get _interestSummary => driveCategories
      .where(
        (c) =>
            _interests.contains(c.id) ||
            c.children.keys.any(_interests.contains),
      )
      .map((c) => c.label)
      .join(', ');
  void _preferenceChanged(VoidCallback action) {
    _change(action);
    _remember();
  }

  DriveSearch? _search;
  DrivePlace? _selected;
  DrivePlan? _plan;
  String _selectedQuery = '';
  String? _error;
  bool _busy = true, _return = false;
  int _minutes = 180, _stopMinutes = 15;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.narration?.stop().catchError((Object _) {}));
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshNarration());
  }

  Future<void> _refreshNarration() async {
    try {
      final active = await widget.narration?.isActive() ?? false;
      if (mounted) setState(() => _driveActive = active);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is RoverApiException
              ? e.problem?.displayMessage ?? e.message
              : e is PlatformException
              ? e.message ?? 'Drive audio could not start.'
              : e is StateError
              ? e.message.toString()
              : 'Could not complete the request. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find() => _run(() async {
    setState(() {
      _selected = null;
      _plan = null;
      _search = null;
    });
    final query = _query.text.trim();
    if (query.isEmpty) throw StateError('Enter a town, landmark or address.');
    final fix = await widget.location.ensureDeviceLocation(forceRefresh: true);
    if (fix.location == null) {
      throw StateError('Allow location access and try again outdoors.');
    }
    final found = await widget.repository.search(query, fix.location!);
    if (!mounted) return;
    setState(() {
      _search = found;
      _selectedQuery = query;
    });
  });
  Future<void> _buildPlan() => _run(() async {
    final place = _selected;
    if (place == null) return;
    setState(() => _plan = null);
    final fix = await widget.location.ensureDeviceLocation(forceRefresh: true);
    if (fix.location == null) {
      throw StateError('Allow location access and try again outdoors.');
    }
    final result = await widget.repository.plan(
      DriveRequest(
        origin: fix.location!,
        destination: place,
        query: _selectedQuery,
        returnToStart: _return,
        availableMinutes: _minutes,
        minutesPerStop: _stopMinutes,
        interests: _interests.toList(),
        preferences: _preferences,
      ),
    );
    if (mounted) setState(() => _plan = result);
  });
  Future<void> _navigate({DrivePlace? leg}) => _run(() async {
    final plan = _plan;
    if (plan == null || !plan.fitsBudget) return;
    if (!await widget.beforeNavigate() || !mounted) return;
    var section = 0;
    if (leg == null && plan.navigationSections > 1) {
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Choose navigation section'),
          children: [
            for (var i = 0; i < plan.navigationSections; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, i),
                child: Text(
                  'Part ${i + 1}: ${plan.visits.skip(i * 4).take(4).map((p) => p.name).join(' > ')}',
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      section = selected;
    }
    final uri = plan.directions(leg: leg, section: section);
    final narration = widget.narration;
    if (_automaticStories && narration != null && leg?.id != 'start') {
      setState(() => _preparing = 'Preparing stop introductions and audio...');
      try {
        final statuses = await narration.prepare(plan);
        if (!mounted) return;
        setState(() => _storyStatus = statuses);
        final requested = leg == null
            ? [...plan.stops, plan.destination]
            : [leg];
        final ready = requested
            .where((p) => statuses[p.id] == 'Audio ready')
            .length;
        if (ready == 0) {
          throw StateError(
            'No stop audio is ready. Turn off automatic stories for directions only, or retry preparation.',
          );
        }
        if (ready < requested.length) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Some stops will be silent'),
              content: Text(
                'Audio is ready for $ready of ${requested.length} stops. Continue with these introductions?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          if (proceed != true || !mounted) return;
        }
        if (!mounted ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.paused) {
          return;
        }
        await narration.start(plan, leg: leg);
        if (mounted) setState(() => _driveActive = true);
      } finally {
        if (mounted) setState(() => _preparing = null);
      }
    } else {
      await narration?.stop();
      if (mounted) setState(() => _driveActive = false);
    }
    if (!mounted) return;
    bool opened;
    try {
      opened = await (widget.launchDirections?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      await narration?.stop();
      if (mounted) setState(() => _driveActive = false);
      rethrow;
    }
    if (!opened) {
      await narration?.stop();
      if (mounted) setState(() => _driveActive = false);
      throw StateError('Google Maps could not open. Please try again.');
    }
  });
  Future<void> _parkedStory() async {
    final ready = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Safely parked?'),
        content: const Text(
          'Stop in a safe, permitted place before using stories or the camera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I am parked'),
          ),
        ],
      ),
    );
    if (ready == true && mounted) {
      await widget.narration?.stop();
      if (!mounted) return;
      setState(() => _driveActive = false);
      widget.tellHere();
    }
  }

  void _change(VoidCallback action) => setState(() {
    unawaited(widget.narration?.stop().catchError((Object _) {}));
    _driveActive = false;
    _storyStatus = {};
    action();
    _plan = null;
    _error = null;
  });
  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Scenic Drive')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.my_location),
                title: Text('Starting from your current location'),
              ),
              TextField(
                controller: _query,
                enabled: !_busy,
                maxLength: 256,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (!_busy) _find();
                },
                onChanged: (_) => _change(() {
                  _selected = null;
                  _search = null;
                }),
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  hintText: 'Town, landmark or address',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _find,
                  icon: const Icon(Icons.search),
                  label: const Text('Find destination'),
                ),
              ),
              if (_search != null && _search!.places.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No destinations found. Try a town name with its country.',
                  ),
                ),
              for (final place in _search?.places ?? <DrivePlace>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(place.name),
                  subtitle: Text(
                    [
                      place.address,
                      place.attribution,
                    ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
                  ),
                  trailing: Icon(
                    _selected?.id == place.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  selected: _selected?.id == place.id,
                  onTap: _busy ? null : () => _change(() => _selected = place),
                ),
              for (final warning in _search?.warnings ?? <String>[])
                Text(warning),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Return to start'),
                value: _return,
                onChanged: _busy
                    ? null
                    : (value) => _change(() => _return = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _minutes,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Total time, including stops',
                ),
                items: [30, 60, 90, 120, 180, 240, 360, 480, 720]
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m, child: Text('$m minutes')),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (m) {
                        if (m != null) _change(() => _minutes = m);
                      },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                initialValue: _stopMinutes,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Time at each stop and destination',
                ),
                items: [5, 10, 15, 20, 30, 45, 60]
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m, child: Text('$m minutes')),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (m) {
                        if (m != null) _change(() => _stopMinutes = m);
                      },
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Interests'),
                subtitle: Text(
                  _interestSummary.isEmpty ? 'Direct trip' : _interestSummary,
                ),
                trailing: const Icon(Icons.tune),
                onTap: _busy ? null : _chooseInterests,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Driving preferences'),
                subtitle: Text(
                  '${_localRoads ? 'Prefer local roads' : 'Standard driving route'} · Up to $_maxDetour min detour per stop',
                ),
                children: [
                  SwitchListTile(
                    title: const Text('Prefer local roads'),
                    subtitle: const Text('Avoid motorways where possible'),
                    value: _localRoads,
                    onChanged: _busy
                        ? null
                        : (v) => _preferenceChanged(() => _localRoads = v),
                  ),
                  SwitchListTile(
                    title: const Text('Avoid tolls where possible'),
                    value: _avoidTolls,
                    onChanged: _busy
                        ? null
                        : (v) => _preferenceChanged(() => _avoidTolls = v),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _maxDetour,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Maximum extra driving per stop',
                    ),
                    items: {5, 10, 15, 30, 60, _maxDetour}
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text('$v minutes'),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) {
                              _preferenceChanged(() => _maxDetour = v);
                            }
                          },
                  ),
                  SwitchListTile(
                    title: const Text('Look for rest stops'),
                    value: _restStops,
                    onChanged: _busy
                        ? null
                        : (v) => _preferenceChanged(() => _restStops = v),
                  ),
                  SwitchListTile(
                    title: const Text('Look for EV charging stops'),
                    value: _chargingStops,
                    subtitle: const Text(
                      'Check compatibility, availability and charging time',
                    ),
                    onChanged: _busy
                        ? null
                        : (v) => _preferenceChanged(() => _chargingStops = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || _selected == null ? null : _buildPlan,
                icon: const Icon(Icons.route),
                label: const Text('Plan drive'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_preparing != null) Text(_preparing!),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (plan != null) ...[
                const Divider(height: 32),
                Text(
                  plan.destination.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.totalMinutes} min total · ${(plan.distanceMeters / 1000).toStringAsFixed(1)} km',
                ),
                Text(
                  '${plan.drivingMinutes} min driving + ${plan.stopMinutes} min stops + ${plan.bufferMinutes} min buffer',
                ),
                Text(
                  '${plan.stops.length + 1} visits x ${plan.stopMinutes ~/ (plan.stops.length + 1)} min = ${plan.stopMinutes} min at stops, including your destination',
                ),
                if (plan.fitsBudget)
                  Text(
                    '${plan.availableMinutes - plan.totalMinutes} minutes left in your budget',
                  ),
                if (!plan.fitsBudget)
                  Text(
                    'Needs at least ${plan.totalMinutes} minutes. Choose more time or a closer destination.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 16),
                RoverMapView(
                  currentLocation: plan.origin,
                  orderedStops: const [],
                  routeGeometry: plan.geometry,
                  overview: true,
                  height: 280,
                ),
                const SizedBox(height: 12),
                for (final place in [...plan.stops, plan.destination])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      place.id == plan.destination.id
                          ? Icons.flag
                          : Icons.place,
                    ),
                    title: Text(place.name),
                    subtitle: Text(
                      [
                        place.address,
                        place.attribution,
                      ].whereType<String>().join('\n'),
                    ),
                    trailing: IconButton(
                      tooltip: 'Drive to ${place.name}',
                      icon: const Icon(Icons.directions_car),
                      onPressed: _busy || !plan.fitsBudget
                          ? null
                          : () => _navigate(leg: place),
                    ),
                  ),
                if (plan.returnToStart)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Return to starting location'),
                    trailing: IconButton(
                      tooltip: 'Drive to starting location',
                      icon: const Icon(Icons.directions_car),
                      onPressed: _busy || !plan.fitsBudget
                          ? null
                          : () => _navigate(leg: plan.visits.last),
                    ),
                  ),
                for (final warning in plan.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(warning),
                  ),
                const SizedBox(height: 8),
                if (widget.narration != null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic stop stories'),
                    subtitle: const Text(
                      'Prepare while parked. Location stays on with Google Maps or the screen locked.',
                    ),
                    value: _automaticStories,
                    onChanged: _busy
                        ? null
                        : (value) async {
                            if (!value) await widget.narration!.stop();
                            if (mounted) {
                              setState(() {
                                _automaticStories = value;
                                if (!value) _driveActive = false;
                              });
                            }
                          },
                  ),
                  for (final place in [...plan.stops, plan.destination])
                    if (_storyStatus[place.id] != null)
                      Text('${place.name}: ${_storyStatus[place.id]}'),
                  if (_driveActive)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await widget.narration!.stop();
                              if (mounted) setState(() => _driveActive = false);
                            }),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop drive stories'),
                    ),
                ],
                FilledButton.icon(
                  onPressed: _busy || !plan.fitsBudget ? null : _navigate,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Open driving directions'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _parkedStory,
                  icon: const Icon(Icons.headphones),
                  label: const Text('Tell me about here'),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

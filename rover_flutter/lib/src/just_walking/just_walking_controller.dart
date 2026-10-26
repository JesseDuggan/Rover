import 'package:flutter/foundation.dart';

import '../api/location_story_models.dart';
import '../api/walk_repository.dart';
import '../location/rover_location.dart';

class JustWalkingController extends ChangeNotifier {
  JustWalkingController({
    required this.repository,
    required this.narrate,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WalkRepository repository;
  final Future<bool> Function(LocationPlaceSummary, RoverLatLng) narrate;
  final DateTime Function() _clock;
  final Set<String> heard = {};
  final Map<String, DateTime> _retryAfter = {};
  List<LocationPlaceSummary> places = [];
  RoverLocationReading? reading;
  String status = 'Waiting for location';
  bool paused = false;
  bool busy = false;
  bool speaking = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastSearch;
  DateTime? _lastPlayback;
  RoverLatLng? _searchLocation;

  void setPaused(bool value) {
    paused = value;
    _generation++;
    status = value ? 'Paused' : 'Looking for nearby stories';
    _notify();
  }

  Future<void> update(
    RoverLocationReading value, {
    bool refresh = false,
  }) async {
    if (_disposed || paused) return;
    final now = _clock().toUtc();
    final accuracy = value.accuracyMeters;
    if (!value.location.latitude.isFinite ||
        !value.location.longitude.isFinite ||
        value.location.latitude.abs() > 90 ||
        value.location.longitude.abs() > 180 ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 40 ||
        now.difference(value.recordedAtUtc).abs() >
            const Duration(seconds: 30)) {
      status = 'Waiting for an accurate location';
      reading = null;
      _notify();
      return;
    }
    reading = value;
    _notify();
    if (busy || speaking) return;
    final elapsed = _lastSearch == null ? null : now.difference(_lastSearch!);
    final moved =
        _searchLocation == null ||
        value.location.distanceTo(_searchLocation!) >= 120;
    final shouldSearch =
        elapsed == null ||
        (refresh && elapsed >= const Duration(seconds: 30)) ||
        (moved && elapsed >= const Duration(seconds: 90)) ||
        elapsed >= const Duration(minutes: 3);
    if (shouldSearch) {
      busy = true;
      _lastSearch = now;
      final generation = _generation;
      status = 'Finding nearby stories';
      _notify();
      try {
        final result = await repository.getLocationContext(
          latitude: value.location.latitude,
          longitude: value.location.longitude,
          radiusMeters: 500,
        );
        if (_disposed || paused || generation != _generation) return;
        _searchLocation = value.location;
        places = result.rankedPlaces
            .where(
              (p) =>
                  p.canonicalId.isNotEmpty &&
                  p.sourceReferences.isNotEmpty &&
                  p.facts.isNotEmpty &&
                  value.location.distanceTo(p.coordinates) <= 500,
            )
            .toList();
        status = places.isEmpty
            ? 'No verified stories nearby yet'
            : 'Stories nearby';
      } catch (_) {
        if (!_disposed && generation == _generation) {
          status = 'Could not refresh nearby stories. Try again shortly.';
        }
      } finally {
        busy = false;
        _notify();
      }
    }
    if (_disposed || paused || reading == null) return;
    if (_lastPlayback != null &&
        now.difference(_lastPlayback!) < const Duration(seconds: 60)) {
      return;
    }
    final current = reading!;
    // Never play a result for a location the walker has already left.
    final nearby =
        places
            .where(
              (p) =>
                  !heard.contains(p.canonicalId) &&
                  !(_retryAfter[p.canonicalId]?.isAfter(now) ?? false) &&
                  current.location.distanceTo(p.coordinates) <= 100,
            )
            .toList()
          ..sort(
            (a, b) => current.location
                .distanceTo(a.coordinates)
                .compareTo(current.location.distanceTo(b.coordinates)),
          );
    if (nearby.isNotEmpty) {
      await play(nearby.first);
    } else if (places.isNotEmpty) {
      status = places.every((p) => heard.contains(p.canonicalId))
          ? 'All current nearby stories heard'
          : 'More stories nearby as you walk';
      _notify();
    }
  }

  Future<void> play(LocationPlaceSummary place) async {
    final current = reading;
    if (_disposed ||
        paused ||
        speaking ||
        busy ||
        current == null ||
        _clock().toUtc().difference(current.recordedAtUtc).abs() >
            const Duration(seconds: 30) ||
        current.location.distanceTo(place.coordinates) > 500) {
      return;
    }
    speaking = true;
    _lastPlayback = _clock().toUtc();
    final generation = _generation;
    status = 'Playing: ${place.name}';
    _notify();
    try {
      final completed = await narrate(place, current.location);
      if (_disposed || generation != _generation) return;
      if (completed) heard.add(place.canonicalId);
      if (!completed) {
        _retryAfter[place.canonicalId] = _clock().toUtc().add(
          const Duration(minutes: 10),
        );
      }
      status = completed
          ? places.every((p) => heard.contains(p.canonicalId))
                ? 'All current nearby stories heard'
                : 'More stories nearby as you walk'
          : 'No story played. Looking for other nearby stories as you walk.';
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _retryAfter[place.canonicalId] = _clock().toUtc().add(
          const Duration(minutes: 10),
        );
        status = 'Could not play this story. Try again.';
      }
    } finally {
      speaking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

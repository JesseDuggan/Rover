import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api/location_story_models.dart';
import '../api/speech_models.dart';
import '../api/walk_repository.dart';
import '../api/rover_api_client.dart';
import 'scenic_drive.dart';

abstract class DriveNarration {
  Future<Map<String, String>> prepare(DrivePlan plan);
  Future<void> start(DrivePlan plan, {DrivePlace? leg});
  Future<void> stop();
  Future<bool> isActive();
}

bool usableDriveStory(
  LocationStoryResponse story,
  DrivePlace place,
  DateTime now,
) =>
    story.placeId == place.id &&
    story.shortSpokenNarration.trim().isNotEmpty &&
    story.factIdsUsed.isNotEmpty &&
    story.sourceReferences.isNotEmpty &&
    story.researchStatus != 'failed' &&
    story.researchStatus != 'empty' &&
    !(story.expiresUtc?.isBefore(now) ?? false);

class DeviceDriveNarration implements DriveNarration {
  DeviceDriveNarration(this.repository);
  final WalkRepository repository;
  static const channel = MethodChannel('ai.myrover.rover/drive');
  DrivePlan? _plan;
  Directory? _directory;
  final Map<String, Map<String, Object?>> _stops = {};
  final Map<String, DateTime?> _expiry = {};
  int _epoch = 0;

  @override
  Future<Map<String, String>> prepare(DrivePlan plan) async {
    if (!Platform.isAndroid) {
      throw StateError('Automatic drive stories currently require Android.');
    }
    if (identical(_plan, plan) &&
        _stops.isNotEmpty &&
        _stops.values.every(
          (s) =>
              s['audio'] is String && File(s['audio'] as String).existsSync(),
        ) &&
        _expiry.values.every(
          (e) => e != null && e.isAfter(DateTime.now().toUtc()),
        )) {
      return {
        for (final p in [...plan.stops, plan.destination])
          p.id: _stops[p.id]?['audio'] != null
              ? 'Audio ready'
              : 'No verified audio available',
      };
    }
    await stop();
    final token = ++_epoch;
    _plan = plan;
    _stops.clear();
    _expiry.clear();
    _directory = Directory(
      '${(await getTemporaryDirectory()).path}/drive_narration',
    );
    await _directory!.create(recursive: true);
    // Only this feature's fixed directory is cleared, after its service stops.
    for (final file in _directory!.listSync().whereType<File>()) {
      await file.delete();
    }
    final statuses = <String, String>{};
    var index = 0;
    for (final place in [...plan.stops, plan.destination]) {
      if (token != _epoch) throw StateError('Story preparation cancelled.');
      final entry = <String, Object?>{
        'id': place.id,
        'name': place.name,
        'latitude': place.location.latitude,
        'longitude': place.location.longitude,
      };
      _stops[place.id] = entry;
      try {
        final story = await RoverApiClient().createDriveStopStory(
          id: place.id,
          name: place.name,
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        );
        if (token != _epoch) throw StateError('Story preparation cancelled.');
        if (!usableDriveStory(story, place, DateTime.now().toUtc())) {
          statuses[place.id] = 'No verified story available';
          continue;
        }
        // Keep the approach introduction short and end on a sentence boundary.
        final intro = story.shortSpokenNarration.trim();
        final sentences = intro.split(RegExp(r'(?<=[.!?])\s+'));
        var short = '';
        for (final sentence in sentences) {
          if ((short + sentence).split(RegExp(r'\s+')).length > 180) break;
          short = '$short $sentence'.trim();
        }
        if (short.isEmpty) {
          statuses[place.id] = 'No short introduction available';
          continue;
        }
        final attribution = story.requiredAttribution.isEmpty
            ? ''
            : ' Sources: ${story.requiredAttribution.join(', ')}.';
        final text = 'Coming up: ${place.name}. $short$attribution';
        final audio = await repository.renderSpeech(
          RenderSpeechRequest(
            text: text,
            purpose: 'DiscoveryDescription',
            cacheEligible: false,
          ),
        );
        if (token != _epoch) throw StateError('Story preparation cancelled.');
        if (!audio.contentType.startsWith('audio/') || audio.bytes.isEmpty) {
          throw StateError('No audio returned');
        }
        final file = File('${_directory!.path}/${index++}.audio');
        await file.writeAsBytes(audio.bytes, flush: true);
        entry['audio'] = file.path;
        entry['expires'] = story.expiresUtc?.millisecondsSinceEpoch;
        _expiry[place.id] = story.expiresUtc;
        statuses[place.id] = 'Audio ready';
      } catch (_) {
        if (token != _epoch) throw StateError('Story preparation cancelled.');
        statuses[place.id] = 'Audio unavailable; this stop will be silent';
      }
    }
    return statuses;
  }

  @override
  Future<void> start(DrivePlan plan, {DrivePlace? leg}) async {
    if (!identical(plan, _plan) || _directory == null) {
      throw StateError('Prepare stories first.');
    }
    final stops = _stops.values
        .where((s) => leg == null || s['id'] == leg.id)
        .toList();
    final now = DateTime.now().toUtc();
    for (final stop in stops) {
      if (_expiry[stop['id']]?.isBefore(now) ?? false) stop.remove('audio');
    }
    if (!stops.any((s) => s['audio'] != null)) {
      throw StateError(
        'No stop audio is ready. Turn off automatic stories to use directions only.',
      );
    }
    final manifest = File('${_directory!.path}/session.json');
    await manifest.writeAsString(
      jsonEncode({
        'id': '$_epoch-${leg?.id ?? 'all'}',
        'minutes': plan.availableMinutes + 60,
        'route': plan.geometry.map((p) => [p.latitude, p.longitude]).toList(),
        'stops': stops,
      }),
      flush: true,
    );
    await const MethodChannel('ai.myrover.rover/voice')
        .invokeMethod<void>('walkingNotificationPermission');
    await channel.invokeMethod<void>('start', {'path': manifest.path});
  }

  @override
  Future<void> stop() async {
    _epoch++;
    if (Platform.isAndroid) await channel.invokeMethod<void>('stop');
  }

  @override
  Future<bool> isActive() async =>
      Platform.isAndroid &&
      (await channel.invokeMethod<bool>('active') ?? false);
}

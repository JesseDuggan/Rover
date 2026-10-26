import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../location/rover_location.dart';
import 'memory_store.dart';

/// Local-only, timestamped GPS fixes. Planned geometry is never used here.
class WalkTrailStore {
  WalkTrailStore({this.directory, DateTime Function()? now, this.memoryStore})
    : now = now ?? DateTime.now;
  final Directory? directory;
  final MemoryStore? memoryStore;
  final DateTime Function() now;
  Future<void> _pending = Future.value();
  final Map<String, List<Map<String, dynamic>>> _buffer = {};
  final Map<String, Map<String, dynamic>?> _last = {};
  final Map<String, int> _counts = {};
  final Set<String> _gaps = {};
  Timer? _timer;
  bool _closed = false;
  bool failed = false;

  Future<Directory> _root() async =>
      (directory ??
              Directory(
                '${(await getApplicationSupportDirectory()).path}/walk_trails',
              ))
          .create(recursive: true);
  Future<File> _file(String id) async => File(
    '${(await _root()).path}/${base64Url.encode(utf8.encode(id))}.jsonl',
  );

  Future<List<Map<String, dynamic>>> read(String sessionId) async {
    await flush();
    return _read(sessionId);
  }

  Future<List<Map<String, dynamic>>> readJourney(String journeyId) async {
    await flush();
    final memories = memoryStore ?? MemoryStore();
    final canonical = await memories.journeyId(journeyId);
    final result = <Map<String, dynamic>>[];
    await for (final entry in (await _root()).list()) {
      if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
      final name = entry.uri.pathSegments.last;
      String session;
      try {
        session = utf8.decode(
          base64Url.decode(name.substring(0, name.length - 6)),
        );
      } on FormatException {
        continue;
      }
      final linked = await memories.journeyId(session);
      for (final point in await _read(session)) {
        if (linked == canonical || point['journeyId'] == canonical) {
          result.add({...point, 'recordingId': session});
        }
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _read(String id) async {
    final file = await _file(id);
    if (!await file.exists()) return [];
    final result = <Map<String, dynamic>>[];
    for (final line in await file.readAsLines()) {
      try {
        result.add(jsonDecode(line) as Map<String, dynamic>);
      } on FormatException {
        // A force-close can interrupt the final append; keep complete fixes.
      } on TypeError {
        // Ignore malformed entries without losing the rest of the recording.
      }
    }
    return result;
  }

  Future<void> record(String id, RoverLocationReading reading) {
    if (_closed) return Future.value();
    _pending = _pending
        .then((_) async {
          final accuracy = reading.accuracyMeters;
          final p = reading.location;
          final age = now().toUtc().difference(reading.recordedAtUtc).inSeconds;
          if (reading.isMocked ||
              accuracy == null ||
              !accuracy.isFinite ||
              accuracy < 0 ||
              accuracy > 25 ||
              age > 30 ||
              age < -5 ||
              !p.latitude.isFinite ||
              !p.longitude.isFinite ||
              p.latitude.abs() > 90 ||
              p.longitude.abs() > 180) {
            return;
          }
          if (!_last.containsKey(id)) {
            final previous = await _read(id);
            _last[id] = previous.isEmpty ? null : previous.last;
            _counts[id] = previous.length;
            _gaps.add(id);
          }
          if (_counts[id]! >= 24000) return;
          final last = _last[id];
          var segment = (last?['segment'] as int?) ?? 0;
          if (last != null) {
            final elapsed = reading.recordedAtUtc.difference(
              DateTime.parse(last['at'] as String),
            );
            if (elapsed.inMilliseconds < 5000) return;
            final distance = RoverLatLng(
              latitude: (last['latitude'] as num).toDouble(),
              longitude: (last['longitude'] as num).toDouble(),
            ).distanceTo(p);
            if (elapsed.inSeconds < 60 &&
                distance / (elapsed.inMilliseconds / 1000) > 8) {
              return;
            }
            if (distance < 3 && elapsed.inSeconds < 30 && !_gaps.contains(id)) {
              return;
            }
            if (_gaps.contains(id) || elapsed.inSeconds > 60) segment++;
          }
          final point = <String, dynamic>{
            'version': 1,
            'journeyId': await (memoryStore ?? MemoryStore()).journeyId(id),
            'at': reading.recordedAtUtc.toUtc().toIso8601String(),
            'latitude': p.latitude,
            'longitude': p.longitude,
            'accuracyMeters': accuracy,
            'segment': segment,
          };
          _gaps.remove(id);
          _last[id] = point;
          _counts[id] = _counts[id]! + 1;
          (_buffer[id] ??= []).add(point);
          _timer ??= Timer(const Duration(seconds: 20), () {
            _timer = null;
            unawaited(flush());
          });
        })
        .catchError((Object _) {
          failed = true;
        });
    return _pending;
  }

  Future<void> pause(String? sessionId) async {
    await _pending;
    if (sessionId != null) _gaps.add(sessionId);
    await flush();
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _pending = _pending
        .then((_) async {
          for (final id in _buffer.keys.toList()) {
            final points = _buffer[id]!;
            if (points.isEmpty) continue;
            // Leading newline isolates an incomplete final line after a crash.
            await (await _file(id)).writeAsString(
              '\n${points.map(jsonEncode).join('\n')}\n',
              mode: FileMode.append,
              flush: true,
            );
            points.clear();
          }
        })
        .catchError((Object _) {
          failed = true;
        });
    return _pending;
  }

  Future<void> close() async {
    _closed = true;
    await flush();
    _timer?.cancel();
    _timer = null;
  }

  Future<void> delete(String id) async {
    await flush();
    final file = await _file(id);
    if (await file.exists()) await file.delete();
    _buffer.remove(id);
    _last.remove(id);
    _counts.remove(id);
    _gaps.remove(id);
  }
}

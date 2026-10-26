import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../adventure/roam.dart';
import '../active_roam/route_persistence.dart';
import '../location/rover_location.dart';

class MemoryJourney {
  const MemoryJourney({required this.id, required this.route});
  final String id;
  final RoverRoam route;
  String get displayName {
    final title = route.title.trim();
    if (title.isNotEmpty &&
        !['rover walk', 'walkabout walk', 'walk'].contains(title.toLowerCase())) {
      return title;
    }
    return route.stops.isNotEmpty
        ? 'Walk near ${route.stops.first.name}'
        : 'Local walk';
  }

  Map<String, dynamic> toJson() => {'id': id, 'route': routeToJson(route)};
  factory MemoryJourney.fromJson(Map<String, dynamic> json) => MemoryJourney(
    id: json['id'] as String,
    route: routeFromJson(json['route'] as Map<String, dynamic>),
  );
}

class MemoryDetails {
  const MemoryDetails({
    this.journey,
    this.capturedAt,
    this.location,
    this.accuracyMeters,
    this.poiName,
    this.caption = '',
    this.sharingLocked = false,
  });
  final MemoryJourney? journey;
  final DateTime? capturedAt;
  final RoverLatLng? location;
  final double? accuracyMeters;
  final String? poiName;
  final String caption;
  final bool sharingLocked;
  MemoryDetails withSharingLocked(bool value) => MemoryDetails(
    journey: journey,
    capturedAt: capturedAt,
    location: location,
    accuracyMeters: accuracyMeters,
    poiName: poiName,
    caption: caption,
    sharingLocked: value,
  );
  MemoryDetails withJourney(MemoryJourney value) => MemoryDetails(
    journey: value,
    capturedAt: capturedAt,
    location: location,
    accuracyMeters: accuracyMeters,
    poiName: journey?.id == value.id ? poiName : null,
    caption: caption,
    sharingLocked: sharingLocked,
  );
  MemoryDetails withPlace(String? value) => MemoryDetails(
    journey: journey,
    capturedAt: capturedAt,
    location: location,
    accuracyMeters: accuracyMeters,
    poiName: value,
    caption: caption,
    sharingLocked: sharingLocked,
  );
  MemoryDetails withCaption(String value) => MemoryDetails(
    journey: journey,
    capturedAt: capturedAt,
    location: location,
    accuracyMeters: accuracyMeters,
    poiName: poiName,
    caption: value.trim(),
    sharingLocked: sharingLocked,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'visibility': 'private',
    'sharingLocked': sharingLocked,
    'journey': journey?.toJson(),
    'capturedAt': capturedAt?.toUtc().toIso8601String(),
    'latitude': location?.latitude,
    'longitude': location?.longitude,
    'accuracyMeters': accuracyMeters,
    'poiName': poiName,
    'caption': caption,
  };
  factory MemoryDetails.fromJson(Map<String, dynamic> json) => MemoryDetails(
    journey: json['journey'] == null
        ? null
        : MemoryJourney.fromJson(json['journey'] as Map<String, dynamic>),
    capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? ''),
    location: json['latitude'] == null || json['longitude'] == null
        ? null
        : RoverLatLng(
            latitude: (json['latitude'] as num).toDouble(),
            longitude: (json['longitude'] as num).toDouble(),
          ),
    accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    poiName: json['poiName'] as String?,
    caption: json['caption'] as String? ?? '',
    sharingLocked: json['sharingLocked'] as bool? ?? false,
  );
}

class WalkMemory {
  const WalkMemory(this.file, {this.details = const MemoryDetails()});
  final File file;
  final MemoryDetails details;
  bool get isVideo => file.path.endsWith('.mp4');
  String get id => file.uri.pathSegments.last;
}

/// Device-local media only; never uploaded or added to the public photo library.
class MemoryStore {
  MemoryStore({this.directory});
  final Directory? directory;
  Future<Directory> _root() async =>
      (directory ??
              Directory(
                '${(await getApplicationSupportDirectory()).path}/walk_memories',
              ))
          .create(recursive: true);

  Future<List<WalkMemory>> list() async {
    final files = await (await _root())
        .list()
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'/[0-9]+-[0-9]+\.(jpg|mp4)$')
                  .hasMatch(entry.path.replaceAll('\\', '/')),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return Future.wait(
      files.map((file) async {
        try {
          final json = jsonDecode(
            await File('${file.path}.json').readAsString(),
          );
          return WalkMemory(
            file,
            details: MemoryDetails.fromJson(json as Map<String, dynamic>),
          );
        } on FileSystemException {
          return WalkMemory(file);
        } on FormatException {
          return WalkMemory(file);
        } on TypeError {
          return WalkMemory(file);
        }
      }),
    );
  }

  // Preview sessions are transient; flatten each link to its original route.
  Future<String> journeyId(String sessionId) async {
    final file = File(
      '${(await _root()).path}/route-${base64Url.encode(utf8.encode(sessionId))}.json',
    );
    if (!await file.exists()) return sessionId;
    return (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['id']
        as String;
  }

  Future<void> linkSession(String sessionId, String originalId) async {
    final id = await journeyId(originalId);
    final file = File(
      '${(await _root()).path}/route-${base64Url.encode(utf8.encode(sessionId))}.json',
    );
    await file.writeAsString(jsonEncode({'id': id}), flush: true);
  }

  Future<void> renameJourney(MemoryJourney journey, String name) async {
    final title = name.trim();
    if (title.isEmpty || title.length > 160) {
      throw const FormatException('Invalid walk name');
    }
    final id = await journeyId(journey.id);
    for (final memory in await list()) {
      final linked = memory.details.journey;
      if (linked != null && await journeyId(linked.id) == id) {
        await _writeDetails(
          memory.file,
          memory.details.withJourney(
            MemoryJourney(
              id: linked.id,
              route: linked.route.copyWith(title: title),
            ),
          ),
        );
      }
    }
  }

  Future<File> _uploadFile(String shareId) async => File(
    '${(await _root()).path}/upload-${base64Url.encode(utf8.encode(shareId))}.json',
  );

  Future<void> saveUploadFiles(String shareId, Map<String, String> files) async {
    final file = await _uploadFile(shareId);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(files), flush: true);
    await pending.rename(file.path);
  }

  Future<Map<String, String>> uploadFiles(String shareId) async {
    try {
      return Map<String, String>.from(jsonDecode(await (await _uploadFile(shareId)).readAsString()) as Map);
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> forgetUpload(String shareId) async {
    final file = await _uploadFile(shareId);
    if (await file.exists()) await file.delete();
  }

  Future<void> updateDetails(WalkMemory memory, MemoryDetails details) async {
    if (!(await list()).any(
      (m) =>
          m.file.absolute.uri.normalizePath() ==
          memory.file.absolute.uri.normalizePath(),
    )) {
      throw const FileSystemException('Not a saved memory');
    }
    await _writeDetails(memory.file, details);
  }

  Future<void> _writeDetails(File file, MemoryDetails details) async {
    final pending = File('${file.path}.json.pending');
    await pending.writeAsString(jsonEncode(details.toJson()), flush: true);
    await pending.rename('${file.path}.json');
  }

  Future<MemoryDetails> attachToWalk(
    WalkMemory memory,
    MemoryJourney journey,
  ) async {
    final canonical = MemoryJourney(
      id: await journeyId(journey.id),
      route: journey.route,
    );
    final details = memory.details.withJourney(canonical);
    await updateDetails(memory, details);
    return details;
  }

  Future<WalkMemory> save(
    File source, {
    required bool video,
    MemoryDetails details = const MemoryDetails(),
  }) async {
    if (await source.length() == 0) {
      throw const FileSystemException('Empty capture');
    }
    final root = await _root();
    final name =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final pending = File('${root.path}/$name.pending');
    try {
      await source.copy(pending.path);
      final file = File('${root.path}/$name.${video ? 'mp4' : 'jpg'}');
      await _writeDetails(file, details);
      return WalkMemory(await pending.rename(file.path), details: details);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  Future<void> delete(WalkMemory memory) async {
    final root = await _root();
    final matches = await list();
    if (!matches.any(
      (item) =>
          item.file.absolute.uri.normalizePath() ==
          memory.file.absolute.uri.normalizePath(),
    )) {
      throw const FileSystemException('Not a saved memory');
    }
    await File('${root.path}/${memory.id}').delete();
    final metadata = File('${root.path}/${memory.id}.json');
    if (await metadata.exists()) await metadata.delete();
  }
}

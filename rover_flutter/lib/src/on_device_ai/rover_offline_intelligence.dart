import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../active_roam/active_roam_session.dart';
import '../api/location_observation_models.dart';
import '../api/location_story_models.dart';
import '../api/problem_details.dart';
import '../api/rover_api_client.dart';
import '../diagnostics/field_diagnostics.dart';
import '../location/rover_location.dart';
import 'rover_scout.dart';

class RoverOfflineCacheSnapshot {
  const RoverOfflineCacheSnapshot({
    required this.enabled,
    required this.entryCount,
    required this.sizeBytes,
    required this.connectivityState,
    required this.cacheState,
    this.lastUpdatedUtc,
    this.isPreloading = false,
  });

  final bool enabled;
  final int entryCount;
  final int sizeBytes;
  final RoverConnectivityState connectivityState;
  final RoverOfflineCacheState cacheState;
  final DateTime? lastUpdatedUtc;
  final bool isPreloading;
}

class RoverOfflineIntelligence extends ChangeNotifier {
  RoverOfflineIntelligence({
    File? cacheFile,
    RoverApiClient? client,
    DateTime Function()? nowUtc,
    this.maximumEntries = 50,
    this.maximumBytes = 5 * 1024 * 1024,
  }) : _cacheFile = kIsWeb
           ? null
           : cacheFile ??
                 File(
                   '${Directory.systemTemp.path}'
                   '${Platform.pathSeparator}rover_offline_story_packs.json',
                 ),
       _client = client ?? RoverApiClient(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static final RoverOfflineIntelligence instance = RoverOfflineIntelligence();

  final File? _cacheFile;
  final RoverApiClient _client;
  final DateTime Function() _nowUtc;
  final int maximumEntries;
  final int maximumBytes;
  final List<_OfflineStoryEntry> _entries = [];

  bool _enabled = false;
  Future<void>? _loadFuture;
  bool _isPreloading = false;
  int _sizeBytes = 0;
  RoverConnectivityState _connectivityState = RoverConnectivityState.unknown;
  String? _preloadedJourneyKey;
  Future<void>? _preload;

  bool get enabled => _enabled;
  RoverConnectivityState get connectivityState => _connectivityState;
  RoverOfflineCacheState get cacheState => !_enabled || _entries.isEmpty
      ? RoverOfflineCacheState.unavailable
      : RoverOfflineCacheState.available;

  RoverOfflineCacheSnapshot get snapshot => RoverOfflineCacheSnapshot(
    enabled: _enabled,
    entryCount: _entries.length,
    sizeBytes: _sizeBytes,
    connectivityState: _connectivityState,
    cacheState: cacheState,
    lastUpdatedUtc: _entries.isEmpty ? null : _entries.first.cachedAtUtc,
    isPreloading: _isPreloading,
  );

  void configure({required bool enabled}) {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    if (enabled) {
      unawaited(refreshStatus(probe: false));
    } else {
      _connectivityState = RoverConnectivityState.unknown;
      _preloadedJourneyKey = null;
    }
    notifyListeners();
  }

  Future<RoverOfflineCacheSnapshot> refreshStatus({bool probe = true}) async {
    await _ensureLoaded();
    if (_enabled && probe) {
      try {
        await _client.getHealth();
        markOnline();
      } on RoverApiConnectionException {
        markOffline();
      } on RoverApiTimeoutException {
        markOffline();
      } on RoverApiException {
        markOnline();
      }
    }
    notifyListeners();
    return snapshot;
  }

  void markOnline() => _setConnectivity(RoverConnectivityState.online);
  void markOffline() => _setConnectivity(RoverConnectivityState.offline);

  Future<void> store(
    LocationStoryRequest request,
    LocationStoryResponse response,
  ) async {
    if (!_enabled) {
      return;
    }
    await _ensureLoaded();
    final entry = _sanitize(request, response, _nowUtc());
    if (entry == null) {
      FieldDiagnostics.instance.record(
        'offline',
        'Story Pack not cached because it was unverified, expired, empty, or restricted',
      );
      return;
    }

    _entries.removeWhere(
      (candidate) =>
          candidate.placeId == entry.placeId ||
          candidate.aliases.any(entry.aliases.contains),
    );
    _entries.insert(0, entry);
    _trim();
    await _persist();
    FieldDiagnostics.instance.record(
      'offline',
      'cached ${entry.name}; entries=${_entries.length}; bytes=$_sizeBytes',
    );
    notifyListeners();
  }

  Future<LocationStoryResponse?> findStory(LocationStoryRequest request) async {
    if (!_enabled) {
      return null;
    }
    await _ensureLoaded();
    final now = _nowUtc();
    final selected = request.selectedPlaceIds
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();
    _OfflineStoryEntry? match;
    for (final entry in _entries) {
      if (entry.expiresUtc.isBefore(now)) {
        continue;
      }
      if (selected.isNotEmpty && entry.aliases.any(selected.contains)) {
        match = entry;
        break;
      }
    }
    if (match == null && selected.isEmpty) {
      final nearby = _nearbyEntries(
        request.location,
        request.radiusMeters.toDouble(),
        now,
      );
      if (nearby.isNotEmpty) {
        match = nearby.first.entry;
      }
    }
    if (match == null) {
      return null;
    }
    FieldDiagnostics.instance.record(
      'offline',
      'offline cached story matched ${match.name}',
    );
    return match.offlineResponse;
  }

  Future<LocationStoryContext?> findContext({
    required RoverLatLng location,
    required int radiusMeters,
  }) async {
    if (!_enabled) {
      return null;
    }
    await _ensureLoaded();
    final matches = _nearbyEntries(
      location,
      radiusMeters.toDouble(),
      _nowUtc(),
    );
    if (matches.isEmpty) {
      return null;
    }
    return LocationStoryContext(
      rankedPlaces: matches
          .map((match) => match.entry.toPlaceSummary(match.distanceMeters))
          .toList(growable: false),
      sourceWarnings: const [
        'Offline cached match. Live hours, closures, prices, events, and position details are unavailable.',
      ],
      providerStatus: [
        LocationProviderStatus(
          providerName: 'ROVER device cache',
          enabled: true,
          succeeded: true,
          resultCount: matches.length,
          warning: 'Using previously verified Story Packs.',
        ),
      ],
    );
  }

  Future<LocationObservationResolution?> resolveObservation(
    LocationObservationResolveRequest request,
  ) async {
    final context = await findContext(
      location: request.location,
      radiusMeters: request.radiusMeters,
    );
    if (context == null) {
      return null;
    }
    final query = _normalizeWords(request.recognizedText);
    final candidates = <LocationObservationCandidate>[];
    for (final place in context.rankedPlaces) {
      final score = _nameSimilarity(query, _normalizeWords(place.name));
      if (score < 0.35) {
        continue;
      }
      final distance = place.distanceFromUserMeters ?? 0;
      candidates.add(
        LocationObservationCandidate(
          place: place,
          matchConfidence: score,
          nameSimilarity: score,
          distanceScore: (1 - distance / request.radiusMeters).clamp(0, 1),
          headingScore: 0,
          matchReasons: const ['Offline cached name match'],
        ),
      );
    }
    candidates.sort((a, b) => b.matchConfidence.compareTo(a.matchConfidence));
    if (candidates.isEmpty) {
      return null;
    }
    final verified = candidates.first.matchConfidence >= 0.72;
    return LocationObservationResolution(
      status: verified
          ? LocationObservationResolutionStatus.verified
          : LocationObservationResolutionStatus.ambiguous,
      selectedPlaceId: verified ? candidates.first.place.canonicalId : null,
      candidates: candidates.take(5).toList(growable: false),
      diagnosticCode: verified
          ? 'offline_cached_match'
          : 'offline_cached_ambiguous',
      warnings: const [
        'Matched against previously verified offline place names. Live verification was unavailable.',
      ],
    );
  }

  Future<void> preloadJourney(RoamSession session) {
    if (!_enabled || session.apiWalkSessionId == null) {
      return Future.value();
    }
    final key =
        '${session.apiWalkSessionId}:${session.routeRevision}:'
        '${session.roam.stops.map((stop) => stop.id).join(',')}';
    if (_preloadedJourneyKey == key) {
      return _preload ?? Future.value();
    }
    _preloadedJourneyKey = key;
    return _preload = _runPreload(session, key);
  }

  Future<void> _runPreload(RoamSession session, String key) async {
    await _ensureLoaded();
    _isPreloading = true;
    notifyListeners();
    var stored = 0;
    try {
      for (final stop in session.roam.stops) {
        if (_preloadedJourneyKey != key) {
          break;
        }
        final request = LocationStoryRequest(
          location: stop.coordinates,
          radiusMeters: 150,
          routeGeometry: session.roam.routeGeometry,
          interests: [stop.category],
          selectedPlaceIds: [stop.id],
          routeId: session.apiWalkSessionId,
          narrationStyle: 'Conversational',
        );
        if (await findStory(request) != null) {
          continue;
        }
        try {
          final response = await _client.createLocationStory(request);
          markOnline();
          if (_preloadedJourneyKey != key) {
            break;
          }
          final before = _entries.length;
          await store(request, response);
          if (_entries.length > before) {
            stored++;
          }
        } on RoverApiConnectionException {
          markOffline();
          break;
        } on RoverApiTimeoutException {
          markOffline();
          break;
        } on RoverApiException {
          markOnline();
        }
      }
    } finally {
      _isPreloading = false;
      FieldDiagnostics.instance.record(
        'offline',
        'journey preload finished; added=$stored; entries=${_entries.length}',
      );
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _entries.clear();
    _sizeBytes = 0;
    _preloadedJourneyKey = null;
    final file = _cacheFile;
    if (file != null && await file.exists()) {
      await file.delete();
    }
    FieldDiagnostics.instance.record(
      'offline',
      'device Story Pack cache cleared',
    );
    notifyListeners();
  }

  void _setConnectivity(RoverConnectivityState value) {
    if (_connectivityState == value) {
      return;
    }
    _connectivityState = value;
    FieldDiagnostics.instance.record('offline', 'connectivity=${value.name}');
    notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    return _loadFuture ??= _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final file = _cacheFile;
    if (file == null || !await file.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) {
        return;
      }
      final now = _nowUtc();
      _entries
        ..clear()
        ..addAll(
          (decoded['entries'] as List)
              .whereType<Map>()
              .map(
                (entry) => _OfflineStoryEntry.fromJson(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((entry) => entry.expiresUtc.isAfter(now)),
        );
      _trim();
    } on FormatException {
      _entries.clear();
    } on FileSystemException {
      _entries.clear();
    }
    _recalculateSize();
  }

  Future<void> _persist() async {
    final file = _cacheFile;
    final encoded = jsonEncode({
      'schemaVersion': '1.0',
      'entries': _entries.map((entry) => entry.toJson()).toList(),
    });
    _sizeBytes = utf8.encode(encoded).length;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  void _trim() {
    _entries.removeWhere((entry) => !entry.expiresUtc.isAfter(_nowUtc()));
    while (_entries.length > maximumEntries) {
      _entries.removeLast();
    }
    _recalculateSize();
    while (_entries.length > 1 && _sizeBytes > maximumBytes) {
      _entries.removeLast();
      _recalculateSize();
    }
  }

  void _recalculateSize() {
    _sizeBytes = utf8
        .encode(jsonEncode(_entries.map((entry) => entry.toJson()).toList()))
        .length;
  }

  List<_NearbyOfflineEntry> _nearbyEntries(
    RoverLatLng location,
    double radiusMeters,
    DateTime now,
  ) {
    final matches = <_NearbyOfflineEntry>[];
    for (final entry in _entries) {
      if (!entry.expiresUtc.isAfter(now)) {
        continue;
      }
      final distance = location.distanceTo(entry.coordinates);
      if (distance <= radiusMeters) {
        matches.add(_NearbyOfflineEntry(entry, distance));
      }
    }
    matches.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return matches;
  }

  _OfflineStoryEntry? _sanitize(
    LocationStoryRequest request,
    LocationStoryResponse response,
    DateTime now,
  ) {
    final pack = response.storyPack;
    if (pack == null) {
      return null;
    }
    final validation = _map(pack['validation']);
    final identity = _map(pack['placeIdentity']);
    if (validation?['isValid'] != true || identity == null) {
      return null;
    }
    final isStoryPackV2 = pack['schemaVersion'] == '2.0';
    final declaredRetentionClass = _normalize(
      _map(pack['cacheEligibility'])?['retentionClass'],
    );
    if (isStoryPackV2 &&
        _map(pack['cacheEligibility'])?['offlineEligible'] != true) {
      return null;
    }
    if (isStoryPackV2 &&
        (declaredRetentionClass == 'live' ||
            declaredRetentionClass == 'restricted' ||
            !const {
              'evergreen',
              'expiring',
              'mixed',
            }.contains(declaredRetentionClass))) {
      return null;
    }
    final allSources = _mapList(pack['sources']);
    if (allSources.any(
          (source) =>
              _normalize(source['providerName']).contains('google') ||
              _normalize(source['sourceId']).contains('google') ||
              _normalize(source['attribution']).contains('google maps'),
        ) ||
        _stringList(pack['requiredAttribution'])
            .any((value) => _normalize(value).contains('google maps'))) {
      return null;
    }

    final packExpiry = _parseDate(pack['expiresUtc']);
    if (packExpiry != null && !packExpiry.isAfter(now)) {
      return null;
    }
    final eligibleSources = allSources.where((source) {
      final expires = _parseDate(source['expiresUtc']);
      return expires == null || expires.isAfter(now);
    }).toList();
    final eligibleSourceIds = eligibleSources
        .map((source) => source['sourceId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final claims = <Map<String, dynamic>>[];
    for (final claim in _mapList(pack['evidenceClaims'])) {
      final expires = _parseDate(claim['expiresUtc']);
      final sourceIds = _stringList(claim['sourceIds']);
      if ((expires != null && !expires.isAfter(now)) ||
          sourceIds.isEmpty ||
          !sourceIds.every(eligibleSourceIds.contains) ||
          _unsafeClaim(claim)) {
        continue;
      }
      claims.add(claim);
    }
    final evidenceIds = claims
        .map((claim) => claim['evidenceId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final sections = <Map<String, dynamic>>[];
    for (final section in _mapList(pack['sections'])) {
      final sentences = _mapList(section['sentences']).where((sentence) {
        final ids = _stringList(sentence['evidenceIds']);
        return ids.isNotEmpty && ids.every(evidenceIds.contains);
      }).toList();
      if (sentences.isNotEmpty) {
        sections.add({...section, 'sentences': sentences});
      }
    }
    if (sections.isEmpty) {
      return null;
    }

    final usedSourceIds = claims
        .expand((claim) => _stringList(claim['sourceIds']))
        .toSet();
    final sources = eligibleSources
        .where(
          (source) => usedSourceIds.contains(source['sourceId']?.toString()),
        )
        .toList();
    if (sources.isEmpty) {
      return null;
    }

    final candidateExpiries = <DateTime>[
      ?packExpiry,
      ...claims.map((claim) => _parseDate(claim['expiresUtc'])).nonNulls,
      ...sources.map((source) => _parseDate(source['expiresUtc'])).nonNulls,
    ].where((value) => value.isAfter(now)).toList();
    final evidenceExpiry = candidateExpiries.isEmpty
        ? now.add(const Duration(days: 30))
        : candidateExpiries.reduce((a, b) => a.isBefore(b) ? a : b);
    final retainedClass =
        claims.every((claim) {
          final expiry = _parseDate(claim['expiresUtc']);
          return expiry == null ||
              expiry.isAfter(now.add(const Duration(days: 3)));
        })
        ? 'evergreen'
        : 'expiring';
    final retentionLimit = retainedClass == 'evergreen'
        ? now.add(const Duration(days: 30))
        : now.add(const Duration(days: 7));
    final expiresUtc = evidenceExpiry.isBefore(retentionLimit)
        ? evidenceExpiry
        : retentionLimit;
    if (!expiresUtc.isAfter(now)) {
      return null;
    }

    final arrival = sections.where(
      (section) => _normalize(section['sectionType']) == 'arrival',
    );
    final spokenSections = arrival.isEmpty ? sections.take(1) : arrival;
    final shortNarration = _sectionText(spokenSections);
    final tellMore = _sectionText(sections);
    if (shortNarration.isEmpty) {
      return null;
    }

    final canonicalId = identity['canonicalPlaceId']?.toString().trim() ?? '';
    final placeId = canonicalId.isEmpty
        ? response.placeId?.trim() ?? ''
        : canonicalId;
    if (placeId.isEmpty) {
      return null;
    }
    final name = identity['name']?.toString().trim();
    final aliases = {
      _normalize(placeId),
      _normalize(response.placeId),
      ...request.selectedPlaceIds.map(_normalize),
    }..removeWhere((value) => value.isEmpty);
    final lastVerified =
        _parseDate(pack['lastVerifiedUtc']) ??
        _parseDate(identity['verifiedUtc']) ??
        _parseDate(pack['generatedUtc']) ??
        now;
    final safeSentenceIds = sections
        .expand((section) => _mapList(section['sentences']))
        .map((sentence) => sentence['sentenceId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final safeVariants = isStoryPackV2
        ? _mapList(pack['narrationVariants'])
              .map((variant) {
                final sentenceIds = _stringList(variant['sentenceIds'])
                    .where(safeSentenceIds.contains)
                    .toList(growable: false);
                final variantEvidenceIds = _stringList(variant['evidenceIds'])
                    .where(evidenceIds.contains)
                    .toList(growable: false);
                return {
                  ...variant,
                  'sentenceIds': sentenceIds,
                  'evidenceIds': variantEvidenceIds,
                  'prefetchedAudioReference': null,
                };
              })
              .where((variant) => (variant['sentenceIds'] as List).isNotEmpty)
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final safePack = <String, dynamic>{
      ...pack,
      'sections': sections,
      'evidenceClaims': claims,
      'sources': sources,
      'expiresUtc': expiresUtc.toIso8601String(),
      if (isStoryPackV2) 'narrationVariants': safeVariants,
      if (isStoryPackV2)
        'cacheEligibility': {
          'offlineEligible': true,
          'audioCacheEligible': true,
          'retentionClass': retainedClass,
          'reason': 'Live claims were removed before device persistence.',
        },
    };
    final sourceReferences = sources
        .map(
          (source) => LocationSourceReference(
            providerName: source['providerName']?.toString() ?? 'Unknown',
            providerRecordId: source['providerRecordId']?.toString(),
            sourceTitle: source['sourceTitle']?.toString(),
            sourceUrl: source['sourceUrl']?.toString(),
            attribution: source['attribution']?.toString() ?? '',
            license: source['license']?.toString(),
            retrievedUtc: _parseDate(source['retrievedUtc']),
            expiresUtc: _parseDate(source['expiresUtc']),
            confidenceScore: (source['confidence'] as num?)?.toDouble(),
          ),
        )
        .toList(growable: false);
    final safeResponse = LocationStoryResponse(
      storyTitle: response.storyTitle,
      shortSpokenNarration: shortNarration,
      tellMeMore: tellMore == shortNarration ? null : tellMore,
      placeId: placeId,
      factIdsUsed: evidenceIds.toList(growable: false),
      sourceReferences: sourceReferences,
      confidence: response.confidence,
      requiredAttribution: response.requiredAttribution,
      warnings: const [],
      storyPack: safePack,
      cachedAtUtc: now,
      lastVerifiedUtc: lastVerified,
      expiresUtc: expiresUtc,
    );
    return _OfflineStoryEntry(
      placeId: placeId,
      aliases: aliases,
      name: name == null || name.isEmpty ? response.storyTitle : name,
      address: identity['address']?.toString(),
      categories: _stringList(identity['categories']),
      coordinates: RoverLatLng(
        latitude:
            (identity['latitude'] as num?)?.toDouble() ??
            request.location.latitude,
        longitude:
            (identity['longitude'] as num?)?.toDouble() ??
            request.location.longitude,
      ),
      cachedAtUtc: now,
      lastVerifiedUtc: lastVerified,
      expiresUtc: expiresUtc,
      retentionClass: retainedClass,
      response: safeResponse,
    );
  }
}

class _OfflineStoryEntry {
  const _OfflineStoryEntry({
    required this.placeId,
    required this.aliases,
    required this.name,
    required this.categories,
    required this.coordinates,
    required this.cachedAtUtc,
    required this.lastVerifiedUtc,
    required this.expiresUtc,
    required this.retentionClass,
    required this.response,
    this.address,
  });

  final String placeId;
  final Set<String> aliases;
  final String name;
  final String? address;
  final List<String> categories;
  final RoverLatLng coordinates;
  final DateTime cachedAtUtc;
  final DateTime lastVerifiedUtc;
  final DateTime expiresUtc;
  final String retentionClass;
  final LocationStoryResponse response;

  LocationStoryResponse get offlineResponse {
    final verified = _dateLabel(lastVerifiedUtc);
    return LocationStoryResponse(
      storyTitle: response.storyTitle,
      shortSpokenNarration:
          'From your offline stories, last verified $verified. '
          '${response.shortSpokenNarration}',
      tellMeMore: response.tellMeMore,
      placeId: response.placeId,
      factIdsUsed: response.factIdsUsed,
      sourceReferences: response.sourceReferences,
      confidence: response.confidence,
      requiredAttribution: response.requiredAttribution,
      warnings: const [
        'Offline cached story. Live hours, closures, prices, events, weather, and current conditions are unavailable.',
      ],
      storyPack: response.storyPack,
      offlineCached: true,
      cachedAtUtc: cachedAtUtc,
      lastVerifiedUtc: lastVerifiedUtc,
      expiresUtc: expiresUtc,
    );
  }

  LocationPlaceSummary toPlaceSummary(double distanceMeters) {
    final claims = _mapList(response.storyPack?['evidenceClaims']);
    return LocationPlaceSummary(
      canonicalId: placeId,
      name: name,
      coordinates: coordinates,
      address: address,
      categories: categories,
      shortDescription: response.shortSpokenNarration,
      facts: claims
          .map(
            (claim) => LocationFactSummary(
              factId: claim['evidenceId']?.toString() ?? '',
              factType: claim['claimType']?.toString() ?? 'Fact',
              factText: claim['text']?.toString() ?? '',
              confidenceScore: (claim['confidence'] as num?)?.toDouble() ?? 0,
              isSuitableForNarration: true,
            ),
          )
          .toList(growable: false),
      distanceFromUserMeters: distanceMeters,
      confidenceScore: response.confidence,
      storyWorthinessScore: response.confidence * 100,
      storyWorthinessReasons: const ['Offline cached Story Pack'],
      sourceReferences: response.sourceReferences,
    );
  }

  Map<String, Object?> toJson() => {
    'placeId': placeId,
    'aliases': aliases.toList(growable: false),
    'name': name,
    'address': address,
    'categories': categories,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'cachedAtUtc': cachedAtUtc.toIso8601String(),
    'lastVerifiedUtc': lastVerifiedUtc.toIso8601String(),
    'expiresUtc': expiresUtc.toIso8601String(),
    'retentionClass': retentionClass,
    'response': response.toJson(),
  };

  factory _OfflineStoryEntry.fromJson(Map<String, dynamic> json) {
    return _OfflineStoryEntry(
      placeId: json['placeId'] as String? ?? '',
      aliases: _stringList(json['aliases']).toSet(),
      name: json['name'] as String? ?? 'Offline place',
      address: json['address'] as String?,
      categories: _stringList(json['categories']),
      coordinates: RoverLatLng(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      ),
      cachedAtUtc:
          _parseDate(json['cachedAtUtc']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastVerifiedUtc:
          _parseDate(json['lastVerifiedUtc']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresUtc:
          _parseDate(json['expiresUtc']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      retentionClass: json['retentionClass'] as String? ?? 'expiring',
      response: LocationStoryResponse.fromJson(
        _map(json['response']) ?? const {},
      ),
    );
  }
}

class _NearbyOfflineEntry {
  const _NearbyOfflineEntry(this.entry, this.distanceMeters);

  final _OfflineStoryEntry entry;
  final double distanceMeters;
}

bool _unsafeClaim(Map<String, dynamic> claim) {
  final category = _normalize(claim['category']);
  final type = _normalize(claim['claimType']);
  final text = _normalize(claim['text']);
  const unsafeCategories = {
    'relative_location',
    'opening_hours',
    'business_hours',
    'closure',
    'price',
    'pricing',
    'weather',
    'current_event',
    'event',
    'availability',
  };
  if (unsafeCategories.contains(category) || unsafeCategories.contains(type)) {
    return true;
  }
  final compactKind = '$category$type'.replaceAll(RegExp(r'[^a-z]'), '');
  const unsafeKinds = [
    'relativelocation',
    'openinghours',
    'businesshours',
    'openingstatus',
    'currentevent',
    'liveavailability',
  ];
  if (unsafeKinds.any(compactKind.contains)) {
    return true;
  }
  const phrases = [
    'currently open',
    'currently closed',
    'open today',
    'closed today',
    'hours today',
    'today only',
    'tonight',
    'current price',
    r'costs $',
    'weather',
    'degrees',
    'meters away',
    'metres away',
    'ahead left',
    'ahead right',
  ];
  return phrases.any(text.contains);
}

double _nameSimilarity(String query, String name) {
  if (query.isEmpty || name.isEmpty) {
    return 0;
  }
  if (query.contains(name) || name.contains(query)) {
    return 1;
  }
  final queryWords = query.split(' ').where((word) => word.length > 2).toSet();
  final nameWords = name.split(' ').where((word) => word.length > 2).toSet();
  if (queryWords.isEmpty || nameWords.isEmpty) {
    return 0;
  }
  final overlap = queryWords.intersection(nameWords).length;
  return overlap / nameWords.length;
}

String _sectionText(Iterable<Map<String, dynamic>> sections) => sections
    .expand((section) => _mapList(section['sentences']))
    .map((sentence) => sentence['text']?.toString().trim() ?? '')
    .where((text) => text.isNotEmpty)
    .join(' ');

Map<String, dynamic>? _map(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, dynamic>> _mapList(Object? value) =>
    (value as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);

List<String> _stringList(Object? value) => (value as List? ?? const [])
    .map((item) => item.toString())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

String _normalize(Object? value) =>
    value?.toString().trim().toLowerCase() ?? '';

String _normalizeWords(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _dateLabel(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

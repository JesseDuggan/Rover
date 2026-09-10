class BetaConfigurationStatus {
  const BetaConfigurationStatus({
    required this.environmentName,
    required this.appVersion,
    required this.buildNumber,
    required this.isBeta,
    required this.developmentAuthenticationEnabled,
    required this.developerControlsEnabled,
    required this.simulationEnabled,
    required this.requiresHttpsEndpoints,
    required this.secretsConfiguredServerSide,
    required this.mapboxConfigured,
    required this.elevenLabsConfigured,
    required this.warnings,
  });

  final String environmentName;
  final String appVersion;
  final String buildNumber;
  final bool isBeta;
  final bool developmentAuthenticationEnabled;
  final bool developerControlsEnabled;
  final bool simulationEnabled;
  final bool requiresHttpsEndpoints;
  final bool secretsConfiguredServerSide;
  final bool mapboxConfigured;
  final bool elevenLabsConfigured;
  final List<String> warnings;

  factory BetaConfigurationStatus.fromJson(Map<String, dynamic> json) {
    return BetaConfigurationStatus(
      environmentName: json['environmentName'] as String? ?? 'unknown',
      appVersion: json['appVersion'] as String? ?? 'unknown',
      buildNumber: json['buildNumber'] as String? ?? 'unknown',
      isBeta: json['isBeta'] as bool? ?? false,
      developmentAuthenticationEnabled:
          json['developmentAuthenticationEnabled'] as bool? ?? false,
      developerControlsEnabled:
          json['developerControlsEnabled'] as bool? ?? false,
      simulationEnabled: json['simulationEnabled'] as bool? ?? false,
      requiresHttpsEndpoints: json['requiresHttpsEndpoints'] as bool? ?? false,
      secretsConfiguredServerSide:
          json['secretsConfiguredServerSide'] as bool? ?? false,
      mapboxConfigured: json['mapboxConfigured'] as bool? ?? false,
      elevenLabsConfigured: json['elevenLabsConfigured'] as bool? ?? false,
      warnings: (json['warnings'] as List? ?? const []).cast<String>(),
    );
  }
}

class BetaDiagnosticsReport {
  const BetaDiagnosticsReport({
    required this.appVersion,
    required this.buildNumber,
    required this.apiEnvironment,
    required this.apiHealth,
    required this.mapboxConfigured,
    required this.elevenLabsEnabled,
    required this.elevenLabsConfigured,
    required this.storageMode,
    required this.routingMode,
    required this.discoveryMode,
    required this.localDiscoveryMode,
    required this.conversationMode,
    required this.apiRequestCount,
    required this.locationUpdateCount,
    required this.routeRecalculationCount,
    required this.downloadedAudioBytes,
    required this.speechCacheHits,
    required this.speechCacheMisses,
    this.lastOperationName,
    this.lastOperationMilliseconds,
    this.lastSlowOperationName,
    this.lastSlowOperationMilliseconds,
    this.slowOperations = const [],
    required this.backgroundPendingCount,
    required this.backgroundEnqueuedCount,
    required this.backgroundCompletedCount,
    required this.backgroundFailedCount,
    this.lastBackgroundWorkName,
    this.lastBackgroundWorkMilliseconds,
    this.lastBackgroundFailure,
    this.lastSynchronizationUtc,
    this.lastSafeErrorCode,
  });

  final String appVersion;
  final String buildNumber;
  final String apiEnvironment;
  final String apiHealth;
  final bool mapboxConfigured;
  final bool elevenLabsEnabled;
  final bool elevenLabsConfigured;
  final String storageMode;
  final String routingMode;
  final String discoveryMode;
  final String localDiscoveryMode;
  final String conversationMode;
  final int apiRequestCount;
  final int locationUpdateCount;
  final int routeRecalculationCount;
  final int downloadedAudioBytes;
  final int speechCacheHits;
  final int speechCacheMisses;
  final String? lastOperationName;
  final int? lastOperationMilliseconds;
  final String? lastSlowOperationName;
  final int? lastSlowOperationMilliseconds;
  final List<String> slowOperations;
  final int backgroundPendingCount;
  final int backgroundEnqueuedCount;
  final int backgroundCompletedCount;
  final int backgroundFailedCount;
  final String? lastBackgroundWorkName;
  final int? lastBackgroundWorkMilliseconds;
  final String? lastBackgroundFailure;
  final String? lastSynchronizationUtc;
  final String? lastSafeErrorCode;

  factory BetaDiagnosticsReport.fromJson(Map<String, dynamic> json) {
    return BetaDiagnosticsReport(
      appVersion: json['appVersion'] as String? ?? 'unknown',
      buildNumber: json['buildNumber'] as String? ?? 'unknown',
      apiEnvironment: json['apiEnvironment'] as String? ?? 'unknown',
      apiHealth: json['apiHealth'] as String? ?? 'unknown',
      mapboxConfigured: json['mapboxConfigured'] as bool? ?? false,
      elevenLabsEnabled: json['elevenLabsEnabled'] as bool? ?? false,
      elevenLabsConfigured: json['elevenLabsConfigured'] as bool? ?? false,
      storageMode: json['storageMode'] as String? ?? 'unknown',
      routingMode: json['routingMode'] as String? ?? 'unknown',
      discoveryMode: json['discoveryMode'] as String? ?? 'unknown',
      localDiscoveryMode: json['localDiscoveryMode'] as String? ?? 'unknown',
      conversationMode: json['conversationMode'] as String? ?? 'unknown',
      apiRequestCount: json['apiRequestCount'] as int? ?? 0,
      locationUpdateCount: json['locationUpdateCount'] as int? ?? 0,
      routeRecalculationCount: json['routeRecalculationCount'] as int? ?? 0,
      downloadedAudioBytes: json['downloadedAudioBytes'] as int? ?? 0,
      speechCacheHits: json['speechCacheHits'] as int? ?? 0,
      speechCacheMisses: json['speechCacheMisses'] as int? ?? 0,
      lastOperationName: json['lastOperationName'] as String?,
      lastOperationMilliseconds: json['lastOperationMilliseconds'] as int?,
      lastSlowOperationName: json['lastSlowOperationName'] as String?,
      lastSlowOperationMilliseconds:
          json['lastSlowOperationMilliseconds'] as int?,
      slowOperations: (json['slowOperations'] as List? ?? const [])
          .cast<String>(),
      backgroundPendingCount: json['backgroundPendingCount'] as int? ?? 0,
      backgroundEnqueuedCount: json['backgroundEnqueuedCount'] as int? ?? 0,
      backgroundCompletedCount: json['backgroundCompletedCount'] as int? ?? 0,
      backgroundFailedCount: json['backgroundFailedCount'] as int? ?? 0,
      lastBackgroundWorkName: json['lastBackgroundWorkName'] as String?,
      lastBackgroundWorkMilliseconds:
          json['lastBackgroundWorkMilliseconds'] as int?,
      lastBackgroundFailure: json['lastBackgroundFailure'] as String?,
      lastSynchronizationUtc: json['lastSynchronizationUtc'] as String?,
      lastSafeErrorCode: json['lastSafeErrorCode'] as String?,
    );
  }

  String toRedactedText() {
    return [
      'Rover diagnostics',
      'version: $appVersion',
      'build: $buildNumber',
      'environment: $apiEnvironment',
      'api health: $apiHealth',
      'map configured: $mapboxConfigured',
      'elevenlabs enabled: $elevenLabsEnabled',
      'elevenlabs configured: $elevenLabsConfigured',
      'storage: $storageMode',
      'routing: $routingMode',
      'discovery: $discoveryMode',
      'local discovery: $localDiscoveryMode',
      'conversation: $conversationMode',
      'api requests: $apiRequestCount',
      'location updates: $locationUpdateCount',
      'route recalculations: $routeRecalculationCount',
      'audio bytes: $downloadedAudioBytes',
      'speech cache hits: $speechCacheHits',
      'speech cache misses: $speechCacheMisses',
      'last api operation: ${lastOperationName ?? 'none'} ${lastOperationMilliseconds == null ? '' : '$lastOperationMilliseconds ms'}',
      'last slow api operation: ${lastSlowOperationName ?? 'none'} ${lastSlowOperationMilliseconds == null ? '' : '$lastSlowOperationMilliseconds ms'}',
      if (slowOperations.isNotEmpty) 'recent slow api operations:',
      ...slowOperations,
      'background pending: $backgroundPendingCount',
      'background enqueued: $backgroundEnqueuedCount',
      'background completed: $backgroundCompletedCount',
      'background failed: $backgroundFailedCount',
      'last background work: ${lastBackgroundWorkName ?? 'none'} ${lastBackgroundWorkMilliseconds == null ? '' : '$lastBackgroundWorkMilliseconds ms'}',
      'last background failure: ${lastBackgroundFailure ?? 'none'}',
      'last sync: ${lastSynchronizationUtc ?? 'none'}',
      'last error: ${lastSafeErrorCode ?? 'none'}',
    ].join('\n');
  }
}

class ProblemReportRequest {
  const ProblemReportRequest({
    required this.category,
    this.description,
    this.walkSessionId,
    this.stopId,
    this.correlationId,
    this.appVersion = '1.0.0-beta',
    this.buildNumber = '9',
    this.deviceModel = 'Android device',
    this.osVersion = 'Android',
    this.connectivityState = 'unknown',
    this.preciseLocationAttached = false,
  });

  final String category;
  final String? description;
  final String? walkSessionId;
  final String? stopId;
  final String? correlationId;
  final String appVersion;
  final String buildNumber;
  final String deviceModel;
  final String osVersion;
  final String connectivityState;
  final bool preciseLocationAttached;

  Map<String, Object?> toJson() => {
    'category': category,
    'description': description,
    'walkSessionId': walkSessionId,
    'stopId': stopId,
    'correlationId': correlationId,
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'deviceModel': deviceModel,
    'osVersion': osVersion,
    'connectivityState': connectivityState,
    'preciseLocationAttached': preciseLocationAttached,
  };
}

class ProblemReportReceipt {
  const ProblemReportReceipt({
    required this.problemReportId,
    required this.severity,
    required this.receivedAtUtc,
    required this.queued,
  });

  final String problemReportId;
  final String severity;
  final String receivedAtUtc;
  final bool queued;

  factory ProblemReportReceipt.fromJson(Map<String, dynamic> json) {
    return ProblemReportReceipt(
      problemReportId: json['problemReportId'] as String,
      severity: json['severity'] as String,
      receivedAtUtc: json['receivedAtUtc'] as String,
      queued: json['queued'] as bool? ?? false,
    );
  }
}

class PostWalkFeedbackRequest {
  const PostWalkFeedbackRequest({
    required this.overallRating,
    this.directionsEasyToFollow,
    this.stopsDetectedCorrectly,
    this.narrationEnjoyable,
    this.askRoverUseful,
    this.walkRightLength,
    this.wouldTakeAnotherWalk,
    this.comments,
    this.appVersion = '1.0.0-beta',
    this.buildNumber = '9',
  });

  final int overallRating;
  final bool? directionsEasyToFollow;
  final bool? stopsDetectedCorrectly;
  final bool? narrationEnjoyable;
  final bool? askRoverUseful;
  final bool? walkRightLength;
  final bool? wouldTakeAnotherWalk;
  final String? comments;
  final String appVersion;
  final String buildNumber;

  Map<String, Object?> toJson() => {
    'overallRating': overallRating,
    'directionsEasyToFollow': directionsEasyToFollow,
    'stopsDetectedCorrectly': stopsDetectedCorrectly,
    'narrationEnjoyable': narrationEnjoyable,
    'askRoverUseful': askRoverUseful,
    'walkRightLength': walkRightLength,
    'wouldTakeAnotherWalk': wouldTakeAnotherWalk,
    'comments': comments,
    'appVersion': appVersion,
    'buildNumber': buildNumber,
  };
}

class PostWalkFeedbackReceipt {
  const PostWalkFeedbackReceipt({
    required this.feedbackId,
    required this.walkSessionId,
    required this.receivedAtUtc,
  });

  final String feedbackId;
  final String walkSessionId;
  final String receivedAtUtc;

  factory PostWalkFeedbackReceipt.fromJson(Map<String, dynamic> json) {
    return PostWalkFeedbackReceipt(
      feedbackId: json['feedbackId'] as String,
      walkSessionId: json['walkSessionId'] as String,
      receivedAtUtc: json['receivedAtUtc'] as String,
    );
  }
}

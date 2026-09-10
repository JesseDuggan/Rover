import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ask_rover_models.dart';
import 'adaptive_route_story_models.dart';
import 'adaptation_models.dart';
import 'beta_models.dart';
import '../diagnostics/performance_diagnostics.dart';
import 'journey_narration_models.dart';
import 'hotel_rate_models.dart';
import 'local_discovery_options.dart';
import 'location_story_models.dart';
import 'location_observation_models.dart';
import 'location_update_models.dart';
import 'problem_details.dart';
import 'profile_models.dart';
import 'rover_api_config.dart';
import 'speech_models.dart';
import 'walk_models.dart';

class RoverApiClient {
  RoverApiClient({RoverApiConfig? config, HttpClient? httpClient})
    : config = config ?? RoverApiConfig.fromEnvironment(),
      _httpClient = httpClient ?? HttpClient();

  final RoverApiConfig config;
  final HttpClient _httpClient;

  Future<Map<String, dynamic>> getHealth() async {
    return _sendJson('GET', '/health');
  }

  Future<BetaConfigurationStatus> getBetaConfiguration() async {
    final json = await _sendJson('GET', '/api/beta/configuration');
    return BetaConfigurationStatus.fromJson(json);
  }

  Future<BetaDiagnosticsReport> getBetaDiagnostics() async {
    final json = await _sendJson('GET', '/api/beta/diagnostics');
    return BetaDiagnosticsReport.fromJson(json);
  }

  Future<ProblemReportReceipt> submitProblemReport(
    ProblemReportRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/beta/problem-reports',
      body: request.toJson(),
    );
    return ProblemReportReceipt.fromJson(json);
  }

  Future<PostWalkFeedbackReceipt> submitPostWalkFeedback(
    String walkSessionId,
    PostWalkFeedbackRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/feedback',
      body: request.toJson(),
    );
    return PostWalkFeedbackReceipt.fromJson(json);
  }

  Future<LocalDiscoveryOptionsResult> getLocalDiscoveryOptions({
    required double latitude,
    required double longitude,
  }) async {
    final json = await _sendJson(
      'GET',
      '/api/beta/local-discovery-options?latitude=$latitude&longitude=$longitude',
    );
    return LocalDiscoveryOptionsResult.fromJson(json);
  }

  Future<HotelRateSearchResult> searchHotelRates(
    HotelRateSearchRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/commerce/hotel-rates/search',
      body: request.toJson(),
    );
    return HotelRateSearchResult.fromJson(json);
  }

  Future<bool> hasPostWalkFeedback(String walkSessionId) async {
    final json = await _sendJson(
      'GET',
      '/api/walks/$walkSessionId/feedback/status',
    );
    return json['submitted'] as bool? ?? false;
  }

  Future<GuestProfile> createOrGetGuestProfile(String installationId) async {
    final json = await _sendJson(
      'POST',
      '/api/profiles/guest',
      body: GuestProfileRequest(installationId: installationId).toJson(),
    );
    return GuestProfile.fromJson(json);
  }

  Future<GuestProfile> updateProfilePreferences(
    String profileId,
    UpdateProfilePreferencesRequest request,
  ) async {
    final json = await _sendJson(
      'PATCH',
      '/api/profiles/$profileId/preferences',
      body: request.toJson(),
    );
    return GuestProfile.fromJson(json);
  }

  Future<GuestProfile> saveDiscovery(
    String profileId,
    SaveDiscoveryRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/profiles/$profileId/saved-discoveries',
      body: request.toJson(),
    );
    return GuestProfile.fromJson(json);
  }

  Future<void> recordStoryInteraction(
    String profileId,
    StoryInteractionRequest request,
  ) async {
    await _sendJson(
      'POST',
      '/api/profiles/$profileId/story-interactions',
      body: request.toJson(),
    );
  }

  Future<void> deleteProfile(String profileId) async {
    await _send('DELETE', '/api/profiles/$profileId');
  }

  Future<WalkSession> createWalk(CreateWalkRequest request) async {
    final json = await _sendJson('POST', '/api/walks', body: request.toJson());
    return WalkSession.fromJson(json);
  }

  Future<WalkSession> getWalk(String walkSessionId) async {
    final json = await _sendJson('GET', '/api/walks/$walkSessionId');
    return WalkSession.fromJson(json);
  }

  Future<List<WalkStop>> getStops(String walkSessionId) async {
    final json = await _sendJsonList('GET', '/api/walks/$walkSessionId/stops');
    return json.map((item) => WalkStop.fromJson(item)).toList();
  }

  Future<WalkStop?> getNextStop(String walkSessionId) async {
    final response = await _sendNullableJson(
      'GET',
      '/api/walks/$walkSessionId/next-stop',
    );
    return response == null ? null : WalkStop.fromJson(response);
  }

  Future<WalkSession> startWalk(String walkSessionId) async {
    final json = await _sendJson('POST', '/api/walks/$walkSessionId/start');
    return WalkSession.fromJson(json);
  }

  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  }) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/stops/$stopId/arrive',
      body: latitude == null || longitude == null
          ? <String, Object?>{}
          : {'latitude': latitude, 'longitude': longitude},
    );
    return WalkSession.fromJson(json);
  }

  Future<LocationUpdateResult> updateLocation(
    String walkSessionId,
    LocationUpdateRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/location',
      body: request.toJson(),
    );
    return LocationUpdateResult.fromJson(json);
  }

  Future<AskRoverResponse> askRover(
    String walkSessionId,
    AskRoverRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/ask',
      body: request.toJson(),
    );
    return AskRoverResponse.fromJson(json);
  }

  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/journey-narration/evaluate',
      body: request.toJson(),
    );
    return JourneyNarrationDecision.fromJson(json);
  }

  Future<AdaptiveRouteStoryPackState> generateRouteStoryPack(
    String walkSessionId,
    GenerateRouteStoryPackRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/route-story-pack/generate',
      body: request.toJson(),
    );
    return AdaptiveRouteStoryPackState.fromJson(json);
  }

  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(
    String walkSessionId,
  ) async {
    final json = await _sendJson(
      'GET',
      '/api/walks/$walkSessionId/route-story-pack/status',
    );
    return AdaptiveRouteStoryPackState.fromJson(json);
  }

  Future<AdaptiveRouteStoryPack> getRouteStoryPack(String walkSessionId) async {
    final json = await _sendJson(
      'GET',
      '/api/walks/$walkSessionId/route-story-pack',
    );
    return AdaptiveRouteStoryPack.fromJson(json);
  }

  Future<AdaptiveRouteStorySelection?> getNextRouteStory(
    String walkSessionId,
    NextRouteStoryRequest request,
  ) async {
    final json = await _sendNullableJsonWithBody(
      'POST',
      '/api/walks/$walkSessionId/route-story-pack/next',
      request.toJson(),
    );
    return json == null ? null : AdaptiveRouteStorySelection.fromJson(json);
  }

  Future<AdaptiveRouteStoryAnswer> askRouteStory(
    String walkSessionId,
    RouteStoryQuestionRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/route-story-pack/ask',
      body: request.toJson(),
    );
    return AdaptiveRouteStoryAnswer.fromJson(json);
  }

  Future<void> recordRouteStoryPlayback(
    String walkSessionId,
    RouteStoryPlaybackEventRequest request,
  ) async {
    await _send(
      'POST',
      '/api/walks/$walkSessionId/route-story-pack/playback-events',
      body: request.toJson(),
    );
  }

  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/location-story',
      body: request.toJson(),
    );
    return LocationStoryResponse.fromJson(json);
  }

  Future<LocationObservationResolution> resolveLocationObservation(
    LocationObservationResolveRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/location-observations/resolve',
      body: request.toJson(),
    );
    return LocationObservationResolution.fromJson(json);
  }

  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  }) async {
    final route = routeId == null
        ? ''
        : '&routeId=${Uri.encodeComponent(routeId)}';
    final json = await _sendJson(
      'GET',
      '/api/location-context?lat=$latitude&lng=$longitude&radiusMeters=$radiusMeters$route',
    );
    return LocationStoryContext.fromJson(json);
  }

  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/adaptations/evaluate',
      body: request.toJson(),
    );
    return WalkAdaptationProposal.fromJson(json);
  }

  Future<WalkSession> acceptAdaptation(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/adaptations/$adaptationId/accept',
      body: {'routeRevision': routeRevision},
    );
    return WalkSession.fromJson(json);
  }

  Future<WalkAdaptationProposal> rejectAdaptation(
    String walkSessionId,
    String adaptationId,
  ) async {
    final json = await _sendJson(
      'POST',
      '/api/walks/$walkSessionId/adaptations/$adaptationId/reject',
    );
    return WalkAdaptationProposal.fromJson(json);
  }

  Future<WalkSession> completeWalk(String walkSessionId) async {
    final json = await _sendJson('POST', '/api/walks/$walkSessionId/complete');
    return WalkSession.fromJson(json);
  }

  Future<WalkSession> cancelWalk(String walkSessionId) async {
    final json = await _sendJson('POST', '/api/walks/$walkSessionId/cancel');
    return WalkSession.fromJson(json);
  }

  Future<RenderedSpeechAudio> renderSpeech(RenderSpeechRequest body) async {
    final stopwatch = Stopwatch()..start();
    const operationName = 'POST /api/speech/render';
    try {
      final request = await _httpClient
          .openUrl('POST', config.uri('/api/speech/render'))
          .timeout(config.connectionTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'audio/mpeg');
      _applyDevelopmentUser(request);
      request.write(jsonEncode(body.toJson()));

      final response = await request.close().timeout(config.responseTimeout);
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        PerformanceDiagnostics.instance.record(
          operationName,
          stopwatch.elapsed,
        );
        return RenderedSpeechAudio(
          bytes: bytes,
          contentType: response.headers.contentType?.mimeType ?? 'audio/mpeg',
          provider:
              response.headers.value('x-rover-speech-provider') ?? 'Unknown',
          cacheStatus:
              response.headers.value('x-rover-speech-cache') ?? 'unknown',
          usedFallback:
              response.headers.value('x-rover-speech-fallback') == 'true',
          fallbackReason: response.headers.value(
            'x-rover-speech-fallback-reason',
          ),
        );
      }

      PerformanceDiagnostics.instance.record(
        '$operationName HTTP ${response.statusCode}',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiException(
        'Premium Rover voice is unavailable.',
        statusCode: response.statusCode,
      );
    } on TimeoutException {
      PerformanceDiagnostics.instance.record(
        '$operationName timeout',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiTimeoutException(
        'Premium Rover voice timed out while contacting '
        '${config.normalizedBaseUrl}. Confirm the laptop and device are on '
        'the same network.',
      );
    } on SocketException {
      PerformanceDiagnostics.instance.record(
        '$operationName connection failed',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiConnectionException(
        'Premium Rover voice could not reach ${config.normalizedBaseUrl}. '
        'The connection was refused or the network is unavailable. Confirm '
        'the laptop and device are on the same network.',
      );
    }
  }

  void close({bool force = false}) {
    _httpClient.close(force: force);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final decoded = await _send(method, path, body: body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const RoverApiException(
      'The Rover API returned an unexpected response.',
    );
  }

  Future<Map<String, dynamic>?> _sendNullableJson(
    String method,
    String path,
  ) async {
    final decoded = await _send(method, path);
    if (decoded == null) {
      return null;
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const RoverApiException(
      'The Rover API returned an unexpected response.',
    );
  }

  Future<Map<String, dynamic>?> _sendNullableJsonWithBody(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    final decoded = await _send(method, path, body: body);
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic>) return decoded;
    throw const RoverApiException(
      'The Rover API returned an unexpected response.',
    );
  }

  Future<List<Map<String, dynamic>>> _sendJsonList(
    String method,
    String path,
  ) async {
    final decoded = await _send(method, path);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    throw const RoverApiException(
      'The Rover API returned an unexpected response.',
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final operationName = '$method $path';
    final stopwatch = Stopwatch()..start();
    try {
      final request = await _httpClient
          .openUrl(method, config.uri(path))
          .timeout(config.connectionTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      _applyDevelopmentUser(request);

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(config.responseTimeout);
      final source = await response.transform(utf8.decoder).join();
      final decoded = source.trim().isEmpty ? null : jsonDecode(source);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        PerformanceDiagnostics.instance.record(
          operationName,
          stopwatch.elapsed,
        );
        return decoded;
      }

      final problem = decoded is Map<String, dynamic>
          ? ProblemDetails.fromJson(decoded)
          : null;
      final failureReason = problem?.displayMessage;
      PerformanceDiagnostics.instance.record(
        failureReason == null || failureReason.isEmpty
            ? '$operationName HTTP ${response.statusCode}'
            : '$operationName HTTP ${response.statusCode}: $failureReason',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiException(
        problem?.displayMessage ??
            'The Rover API returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        problem: problem,
      );
    } on TimeoutException {
      PerformanceDiagnostics.instance.record(
        '$operationName timeout',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiTimeoutException(
        'The Rover API at ${config.normalizedBaseUrl} timed out. Confirm the '
        'API is running and the laptop and device are on the same network.',
      );
    } on SocketException {
      PerformanceDiagnostics.instance.record(
        '$operationName connection failed',
        stopwatch.elapsed,
        success: false,
      );
      throw RoverApiConnectionException(
        'Could not reach the Rover API at ${config.normalizedBaseUrl}. The '
        'connection was refused or the network is unavailable. Confirm the '
        'laptop and device are on the same network.',
      );
    }
  }

  void _applyDevelopmentUser(HttpClientRequest request) {
    final user = config.developmentUser;
    if (user != null && user.trim().isNotEmpty) {
      request.headers.set('X-Rover-Dev-User', user.trim());
    }
  }
}

import 'ask_rover_models.dart';
import 'adaptive_route_story_models.dart';
import 'adaptation_models.dart';
import 'journey_narration_models.dart';
import 'location_update_models.dart';
import 'location_story_models.dart';
import 'location_observation_models.dart';
import 'local_discovery_options.dart';
import 'profile_models.dart';
import '../location/rover_location.dart';
import '../on_device_ai/rover_offline_intelligence.dart';
import 'problem_details.dart';
import 'rover_api_client.dart';
import 'speech_models.dart';
import 'walk_models.dart';

abstract class WalkRepository {
  Future<Map<String, dynamic>> getHealth();
  Future<GuestProfile> createOrGetGuestProfile(String installationId);
  Future<GuestProfile> updateProfilePreferences(
    String profileId,
    UpdateProfilePreferencesRequest request,
  );
  Future<GuestProfile> saveDiscovery(
    String profileId,
    SaveDiscoveryRequest request,
  );
  Future<void> recordStoryInteraction(
    String profileId,
    StoryInteractionRequest request,
  ) async {}
  Future<void> deleteProfile(String profileId);
  Future<RenderedSpeechAudio> renderSpeech(RenderSpeechRequest request);
  Future<LocalDiscoveryOptionsResult> getLocalDiscoveryOptions({
    required double latitude,
    required double longitude,
  });
  Future<WalkSession> createWalk(CreateWalkRequest request);
  Future<WalkSession> getWalk(String walkSessionId);
  Future<List<WalkStop>> getStops(String walkSessionId);
  Future<WalkStop?> getNextStop(String walkSessionId);
  Future<WalkSession> startWalk(String walkSessionId);
  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  });
  Future<LocationUpdateResult> updateLocation(
    String walkSessionId,
    LocationUpdateRequest request,
  );
  Future<AskRoverResponse> askRover(
    String walkSessionId,
    AskRoverRequest request,
  );
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  );
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  );
  Future<LocationObservationResolution> resolveLocationObservation(
    LocationObservationResolveRequest request,
  );
  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  });
  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  );
  Future<WalkSession> acceptAdaptation(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  );
  Future<WalkAdaptationProposal> rejectAdaptation(
    String walkSessionId,
    String adaptationId,
  );
  Future<WalkSession> completeWalk(String walkSessionId);
  Future<WalkSession> cancelWalk(String walkSessionId);
}

abstract class AdaptiveRouteStoryRepository {
  Future<AdaptiveRouteStoryPackState> generateRouteStoryPack(
    String walkSessionId,
    GenerateRouteStoryPackRequest request,
  );
  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(
    String walkSessionId,
  );
  Future<AdaptiveRouteStoryPack> getRouteStoryPack(String walkSessionId);
  Future<AdaptiveRouteStorySelection?> getNextRouteStory(
    String walkSessionId,
    NextRouteStoryRequest request,
  );
  Future<AdaptiveRouteStoryAnswer> askRouteStory(
    String walkSessionId,
    RouteStoryQuestionRequest request,
  );
  Future<void> recordRouteStoryPlayback(
    String walkSessionId,
    RouteStoryPlaybackEventRequest request,
  );
}

class HttpWalkRepository
    implements WalkRepository, AdaptiveRouteStoryRepository {
  HttpWalkRepository({
    RoverApiClient? client,
    RoverOfflineIntelligence? offlineIntelligence,
  }) : _client = client ?? RoverApiClient(),
       _offlineIntelligence =
           offlineIntelligence ?? RoverOfflineIntelligence.instance;

  final RoverApiClient _client;
  final RoverOfflineIntelligence _offlineIntelligence;

  @override
  Future<Map<String, dynamic>> getHealth() async {
    try {
      final result = await _client.getHealth();
      _offlineIntelligence.markOnline();
      return result;
    } on RoverApiConnectionException {
      _offlineIntelligence.markOffline();
      rethrow;
    } on RoverApiTimeoutException {
      _offlineIntelligence.markOffline();
      rethrow;
    }
  }

  @override
  Future<GuestProfile> createOrGetGuestProfile(String installationId) {
    return _client.createOrGetGuestProfile(installationId);
  }

  @override
  Future<GuestProfile> updateProfilePreferences(
    String profileId,
    UpdateProfilePreferencesRequest request,
  ) {
    return _client.updateProfilePreferences(profileId, request);
  }

  @override
  Future<GuestProfile> saveDiscovery(
    String profileId,
    SaveDiscoveryRequest request,
  ) {
    return _client.saveDiscovery(profileId, request);
  }

  @override
  Future<void> recordStoryInteraction(
    String profileId,
    StoryInteractionRequest request,
  ) {
    return _client.recordStoryInteraction(profileId, request);
  }

  @override
  Future<void> deleteProfile(String profileId) {
    return _client.deleteProfile(profileId);
  }

  @override
  Future<RenderedSpeechAudio> renderSpeech(RenderSpeechRequest request) {
    return _client.renderSpeech(request);
  }

  @override
  Future<LocalDiscoveryOptionsResult> getLocalDiscoveryOptions({
    required double latitude,
    required double longitude,
  }) {
    return _client.getLocalDiscoveryOptions(
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<WalkSession> createWalk(CreateWalkRequest request) {
    return _client.createWalk(request);
  }

  @override
  Future<WalkSession> getWalk(String walkSessionId) {
    return _client.getWalk(walkSessionId);
  }

  @override
  Future<List<WalkStop>> getStops(String walkSessionId) {
    return _client.getStops(walkSessionId);
  }

  @override
  Future<WalkStop?> getNextStop(String walkSessionId) {
    return _client.getNextStop(walkSessionId);
  }

  @override
  Future<WalkSession> startWalk(String walkSessionId) {
    return _client.startWalk(walkSessionId);
  }

  @override
  Future<WalkSession> arriveAtStop(
    String walkSessionId,
    String stopId, {
    double? latitude,
    double? longitude,
  }) {
    return _client.arriveAtStop(
      walkSessionId,
      stopId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<LocationUpdateResult> updateLocation(
    String walkSessionId,
    LocationUpdateRequest request,
  ) {
    return _client.updateLocation(walkSessionId, request);
  }

  @override
  Future<AskRoverResponse> askRover(
    String walkSessionId,
    AskRoverRequest request,
  ) {
    return _client.askRover(walkSessionId, request);
  }

  @override
  Future<JourneyNarrationDecision> evaluateJourneyNarration(
    String walkSessionId,
    JourneyNarrationEvaluateRequest request,
  ) {
    return _client.evaluateJourneyNarration(walkSessionId, request);
  }

  @override
  Future<AdaptiveRouteStoryPackState> generateRouteStoryPack(
    String walkSessionId,
    GenerateRouteStoryPackRequest request,
  ) => _client.generateRouteStoryPack(walkSessionId, request);

  @override
  Future<AdaptiveRouteStoryPackState> getRouteStoryPackStatus(
    String walkSessionId,
  ) => _client.getRouteStoryPackStatus(walkSessionId);

  @override
  Future<AdaptiveRouteStoryPack> getRouteStoryPack(String walkSessionId) =>
      _client.getRouteStoryPack(walkSessionId);

  @override
  Future<AdaptiveRouteStorySelection?> getNextRouteStory(
    String walkSessionId,
    NextRouteStoryRequest request,
  ) => _client.getNextRouteStory(walkSessionId, request);

  @override
  Future<AdaptiveRouteStoryAnswer> askRouteStory(
    String walkSessionId,
    RouteStoryQuestionRequest request,
  ) => _client.askRouteStory(walkSessionId, request);

  @override
  Future<void> recordRouteStoryPlayback(
    String walkSessionId,
    RouteStoryPlaybackEventRequest request,
  ) => _client.recordRouteStoryPlayback(walkSessionId, request);

  @override
  Future<LocationStoryResponse> createLocationStory(
    LocationStoryRequest request,
  ) async {
    try {
      final response = await _client.createLocationStory(request);
      _offlineIntelligence.markOnline();
      await _offlineIntelligence.store(request, response);
      return response;
    } on RoverApiConnectionException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.findStory(request);
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiTimeoutException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.findStory(request);
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiException {
      _offlineIntelligence.markOnline();
      rethrow;
    }
  }

  @override
  Future<LocationObservationResolution> resolveLocationObservation(
    LocationObservationResolveRequest request,
  ) async {
    try {
      final response = await _client.resolveLocationObservation(request);
      _offlineIntelligence.markOnline();
      return response;
    } on RoverApiConnectionException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.resolveObservation(request);
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiTimeoutException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.resolveObservation(request);
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiException {
      _offlineIntelligence.markOnline();
      rethrow;
    }
  }

  @override
  Future<LocationStoryContext> getLocationContext({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? routeId,
  }) async {
    try {
      final response = await _client.getLocationContext(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        routeId: routeId,
      );
      _offlineIntelligence.markOnline();
      return response;
    } on RoverApiConnectionException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.findContext(
        location: RoverLatLng(latitude: latitude, longitude: longitude),
        radiusMeters: radiusMeters,
      );
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiTimeoutException {
      _offlineIntelligence.markOffline();
      final cached = await _offlineIntelligence.findContext(
        location: RoverLatLng(latitude: latitude, longitude: longitude),
        radiusMeters: radiusMeters,
      );
      if (cached != null) {
        return cached;
      }
      rethrow;
    } on RoverApiException {
      _offlineIntelligence.markOnline();
      rethrow;
    }
  }

  @override
  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) {
    return _client.evaluateAdaptation(walkSessionId, request);
  }

  @override
  Future<WalkSession> acceptAdaptation(
    String walkSessionId,
    String adaptationId,
    int routeRevision,
  ) {
    return _client.acceptAdaptation(walkSessionId, adaptationId, routeRevision);
  }

  @override
  Future<WalkAdaptationProposal> rejectAdaptation(
    String walkSessionId,
    String adaptationId,
  ) {
    return _client.rejectAdaptation(walkSessionId, adaptationId);
  }

  @override
  Future<WalkSession> completeWalk(String walkSessionId) {
    return _client.completeWalk(walkSessionId);
  }

  @override
  Future<WalkSession> cancelWalk(String walkSessionId) {
    return _client.cancelWalk(walkSessionId);
  }
}

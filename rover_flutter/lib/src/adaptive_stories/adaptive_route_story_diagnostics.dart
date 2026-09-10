import 'package:flutter/foundation.dart';

import '../api/adaptive_route_story_models.dart';

class AdaptiveRouteStoryDiagnostics extends ChangeNotifier {
  AdaptiveRouteStoryDiagnostics._();

  static final AdaptiveRouteStoryDiagnostics instance =
      AdaptiveRouteStoryDiagnostics._();

  String status = 'not loaded';
  int storyCount = 0;
  int heardCount = 0;
  int savedCount = 0;
  bool offlineEligible = false;
  bool deviceCached = false;
  bool usingOfflinePack = false;
  int queuedEventCount = 0;
  DateTime? updatedUtc;
  String? error;

  void update(
    AdaptiveRouteStoryPackState? state, {
    required bool isOfflineEligible,
    required bool isDeviceCached,
    required bool usingOfflinePack,
    required int queuedEventCount,
    String? errorMessage,
  }) {
    status = state?.status ?? 'not loaded';
    storyCount = state?.pack?.stories.length ?? 0;
    heardCount = state?.heardStoryIds.length ?? 0;
    savedCount = state?.savedStoryIds.length ?? 0;
    offlineEligible = isOfflineEligible;
    deviceCached = isDeviceCached;
    this.usingOfflinePack = usingOfflinePack;
    this.queuedEventCount = queuedEventCount;
    updatedUtc = state?.updatedUtc;
    error = errorMessage;
    notifyListeners();
  }
}

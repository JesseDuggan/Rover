import '../api/location_story_models.dart';
import '../preferences/rover_preferences.dart';
import 'rover_scout.dart';

enum RoverStoryFreshness { stable, timeSensitive }

enum RoverNarrationLength { short, standard, detailed }

class RoverCuratorStoryCandidate {
  const RoverCuratorStoryCandidate({
    required this.storyId,
    required this.verifiedEvidenceIds,
    this.interests = const [],
    this.exclusionTags = const [],
    this.routeStopIds = const [],
    this.allowedTravelModes = const {},
    this.accessibilityTags = const [],
    this.estimatedMinutes = 1,
    this.narrationLength = RoverNarrationLength.standard,
    this.freshness = RoverStoryFreshness.stable,
    this.expiresAtUtc,
    this.confidence = 0,
    this.baseScore = 0,
  });

  final String storyId;
  final List<String> verifiedEvidenceIds;
  final List<String> interests;
  final List<String> exclusionTags;
  final List<String> routeStopIds;
  final Set<RoverTravelMode> allowedTravelModes;
  final List<String> accessibilityTags;
  final int estimatedMinutes;
  final RoverNarrationLength narrationLength;
  final RoverStoryFreshness freshness;
  final DateTime? expiresAtUtc;
  final double confidence;
  final double baseScore;

  factory RoverCuratorStoryCandidate.fromPlace(
    LocationPlaceSummary place, {
    List<String> routeStopIds = const [],
  }) {
    final evidenceIds = place.facts
        .where(
          (fact) =>
              fact.isSuitableForNarration && fact.factId.trim().isNotEmpty,
        )
        .map((fact) => fact.factId)
        .toSet()
        .toList(growable: false);
    final accessibility = place.accessibilityInformation?.trim();
    return RoverCuratorStoryCandidate(
      storyId: place.canonicalId,
      verifiedEvidenceIds: evidenceIds,
      interests: place.categories,
      routeStopIds: routeStopIds,
      accessibilityTags: accessibility == null || accessibility.isEmpty
          ? const []
          : [accessibility],
      confidence: place.confidenceScore,
      baseScore: place.storyWorthinessScore,
    );
  }
}

class RoverCuratorPreferences {
  const RoverCuratorPreferences({
    this.interests = const [],
    this.exclusions = const [],
    this.availableMinutes,
    this.mobilityPreference,
    this.preferredNarrationLength = RoverNarrationLength.standard,
  });

  final List<String> interests;
  final List<String> exclusions;
  final int? availableMinutes;
  final String? mobilityPreference;
  final RoverNarrationLength preferredNarrationLength;

  factory RoverCuratorPreferences.fromPreferences(
    RoverPreferences preferences, {
    int? availableMinutes,
    List<String> exclusions = const [],
  }) {
    final depth = preferences.contentDepth.toLowerCase();
    final narrationLength = depth.contains('short') || depth.contains('quick')
        ? RoverNarrationLength.short
        : depth.contains('detail') || depth.contains('deep')
        ? RoverNarrationLength.detailed
        : RoverNarrationLength.standard;
    final mobility = preferences.mobility.trim();
    return RoverCuratorPreferences(
      interests: preferences.interests,
      exclusions: exclusions,
      availableMinutes: availableMinutes,
      mobilityPreference: mobility.isEmpty ? null : mobility,
      preferredNarrationLength: narrationLength,
    );
  }
}

class RoverRankedStoryCandidate {
  const RoverRankedStoryCandidate({
    required this.candidate,
    required this.score,
    required this.reasons,
  });

  final RoverCuratorStoryCandidate candidate;
  final double score;
  final List<String> reasons;
}

class RoverCuratorDecision {
  const RoverCuratorDecision({
    required this.rankedCandidates,
    required this.excludedCandidateCount,
    required this.diagnosticCode,
    this.selected,
    this.suppressionReason,
  });

  final List<RoverRankedStoryCandidate> rankedCandidates;
  final RoverRankedStoryCandidate? selected;
  final int excludedCandidateCount;
  final String diagnosticCode;
  final String? suppressionReason;

  bool get isSuppressed => selected == null && suppressionReason != null;

  String get diagnosticSummary =>
      'code=$diagnosticCode; eligible=${rankedCandidates.length}; '
      'excluded=$excludedCandidateCount; '
      'selected=${selected == null ? 'no' : 'yes'}; '
      'topScore=${selected?.score.toStringAsFixed(1) ?? '-'}';
}

class RoverCuratorService {
  const RoverCuratorService();

  RoverCuratorDecision rank({
    required RoverSituationSnapshot situation,
    required List<RoverCuratorStoryCandidate> candidates,
    required RoverCuratorPreferences preferences,
    Set<String> previouslyNarratedContentIds = const {},
    DateTime? nowUtc,
  }) {
    final now = nowUtc ?? DateTime.now().toUtc();
    final ranked = <RoverRankedStoryCandidate>[];
    var excluded = 0;

    for (final candidate in candidates) {
      final normalizedEvidence = candidate.verifiedEvidenceIds
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      if (candidate.storyId.trim().isEmpty || normalizedEvidence.isEmpty) {
        excluded++;
        continue;
      }
      if (previouslyNarratedContentIds.contains(candidate.storyId) ||
          normalizedEvidence.any(previouslyNarratedContentIds.contains)) {
        excluded++;
        continue;
      }
      if (_isStale(candidate, now) ||
          _matchesAny(candidate.exclusionTags, preferences.exclusions)) {
        excluded++;
        continue;
      }
      if (candidate.allowedTravelModes.isNotEmpty &&
          !candidate.allowedTravelModes.contains(situation.travelMode)) {
        excluded++;
        continue;
      }
      final availableMinutes = preferences.availableMinutes;
      if (availableMinutes != null &&
          candidate.estimatedMinutes > availableMinutes) {
        excluded++;
        continue;
      }

      final reasons = <String>['verified evidence'];
      var score = candidate.baseScore.clamp(0, 100).toDouble();
      score += candidate.confidence.clamp(0, 1) * 20;
      if (_matchesAny(candidate.interests, preferences.interests)) {
        score += 25;
        reasons.add('interest match');
      }
      if (candidate.routeStopIds.contains(situation.currentStopId)) {
        score += 30;
        reasons.add('current route relevance');
      } else if (candidate.routeStopIds.isNotEmpty) {
        score += 12;
        reasons.add('route relevance');
      }
      if (situation.nearbyVerifiedPoiIds.contains(candidate.storyId)) {
        score += 20;
        reasons.add('nearby verified place');
      }
      if (candidate.narrationLength == preferences.preferredNarrationLength) {
        score += 8;
        reasons.add('preferred length');
      }
      final mobility = preferences.mobilityPreference;
      if (mobility != null &&
          candidate.accessibilityTags.any(
            (tag) => tag.toLowerCase().contains(mobility.toLowerCase()),
          )) {
        score += 8;
        reasons.add('accessibility match');
      }
      ranked.add(
        RoverRankedStoryCandidate(
          candidate: candidate,
          score: score,
          reasons: List.unmodifiable(reasons),
        ),
      );
    }

    ranked.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      return scoreOrder != 0
          ? scoreOrder
          : left.candidate.storyId.compareTo(right.candidate.storyId);
    });

    if (situation.routeState == RoverRouteState.inactive) {
      return _decision(
        ranked,
        excluded,
        code: 'journey_inactive',
        suppression: 'Optional stories wait for an active journey.',
      );
    }
    if (situation.hasNavigationUrgency ||
        situation.attentionOpportunity == RoverAttentionOpportunity.blocked) {
      return _decision(
        ranked,
        excluded,
        code: 'navigation_urgent',
        suppression: 'Navigation or arrival needs attention.',
      );
    }
    if (ranked.isEmpty) {
      return _decision(
        ranked,
        excluded,
        code: 'no_eligible_verified_story',
        suppression: 'No eligible verified story is available.',
      );
    }
    return RoverCuratorDecision(
      rankedCandidates: List.unmodifiable(ranked),
      selected: ranked.first,
      excludedCandidateCount: excluded,
      diagnosticCode: 'selected_deterministically',
    );
  }

  bool _isStale(RoverCuratorStoryCandidate candidate, DateTime now) {
    final expiry = candidate.expiresAtUtc;
    if (expiry != null && !expiry.isAfter(now)) {
      return true;
    }
    return candidate.freshness == RoverStoryFreshness.timeSensitive &&
        expiry == null;
  }

  bool _matchesAny(List<String> values, List<String> desired) {
    final normalizedDesired = desired
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedDesired.isEmpty) {
      return false;
    }
    return values
        .map((value) => value.trim().toLowerCase())
        .any(normalizedDesired.contains);
  }

  RoverCuratorDecision _decision(
    List<RoverRankedStoryCandidate> ranked,
    int excluded, {
    required String code,
    required String suppression,
  }) {
    return RoverCuratorDecision(
      rankedCandidates: List.unmodifiable(ranked),
      excludedCandidateCount: excluded,
      diagnosticCode: code,
      suppressionReason: suppression,
    );
  }
}

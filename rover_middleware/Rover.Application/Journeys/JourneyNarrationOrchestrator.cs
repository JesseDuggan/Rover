using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public enum JourneyNarrationKind
{
    QuietWalk,
    NearbyLandmark,
    LocalHistory,
    FunFact,
    ApproachingStop,
    ArrivalStory,
    WeatherOrTimeContext
}

public enum JourneyAudioPriority
{
    ContextualStory = 30,
    FunFact = 35,
    UserRequested = 50,
    ApproachingStop = 65,
    Arrival = 80,
    Navigation = 90,
    Safety = 100
}

public sealed record JourneyNarrationQuery(
    GeoLocation CurrentLocation,
    double? GpsAccuracyMeters,
    double? HeadingDegrees,
    double? SpeedMetersPerSecond,
    IReadOnlyCollection<string> AlreadyNarratedFactIds,
    DateTimeOffset RequestedAtUtc)
{
    public string? RouteId { get; init; }
    public int? SecondsUntilNextManeuver { get; init; }
    public int? StoryDurationSeconds { get; init; }
    public string StoryDensity { get; init; } = "highlights";
    public IReadOnlyCollection<string> PreferredStoryCategories { get; init; } = Array.Empty<string>();
    public IReadOnlyCollection<string> ExcludedStoryCategories { get; init; } = Array.Empty<string>();
    public string RouteState { get; init; } = "onRoute";
    public bool UserAttentionAvailable { get; init; } = true;
    public bool RecentDirectInteraction { get; init; }
    public bool ConnectivityAvailable { get; init; } = true;
    public bool AudioAlreadyQueued { get; init; }
    public bool BatterySaverEnabled { get; init; }
    public string? ThermalState { get; init; }
    public string? InterruptedStoryId { get; init; }
    public string? InterruptedStoryRouteId { get; init; }
    public DateTimeOffset? InterruptedStoryExpiresUtc { get; init; }
    public bool InterruptedStoryStillRelevant { get; init; }
    public IReadOnlyDictionary<string, int> LearnedCategoryScores { get; init; } = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
}

public sealed record JourneyNarrationDecision(
    bool ShouldNarrate,
    JourneyNarrationKind Kind,
    JourneyAudioPriority Priority,
    string? NarrationText,
    string? PlaceId,
    IReadOnlyList<string> FactIdsUsed,
    IReadOnlyList<LocationSource> SourceReferences,
    int CooldownSeconds,
    IReadOnlyList<string> Warnings)
{
    public bool SchedulerApplied { get; init; }
    public NarrativeScheduleAction ScheduleAction { get; init; } = NarrativeScheduleAction.Narrate;
    public string? ScheduleReason { get; init; }
    public string? StoryId { get; init; }
    public DateTimeOffset? StoryExpiresUtc { get; init; }
    public int? EstimatedDurationSeconds { get; init; }
    public double? RankingScore { get; init; }
    public IReadOnlyList<string> RankingReasons { get; init; } = Array.Empty<string>();
    public bool AudioCacheEligible { get; init; }
    public string RetentionClass { get; init; } = "restricted";
}

public interface IJourneyNarrationOrchestrator
{
    Task<JourneyNarrationDecision> EvaluateAsync(WalkSession session, JourneyNarrationQuery query, CancellationToken cancellationToken);
}

public sealed class JourneyNarrationOrchestrator : IJourneyNarrationOrchestrator
{
    private const int ContextRadiusMeters = 650;
    private const int MinimumCooldownSeconds = 90;
    private const int ArrivalNarrationReservationMeters = 75;

    private readonly ILocationStoryContextService _locationContext;
    private readonly Phase15Options _options;
    private readonly INarrativeScheduler _scheduler;

    public JourneyNarrationOrchestrator(
        ILocationStoryContextService locationContext,
        Phase15Options? options = null,
        INarrativeScheduler? scheduler = null)
    {
        _locationContext = locationContext;
        _options = options ?? new Phase15Options();
        _scheduler = scheduler ?? new DeterministicNarrativeScheduler(_options);
    }

    public async Task<JourneyNarrationDecision> EvaluateAsync(WalkSession session, JourneyNarrationQuery query, CancellationToken cancellationToken)
    {
        if (session.Status != WalkSessionStatus.InProgress)
        {
            return Quiet("Walk is not actively navigating.");
        }

        var nextStop = session.NextStop;
        if (nextStop is null)
        {
            return Quiet("There is no next stop.");
        }

        if (query.GpsAccuracyMeters is > 100)
        {
            return Quiet("GPS accuracy is too low for confident narration.");
        }

        var distanceToNext = RouteMath.DistanceMeters(query.CurrentLocation, nextStop.Location);
        if (distanceToNext <= nextStop.ArrivalRadiusMeters + ArrivalNarrationReservationMeters)
        {
            return Quiet("The upcoming stop's story is reserved for confirmed geofence entry.");
        }

        if (SchedulerEnabled)
        {
            var readiness = _scheduler.Evaluate(query);
            if (readiness.Action != NarrativeScheduleAction.Narrate)
            {
                return ScheduledControl(readiness);
            }
        }

        var context = await _locationContext.GetContextAsync(
            new LocationContextQuery(
                query.CurrentLocation,
                ContextRadiusMeters,
                session.WalkSessionId,
                null,
                session.Route.Coordinates,
                session.Interests),
            cancellationToken);

        var narrated = query.AlreadyNarratedFactIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var place = context.RankedPlaces
            .Where(place => place.DistanceFromUserMeters is null or <= ContextRadiusMeters)
            .Where(place => !IsReservedArrivalPlace(place, nextStop))
            .Select(place => new
            {
                Place = place,
                Fact = place.Facts
                    .Where(fact => fact.IsSuitableForNarration
                        && fact.ConfidenceScore >= 0.65
                        && !narrated.Contains(fact.FactId)
                        && !MatchesStoryCategory(fact.FactType, place.Categories, query.ExcludedStoryCategories))
                    .OrderByDescending(fact => ScoreCandidate(place, fact, query).Score)
                    .ThenBy(fact => fact.FactId, StringComparer.OrdinalIgnoreCase)
                    .FirstOrDefault()
            })
            .Where(candidate => candidate.Fact is not null)
            .Select(candidate => new RankedStoryCandidate(
                candidate.Place,
                candidate.Fact!,
                ScoreCandidate(candidate.Place, candidate.Fact!, query)))
            .OrderByDescending(candidate => candidate.Ranking.Score)
            .ThenBy(candidate => candidate.Place.CanonicalId, StringComparer.OrdinalIgnoreCase)
            .ThenBy(candidate => candidate.Fact.FactId, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        if (place is not null)
        {
            var fact = place.Fact;
            var name = place.Place.Name.Trim();
            var lead = place.Place.DistanceFromUserMeters is { } meters
                ? $"{name} is {Math.Max(1, (int)Math.Round(meters))} meters away"
                : $"{name} is nearby";
            var synthesized = await _locationContext.CreateStoryAsync(
                new LocationStoryRequest(
                    query.CurrentLocation,
                    ContextRadiusMeters,
                    session.WalkSessionId,
                    null,
                    session.Route.Coordinates,
                    session.Interests,
                    new[] { place.Place.CanonicalId },
                    "short-spoken"),
                cancellationToken);
            var narrationText = !string.IsNullOrWhiteSpace(synthesized.ShortSpokenNarration)
                ? synthesized.ShortSpokenNarration
                : $"{lead}. {fact.FactText}";
            var factIds = synthesized.FactIdsUsed.Count > 0
                ? synthesized.FactIdsUsed
                : new[] { fact.FactId };
            var sources = synthesized.SourceReferences.Count > 0
                ? synthesized.SourceReferences
                : new[] { fact.Source };
            var warnings = context.SourceWarnings.Concat(synthesized.Warnings).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            var estimatedDuration = EstimateDurationSeconds(narrationText);
            var storyId = synthesized.StoryPack?.StoryId
                ?? $"journey:{synthesized.PlaceId ?? place.Place.CanonicalId}:{factIds.FirstOrDefault() ?? "context"}";
            var storyExpiresUtc = synthesized.StoryPack?.ExpiresUtc
                ?? sources.Where(source => source.ExpiresUtc.HasValue).Select(source => source.ExpiresUtc).Min();
            var decision = new JourneyNarrationDecision(
                true,
                ResolveKind(fact),
                ResolvePriority(fact),
                narrationText,
                synthesized.PlaceId ?? place.Place.CanonicalId,
                factIds,
                sources,
                MinimumCooldownSeconds,
                warnings)
            {
                StoryId = storyId,
                StoryExpiresUtc = storyExpiresUtc,
                EstimatedDurationSeconds = estimatedDuration,
                RankingScore = place.Ranking.Score,
                RankingReasons = place.Ranking.Reasons,
                AudioCacheEligible = synthesized.StoryPack?.CacheEligibility?.AudioCacheEligible == true,
                RetentionClass = synthesized.StoryPack?.CacheEligibility?.RetentionClass ?? "restricted"
            };
            return ApplyScheduler(decision, query with { StoryDurationSeconds = estimatedDuration }, fact.ConfidenceScore);
        }

        if (!MatchesStoryCategory("weather", Array.Empty<string>(), query.ExcludedStoryCategories)
            && context.WeatherTimeContext?.Summary is { Length: > 0 } weather)
        {
            var estimatedDuration = EstimateDurationSeconds(weather);
            var decision = new JourneyNarrationDecision(
                true,
                JourneyNarrationKind.WeatherOrTimeContext,
                JourneyAudioPriority.ContextualStory,
                weather,
                null,
                Array.Empty<string>(),
                context.WeatherTimeContext.Source is null ? Array.Empty<LocationSource>() : new[] { context.WeatherTimeContext.Source },
                MinimumCooldownSeconds,
                context.SourceWarnings)
            {
                StoryId = $"weather:{session.WalkSessionId}:{context.WeatherTimeContext.ObservedUtc?.UtcTicks ?? query.RequestedAtUtc.UtcTicks}",
                StoryExpiresUtc = context.WeatherTimeContext.Source?.ExpiresUtc,
                EstimatedDurationSeconds = estimatedDuration
            };
            return ApplyScheduler(decision, query with { StoryDurationSeconds = estimatedDuration });
        }

        return Quiet("No unused verified local facts were available close enough to this part of the route.");
    }

    private static JourneyNarrationDecision Quiet(string warning)
    {
        return new JourneyNarrationDecision(
            false,
            JourneyNarrationKind.QuietWalk,
            JourneyAudioPriority.ContextualStory,
            null,
            null,
            Array.Empty<string>(),
            Array.Empty<LocationSource>(),
            MinimumCooldownSeconds,
            new[] { warning })
        {
            ScheduleAction = NarrativeScheduleAction.Silence,
            ScheduleReason = warning
        };
    }

    private JourneyNarrationDecision ApplyScheduler(JourneyNarrationDecision decision, JourneyNarrationQuery query, double? evidenceStrength = null)
    {
        if (!SchedulerEnabled) return decision;
        var result = _scheduler.Evaluate(query, evidenceStrength);
        return result.Action == NarrativeScheduleAction.Narrate
            ? decision with { SchedulerApplied = true, ScheduleAction = result.Action, ScheduleReason = result.Reason }
            : ScheduledControl(result);
    }

    private static JourneyNarrationDecision ScheduledControl(NarrativeScheduleResult result) =>
        Quiet(result.Reason) with
        {
            SchedulerApplied = true,
            ScheduleAction = result.Action,
            ScheduleReason = result.Reason
        };

    private bool SchedulerEnabled => _options.Enabled && _options.NarrativeSchedulerEnabled;

    private static int EstimateDurationSeconds(string text)
    {
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        return Math.Max(5, (int)Math.Ceiling(words / 2.5));
    }

    private static JourneyNarrationKind ResolveKind(LocationFact fact)
    {
        if (fact.FactType.Contains("history", StringComparison.OrdinalIgnoreCase)
            || fact.FactType.Contains("heritage", StringComparison.OrdinalIgnoreCase))
        {
            return JourneyNarrationKind.LocalHistory;
        }

        if (fact.FactType.Contains("fun", StringComparison.OrdinalIgnoreCase))
        {
            return JourneyNarrationKind.FunFact;
        }

        return JourneyNarrationKind.NearbyLandmark;
    }

    private static JourneyAudioPriority ResolvePriority(LocationFact fact)
    {
        return fact.ConfidenceScore >= 0.8
            ? JourneyAudioPriority.ContextualStory
            : JourneyAudioPriority.FunFact;
    }

    private static bool MatchesStoryCategory(
        string factType,
        IReadOnlyList<string> placeCategories,
        IReadOnlyCollection<string> categories)
    {
        var searchable = $"{factType} {string.Join(' ', placeCategories)}".ToLowerInvariant();
        return categories
            .Select(category => category.Trim().ToLowerInvariant())
            .Where(category => category.Length > 0)
            .Any(category => searchable.Contains(category, StringComparison.Ordinal));
    }

    private static StoryCandidateRanking ScoreCandidate(LocationPlace place, LocationFact fact, JourneyNarrationQuery query)
    {
        var category = NormalizeCategory(fact.FactType, place.Categories);
        var score = fact.ConfidenceScore * 100;
        var reasons = new List<string> { $"evidence {fact.ConfidenceScore:0.00}" };

        if (place.DistanceFromUserMeters is { } distance)
        {
            var proximity = Math.Max(0, 20 - Math.Min(20, distance / 32.5));
            score += proximity;
            reasons.Add($"proximity +{proximity:0.0}");
        }
        if (MatchesStoryCategory(fact.FactType, place.Categories, query.PreferredStoryCategories))
        {
            score += 20;
            reasons.Add("explicit preference +20");
        }
        if (query.LearnedCategoryScores.TryGetValue(category, out var learned))
        {
            var adjustment = Math.Clamp(learned, -10, 10) * 3;
            score += adjustment;
            reasons.Add($"interaction affinity {adjustment:+#;-#;0}");
        }
        var storyWorthiness = Math.Clamp(place.StoryWorthinessScore, 0, 100) / 10;
        score += storyWorthiness;
        reasons.Add($"story worthiness +{storyWorthiness:0.0}");
        return new StoryCandidateRanking(Math.Round(score, 2), reasons);
    }

    private static bool IsReservedArrivalPlace(LocationPlace place, WalkStop nextStop)
    {
        var stopIdentity = NormalizePlaceIdentity(nextStop.StopId);
        var placeIdentities = place.ProviderIds.Values
            .Append(place.CanonicalId)
            .Select(NormalizePlaceIdentity)
            .Where(value => value.Length > 0);
        if (stopIdentity.Length > 0 && placeIdentities.Contains(stopIdentity, StringComparer.OrdinalIgnoreCase))
        {
            return true;
        }

        return NormalizePlaceName(place.Name) == NormalizePlaceName(nextStop.Name)
            && RouteMath.DistanceMeters(place.Coordinates, nextStop.Location) <= 100;
    }

    private static string NormalizePlaceIdentity(string value)
    {
        var normalized = new string(value
            .Trim()
            .ToLowerInvariant()
            .Where(char.IsLetterOrDigit)
            .ToArray());
        var googlePlaceId = normalized.IndexOf("chij", StringComparison.Ordinal);
        return googlePlaceId >= 0 ? normalized[googlePlaceId..] : normalized;
    }

    private static string NormalizePlaceName(string value) =>
        new(value.Trim().ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

    private static string NormalizeCategory(string factType, IReadOnlyCollection<string> placeCategories)
    {
        var value = factType.Trim().ToLowerInvariant();
        if (value.Contains("histor", StringComparison.Ordinal)) return "history";
        if (value.Contains("weather", StringComparison.Ordinal)) return "weather";
        if (value.Contains("event", StringComparison.Ordinal)) return "events";
        return placeCategories.FirstOrDefault(category => !string.IsNullOrWhiteSpace(category))?.Trim().ToLowerInvariant()
            ?? value;
    }

    private sealed record StoryCandidateRanking(double Score, IReadOnlyList<string> Reasons);
    private sealed record RankedStoryCandidate(LocationPlace Place, LocationFact Fact, StoryCandidateRanking Ranking);
}

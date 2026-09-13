using Microsoft.Extensions.Logging;
using Rover.Application.Walks;
using Rover.Application.Journeys;
using Rover.Domain.Walks;

namespace Rover.Application.LocationIntelligence;

public sealed class LocationStoryContextService : ILocationStoryContextService
{
    private readonly IReadOnlyList<ILocationContextProvider> _providers;
    private readonly ILocationContextCache _cache;
    private readonly ILocationPlaceResolver _resolver;
    private readonly ILocationStoryRankingService _ranking;
    private readonly ILocationStorySynthesizer _synthesizer;
    private readonly SafeFallbackLocationStorySynthesizer _safeFallback;
    private readonly IStoryPackFactory _storyPackFactory;
    private readonly IStoryGroundingValidator _groundingValidator;
    private readonly IStoryPackRepository _storyPackRepository;
    private readonly IEvidenceRepository _evidenceRepository;
    private readonly LocationIntelligenceOptions _options;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<LocationStoryContextService> _logger;
    private readonly IJourneyNarrativeArcService? _narrativeArcs;
    private readonly IWalkSessionRepository? _walkSessions;

    public LocationStoryContextService(
        IEnumerable<ILocationContextProvider> providers,
        ILocationContextCache cache,
        ILocationPlaceResolver resolver,
        ILocationStoryRankingService ranking,
        ILocationStorySynthesizer synthesizer,
        SafeFallbackLocationStorySynthesizer safeFallback,
        IStoryPackFactory storyPackFactory,
        IStoryGroundingValidator groundingValidator,
        IStoryPackRepository storyPackRepository,
        IEvidenceRepository evidenceRepository,
        LocationIntelligenceOptions options,
        TimeProvider timeProvider,
        ILogger<LocationStoryContextService> logger,
        IJourneyNarrativeArcService? narrativeArcs = null,
        IWalkSessionRepository? walkSessions = null)
    {
        _providers = providers.ToArray();
        _cache = cache;
        _resolver = resolver;
        _ranking = ranking;
        _synthesizer = synthesizer;
        _safeFallback = safeFallback;
        _storyPackFactory = storyPackFactory;
        _groundingValidator = groundingValidator;
        _storyPackRepository = storyPackRepository;
        _evidenceRepository = evidenceRepository;
        _options = options;
        _timeProvider = timeProvider;
        _logger = logger;
        _narrativeArcs = narrativeArcs;
        _walkSessions = walkSessions;
    }

    public async Task<LocationStoryContext> GetContextAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        ValidateQuery(query, _options);
        var cacheKey = CacheKey(query);
        var providers = _providers.Where(provider => query.IncludeGooglePlaces
            || !provider.Name.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase)).ToArray();
        var aggregateCachingAllowed = providers
            .OfType<ILocationContextCachePolicy>()
            .All(provider => provider.AllowsAggregateCaching);
        if (aggregateCachingAllowed && _cache.TryGet<LocationStoryContext>(cacheKey, out var cached) && cached is not null)
        {
            return cached with { CacheStatus = new LocationCacheStatus(cacheKey, true, null) };
        }

        var now = _timeProvider.GetUtcNow();
        var places = new List<LocationPlace>();
        var warnings = new List<string>();
        var statuses = new List<LocationProviderStatus>();
        WeatherTimeContext? weather = null;

        var providerResults = await Task.WhenAll(providers.Select(provider =>
            FetchProviderAsync(provider, query, cancellationToken)));
        foreach (var fetch in providerResults)
        {
            if (fetch.Result is { } result)
            {
                places.AddRange(result.Places);
                weather ??= result.WeatherTimeContext;
                warnings.AddRange(result.Warnings);
                statuses.Add(new LocationProviderStatus(result.ProviderName, result.Enabled, true, result.CacheHit, result.Places.Count, result.LatencyMilliseconds, result.Warnings.FirstOrDefault()));
            }
            else if (fetch.Error is { } exception)
            {
                _logger.LogWarning(exception, "Location context provider {Provider} failed", fetch.ProviderName);
                warnings.Add($"{fetch.ProviderName} failed: {exception.Message}");
                statuses.Add(new LocationProviderStatus(fetch.ProviderName, true, false, false, 0, 0, exception.Message));
            }
        }

        var resolved = _resolver.Resolve(places, query, now);
        var ranked = _ranking.Rank(resolved, query, now)
            .Take(Math.Max(1, _options.MaximumReturnedPlaces))
            .ToArray();
        var context = new LocationStoryContext(
            query.UserLocation,
            query.RadiusMeters,
            query.RouteId,
            query.ProfileId,
            now,
            ranked,
            weather,
            warnings.Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
            statuses,
            new LocationCacheStatus(
                cacheKey,
                false,
                aggregateCachingAllowed ? now.AddMinutes(_options.PoiCacheMinutes) : null))
        {
            RouteSegmentId = query.RouteSegmentId,
            DirectionalContext = query.DirectionalContext
        };

        if (aggregateCachingAllowed)
        {
            _cache.Set(cacheKey, context, TimeSpan.FromMinutes(Math.Max(1, _options.PoiCacheMinutes)));
        }
        return context;
    }

    private static async Task<ProviderFetch> FetchProviderAsync(
        ILocationContextProvider provider,
        LocationContextQuery query,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            return new ProviderFetch(
                provider.Name,
                await provider.GetContextAsync(query, cancellationToken),
                null);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new ProviderFetch(provider.Name, null, exception);
        }
    }

    public async Task<LocationStoryResult> CreateStoryAsync(LocationStoryRequest request, CancellationToken cancellationToken)
    {
        var context = await GetContextAsync(
            new LocationContextQuery(
                request.UserCoordinates,
                request.RadiusMeters,
                request.RouteId,
                request.ProfileId,
                request.RouteGeometry,
                request.Interests)
            {
                RouteSegmentId = request.RouteSegmentId,
                DirectionalContext = request.DirectionalContext
            },
            cancellationToken);

        var selectedPlace = SelectPlace(context, request.SelectedPlaceIds);
        var storageKey = selectedPlace is null
            ? null
            : StoryPackStorageKey.Create(
                selectedPlace.CanonicalId,
                request.ProfileId,
                request.NarrationStyle,
                request.Interests,
                _storyPackFactory.SchemaVersion);
        var selectedPlaceId = selectedPlace?.CanonicalId;
        if (storageKey is not null)
        {
            var lookupKeys = string.Equals(_storyPackFactory.SchemaVersion, "1.1", StringComparison.Ordinal)
                ? new[] { storageKey }
                : new[]
                {
                    storageKey,
                    StoryPackStorageKey.Create(
                        selectedPlace!.CanonicalId,
                        request.ProfileId,
                        request.NarrationStyle,
                        request.Interests,
                        "1.1")
                };
            foreach (var lookupKey in lookupKeys.DistinctBy(key => key.Value, StringComparer.Ordinal))
            {
                try
                {
                    var cached = await _storyPackRepository.GetAsync(lookupKey, cancellationToken);
                    if (cached is not null)
                    {
                        await CollectForNarrativeArcAsync(request.RouteId, cached.StoryPack, cancellationToken);
                        return cached with
                        {
                            Warnings = cached.Warnings
                                .Append("Story Pack loaded from persistent storage.")
                                .Distinct(StringComparer.OrdinalIgnoreCase)
                                .ToArray()
                        };
                    }
                }
                catch (Exception exception) when (exception is not OperationCanceledException)
                {
                    _logger.LogWarning(exception, "Persistent Story Pack lookup failed for {PlaceId}", selectedPlaceId);
                }
            }
        }

        var story = await _synthesizer.CreateStoryAsync(context, request.SelectedPlaceIds, request.NarrationStyle, cancellationToken);
        var grounded = GroundStory(context, story, request.NarrationStyle, request.Interests);
        if (grounded.StoryPack?.Validation?.IsValid == true)
        {
            await PersistAsync(storageKey, grounded, cancellationToken);
            await CollectForNarrativeArcAsync(request.RouteId, grounded.StoryPack, cancellationToken);
            return grounded;
        }

        _logger.LogWarning(
            "Location story grounding rejected synthesized narration for place {PlaceId}; deterministic fallback will be used",
            story.PlaceId);
        var fallback = await _safeFallback.CreateStoryAsync(context, request.SelectedPlaceIds, request.NarrationStyle, cancellationToken);
        var groundedFallback = GroundStory(
            context,
            fallback with
            {
                Warnings = fallback.Warnings
                    .Append("Generated narration failed grounding validation; deterministic fallback used.")
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToArray()
            },
            request.NarrationStyle,
            request.Interests);
        await PersistAsync(storageKey, groundedFallback, cancellationToken);
        await CollectForNarrativeArcAsync(request.RouteId, groundedFallback.StoryPack, cancellationToken);
        return groundedFallback;
    }

    private async Task CollectForNarrativeArcAsync(string? walkSessionId, StoryPack? storyPack, CancellationToken cancellationToken)
    {
        if (_narrativeArcs is null || _walkSessions is null || storyPack?.Validation?.IsValid != true || string.IsNullOrWhiteSpace(walkSessionId))
        {
            return;
        }

        var session = await _walkSessions.GetByIdAsync(walkSessionId, cancellationToken);
        if (session is not null)
        {
            await _narrativeArcs.AddStoryPackAsync(session, storyPack, cancellationToken);
        }
    }

    private async Task PersistAsync(
        StoryPackStorageKey? storageKey,
        LocationStoryResult story,
        CancellationToken cancellationToken)
    {
        if (storageKey is null || story.StoryPack?.Validation?.IsValid != true)
        {
            return;
        }

        try
        {
            await _storyPackRepository.StoreAsync(storageKey, story, cancellationToken);
            await _evidenceRepository.StoreAsync(story.StoryPack, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            _logger.LogWarning(exception, "Persistent Story Pack write failed for {PlaceId}", story.PlaceId);
        }
    }

    private static LocationPlace? SelectPlace(
        LocationStoryContext context,
        IReadOnlyCollection<string> selectedPlaceIds)
    {
        var requested = selectedPlaceIds
            .Where(placeId => !string.IsNullOrWhiteSpace(placeId))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return requested.Count > 0
            ? context.RankedPlaces.FirstOrDefault(place => requested.Contains(place.CanonicalId))
            : context.RankedPlaces.FirstOrDefault(place =>
                  place.Facts.Any(fact => fact.IsSuitableForNarration && fact.ConfidenceScore >= 0.6))
              ?? context.RankedPlaces.FirstOrDefault();
    }

    private LocationStoryResult GroundStory(
        LocationStoryContext context,
        LocationStoryResult story,
        string? narrationStyle,
        IReadOnlyCollection<string> interests)
    {
        var now = _timeProvider.GetUtcNow();
        var storyPack = _storyPackFactory.Create(context, story, narrationStyle, interests, now);
        var validation = _groundingValidator.Validate(storyPack, now);
        return story with { StoryPack = storyPack with { Validation = validation } };
    }

    public static void ValidateQuery(LocationContextQuery query, LocationIntelligenceOptions options)
    {
        if (query.UserLocation.Latitude is < -90 or > 90 || query.UserLocation.Longitude is < -180 or > 180)
        {
            throw new ArgumentException("Latitude and longitude must be valid coordinates.");
        }

        if (query.RadiusMeters <= 0 || query.RadiusMeters > Math.Max(1, options.MaxRadiusMeters))
        {
            throw new ArgumentException($"Radius must be between 1 and {options.MaxRadiusMeters} meters.");
        }
    }

    private static string CacheKey(LocationContextQuery query)
    {
        var lat = Math.Round(query.UserLocation.Latitude, 3);
        var lng = Math.Round(query.UserLocation.Longitude, 3);
        var interests = string.Join(",", query.Interests.Order(StringComparer.OrdinalIgnoreCase));
        return $"location-context:{lat:F3}:{lng:F3}:{query.RadiusMeters}:{query.RouteId}:{query.RouteSegmentId}:{query.DirectionalContext}:{query.ProfileId}:{interests}:google={query.IncludeGooglePlaces}";
    }
    private sealed record ProviderFetch(
        string ProviderName,
        LocationContextProviderResult? Result,
        Exception? Error);
}

public sealed class DeterministicLocationPlaceResolver : ILocationPlaceResolver
{
    private static readonly string[] CollisionProneCategories =
    [
        "bar", "business", "cafe", "coffee", "food", "hotel", "lodging", "restaurant", "shop", "store"
    ];

    private readonly LocationIntelligenceOptions _options;

    public DeterministicLocationPlaceResolver(LocationIntelligenceOptions options)
    {
        _options = options;
    }

    public IReadOnlyList<LocationPlace> Resolve(IReadOnlyList<LocationPlace> places, LocationContextQuery query, DateTimeOffset now)
    {
        var merged = new List<LocationPlace>();
        foreach (var place in places.Where(place => !string.IsNullOrWhiteSpace(place.Name)))
        {
            var resolvedPlace = WithDistances(WithStandaloneIdentity(place, now), query, now);
            var index = -1;
            PlaceIdentityMatchMethod matchMethod = PlaceIdentityMatchMethod.Unresolved;
            for (var candidateIndex = 0; candidateIndex < merged.Count; candidateIndex++)
            {
                if (TryClassifyDuplicate(merged[candidateIndex], resolvedPlace, out matchMethod))
                {
                    index = candidateIndex;
                    break;
                }
            }

            if (index < 0)
            {
                merged.Add(resolvedPlace);
                continue;
            }

            merged[index] = Merge(merged[index], resolvedPlace, matchMethod, now);
        }

        return merged;
    }

    private bool TryClassifyDuplicate(LocationPlace left, LocationPlace right, out PlaceIdentityMatchMethod matchMethod)
    {
        if (SharedProviderId(left, right))
        {
            matchMethod = PlaceIdentityMatchMethod.SharedProviderIdentifier;
            return true;
        }

        var distance = RouteMath.DistanceMeters(left.Coordinates, right.Coordinates);
        if (distance > Math.Min(_options.MergeDistanceMeters, 25))
        {
            matchMethod = PlaceIdentityMatchMethod.Unresolved;
            return false;
        }

        var nameScore = NameSimilarity(left.Name, right.Name);
        var categoryMatch = left.Categories.Count > 0
            && right.Categories.Count > 0
            && left.Categories.Any(category => right.Categories.Contains(category, StringComparer.OrdinalIgnoreCase));
        var addressScore = AddressSimilarity(left.Address, right.Address);
        var bothAddressesKnown = !string.IsNullOrWhiteSpace(left.Address) && !string.IsNullOrWhiteSpace(right.Address);
        var collisionProne = left.Categories.Concat(right.Categories)
            .Any(category => CollisionProneCategories.Any(term => category.Contains(term, StringComparison.OrdinalIgnoreCase)));
        var conservativeMatch = nameScore >= 0.92
            && categoryMatch
            && ((bothAddressesKnown && addressScore >= 0.7)
                || (!bothAddressesKnown && !collisionProne && nameScore == 1));
        matchMethod = conservativeMatch
            ? PlaceIdentityMatchMethod.ConservativeNameAndGeography
            : PlaceIdentityMatchMethod.Unresolved;
        return conservativeMatch;
    }

    private static bool SharedProviderId(LocationPlace left, LocationPlace right)
    {
        foreach (var id in left.ProviderIds)
        {
            if (right.ProviderIds.TryGetValue(id.Key, out var value) && string.Equals(id.Value, value, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static LocationPlace Merge(LocationPlace left, LocationPlace right, PlaceIdentityMatchMethod matchMethod, DateTimeOffset now)
    {
        var providers = left.ProviderIds.Concat(right.ProviderIds)
            .GroupBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Value, StringComparer.OrdinalIgnoreCase);
        var facts = left.Facts.Concat(right.Facts)
            .GroupBy(fact => fact.FactId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(fact => fact.ConfidenceScore).First())
            .ToArray();
        var sources = left.SourceReferences.Concat(right.SourceReferences)
            .GroupBy(source => $"{source.ProviderName}:{source.ProviderRecordId}:{source.SourceUrl}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();
        var categories = left.Categories.Concat(right.Categories)
            .Where(category => !string.IsNullOrWhiteSpace(category))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var identityConfidence = matchMethod == PlaceIdentityMatchMethod.SharedProviderIdentifier ? 0.98 : 0.76;
        var candidates = IdentityCandidates(left).Concat(IdentityCandidates(right))
            .GroupBy(candidate => $"{candidate.ProviderName}:{candidate.ProviderRecordId}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(candidate => candidate.Confidence).First())
            .ToArray();

        return left with
        {
            Address = left.Address ?? right.Address,
            City = left.City ?? right.City,
            Region = left.Region ?? right.Region,
            CountryCode = left.CountryCode ?? right.CountryCode,
            Categories = categories,
            ShortDescription = PreferLonger(left.ShortDescription, right.ShortDescription),
            Facts = facts,
            SourceReferences = sources,
            ProviderIds = providers,
            ConfidenceScore = Math.Clamp((left.ConfidenceScore + right.ConfidenceScore) / 2 + 0.08, 0, 1),
            ImageReferences = left.ImageReferences.Concat(right.ImageReferences).ToArray(),
            OpeningStatus = left.OpeningStatus ?? right.OpeningStatus,
            AccessibilityInformation = left.AccessibilityInformation ?? right.AccessibilityInformation,
            LastRefreshedUtc = now,
            IdentityResolution = new PlaceIdentityResolution(
                matchMethod,
                matchMethod == PlaceIdentityMatchMethod.SharedProviderIdentifier
                    ? GroundingVerificationStatus.Verified
                    : GroundingVerificationStatus.Provisional,
                identityConfidence,
                candidates,
                now)
        };
    }

    private static LocationPlace WithStandaloneIdentity(LocationPlace place, DateTimeOffset now)
    {
        if (place.IdentityResolution is not null)
        {
            return place;
        }

        var candidates = IdentityCandidates(place).ToArray();
        return place with
        {
            IdentityResolution = new PlaceIdentityResolution(
                candidates.Length > 0 ? PlaceIdentityMatchMethod.ExplicitProviderIdentifier : PlaceIdentityMatchMethod.Unresolved,
                candidates.Length > 0 ? GroundingVerificationStatus.Provisional : GroundingVerificationStatus.Unavailable,
                candidates.Length > 0 ? Math.Clamp(place.ConfidenceScore, 0, 1) : 0,
                candidates,
                now)
        };
    }

    private static IEnumerable<PlaceIdentityCandidate> IdentityCandidates(LocationPlace place)
    {
        place.ProviderIds.TryGetValue("wikidata", out var wikidataQid);
        foreach (var providerId in place.ProviderIds.Where(pair => !string.IsNullOrWhiteSpace(pair.Value)))
        {
            yield return new PlaceIdentityCandidate(providerId.Key, providerId.Value, wikidataQid, place.ConfidenceScore);
        }
    }

    private static LocationPlace WithDistances(LocationPlace place, LocationContextQuery query, DateTimeOffset now)
    {
        var userDistance = RouteMath.DistanceMeters(query.UserLocation, place.Coordinates);
        var routeDistance = query.RouteGeometry.Count == 0 ? (double?)null : RouteMath.DistanceFromRouteMeters(place.Coordinates, query.RouteGeometry);
        int? detourMinutes = routeDistance is null ? null : Math.Max(1, (int)Math.Ceiling(routeDistance.Value * 2 / 80));

        return place with
        {
            DistanceFromUserMeters = Math.Round(userDistance, 1),
            DistanceFromRouteMeters = routeDistance is null ? null : Math.Round(routeDistance.Value, 1),
            EstimatedDetourMinutes = detourMinutes,
            DirectionFromUser = Direction(query.UserLocation, place.Coordinates),
            LastRefreshedUtc = now
        };
    }

    private static string Direction(GeoLocation from, GeoLocation to)
    {
        var bearing = Bearing(from, to);
        var directions = new[] { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" };
        return directions[(int)Math.Round(bearing / 45) % directions.Length];
    }

    private static double Bearing(GeoLocation from, GeoLocation to)
    {
        var lat1 = from.Latitude * Math.PI / 180;
        var lat2 = to.Latitude * Math.PI / 180;
        var deltaLng = (to.Longitude - from.Longitude) * Math.PI / 180;
        var y = Math.Sin(deltaLng) * Math.Cos(lat2);
        var x = Math.Cos(lat1) * Math.Sin(lat2) - Math.Sin(lat1) * Math.Cos(lat2) * Math.Cos(deltaLng);
        return (Math.Atan2(y, x) * 180 / Math.PI + 360) % 360;
    }

    private static double NameSimilarity(string left, string right)
    {
        var a = Normalize(left);
        var b = Normalize(right);
        if (a == b)
        {
            return 1;
        }

        if (a.Contains(b, StringComparison.OrdinalIgnoreCase) || b.Contains(a, StringComparison.OrdinalIgnoreCase))
        {
            return 0.9;
        }

        var aWords = a.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var bWords = b.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return aWords.Count == 0 || bWords.Count == 0 ? 0 : (double)aWords.Intersect(bWords).Count() / aWords.Union(bWords).Count();
    }

    private static double AddressSimilarity(string? left, string? right)
    {
        if (string.IsNullOrWhiteSpace(left) || string.IsNullOrWhiteSpace(right))
        {
            return 0.5;
        }

        return NameSimilarity(left, right);
    }

    private static string Normalize(string value)
    {
        var chars = value.ToLowerInvariant().Where(character => char.IsLetterOrDigit(character) || char.IsWhiteSpace(character)).ToArray();
        return new string(chars).Replace(" cafe", " coffee", StringComparison.OrdinalIgnoreCase).Trim();
    }

    private static string? PreferLonger(string? left, string? right)
    {
        if (string.IsNullOrWhiteSpace(left))
        {
            return right;
        }

        if (string.IsNullOrWhiteSpace(right))
        {
            return left;
        }

        return right.Length > left.Length ? right : left;
    }
}

public sealed class DeterministicLocationStoryRankingService : ILocationStoryRankingService
{
    private readonly LocationIntelligenceOptions _options;

    public DeterministicLocationStoryRankingService(LocationIntelligenceOptions options)
    {
        _options = options;
    }

    public IReadOnlyList<LocationPlace> Rank(IReadOnlyList<LocationPlace> places, LocationContextQuery query, DateTimeOffset now)
    {
        return places
            .Select(place => Score(place, query))
            .OrderByDescending(place => query.RouteSegmentId is null ? 0 : place.Facts
                .Where(fact => fact.Source.ExpiresUtc is null || fact.Source.ExpiresUtc > now)
                .Select(RouteStoryEvidence.Priority).DefaultIfEmpty(0).Max())
            .ThenByDescending(place => place.StoryWorthinessScore)
            .ThenBy(place => place.DistanceFromUserMeters ?? double.MaxValue)
            .ToArray();
    }

    private LocationPlace Score(LocationPlace place, LocationContextQuery query)
    {
        var score = place.ConfidenceScore * 35;
        var reasons = new List<string>();

        if (place.DistanceFromUserMeters is { } userDistance)
        {
            var distanceScore = Math.Max(0, 25 - userDistance / Math.Max(1, query.RadiusMeters) * 25);
            score += distanceScore;
            reasons.Add($"{Math.Max(1, (int)Math.Round(userDistance / 80))} minutes from you");
        }

        if (place.DistanceFromRouteMeters is { } routeDistance)
        {
            var routeScore = routeDistance <= _options.RouteNearDistanceMeters ? 20 : Math.Max(0, 12 - routeDistance / 50);
            score += routeScore;
            reasons.Add(routeDistance <= _options.RouteNearDistanceMeters ? "Near your current route" : $"{Math.Round(routeDistance)} meters from your route");
        }

        var narratedFacts = place.Facts.Count(fact => fact.IsSuitableForNarration && fact.ConfidenceScore >= 0.65);
        if (narratedFacts > 0)
        {
            score += Math.Min(18, narratedFacts * 6);
            reasons.Add($"{narratedFacts} sourced story fact{(narratedFacts == 1 ? "" : "s")}");
        }

        foreach (var interest in query.Interests.Where(interest => !string.IsNullOrWhiteSpace(interest)))
        {
            if (place.Categories.Any(category => category.Contains(interest, StringComparison.OrdinalIgnoreCase))
                || place.Name.Contains(interest, StringComparison.OrdinalIgnoreCase)
                || (place.ShortDescription?.Contains(interest, StringComparison.OrdinalIgnoreCase) ?? false))
            {
                score += 12;
                reasons.Add($"Matches your interest in {interest}");
                break;
            }
        }

        if (place.ProviderIds.ContainsKey("wikidata") || place.ProviderIds.ContainsKey("wikipedia") || place.Categories.Any(category => category.Contains("historic", StringComparison.OrdinalIgnoreCase)))
        {
            score += 10;
            reasons.Add("Has cultural or historical context");
        }

        if (!string.IsNullOrWhiteSpace(place.OpeningStatus))
        {
            score += 3;
            reasons.Add($"Opening status known: {place.OpeningStatus}");
        }

        if (!string.IsNullOrWhiteSpace(place.AccessibilityInformation))
        {
            score += 3;
            reasons.Add("Has accessibility information");
        }

        reasons.Add("You have not discovered this location before");
        return place with
        {
            StoryWorthinessScore = Math.Round(Math.Clamp(score, 0, 100), 2),
            StoryWorthinessReasons = reasons.Distinct(StringComparer.OrdinalIgnoreCase).Take(5).ToArray()
        };
    }
}

public sealed class SafeFallbackLocationStorySynthesizer : ILocationStorySynthesizer
{
    public Task<LocationStoryResult> CreateStoryAsync(LocationStoryContext context, IReadOnlyCollection<string> selectedPlaceIds, string? narrationStyle, CancellationToken cancellationToken)
    {
        var requestedPlaceIds = selectedPlaceIds
            .Where(placeId => !string.IsNullOrWhiteSpace(placeId))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var selected = requestedPlaceIds.Count > 0
            ? context.RankedPlaces.FirstOrDefault(place => requestedPlaceIds.Contains(place.CanonicalId))
            : context.RankedPlaces.FirstOrDefault(place => place.Facts.Any(fact => fact.IsSuitableForNarration && fact.ConfidenceScore >= 0.6))
                ?? context.RankedPlaces.FirstOrDefault();

        if (selected is null)
        {
            return Task.FromResult(new LocationStoryResult(
                "Nearby context",
                "For this stretch, Rover has your live route and map context, but no sourced place detail close enough to narrate yet.",
                null,
                null,
                Array.Empty<string>(),
                Array.Empty<LocationSource>(),
                0.2,
                Array.Empty<string>(),
                new[] { "No verified location facts were available." }));
        }

        var fact = selected.Facts
            .Where(fact => fact.IsSuitableForNarration)
            .OrderByDescending(fact => fact.ConfidenceScore)
            .FirstOrDefault();
        var narration = fact is null
            ? $"{selected.Name} is {DistancePhrase(selected)} to the {selected.DirectionFromUser ?? "nearby"}. Rover has basic map context for this place, but no verified story facts yet."
            : $"{selected.Name} is {DistancePhrase(selected)} to the {selected.DirectionFromUser ?? "nearby"}. {fact.FactText}";
        var sources = fact is null ? selected.SourceReferences : new[] { fact.Source };

        return Task.FromResult(new LocationStoryResult(
            selected.Name,
            narration,
            selected.ShortDescription,
            selected.CanonicalId,
            fact is null ? Array.Empty<string>() : new[] { fact.FactId },
            sources,
            fact?.ConfidenceScore ?? selected.ConfidenceScore,
            sources.Select(source => source.Attribution).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
            fact is null ? new[] { "No high-confidence narrative fact was available for this place." } : Array.Empty<string>()));
    }

    private static string DistancePhrase(LocationPlace place)
    {
        if (place.DistanceFromUserMeters is not { } meters)
        {
            return "nearby";
        }

        return meters < 1000 ? $"{Math.Round(meters)} meters away" : $"{Math.Round(meters / 1000, 1)} kilometers away";
    }

}

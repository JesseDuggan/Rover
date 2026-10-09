using System.Diagnostics;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Infrastructure.Journeys;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class OntarioFieldTestProvider(OntarioFieldTestOptions options, OntarioMunicipalHeritageClient municipal,
    IHttpClientFactory clients, ILocationContextCache cache, TimeProvider clock, IOntarioFieldTestRecorder recorder)
    : ILocationContextProvider, ILocationContextCachePolicy
{
    private static readonly SemaphoreSlim[] CompanionGates = Enumerable.Range(0, 32).Select(_ => new SemaphoreSlim(1)).ToArray();
    public string Name => "OntarioFieldTesting";
    // Always reevaluate enrollment before using municipal caches, including after a flag change.
    public bool AllowsAggregateCaching => !options.Enabled;

    public async Task<LocationContextProviderResult> GetContextAsync(LocationContextQuery query, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var match = options.Match(query.ProfileId, query.UserLocation);
        if (match is not { } pilot) return new(Name, false, [], null, [], false, 0);
        var interests = query.Interests.ToArray();
        if (!new[] { "history", "architecture", "culture", "people", "hidden_gem", "fun_fact" }
            .Any(category => StoryInterestPolicy.Allows(category, interests)))
            return new(Name, true, [], null, [], false, 0);
        var watch = Stopwatch.StartNew();
        var bounded = query with { RadiusMeters = Math.Min(query.RadiusMeters, pilot.Value.SearchRadiusMeters) };
        var results = new List<LocationContextProviderResult>();
        if (StoryInterestPolicy.Allows("history", interests) || StoryInterestPolicy.Allows("architecture", interests))
            foreach (var dataset in pilot.Value.Datasets.Take(4))
                results.Add(await municipal.FindAsync(pilot.Key, pilot.Value, dataset, bounded, token));
        if (pilot.Value.IncludeExistingHeritageSources)
        {
            var settings = new LocationProviderOptions { Enabled = true, MaximumResults = 20, CacheMinutes = 1440, TimeoutSeconds = 6 };
            ILocationContextProvider[] companions = [new WikipediaLocationContextProvider(clients, cache, clock, settings),
                new WikidataLocationContextProvider(clients, cache, clock, settings),
                new ParksCanadaHeritageLocationContextProvider(clients, cache, clock, settings, pilot.Value.SearchRadiusMeters)];
            foreach (var provider in companions)
                results.Add(await CompanionAsync(pilot.Key, provider, bounded, token));
        }
        var raw = results.SelectMany(result => result.Places).ToArray();
        var retained = raw.Where(p => pilot.Value.Contains(p.Coordinates)
            && RouteMath.DistanceMeters(query.UserLocation, p.Coordinates) <= bounded.RadiusMeters).ToArray();
        var resolved = new DeterministicLocationPlaceResolver(new LocationIntelligenceOptions()).Resolve(retained, bounded, clock.GetUtcNow());
        var places = resolved.Select(place => RespectInterests(place, interests))
            .OrderBy(p => RouteMath.DistanceMeters(query.UserLocation, p.Coordinates) > pilot.Value.MaximumStopDistanceMeters)
            .ThenByDescending(p => p.Facts.Any(f => RouteStoryEvidence.Priority(f) > 0))
            .ThenBy(p => RouteMath.DistanceMeters(query.UserLocation, p.Coordinates))
            .Take(Math.Clamp(pilot.Value.MaximumPlaces, 1, 100)).ToArray();
        recorder.Record(new(pilot.Key, "pilot-context", "complete", watch.ElapsedMilliseconds,
            raw.Length, places.Count(p => p.SourceReferences.Count > 0), 0,
            raw.Length - retained.Length, retained.Length - resolved.Count, GeographicProfileId: pilot.Value.GeographicProfileId));
        return new(Name, true, places, null, results.SelectMany(r => r.Warnings).Distinct().ToArray(),
            results.Count > 0 && results.All(r => r.CacheHit), watch.ElapsedMilliseconds);
    }

    private async Task<LocationContextProviderResult> CompanionAsync(string market, ILocationContextProvider provider,
        LocationContextQuery query, CancellationToken token)
    {
        var key = $"ontario-companion-cooldown:{options.Markets[market].GeographicProfileId}:{provider.Name}";
        var gate = CompanionGates[(uint)StringComparer.Ordinal.GetHashCode(key) % (uint)CompanionGates.Length];
        await gate.WaitAsync(token);
        try
        {
            if (cache.TryGet<LocationContextProviderResult>(key, out var unavailable) && unavailable is not null)
                return unavailable with { CacheHit = true };
            LocationContextProviderResult result;
            try { result = await provider.GetContextAsync(query, token); }
            catch (Exception error) when (error is not OperationCanceledException)
            { result = new(provider.Name, true, [], null, [provider.Name + " unavailable during pilot discovery."], false, 0); }
            if (result.Places.Count == 0 && result.Warnings.Count > 0)
                cache.Set(key, result, TimeSpan.FromSeconds(30));
            return result;
        }
        finally { gate.Release(); }
    }

    private static LocationPlace RespectInterests(LocationPlace place, string[] interests)
    {
        var categories = place.Categories.Select(category => category.ToLowerInvariant() switch
        {
            "heritage" or "local history" => "history",
            _ => category
        }).Where(category => StoryInterestPolicy.Allows(category, interests)).Distinct().ToArray();
        // Unclassified subjects remain research anchors, not automatically narrated history.
        // The existing researcher can classify their evidence against the listener's interests.
        var facts = place.Facts.Select(fact => categories.Length == 0
            ? fact with { IsSuitableForNarration = false }
            : fact.FactType == "authoritative_heritage_description"
                && (place.ShortDescription?.Length ?? 0) >= 40
                && place.ShortDescription!.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 6
                    ? fact with { FactType = "historical_heritage_description" } : fact).ToArray();
        return place with { Categories = categories, Facts = facts };
    }
}

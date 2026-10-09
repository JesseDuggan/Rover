using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.LocationIntelligence;

namespace Rover.Infrastructure.Walks;

public sealed class OntarioLocalDiscoveryProvider(ILocalDiscoveryProvider existing, OntarioFieldTestProvider heritage,
    OntarioFieldTestOptions options) : ILocalDiscoveryProvider
{
    public bool RequiresRealPlaces => existing.RequiresRealPlaces;
    public async Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken token) =>
        (await DiscoverForPlanningAsync(command, token, 12)).Stops;
    public async Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken token, int maximumStops = 30) =>
        (await DiscoverForPlanningAsync(command, token, maximumStops)).Stops;

    public async Task<LocalDiscoveryResult> DiscoverForPlanningAsync(CreateWalkCommand command, CancellationToken token, int maximumStops)
    {
        var ordinary = await existing.DiscoverForPlanningAsync(command, token, maximumStops);
        if (options.Match(command.ProfileId, command.StartingLocation) is not { } market) return ordinary;
        var context = await heritage.GetContextAsync(new(command.StartingLocation, market.Value.SearchRadiusMeters,
            null, command.ProfileId, [], command.Interests), token);
        var stops = ordinary.Stops.ToList();
        var additions = new List<WalkStop>();
        foreach (var place in context.Places)
        {
            if (place.Categories.Count == 0) continue;
            // A regional search is not permission to stretch a short walking route to 8-10 km.
            if (RouteMath.DistanceMeters(command.StartingLocation, place.Coordinates) > market.Value.MaximumStopDistanceMeters) continue;
            // Nearby alone is not identity. Preserve an existing POI's coordinates and public-access route.
            var index = stops.FindIndex(stop => Matches(stop, place));
            if (index >= 0)
            {
                stops[index] = Enrich(stops[index], place);
                continue;
            }
            if (additions.Any(stop => Matches(stop, place))) continue;
            var source = place.SourceReferences.FirstOrDefault();
            if (source is null) continue;
            var description = place.ShortDescription ?? place.Name;
            additions.Add(new(place.CanonicalId, 1, place.Name, place.Coordinates, description,
                place.Facts.FirstOrDefault(f => RouteStoryEvidence.Priority(f) > 0)?.FactText ?? description,
                place.Categories.FirstOrDefault() ?? "history", ContentType.History, ContentSource.LocalRecommendation,
                3, 0, WalkGeofenceDefaults.StandardArrivalRadiusMeters, address: place.Address,
                websiteUrl: source.SourceUrl, discoveryProviderName: source.ProviderName, providerPlaceId: source.ProviderRecordId,
                sourceUrl: source.SourceUrl, requiredAttribution: place.SourceReferences.Select(s => s.Attribution).Distinct().ToArray()));
        }
        if (additions.Count == 0) return new(stops, ordinary.Diagnostic);
        // Mix verified heritage with existing amenities; never require a minimum heritage count.
        var mixed = new List<WalkStop>();
        for (var i = 0; i < Math.Max(stops.Count, additions.Count); i++)
        {
            if (i < additions.Count) mixed.Add(additions[i]);
            if (i < stops.Count) mixed.Add(stops[i]);
        }
        return new(mixed.Take(Math.Clamp(maximumStops, 2, 50)).ToArray(), ordinary.Diagnostic);
    }
    private static bool Matches(WalkStop stop, LocationPlace place) =>
        RouteMath.DistanceMeters(stop.Location, place.Coordinates) < 25
        && (stop.Name.Equals(place.Name, StringComparison.OrdinalIgnoreCase)
            || !string.IsNullOrWhiteSpace(stop.Address) && Normalize(stop.Address) == Normalize(place.Address));

    private static WalkStop Enrich(WalkStop stop, LocationPlace place)
    {
        var fact = place.Facts.FirstOrDefault(f => RouteStoryEvidence.Priority(f) > 0);
        if (fact is null || stop.Narration.Contains(fact.FactText, StringComparison.Ordinal)) return stop;
        var enriched = new WalkStop(stop.StopId, stop.SequenceNumber, stop.Name, stop.Location,
            stop.ShortDescription, stop.Narration + " " + fact.FactText, stop.Category, stop.ContentType,
            stop.ContentSource, stop.EstimatedVisitMinutes, stop.DistanceFromPreviousStopMeters, stop.ArrivalRadiusMeters,
            stop.SponsoredDisclosure, stop.Address, stop.WebsiteUrl, stop.PhoneNumber, stop.MenuUrl,
            stop.DiscoveryProviderName, stop.ProviderPlaceId, stop.SourceUrl,
            stop.RequiredAttribution.Append($"{fact.Source.Attribution} Source: {fact.Source.SourceUrl}").Distinct().ToArray())
            { IsDestination = stop.IsDestination };
        if (stop.ArrivedAtUtc is { } arrived) enriched.MarkArrived(arrived);
        return enriched;
    }
    private static string Normalize(string? address) => new((address ?? "").Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
}

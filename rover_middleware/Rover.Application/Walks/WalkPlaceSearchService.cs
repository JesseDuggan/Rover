using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;
using System.Text.Json;

namespace Rover.Application.Walks;

public sealed record WalkPlaceSelection(string Query, string PlaceId, bool IsDestination = false);
public sealed record WalkPlaceOption(string PlaceId, string Name, string? Address,
    double Latitude, double Longitude, string Attribution);
public sealed record WalkPlaceSearchResult(IReadOnlyList<WalkPlaceOption> Places, IReadOnlyList<string> Warnings);

// Re-resolve the selected provider identity; never turn client-supplied coordinates
// or an ambiguous free-text request into a claimed real place.
public sealed class WalkPlaceSearchService(IEnumerable<ICandidateObservationSearchProvider> providers)
{
    public static bool IsValid(WalkPlaceSelection? selection) => selection is null ||
        (!string.IsNullOrWhiteSpace(selection.Query) && selection.Query.Length <= 256 &&
         !string.IsNullOrWhiteSpace(selection.PlaceId) && selection.PlaceId.Length <= 256);

    public async Task<WalkPlaceSearchResult> SearchAsync(string query, GeoLocation location, CancellationToken ct)
    {
        var result = await SearchPlacesAsync(query, location, ct);
        return new(result.Places.Select(place => new WalkPlaceOption(place.CanonicalId, place.Name,
            place.Address, place.Coordinates.Latitude, place.Coordinates.Longitude,
            string.Join(", ", place.SourceReferences.Select(source => source.Attribution).Distinct()))).ToArray(),
            result.Warnings);
    }

    public async Task<WalkStop> ResolveAsync(WalkPlaceSelection selection, GeoLocation location, CancellationToken ct)
    {
        if (!IsValid(selection)) throw new InvalidOperationException("Search for and select a place first.");
        var result = await SearchPlacesAsync(selection.Query, location, ct);
        var place = result.Places.FirstOrDefault(place => place.CanonicalId == selection.PlaceId)
            ?? throw new InvalidOperationException("That place could not be verified. Search again and select a result.");
        var source = place.SourceReferences.First();
        var description = place.ShortDescription ?? place.Address ?? place.Name;
        // A stop identifies a visit, not the provider's place. Returning to an
        // already visited destination must remain a new, unvisited stop.
        return new WalkStop(
            $"selected-{Guid.NewGuid():n}", 1, place.Name, place.Coordinates, description,
            place.Facts.FirstOrDefault(fact => fact.IsSuitableForNarration)?.FactText ?? description,
            place.Categories.FirstOrDefault() ?? "Place", ContentType.History, ContentSource.LocalRecommendation,
            selection.IsDestination ? 0 : 5, 0, WalkGeofenceDefaults.StandardArrivalRadiusMeters,
            address: place.Address, discoveryProviderName: source.ProviderName,
            providerPlaceId: source.ProviderRecordId, sourceUrl: source.SourceUrl,
            requiredAttribution: place.SourceReferences.Select(reference => reference.Attribution).Distinct().ToArray())
        { IsDestination = selection.IsDestination };
    }

    private async Task<(IReadOnlyList<LocationPlace> Places, IReadOnlyList<string> Warnings)> SearchPlacesAsync(
        string query, GeoLocation location, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(query) || query.Length > 256)
            throw new InvalidOperationException("Enter a place name of up to 256 characters.");
        var places = new List<LocationPlace>();
        var warnings = new List<string>();
        foreach (var provider in providers)
        {
            CandidateObservationSearchResult result;
            try
            {
                result = await provider.SearchAsync(new CandidateObservationQuery(query.Trim(), location,
                    null, null, 50000, null, Array.Empty<string>()), ct);
            }
            catch (Exception error) when (error is HttpRequestException or JsonException ||
                (error is OperationCanceledException && !ct.IsCancellationRequested))
            {
                warnings.Add("A place search provider is temporarily unavailable.");
                continue;
            }
            places.AddRange(result.Places.Where(place => place.SourceReferences.Count > 0 &&
                double.IsFinite(place.Coordinates.Latitude) && double.IsFinite(place.Coordinates.Longitude) &&
                Math.Abs(place.Coordinates.Latitude) <= 90 && Math.Abs(place.Coordinates.Longitude) <= 180 &&
                RouteMath.DistanceMeters(location, place.Coordinates) <= 50000));
            warnings.AddRange(result.Warnings);
        }
        return (places.DistinctBy(place => place.CanonicalId).Take(10).ToArray(), warnings);
    }
}

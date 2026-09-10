using Microsoft.Extensions.Options;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.LocationIntelligence;

namespace Rover.Infrastructure.Walks;

public sealed class GooglePlacesLocalDiscoveryProvider : ILocalDiscoveryProvider
{
    private readonly GooglePlacesLocationContextProvider _placesProvider;
    private readonly LocalDiscoveryOptions _options;

    public GooglePlacesLocalDiscoveryProvider(
        GooglePlacesLocationContextProvider placesProvider,
        IOptions<LocalDiscoveryOptions> options)
    {
        _placesProvider = placesProvider;
        _options = options.Value;
    }

    public async Task<IReadOnlyList<WalkStop>> FindStopsAsync(
        CreateWalkCommand command,
        CancellationToken cancellationToken)
    {
        var selected = await FindCandidateStopsAsync(
            command,
            cancellationToken,
            Math.Clamp(_options.MaximumStops, 3, 12));
        return selected.Count < _options.MinimumStops
            ? Array.Empty<WalkStop>()
            : selected;
    }

    public async Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(
        CreateWalkCommand command,
        CancellationToken cancellationToken,
        int maximumStops = 30)
    {
        if (!_options.Enabled)
        {
            return Array.Empty<WalkStop>();
        }

        var result = await _placesProvider.GetContextAsync(
            new LocationContextQuery(
                command.StartingLocation,
                Math.Clamp(_options.MaximumDistanceMeters, 100, 50000),
                null,
                null,
                Array.Empty<GeoLocation>(),
                command.Interests),
            cancellationToken);

        var selected = result.Places
            .Select(place => new
            {
                Place = place,
                Distance = RouteMath.DistanceMeters(command.StartingLocation, place.Coordinates)
            })
            .Where(candidate => candidate.Distance > 40 && candidate.Distance < _options.MaximumDistanceMeters)
            .OrderBy(candidate => Score(candidate.Place, candidate.Distance, command.Interests))
            .Take(Math.Max(1, maximumStops))
            .ToArray();

        return selected
            .Select((candidate, index) => ToStop(
                candidate.Place,
                index + 1,
                index == 0
                    ? 0
                    : (int)Math.Round(RouteMath.DistanceMeters(
                        selected[index - 1].Place.Coordinates,
                        candidate.Place.Coordinates))))
            .ToArray();
    }

    private static WalkStop ToStop(LocationPlace place, int sequenceNumber, int distanceFromPreviousStopMeters)
    {
        var category = DisplayCategory(place);
        var source = place.SourceReferences.FirstOrDefault(reference =>
            reference.ProviderName.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase));
        var providerPlaceId = place.ProviderIds.TryGetValue("google_places", out var placeId)
            ? placeId
            : source?.ProviderRecordId;
        var attributions = place.SourceReferences
            .Select(reference => reference.Attribution)
            .Where(attribution => !string.IsNullOrWhiteSpace(attribution))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var description = !string.IsNullOrWhiteSpace(place.ShortDescription)
            ? place.ShortDescription!
            : !string.IsNullOrWhiteSpace(place.Address)
                ? $"{category} at {place.Address}."
                : $"{place.Name} is a nearby {category.ToLowerInvariant()} stop.";
        var narration = place.Facts.FirstOrDefault(fact => fact.IsSuitableForNarration)?.FactText
            ?? $"You have arrived at {place.Name}. {description}";

        return new WalkStop(
            $"google-{NormalizeId(providerPlaceId ?? place.CanonicalId)}",
            sequenceNumber,
            place.Name,
            place.Coordinates,
            description,
            narration,
            category,
            ContentTypeFor(category),
            ContentSource.LocalRecommendation,
            5,
            distanceFromPreviousStopMeters,
            WalkGeofenceDefaults.StandardArrivalRadiusMeters,
            address: place.Address,
            websiteUrl: source?.SourceUrl,
            discoveryProviderName: "GooglePlaces",
            providerPlaceId: providerPlaceId,
            sourceUrl: source?.SourceUrl,
            requiredAttribution: attributions.Length == 0 ? new[] { "Google Maps" } : attributions);
    }

    private static double Score(LocationPlace place, double distance, IReadOnlyCollection<string> interests)
    {
        var interestMatch = interests.Any(interest =>
            place.Name.Contains(interest, StringComparison.OrdinalIgnoreCase)
            || place.Categories.Any(category => category.Contains(interest, StringComparison.OrdinalIgnoreCase)));
        return (interestMatch ? 0 : 500) + distance;
    }

    private static string DisplayCategory(LocationPlace place)
    {
        var value = place.Categories.FirstOrDefault(category => !string.IsNullOrWhiteSpace(category)) ?? "Place";
        return System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(value.Replace('_', ' ').ToLowerInvariant());
    }

    private static ContentType ContentTypeFor(string category)
    {
        var value = category.ToLowerInvariant();
        if (value.Contains("coffee") || value.Contains("cafe") || value.Contains("bakery") || value.Contains("restaurant"))
        {
            return ContentType.FoodAndDrink;
        }

        if (value.Contains("art")) return ContentType.PublicArt;
        if (value.Contains("architect")) return ContentType.Architecture;
        return ContentType.History;
    }

    private static string NormalizeId(string value)
        => new(value.Where(character => char.IsLetterOrDigit(character) || character is '-' or '_').ToArray());
}

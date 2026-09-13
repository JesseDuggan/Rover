using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class GooglePlacesLocationContextProvider : LocationContextProviderBase, ICandidateObservationSearchProvider, ILocationContextCachePolicy
{
    private const string SearchFieldMask = "places.id,places.displayName.text,places.location,places.formattedAddress,places.addressComponents,places.primaryType,places.primaryTypeDisplayName.text,places.types,places.googleMapsUri,places.businessStatus,places.currentOpeningHours.openNow,places.accessibilityOptions,places.attributions";
    private readonly IHttpClientFactory _httpClientFactory;

    public GooglePlacesLocationContextProvider(
        IHttpClientFactory httpClientFactory,
        ILocationContextCache cache,
        TimeProvider timeProvider,
        LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "GooglePlaces";
    public bool AllowsAggregateCaching => !Options.Enabled;
    protected override bool AllowResultCaching => false;

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(Options.AccessToken))
        {
            return Empty("Google Places is enabled but GOOGLE_PLACES_API_KEY is not configured.");
        }

        var body = new
        {
            includedTypes = MapTypes(query.Interests),
            maxResultCount = Math.Clamp(Options.MaximumResults, 1, 20),
            rankPreference = "DISTANCE",
            languageCode = "en",
            locationRestriction = new
            {
                circle = new
                {
                    center = new
                    {
                        latitude = query.UserLocation.Latitude,
                        longitude = query.UserLocation.Longitude
                    },
                    radius = (double)Math.Min(query.RadiusMeters, 50000)
                }
            }
        };
        var result = await SearchPlacesAsync("places:searchNearby", body, cancellationToken);
        return new LocationContextProviderResult(Name, true, result.Places, null, result.Warnings, false, 0);
    }

    public async Task<CandidateObservationSearchResult> SearchAsync(
        CandidateObservationQuery query,
        CancellationToken cancellationToken)
    {
        if (!Options.Enabled)
        {
            return new CandidateObservationSearchResult(
                Name,
                Array.Empty<LocationPlace>(),
                Array.Empty<string>());
        }

        if (string.IsNullOrWhiteSpace(Options.AccessToken))
        {
            return new CandidateObservationSearchResult(
                Name,
                Array.Empty<LocationPlace>(),
                new[] { "Google Places business search is enabled but GOOGLE_PLACES_API_KEY is not configured." });
        }

        var searchText = string.Join(' ', query.RecognizedText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (searchText.Length > 256)
        {
            searchText = searchText[..256];
        }

        var body = new
        {
            textQuery = searchText,
            maxResultCount = Math.Clamp(Options.MaximumResults, 1, 10),
            languageCode = "en",
            locationBias = new
            {
                circle = new
                {
                    center = new
                    {
                        latitude = query.UserLocation.Latitude,
                        longitude = query.UserLocation.Longitude
                    },
                    radius = (double)Math.Min(query.RadiusMeters, 50000)
                }
            }
        };
        var result = await SearchPlacesAsync("places:searchText", body, cancellationToken);
        var nearby = result.Places
            .Where(place => RouteMath.DistanceMeters(query.UserLocation, place.Coordinates) <= query.RadiusMeters)
            .ToArray();
        return new CandidateObservationSearchResult(Name, nearby, result.Warnings);
    }

    private async Task<(IReadOnlyList<LocationPlace> Places, IReadOnlyList<string> Warnings)> SearchPlacesAsync(
        string operation,
        object body,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(Options.TimeoutSeconds, 2, 30)));
        try
        {
            var endpoint = (Options.Endpoint ?? "https://places.googleapis.com/v1").TrimEnd('/');
            using var request = new HttpRequestMessage(HttpMethod.Post, $"{endpoint}/{operation}")
            {
                Content = JsonContent.Create(body)
            };
            request.Headers.TryAddWithoutValidation("X-Goog-Api-Key", Options.AccessToken);
            request.Headers.TryAddWithoutValidation("X-Goog-FieldMask", SearchFieldMask);

            var client = _httpClientFactory.CreateClient("GooglePlaces");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                if (response.Headers.Contains("X-Rover-Quota-Cooldown"))
                    return (Array.Empty<LocationPlace>(), new[] { "Google Places requests are paused after HTTP 429 (quota exhausted). No new request was sent to Google." });
                return (Array.Empty<LocationPlace>(), new[] { $"Google Places returned HTTP {(int)response.StatusCode} ({response.StatusCode})." });
            }

            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
            if (!document.RootElement.TryGetProperty("places", out var placesElement)
                || placesElement.ValueKind != JsonValueKind.Array)
            {
                return (Array.Empty<LocationPlace>(), new[] { "Google Places returned no places." });
            }

            var places = placesElement.EnumerateArray()
                .Select(ParsePlace)
                .Where(place => place is not null)
                .Cast<LocationPlace>()
                .ToArray();
            return (places, Array.Empty<string>());
        }
        catch (JsonException)
        {
            return (Array.Empty<LocationPlace>(), new[] { "Google Places returned malformed JSON." });
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return (Array.Empty<LocationPlace>(), new[] { "Google Places timed out." });
        }
        catch (HttpRequestException)
        {
            return (Array.Empty<LocationPlace>(), new[] { "Google Places is temporarily unavailable." });
        }
    }

    private LocationPlace? ParsePlace(JsonElement item)
    {
        var id = Text(item, "id");
        var name = NestedText(item, "displayName", "text");
        if (string.IsNullOrWhiteSpace(id)
            || string.IsNullOrWhiteSpace(name)
            || !item.TryGetProperty("location", out var location)
            || Number(location, "latitude") is not { } latitude
            || Number(location, "longitude") is not { } longitude)
        {
            return null;
        }

        var address = Text(item, "formattedAddress");
        var primaryType = Text(item, "primaryType");
        var primaryTypeLabel = NestedText(item, "primaryTypeDisplayName", "text");
        var categories = StringArray(item, "types")
            .Prepend(primaryTypeLabel ?? primaryType ?? "place")
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Replace('_', ' '))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var googleMapsUri = Text(item, "googleMapsUri");
        var source = new LocationSource(
            Name,
            id,
            googleMapsUri,
            "Google Maps",
            "Google Maps Platform terms",
            Now,
            0.88)
        {
            SourceTitle = name
        };
        var sources = new List<LocationSource> { source };
        sources.AddRange(AttributionSources(item));

        var facts = new List<LocationFact>
        {
            new(
                $"googleplaces:{NormalizeId(id)}:identity",
                "poi_identity",
                BuildIdentityFact(name, primaryTypeLabel ?? primaryType, address),
                source,
                0.84,
                true,
                Now)
        };
        var openingStatus = OpeningStatus(item);
        if (!string.IsNullOrWhiteSpace(openingStatus))
        {
            facts.Add(new LocationFact(
                $"googleplaces:{NormalizeId(id)}:opening",
                "opening_status",
                $"Google Places currently lists {name} as {openingStatus.ToLowerInvariant()}.",
                source,
                0.8,
                true,
                Now));
        }

        var accessibility = Accessibility(item);
        if (!string.IsNullOrWhiteSpace(accessibility))
        {
            facts.Add(new LocationFact(
                $"googleplaces:{NormalizeId(id)}:accessibility",
                "accessibility",
                $"Google Places lists {accessibility} at {name}.",
                source,
                0.78,
                true,
                Now));
        }

        var providerIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["google_places"] = id
        };
        return Place(
            $"google-{NormalizeId(id)}",
            name,
            new GeoLocation(latitude, longitude),
            address,
            categories,
            BuildIdentityFact(name, primaryTypeLabel ?? primaryType, address),
            facts,
            sources,
            providerIds,
            0.88,
            Now,
            openingStatus,
            accessibility) with
        {
            City = AddressComponent(item, "locality") ?? AddressComponent(item, "postal_town"),
            Region = AddressComponent(item, "administrative_area_level_1"),
            CountryCode = AddressComponent(item, "country", "shortText")
        };
    }

    private static string? AddressComponent(JsonElement item, string type, string field = "longText")
    {
        if (!item.TryGetProperty("addressComponents", out var components) || components.ValueKind != JsonValueKind.Array) return null;
        foreach (var component in components.EnumerateArray())
        {
            if (StringArray(component, "types").Contains(type)) return Text(component, field);
        }
        return null;
    }

    private IEnumerable<LocationSource> AttributionSources(JsonElement item)
    {
        if (!item.TryGetProperty("attributions", out var attributions)
            || attributions.ValueKind != JsonValueKind.Array)
        {
            yield break;
        }

        foreach (var attribution in attributions.EnumerateArray())
        {
            var provider = Text(attribution, "provider");
            if (string.IsNullOrWhiteSpace(provider))
            {
                continue;
            }

            yield return new LocationSource(
                Name,
                null,
                Text(attribution, "providerUri"),
                provider,
                "Provider terms",
                Now,
                0.8)
            {
                SourceTitle = provider
            };
        }
    }

    private static string OpeningStatus(JsonElement item)
    {
        if (item.TryGetProperty("currentOpeningHours", out var hours)
            && hours.TryGetProperty("openNow", out var openNow)
            && openNow.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            return openNow.GetBoolean() ? "Open now" : "Closed now";
        }

        return Text(item, "businessStatus") switch
        {
            "CLOSED_PERMANENTLY" => "Permanently closed",
            "CLOSED_TEMPORARILY" => "Temporarily closed",
            "OPERATIONAL" => "Operational",
            _ => string.Empty
        };
    }

    private static string? Accessibility(JsonElement item)
    {
        if (!item.TryGetProperty("accessibilityOptions", out var options)
            || options.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var available = new List<string>();
        AddIfTrue(options, "wheelchairAccessibleEntrance", "a wheelchair-accessible entrance", available);
        AddIfTrue(options, "wheelchairAccessibleParking", "wheelchair-accessible parking", available);
        AddIfTrue(options, "wheelchairAccessibleRestroom", "a wheelchair-accessible restroom", available);
        AddIfTrue(options, "wheelchairAccessibleSeating", "wheelchair-accessible seating", available);
        return available.Count == 0 ? null : string.Join(", ", available);
    }

    private static void AddIfTrue(JsonElement item, string property, string text, ICollection<string> values)
    {
        if (item.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True)
        {
            values.Add(text);
        }
    }

    private static string BuildIdentityFact(string name, string? category, string? address)
    {
        var normalizedCategory = category?.Replace('_', ' ');
        if (!string.IsNullOrWhiteSpace(normalizedCategory) && !string.IsNullOrWhiteSpace(address)) return $"{name} is listed by Google Maps as {Article(normalizedCategory)} {normalizedCategory} at {address}.";
        if (!string.IsNullOrWhiteSpace(normalizedCategory)) return $"{name} is listed by Google Maps as {Article(normalizedCategory)} {normalizedCategory}.";
        if (!string.IsNullOrWhiteSpace(address)) return $"{name} is listed by Google Maps at {address}.";
        return $"{name} is a Google Maps place result.";
    }

    private static string[] MapTypes(IReadOnlyCollection<string> interests)
    {
        var mapped = new List<string>();
        foreach (var interest in interests)
        {
            var value = interest.ToLowerInvariant();
            if (value.Contains("history")) mapped.AddRange(["historical_place", "historical_landmark"]);
            if (value.Contains("architect")) mapped.Add("cultural_landmark");
            if (value.Contains("museum")) mapped.Add("museum");
            if (value.Contains("culture") || value.Contains("art")) mapped.Add("art_gallery");
            if (value.Contains("nature") || value.Contains("outdoor")) mapped.Add("park");
            if (value.Contains("food") || value.Contains("restaurant") || value.Contains("burger")) mapped.Add("restaurant");
            if (value.Contains("coffee") || value.Contains("tea") || value.Contains("cake")) mapped.Add("cafe");
            if (value.Contains("hotel") || value.Contains("lodging")) mapped.Add("hotel");
        }

        IEnumerable<string> selectedTypes = mapped.Count == 0
            ? new[] { "tourist_attraction", "museum", "park", "cafe", "restaurant", "hotel" }
            : mapped;
        return selectedTypes
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(50)
            .ToArray();
    }

    private LocationContextProviderResult Empty(string warning)
        => new(Name, true, Array.Empty<LocationPlace>(), null, new[] { warning }, false, 0);

    private static string? Text(JsonElement item, string property)
        => item.ValueKind == JsonValueKind.Object
            && item.TryGetProperty(property, out var value)
            && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;

    private static string? NestedText(JsonElement item, string parent, string property)
        => item.ValueKind == JsonValueKind.Object
            && item.TryGetProperty(parent, out var nested)
                ? Text(nested, property)
                : null;

    private static double? Number(JsonElement item, string property)
        => item.ValueKind == JsonValueKind.Object
            && item.TryGetProperty(property, out var value)
            && value.TryGetDouble(out var number)
                ? number
                : null;

    private static IEnumerable<string> StringArray(JsonElement item, string property)
        => item.TryGetProperty(property, out var values) && values.ValueKind == JsonValueKind.Array
            ? values.EnumerateArray()
                .Where(value => value.ValueKind == JsonValueKind.String)
                .Select(value => value.GetString()!)
                .Where(value => !string.IsNullOrWhiteSpace(value))
            : Array.Empty<string>();

    private static string NormalizeId(string value)
        => new(value.Where(character => char.IsLetterOrDigit(character) || character is '-' or '_').ToArray());

    private static string Article(string value)
        => value.Length > 0 && "aeiou".Contains(char.ToLowerInvariant(value[0])) ? "an" : "a";
}

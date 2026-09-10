using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class MapboxLocalDiscoveryProvider : ILocalDiscoveryProvider
{
    private static readonly string[] DefaultCategories =
    {
        "coffee",
        "cafe",
        "bakery",
        "restaurant",
        "park",
        "tourist_attraction"
    };

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly LocalDiscoveryOptions _options;

    public LocalDiscoveryDebugInfo LastDebugInfo { get; private set; } = LocalDiscoveryDebugInfo.Empty;

    public MapboxLocalDiscoveryProvider(IHttpClientFactory httpClientFactory, IOptions<LocalDiscoveryOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
    }

    public async Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken)
    {
        var selected = await FindCandidateStopsAsync(command, cancellationToken, Math.Clamp(_options.MaximumStops, 3, 12));
        return selected.Count < _options.MinimumStops
            ? Array.Empty<WalkStop>()
            : selected;
    }

    public async Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(
        CreateWalkCommand command,
        CancellationToken cancellationToken,
        int maximumStops = 30)
    {
        var categoryResults = new List<string>();
        var debugInfo = new LocalDiscoveryDebugInfo(
            _options.Enabled,
            !string.IsNullOrWhiteSpace(_options.AccessToken),
            _options.RadiusDegrees,
            _options.MaximumDistanceMeters,
            0,
            0,
            0,
            0,
            Array.Empty<string>(),
            Array.Empty<LocalDiscoveryDebugCandidate>());

        if (!_options.Enabled || string.IsNullOrWhiteSpace(_options.AccessToken))
        {
            LastDebugInfo = debugInfo;
            return Array.Empty<WalkStop>();
        }

        var categories = CategoriesFor(command.Interests);
        var discoveries = new List<CandidateStop>();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_options.Timeout);

        foreach (var category in categories)
        {
            var found = await QueryCategoryAsync(category, command.StartingLocation, categoryResults, timeout.Token);
            discoveries.AddRange(found);
        }

        var withinDistance = discoveries
            .Where(candidate =>
            {
                var distance = RouteMath.DistanceMeters(command.StartingLocation, candidate.Location);
                return distance > 40 && distance < _options.MaximumDistanceMeters;
            })
            .ToArray();

        var selected = withinDistance
            .GroupBy(candidate => candidate.Name, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(candidate => candidate.DistanceMeters).First())
            .OrderBy(candidate => Score(candidate, command.Interests))
            .ThenBy(candidate => candidate.DistanceMeters)
            .Take(Math.Max(1, maximumStops))
            .ToArray();

        LastDebugInfo = debugInfo with
        {
            CategoriesQueried = categoryResults.Count,
            RawCandidateCount = discoveries.Count,
            CandidatesWithinDistance = withinDistance.Length,
            SelectedCount = selected.Length,
            CategoryResults = categoryResults.ToArray(),
            CandidateSamples = withinDistance
                .GroupBy(candidate => candidate.Id, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.OrderBy(candidate => candidate.DistanceMeters).First())
                .OrderBy(candidate => candidate.DistanceMeters)
                .Take(30)
                .Select(candidate => new LocalDiscoveryDebugCandidate(
                    candidate.Id,
                    candidate.Name,
                    candidate.Category,
                    candidate.SourceCategory,
                    (int)Math.Round(candidate.DistanceMeters),
                    candidate.Address,
                    candidate.WebsiteUrl,
                    candidate.PhoneNumber,
                    candidate.MenuUrl))
                .ToArray()
        };

        return selected
            .Select((candidate, index) => candidate.ToStop(index + 1, index == 0 ? 0 : (int)Math.Round(RouteMath.DistanceMeters(selected[index - 1].Location, candidate.Location))))
            .ToArray();
    }

    private async Task<IReadOnlyList<CandidateStop>> QueryCategoryAsync(string category, GeoLocation origin, List<string> categoryResults, CancellationToken cancellationToken)
    {
        var longitude = origin.Longitude.ToString(CultureInfo.InvariantCulture);
        var latitude = origin.Latitude.ToString(CultureInfo.InvariantCulture);
        var url = $"https://api.mapbox.com/search/searchbox/v1/category/{Uri.EscapeDataString(category)}?language=en&limit={_options.LimitPerCategory}&proximity={longitude},{latitude}&radius={_options.RadiusDegrees.ToString(CultureInfo.InvariantCulture)}&country={Uri.EscapeDataString(_options.Country)}&access_token={Uri.EscapeDataString(_options.AccessToken!)}";
        using var response = await _httpClientFactory.CreateClient("MapboxSearch").GetAsync(url, cancellationToken);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            throw new InvalidOperationException("Mapbox local discovery authorization failed. Check the configured server-side token.");
        }

        if (!response.IsSuccessStatusCode)
        {
            categoryResults.Add($"{category}: HTTP {(int)response.StatusCode}");
            return Array.Empty<CandidateStop>();
        }

        using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
        if (!document.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Array)
        {
            categoryResults.Add($"{category}: no features array");
            return Array.Empty<CandidateStop>();
        }

        var candidates = features
            .EnumerateArray()
            .Select(feature => CandidateFromFeature(feature, category, origin))
            .Where(candidate => candidate is not null)
            .Cast<CandidateStop>()
            .ToArray();
        categoryResults.Add($"{category}: {candidates.Length} features");
        return candidates;
    }

    private static CandidateStop? CandidateFromFeature(JsonElement feature, string category, GeoLocation origin)
    {
        if (!feature.TryGetProperty("geometry", out var geometry)
            || !geometry.TryGetProperty("coordinates", out var coordinates)
            || coordinates.GetArrayLength() < 2)
        {
            return null;
        }

        var location = new GeoLocation(coordinates[1].GetDouble(), coordinates[0].GetDouble());
        var properties = feature.TryGetProperty("properties", out var value) ? value : default;
        var metadata = properties.ValueKind == JsonValueKind.Object && properties.TryGetProperty("metadata", out var metadataValue)
            ? metadataValue
            : default;
        var name = ReadString(properties, "name") ?? ReadString(properties, "full_address") ?? "Nearby place";
        var categoryName = ReadString(properties, "poi_category") ?? category.Replace('_', ' ');
        var address = ReadString(properties, "full_address")
            ?? ReadString(properties, "place_formatted")
            ?? ReadString(properties, "address");
        var website = ReadString(properties, "website") ?? ReadString(metadata, "website");
        var phone = ReadString(properties, "phone") ?? ReadString(metadata, "phone");
        var menuUrl = ReadString(properties, "menu")
            ?? ReadString(properties, "menu_url")
            ?? ReadString(properties, "menuUrl")
            ?? ReadString(metadata, "menu")
            ?? ReadString(metadata, "menu_url")
            ?? ReadString(metadata, "menuUrl");
        var distance = RouteMath.DistanceMeters(origin, location);
        return new CandidateStop(Slug(name), name, TitleCase(categoryName), location, distance, category, address, website, phone, menuUrl);
    }

    private static string? ReadString(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(propertyName, out var property)
            && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static IEnumerable<string> CategoriesFor(IReadOnlyCollection<string> interests)
    {
        var mapped = interests
            .SelectMany(interest => interest.ToLowerInvariant() switch
            {
                var value when value.Contains("coffee") => new[] { "coffee", "cafe" },
                var value when value.Contains("tea") => new[] { "tea_room", "cafe" },
                var value when value.Contains("cake") || value.Contains("bakery") || value.Contains("food") => new[] { "bakery", "restaurant" },
                var value when value.Contains("burger") => new[] { "burger", "restaurant" },
                var value when value.Contains("nature") || value.Contains("park") => new[] { "park" },
                var value when value.Contains("art") => new[] { "museum", "art_gallery" },
                var value when value.Contains("history") || value.Contains("architecture") || value.Contains("interesting") => new[] { "tourist_attraction", "monument" },
                _ => Array.Empty<string>()
            })
            .Concat(DefaultCategories)
            .Distinct(StringComparer.OrdinalIgnoreCase);

        return mapped.Take(8);
    }

    private static double Score(CandidateStop candidate, IReadOnlyCollection<string> interests)
    {
        var category = candidate.Category.ToLowerInvariant();
        var interestMatch = interests.Any(interest => category.Contains(interest, StringComparison.OrdinalIgnoreCase) || candidate.Name.Contains(interest, StringComparison.OrdinalIgnoreCase));
        return (interestMatch ? 0 : 500) + candidate.DistanceMeters;
    }

    private static string TitleCase(string value)
    {
        return CultureInfo.InvariantCulture.TextInfo.ToTitleCase(value.Replace('_', ' ').ToLowerInvariant());
    }

    private static string Slug(string value)
    {
        var chars = value.ToLowerInvariant().Select(ch => char.IsLetterOrDigit(ch) ? ch : '-').ToArray();
        return $"mapbox-{new string(chars).Trim('-')}";
    }

    private sealed record CandidateStop(
        string Id,
        string Name,
        string Category,
        GeoLocation Location,
        double DistanceMeters,
        string SourceCategory,
        string? Address,
        string? WebsiteUrl,
        string? PhoneNumber,
        string? MenuUrl)
    {
        public WalkStop ToStop(int sequenceNumber, int distanceFromPreviousStopMeters)
        {
            var description = Address is null
                ? $"{Name} is a nearby {Category.ToLowerInvariant()} stop."
                : $"{Category} near {Address}.";
            var details = new List<string>
            {
                $"You have arrived at {Name}.",
                Address is null
                    ? $"This is a nearby {Category.ToLowerInvariant()} stop."
                    : $"This {Category.ToLowerInvariant()} stop is near {Address}."
            };
            if (!string.IsNullOrWhiteSpace(WebsiteUrl))
            {
                details.Add("Rover has a website link for this place in the stop details.");
            }

            if (!string.IsNullOrWhiteSpace(MenuUrl))
            {
                details.Add("A menu link is also available in the stop details.");
            }

            var narration = string.Join(" ", details);
            return new WalkStop(
                Id,
                sequenceNumber,
                Name,
                Location,
                description,
                narration,
                Category,
                Category.Contains("Coffee", StringComparison.OrdinalIgnoreCase)
                    || Category.Contains("Cafe", StringComparison.OrdinalIgnoreCase)
                    || Category.Contains("Bakery", StringComparison.OrdinalIgnoreCase)
                    || Category.Contains("Restaurant", StringComparison.OrdinalIgnoreCase)
                    ? ContentType.FoodAndDrink
                    : ContentType.History,
                ContentSource.LocalRecommendation,
                5,
                distanceFromPreviousStopMeters,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters,
                address: Address,
                websiteUrl: WebsiteUrl,
                phoneNumber: PhoneNumber,
                menuUrl: MenuUrl);
        }
    }
}

public sealed record LocalDiscoveryDebugInfo(
    bool Enabled,
    bool AccessTokenConfigured,
    double RadiusDegrees,
    int MaximumDistanceMeters,
    int CategoriesQueried,
    int RawCandidateCount,
    int CandidatesWithinDistance,
    int SelectedCount,
    IReadOnlyList<string> CategoryResults,
    IReadOnlyList<LocalDiscoveryDebugCandidate> CandidateSamples)
{
    public static LocalDiscoveryDebugInfo Empty { get; } = new(false, false, 0, 0, 0, 0, 0, 0, Array.Empty<string>(), Array.Empty<LocalDiscoveryDebugCandidate>());
}

public sealed record LocalDiscoveryDebugCandidate(
    string StopId,
    string Name,
    string Category,
    string SourceCategory,
    int DistanceMeters,
    string? Address,
    string? WebsiteUrl,
    string? PhoneNumber,
    string? MenuUrl);

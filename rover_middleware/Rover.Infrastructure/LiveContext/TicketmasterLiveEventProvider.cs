using System.Globalization;
using System.Text.Json;
using Rover.Application.LiveContext;

namespace Rover.Infrastructure.LiveContext;

public sealed class TicketmasterLiveEventProvider : ILiveEventProvider
{
    private const string ProviderName = "Ticketmaster Discovery";
    private readonly HttpClient _httpClient;
    private readonly TicketmasterLiveOptions _options;
    private readonly TimeProvider _timeProvider;

    public TicketmasterLiveEventProvider(HttpClient httpClient, TicketmasterLiveOptions options, TimeProvider timeProvider)
    {
        _httpClient = httpClient;
        _options = options;
        _timeProvider = timeProvider;
    }

    public async Task<LiveProviderResult<LiveEvent>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow();
        if (!_options.Enabled)
        {
            return LiveProviderResult<LiveEvent>.Disabled(ProviderName, now);
        }

        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            return LiveProviderResult<LiveEvent>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Ticketmaster Discovery is enabled but its server key is missing.");
        }

        var uri = "https://app.ticketmaster.com/discovery/v2/events.json"
            + $"?apikey={Uri.EscapeDataString(_options.ApiKey)}"
            + $"&geoPoint={GeoHash.Encode(query.Location.Latitude, query.Location.Longitude, 7)}"
            + $"&radius={Math.Clamp(_options.RadiusKilometers, 1, 100)}&unit=km"
            + $"&size={Math.Clamp(_options.MaximumResults, 1, 20)}&sort=date,asc"
            + $"&startDateTime={Uri.EscapeDataString(query.JourneyStartsUtc.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture))}"
            + $"&endDateTime={Uri.EscapeDataString(query.JourneyEndsUtc.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture))}";
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 2, 30)));

        try
        {
            using var response = await _httpClient.GetAsync(uri, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                return LiveProviderResult<LiveEvent>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Ticketmaster Discovery did not return live events.");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
            var events = Parse(document.RootElement, now, query).ToArray();
            return new LiveProviderResult<LiveEvent>(ProviderName, true, true, events, now, now.AddMinutes(30), null);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        {
            return LiveProviderResult<LiveEvent>.Failed(ProviderName, now, TimeSpan.FromMinutes(2), "Ticketmaster Discovery is temporarily unavailable.");
        }
    }

    private static IEnumerable<LiveEvent> Parse(JsonElement root, DateTimeOffset retrievedUtc, LiveContextQuery query)
    {
        if (!root.TryGetProperty("_embedded", out var embedded)
            || !embedded.TryGetProperty("events", out var events)
            || events.ValueKind != JsonValueKind.Array)
        {
            yield break;
        }

        foreach (var item in events.EnumerateArray())
        {
            var starts = GoogleWeatherLiveProvider.Date(item, "dates", "start", "dateTime");
            if (!starts.HasValue || starts < query.JourneyStartsUtc || starts > query.JourneyEndsUtc) continue;
            var venue = First(item, "_embedded", "venues");
            var eventId = GoogleWeatherLiveProvider.Text(item, "id") ?? Guid.NewGuid().ToString("N");
            var url = GoogleWeatherLiveProvider.Text(item, "url");
            var expires = starts.Value > retrievedUtc ? Min(starts.Value, retrievedUtc.AddMinutes(30)) : retrievedUtc.AddMinutes(10);
            yield return new LiveEvent(
                eventId,
                GoogleWeatherLiveProvider.Text(item, "name") ?? "Local event",
                venue.HasValue ? GoogleWeatherLiveProvider.Text(venue.Value, "name") : null,
                venue.HasValue ? Address(venue.Value) : null,
                starts.Value,
                GoogleWeatherLiveProvider.Date(item, "dates", "end", "dateTime"),
                First(item, "classifications") is JsonElement classification
                    ? GoogleWeatherLiveProvider.Text(classification, "segment", "name")
                    : null,
                venue.HasValue ? ParseNumber(GoogleWeatherLiveProvider.Text(venue.Value, "location", "latitude")) : null,
                venue.HasValue ? ParseNumber(GoogleWeatherLiveProvider.Text(venue.Value, "location", "longitude")) : null,
                query.ForRouteStory ? LiveAutomaticSpeechPolicy.Actionable : LiveAutomaticSpeechPolicy.UserRequestedOnly,
                new LiveSourceReference(ProviderName, eventId, "Ticketmaster", url, "Ticketmaster", retrievedUtc, null, expires));
        }
    }

    private static JsonElement? First(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current)) return null;
        }
        return current.ValueKind == JsonValueKind.Array && current.GetArrayLength() > 0 ? current[0] : null;
    }

    private static string? Address(JsonElement venue)
    {
        var parts = new[]
        {
            GoogleWeatherLiveProvider.Text(venue, "address", "line1"),
            GoogleWeatherLiveProvider.Text(venue, "city", "name"),
            GoogleWeatherLiveProvider.Text(venue, "state", "stateCode"),
            GoogleWeatherLiveProvider.Text(venue, "country", "countryCode")
        };
        var value = string.Join(", ", parts.Where(part => !string.IsNullOrWhiteSpace(part)));
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static double? ParseNumber(string? value) =>
        double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) ? number : null;

    private static DateTimeOffset Min(DateTimeOffset left, DateTimeOffset right) => left < right ? left : right;

    private static class GeoHash
    {
        private const string Alphabet = "0123456789bcdefghjkmnpqrstuvwxyz";

        public static string Encode(double latitude, double longitude, int precision)
        {
            var lat = new[] { -90d, 90d };
            var lng = new[] { -180d, 180d };
            var hash = new char[precision];
            var bit = 0;
            var character = 0;
            var even = true;
            for (var index = 0; index < precision;)
            {
                var range = even ? lng : lat;
                var value = even ? longitude : latitude;
                var midpoint = (range[0] + range[1]) / 2;
                if (value >= midpoint)
                {
                    character |= 1 << (4 - bit);
                    range[0] = midpoint;
                }
                else
                {
                    range[1] = midpoint;
                }

                even = !even;
                if (bit < 4)
                {
                    bit++;
                    continue;
                }

                hash[index++] = Alphabet[character];
                bit = 0;
                character = 0;
            }
            return new string(hash);
        }
    }
}

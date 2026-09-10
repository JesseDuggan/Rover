using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LiveContext;

namespace Rover.Infrastructure.LiveContext;

public sealed class OpenAICurrentInformationProvider : ILiveCurrentInformationProvider
{
    private const string ProviderName = "OpenAI web search";
    private readonly HttpClient _httpClient;
    private readonly OpenAICurrentInformationOptions _options;
    private readonly TimeProvider _timeProvider;

    public OpenAICurrentInformationProvider(HttpClient httpClient, OpenAICurrentInformationOptions options, TimeProvider timeProvider)
    {
        _httpClient = httpClient;
        _options = options;
        _timeProvider = timeProvider;
    }

    public async Task<LiveProviderResult<LiveCurrentInformation>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow();
        if (!_options.Enabled)
        {
            return LiveProviderResult<LiveCurrentInformation>.Disabled(ProviderName, now);
        }

        if (string.IsNullOrWhiteSpace(_options.ApiKey) || string.IsNullOrWhiteSpace(_options.Model))
        {
            return LiveProviderResult<LiveCurrentInformation>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Current-information search is enabled but its server configuration is incomplete.");
        }

        if (string.IsNullOrWhiteSpace(query.ApproximateLocation.City) && string.IsNullOrWhiteSpace(query.ApproximateLocation.Region))
        {
            return new LiveProviderResult<LiveCurrentInformation>(ProviderName, true, true, Array.Empty<LiveCurrentInformation>(), now, now.AddMinutes(10), "Current-information search needs an approximate city or region; precise coordinates were not sent.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 3, 30)));
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        var tool = new Dictionary<string, object?>
        {
            ["type"] = "web_search",
            ["search_context_size"] = "low",
            ["user_location"] = new
            {
                type = "approximate",
                city = query.ApproximateLocation.City,
                region = query.ApproximateLocation.Region,
                country = query.ApproximateLocation.Country,
                timezone = query.ApproximateLocation.TimeZone
            }
        };
        if (_options.TrustedDomains.Count > 0)
        {
            tool["filters"] = new { allowed_domains = _options.TrustedDomains };
        }

        request.Content = JsonContent.Create(new Dictionary<string, object?>
        {
            ["model"] = _options.Model,
            ["store"] = false,
            ["tools"] = new[] { tool },
            ["input"] = BuildPrompt(query),
            ["max_output_tokens"] = 350
        });

        try
        {
            using var response = await _httpClient.SendAsync(request, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                return LiveProviderResult<LiveCurrentInformation>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Current-information search did not return a result.");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
            var (text, citations) = Parse(document.RootElement, now);
            var items = string.IsNullOrWhiteSpace(text) || citations.Count == 0
                ? Array.Empty<LiveCurrentInformation>()
                : new[]
                {
                    new LiveCurrentInformation(
                        $"current-{now:yyyyMMddHHmm}",
                        text.Trim(),
                        "CurrentLocalInformation",
                        query.ForRouteStory ? LiveAutomaticSpeechPolicy.Actionable : LiveAutomaticSpeechPolicy.UserRequestedOnly,
                        citations)
                };
            var warning = items.Length == 0 ? "No cited current local information was available." : null;
            return new LiveProviderResult<LiveCurrentInformation>(ProviderName, true, true, items, now, now.AddMinutes(30), warning);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        {
            return LiveProviderResult<LiveCurrentInformation>.Failed(ProviderName, now, TimeSpan.FromMinutes(2), "Current-information search is temporarily unavailable.");
        }
    }

    private static string BuildPrompt(LiveContextQuery query)
    {
        var place = string.Join(", ", new[] { query.ApproximateLocation.City, query.ApproximateLocation.Region, query.ApproximateLocation.Country }.Where(value => !string.IsNullOrWhiteSpace(value)));
        var interests = query.Interests.Count == 0 ? "general visitor information" : string.Join(", ", query.Interests);
        return $"Find up to three timely, useful, light local facts for a walking visitor in {place} between {query.JourneyStartsUtc:u} and {query.JourneyEndsUtc:u}. Interests: {interests}. Use trustworthy local or official sources and cite every claim. Exclude crime, politics, distressing incidents, and emergency news unless there is an immediate safety need. Do not invent events or details. Respond in under 120 words.";
    }

    private static (string Text, IReadOnlyList<LiveSourceReference> Citations) Parse(JsonElement root, DateTimeOffset retrievedUtc)
    {
        var text = root.TryGetProperty("output_text", out var outputText) ? outputText.GetString() : null;
        var citations = new List<LiveSourceReference>();
        if (!root.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array)
        {
            return (text ?? string.Empty, citations);
        }

        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array) continue;
            foreach (var part in content.EnumerateArray())
            {
                if (string.IsNullOrWhiteSpace(text) && part.TryGetProperty("text", out var partText)) text = partText.GetString();
                if (!part.TryGetProperty("annotations", out var annotations) || annotations.ValueKind != JsonValueKind.Array) continue;
                foreach (var annotation in annotations.EnumerateArray())
                {
                    if (!string.Equals(GoogleWeatherLiveProvider.Text(annotation, "type"), "url_citation", StringComparison.Ordinal)) continue;
                    var url = GoogleWeatherLiveProvider.Text(annotation, "url");
                    if (string.IsNullOrWhiteSpace(url) || citations.Any(citation => citation.Url == url)) continue;
                    citations.Add(new LiveSourceReference(
                        ProviderName,
                        null,
                        GoogleWeatherLiveProvider.Text(annotation, "title"),
                        url,
                        new Uri(url).Host,
                        retrievedUtc,
                        null,
                        retrievedUtc.AddMinutes(30)));
                }
            }
        }

        return (text ?? string.Empty, citations);
    }
}

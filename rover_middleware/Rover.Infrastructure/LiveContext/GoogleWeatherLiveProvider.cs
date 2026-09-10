using System.Globalization;
using System.Text.Json;
using Rover.Application.LiveContext;

namespace Rover.Infrastructure.LiveContext;

public sealed class GoogleWeatherLiveProvider : ILiveWeatherProvider
{
    private const string ProviderName = "Google Weather";
    private readonly HttpClient _httpClient;
    private readonly GoogleWeatherLiveOptions _options;
    private readonly TimeProvider _timeProvider;

    public GoogleWeatherLiveProvider(HttpClient httpClient, GoogleWeatherLiveOptions options, TimeProvider timeProvider)
    {
        _httpClient = httpClient;
        _options = options;
        _timeProvider = timeProvider;
    }

    public async Task<(LiveProviderResult<LiveWeatherCondition> Conditions, LiveProviderResult<LiveWeatherAlert> Alerts)> GetAsync(
        LiveContextQuery query,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow();
        if (!_options.Enabled)
        {
            return (
                LiveProviderResult<LiveWeatherCondition>.Disabled(ProviderName, now),
                LiveProviderResult<LiveWeatherAlert>.Disabled(ProviderName, now));
        }

        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            return (
                LiveProviderResult<LiveWeatherCondition>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Google Weather is enabled but its server key is missing."),
                LiveProviderResult<LiveWeatherAlert>.Failed(ProviderName, now, TimeSpan.FromMinutes(5), "Google Weather is enabled but its server key is missing."));
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 2, 30)));
        var coordinateQuery = $"key={Uri.EscapeDataString(_options.ApiKey)}&location.latitude={Format(query.Location.Latitude)}&location.longitude={Format(query.Location.Longitude)}";
        var currentTask = GetDocumentAsync($"https://weather.googleapis.com/v1/currentConditions:lookup?{coordinateQuery}&languageCode=en&unitsSystem=METRIC", timeout.Token);
        var forecastTask = GetDocumentAsync($"https://weather.googleapis.com/v1/forecast/hours:lookup?{coordinateQuery}&languageCode=en&unitsSystem=METRIC&hours={Math.Clamp(_options.ForecastHours, 1, 24)}&pageSize={Math.Clamp(_options.ForecastHours, 1, 24)}", timeout.Token);
        var alertTask = GetDocumentAsync($"https://weather.googleapis.com/v1/publicAlerts:lookup?{coordinateQuery}&languageCode=en", timeout.Token);
        await Task.WhenAll(currentTask, forecastTask, alertTask);

        var current = await currentTask;
        var forecast = await forecastTask;
        var alerts = await alertTask;
        var conditionItems = current is null ? Array.Empty<LiveWeatherCondition>() : ParseConditions(current.RootElement, forecast?.RootElement, now);
        var alertItems = alerts is null ? Array.Empty<LiveWeatherAlert>() : ParseAlerts(alerts.RootElement, now);
        current?.Dispose();
        forecast?.Dispose();
        alerts?.Dispose();
        var expires = now.AddMinutes(15);
        return (
            new LiveProviderResult<LiveWeatherCondition>(ProviderName, true, current is not null, conditionItems, now, expires, current is null ? "Current weather could not be retrieved." : null),
            new LiveProviderResult<LiveWeatherAlert>(ProviderName, true, alerts is not null, alertItems, now, now.AddMinutes(10), alerts is null ? "Weather alerts could not be retrieved." : null));
    }

    private async Task<JsonDocument?> GetDocumentAsync(string uri, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync(uri, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        {
            return null;
        }
    }

    private static LiveWeatherCondition[] ParseConditions(JsonElement root, JsonElement? forecastRoot, DateTimeOffset retrievedUtc)
    {
        var condition = Text(root, "weatherCondition", "description", "text") ?? Text(root, "weatherCondition", "type") ?? "Current conditions";
        var temperature = Number(root, "temperature", "degrees");
        var feelsLike = Number(root, "feelsLikeTemperature", "degrees");
        var precipitation = Number(root, "precipitation", "probability", "percent");
        var wind = Number(root, "wind", "speed", "value");
        var windDirection = Text(root, "wind", "direction", "cardinal");
        var observed = Date(root, "currentTime") ?? retrievedUtc;
        var meaningful = false;
        if (forecastRoot is JsonElement forecast && forecast.TryGetProperty("forecastHours", out var hours) && hours.ValueKind == JsonValueKind.Array)
        {
            foreach (var hour in hours.EnumerateArray().Take(3))
            {
                var forecastCondition = Text(hour, "weatherCondition", "type");
                var forecastTemperature = Number(hour, "temperature", "degrees");
                var forecastPrecipitation = Number(hour, "precipitation", "probability", "percent");
                var forecastWind = Number(hour, "wind", "speed", "value");
                meaningful |= forecastPrecipitation >= 40
                    || forecastWind >= 35
                    || (temperature.HasValue && forecastTemperature.HasValue && Math.Abs(temperature.Value - forecastTemperature.Value) >= 5)
                    || (!string.IsNullOrWhiteSpace(forecastCondition)
                        && !string.Equals(forecastCondition, Text(root, "weatherCondition", "type"), StringComparison.OrdinalIgnoreCase));
            }
        }

        var source = new LiveSourceReference(ProviderName, null, "Google Weather", "https://weather.google.com/", "Google Weather", retrievedUtc, observed, retrievedUtc.AddMinutes(15));
        return [new LiveWeatherCondition(
            condition,
            temperature,
            feelsLike,
            precipitation,
            wind,
            windDirection,
            observed,
            meaningful,
            meaningful ? LiveAutomaticSpeechPolicy.Actionable : LiveAutomaticSpeechPolicy.UserRequestedOnly,
            source)];
    }

    private static LiveWeatherAlert[] ParseAlerts(JsonElement root, DateTimeOffset retrievedUtc)
    {
        if (!root.TryGetProperty("weatherAlerts", out var alerts) || alerts.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<LiveWeatherAlert>();
        }

        return alerts.EnumerateArray().Select(alert =>
        {
            var starts = Date(alert, "startTime");
            var ends = Date(alert, "expirationTime");
            var sourceName = Text(alert, "dataSource", "publisher") ?? Text(alert, "dataSource", "name") ?? "Public weather authority";
            var sourceUrl = Text(alert, "dataSource", "uri") ?? Text(alert, "dataSource", "url");
            return new LiveWeatherAlert(
                Text(alert, "alertId") ?? Guid.NewGuid().ToString("N"),
                Text(alert, "alertTitle", "text") ?? Text(alert, "eventType") ?? "Weather alert",
                Text(alert, "description") ?? Text(alert, "instruction") ?? "An active public weather alert applies to this area.",
                Text(alert, "severity"),
                starts,
                ends,
                LiveAutomaticSpeechPolicy.Actionable,
                new LiveSourceReference(ProviderName, Text(alert, "alertId"), sourceName, sourceUrl, sourceName, retrievedUtc, starts, ends ?? retrievedUtc.AddMinutes(30)));
        }).ToArray();
    }

    private static string Format(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);

    internal static string? Text(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (current.ValueKind != JsonValueKind.Object || !current.TryGetProperty(part, out current)) return null;
        }
        return current.ValueKind == JsonValueKind.String ? current.GetString() : null;
    }

    internal static double? Number(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (current.ValueKind != JsonValueKind.Object || !current.TryGetProperty(part, out current)) return null;
        }
        return current.TryGetDouble(out var value) ? value : null;
    }

    internal static DateTimeOffset? Date(JsonElement root, params string[] path) =>
        DateTimeOffset.TryParse(Text(root, path), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value) ? value : null;
}

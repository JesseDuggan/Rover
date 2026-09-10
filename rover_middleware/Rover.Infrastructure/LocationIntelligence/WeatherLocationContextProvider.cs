using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class WeatherLocationContextProvider : LocationContextProviderBase
{
    private readonly IHttpClientFactory _httpClientFactory;

    public WeatherLocationContextProvider(IHttpClientFactory httpClientFactory, ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "Weather";

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(Options.AccessToken))
        {
            var source = Source("local-time", null, "Rover local time", null, 0.7);
            var context = new WeatherTimeContext($"Local walk time is {Now.LocalDateTime:h:mm tt}.", null, null, Now, source);
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), context, Array.Empty<string>(), false, 0);
        }

        var client = _httpClientFactory.CreateClient("Weather");
        var endpoint = Options.Endpoint ?? "https://api.openweathermap.org/data/4.0/onecall/current";
        var url = $"{endpoint}?lat={query.UserLocation.Latitude}&lon={query.UserLocation.Longitude}&appid={Uri.EscapeDataString(Options.AccessToken)}&units=metric";
        using var document = await client.GetFromJsonAsync<JsonDocument>(url, cancellationToken);
        if (document is null || !document.RootElement.TryGetProperty("current", out var current))
        {
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { "Weather provider returned no current weather." }, false, 0);
        }

        var temp = current.TryGetProperty("temp", out var tempElement) ? $"{Math.Round(tempElement.GetDouble())} C" : null;
        var conditions = current.TryGetProperty("weather", out var weather)
            && weather.ValueKind == JsonValueKind.Array
            && weather.GetArrayLength() > 0
            && weather[0].TryGetProperty("description", out var description)
                ? description.GetString()
                : null;
        var sourceRef = Source("current", "https://openweathermap.org/", "OpenWeather", "OpenWeather terms", 0.72);
        var summary = string.IsNullOrWhiteSpace(conditions) ? $"Current temperature is {temp}." : $"Current weather is {conditions}, {temp}.";
        return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), new WeatherTimeContext(summary, temp, conditions, Now, sourceRef), Array.Empty<string>(), false, 0);
    }
}

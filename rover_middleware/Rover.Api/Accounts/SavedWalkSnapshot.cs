using System.Text.Json;
using Rover.Api.Contracts;
using Rover.Domain.Walks;

namespace Rover.Api.Accounts;

public static class SavedWalkSnapshot
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static WalkSessionResponse Validate(JsonElement data)
    {
        if (!data.TryGetProperty("walk", out var raw)) throw new ArgumentException("Missing walk.");
        var walk = raw.Deserialize<WalkSessionResponse>(Json) ?? throw new ArgumentException("Missing walk.");
        if (walk.Route is null || walk.Route.Coordinates is null || walk.Route.Coordinates.Count is < 2 or > 30000 ||
            walk.Stops is null || walk.Stops.Count is < 1 or > 100 || walk.Interests is null || walk.AccessibilityPreferences is null ||
            walk.AvailableMinutes is < 1 or > 1440 || walk.EstimatedDurationMinutes is < 0 or > 2880 ||
            walk.EstimatedDistanceMeters is < 0 or > 200000 || walk.Route.DistanceMeters is < 0 or > 200000 ||
            walk.Route.DurationMinutes is < 0 or > 2880 || walk.StartingLocation is null ||
            walk.Route.Maneuvers is null || walk.Route.Maneuvers.Count > 3000 || walk.Route.Bounds is null ||
            walk.Route.Bounds.Southwest is null || walk.Route.Bounds.Northeast is null ||
            walk.RouteSummary is null || walk.RouteSummary.Length > 10000 || walk.Interests.Count > 30 ||
            walk.Interests.Any(x => string.IsNullOrWhiteSpace(x) || x.Length > 80) ||
            !ValidEnum<WalkingPace>(walk.WalkingPace) ||
            walk.AccessibilityPreferences.Any(x => !ValidEnum<AccessibilityPreference>(x)))
            throw new ArgumentException("Invalid route snapshot.");
        CheckLocation(walk.StartingLocation.Latitude, walk.StartingLocation.Longitude);
        CheckLocation(walk.Route.Bounds.Southwest.Latitude, walk.Route.Bounds.Southwest.Longitude);
        CheckLocation(walk.Route.Bounds.Northeast.Latitude, walk.Route.Bounds.Northeast.Longitude);
        foreach (var point in walk.Route.Coordinates)
        {
            if (point is null) throw new ArgumentException("Invalid route point.");
            CheckLocation(point.Latitude, point.Longitude);
        }
        foreach (var maneuver in walk.Route.Maneuvers)
        {
            if (maneuver is null || maneuver.Instruction is null || maneuver.Instruction.Length > 2000 ||
                maneuver.DistanceMeters is < 0 or > 200000 || maneuver.DurationMinutes is < 0 or > 2880)
                throw new ArgumentException("Invalid maneuver.");
            if (maneuver.Location is not null) CheckLocation(maneuver.Location.Latitude, maneuver.Location.Longitude);
        }
        foreach (var stop in walk.Stops)
        {
            if (stop is null) throw new ArgumentException("Missing stop.");
            CheckLocation(stop.Latitude, stop.Longitude);
            if (string.IsNullOrWhiteSpace(stop.Name) || stop.Name.Length > 300 || stop.Narration is null || stop.Narration.Length > 30000 ||
                stop.ShortDescription is null || stop.RequiredAttribution is null || stop.EstimatedVisitMinutes is < 0 or > 1440 ||
                stop.DistanceFromPreviousStopMeters is < 0 or > 200000 || stop.ArrivalRadiusMeters is < 1 or > 1000 ||
                !ValidEnum<ContentType>(stop.ContentType) || !ValidEnum<ContentSource>(stop.ContentSource))
                throw new ArgumentException("Invalid stop.");
        }
        if (data.TryGetProperty("stories", out var stories) && stories.ValueKind != JsonValueKind.Null)
        {
            var pack = stories.Deserialize<Rover.Application.Journeys.AdaptiveRouteStoryPack>(Json);
            if (pack?.Stories is null || pack.Stories.Count > 100 || pack.Stories.Any(s => s is null ||
                s.Title is null || s.Sources is null || s.Variants is null || s.Sources.Any(x => x is null) ||
                s.Variants.Any(v => v is null || v.Narration is null)))
                throw new ArgumentException("Invalid archived stories.");
        }
        return walk;
    }

    private static bool ValidEnum<T>(string value) where T : struct, Enum => Enum.TryParse<T>(value, out var parsed) && Enum.IsDefined(parsed);

    private static void CheckLocation(double lat, double lng)
    {
        if (!double.IsFinite(lat) || !double.IsFinite(lng) || lat is < -90 or > 90 || lng is < -180 or > 180)
            throw new ArgumentException("Invalid coordinates.");
    }

    // A saved route is a template, never a resumable server session. Reset every arrival and playback lifecycle.
    public static WalkSession Restore(JsonElement data)
    {
        var saved = Validate(data);
        var source = saved.Route!;
        var route = new WalkRoute(Guid.NewGuid().ToString("N"), source.Provider, source.Version, DateTimeOffset.UtcNow,
            source.Coordinates.Select(p => new GeoLocation(p.Latitude, p.Longitude)).ToArray(),
            new RouteBounds(new(source.Bounds.Southwest.Latitude, source.Bounds.Southwest.Longitude), new(source.Bounds.Northeast.Latitude, source.Bounds.Northeast.Longitude)),
            source.DistanceMeters, source.DurationMinutes,
            source.Maneuvers.Select(m => new WalkRouteManeuver(m.SequenceNumber, m.Instruction, m.DistanceMeters, m.DurationMinutes,
                m.ManeuverType, m.Location is null ? null : new(m.Location.Latitude, m.Location.Longitude))).ToArray());
        return new WalkSession(Guid.NewGuid().ToString("N"), new(saved.StartingLocation.Latitude, saved.StartingLocation.Longitude),
            DateTimeOffset.UtcNow, saved.AvailableMinutes, saved.EstimatedDurationMinutes, saved.EstimatedDistanceMeters,
            saved.RouteSummary, saved.Interests, Enum.Parse<WalkingPace>(saved.WalkingPace),
            saved.AccessibilityPreferences.Select(Enum.Parse<AccessibilityPreference>).ToArray(),
            saved.Stops.Select((s, i) => new WalkStop(Guid.NewGuid().ToString("N"), i + 1, s.Name, new(s.Latitude, s.Longitude),
                s.ShortDescription, s.Narration, s.Category, Enum.Parse<ContentType>(s.ContentType), Enum.Parse<ContentSource>(s.ContentSource),
                s.EstimatedVisitMinutes, s.DistanceFromPreviousStopMeters, s.ArrivalRadiusMeters, s.SponsoredDisclosure, s.Address,
                s.WebsiteUrl, s.PhoneNumber, s.MenuUrl, s.DiscoveryProviderName, s.ProviderPlaceId, s.SourceUrl, s.RequiredAttribution)
                { IsDestination = s.IsDestination }), route);
    }
}

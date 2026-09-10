using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Rover.Application.LiveContext;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public static class RouteStoryLiveComposer
{
    public static IReadOnlyList<AdaptiveRouteStory> Compose(
        LiveJourneyContext context, IReadOnlyList<RouteStorySegment> segments, DateTimeOffset now)
    {
        var stories = new List<AdaptiveRouteStory>();
        if (segments.Count == 0 || context.ExpiresUtc <= now) return stories;
        if (context.Events.Enabled && context.Events.Succeeded && context.Events.ExpiresUtc > now)
        {
            foreach (var item in context.Events.Items.DistinctBy(item => item.EventId).Take(10))
            {
                if (item.AutomaticSpeechPolicy != LiveAutomaticSpeechPolicy.Actionable
                    || !Fresh(item.Source, now) || item.Latitude is not { } lat || item.Longitude is not { } lon
                    || !double.IsFinite(lat) || !double.IsFinite(lon) || Math.Abs(lat) > 90 || Math.Abs(lon) > 180
                    || item.StartsUtc < now || item.EndsUtc <= now || string.IsNullOrWhiteSpace(item.Name)) continue;
                var location = new GeoLocation(lat, lon);
                var segment = segments.OrderBy(segment => RouteMath.DistanceMeters(segment.Anchor, location)).First();
                if (RouteMath.DistanceMeters(segment.Anchor, location) > 1000) continue;
                var date = item.StartsUtc.ToUniversalTime().ToString("MMMM d, yyyy 'at' HH:mm 'UTC'", CultureInfo.InvariantCulture);
                var text = $"Nearby, {item.Name} is scheduled for {date}"
                    + (string.IsNullOrWhiteSpace(item.VenueName) ? "." : $" at {item.VenueName}.");
                stories.Add(Create($"event:{item.EventId}", item.Name, "local events", text, segment,
                    new[] { item.Source }, new[] { item.Source.ExpiresUtc, context.Events.ExpiresUtc, item.StartsUtc }.Min()));
                if (stories.Count == 2) break;
            }
        }
        if (context.CurrentInformation.Enabled && context.CurrentInformation.Succeeded && context.CurrentInformation.ExpiresUtc > now)
        {
            var item = context.CurrentInformation.Items.FirstOrDefault(item =>
                item.AutomaticSpeechPolicy == LiveAutomaticSpeechPolicy.Actionable
                && !string.IsNullOrWhiteSpace(item.Summary) && item.Sources.Count > 0
                && item.Sources.All(source => Fresh(source, now)));
            if (item is not null)
            {
                var checkedDate = item.Sources.Min(source => source.RetrievedUtc).ToString("MMMM d, yyyy", CultureInfo.InvariantCulture);
                stories.Add(Create($"current:{item.InformationId}", "Around the area now", "current local information",
                    $"Local information checked on {checkedDate}. {item.Summary.Trim()}", segments[0], item.Sources,
                    item.Sources.Select(source => source.ExpiresUtc).Append(context.CurrentInformation.ExpiresUtc).Min()));
            }
        }
        return stories;
    }

    private static bool Fresh(LiveSourceReference source, DateTimeOffset now) =>
        source.ExpiresUtc > now && source.RetrievedUtc <= now && source.RetrievedUtc >= now.AddHours(-1)
        && (source.SourceUpdatedUtc is null || source.SourceUpdatedUtc <= now)
        && Uri.TryCreate(source.Url, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https";

    private static AdaptiveRouteStory Create(string id, string title, string category, string text,
        RouteStorySegment segment, IReadOnlyList<LiveSourceReference> references, DateTimeOffset expires)
    {
        var sources = references.DistinctBy(source => source.Url).Select(source => new AdaptiveStorySource(
            Hash(source.Url!), source.ProviderName, source.Title, source.Url, source.Attribution, source.RetrievedUtc, 0.85)).ToArray();
        var claim = new AdaptiveStoryClaim(Hash(id + text), text, sources.Select(source => source.SourceId).ToArray(), 0.85);
        var duration = Math.Max(1, (int)Math.Ceiling(text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length / 2.5d));
        return new AdaptiveRouteStory($"live-{Hash(id + text)}", segment.SegmentId, id, title,
            RouteStoryIntent.GeneralLocationQuestion, category, segment.Anchor,
            segment.StartRouteMeters, segment.EndRouteMeters,
            new[] { new AdaptiveNarrationVariant(AdaptiveStoryLength.Standard, duration, text, new[] { claim.ClaimId }) },
            new[] { claim }, sources, 0.85, expires);
    }

    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)))[..20].ToLowerInvariant();
}

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Rover.Application.Journeys;

namespace Rover.Api.Usage;

public static class InspectionDetails
{
    public static string StoryKey(string? id) => string.IsNullOrWhiteSpace(id) ? "" :
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id)))[..16].ToLowerInvariant();
    static string Clip(string? s, int max) => (s ?? "")[..Math.Min(s?.Length ?? 0, max)];
    public static string? Source(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            uri.UserInfo.Length > 0 || uri.IsLoopback || uri.HostNameType != UriHostNameType.Dns ||
            !uri.Host.Contains('.') || uri.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)) return null;
        // Strip query/fragment: these may contain tracking IDs or credentials. Original source is in the story.
        return Clip(uri.GetLeftPart(UriPartial.Path), 1200);
    }
    public static UsageEvent Event(UsageScope scope, StoryInspectionEvent item) =>
        scope.Event("Story inspection", "Walkabout", Clip(item.Stage,80), Clip(item.Outcome,100)) with {
            Details = JsonSerializer.Serialize(new {
                story = StoryKey(item.StoryId), title = Clip(item.Title,200),
                reason = Clip(item.Reason,1500), narration = Clip(item.Narration,6000),
                depth = Clip(item.Depth,30), policy = StoryPreparationPolicy.Version,
                sources = (item.Sources ?? []).Take(16).Select(Source).Where(s=>s is not null).Distinct().ToArray()
            })
        };
}

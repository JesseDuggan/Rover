namespace Rover.Application.Journeys;

// Explicit observable decisions only: never model reasoning, prompts, user questions or GPS traces.
public sealed record StoryInspectionEvent(string Stage, string Outcome, string Reason,
    string? StoryId = null, string? Title = null, string? Narration = null,
    IReadOnlyList<string>? Sources = null, string? Depth = null);

public static class StoryInspection
{
    public static readonly AsyncLocal<Action<StoryInspectionEvent>?> Listener = new();
    public static void Record(string stage, string outcome, string reason, string? storyId = null,
        string? title = null, string? narration = null, IReadOnlyList<string>? sources = null, string? depth = null)
    {
        // Diagnostics must never break a journey.
        try { Listener.Value?.Invoke(new(stage, outcome, reason, storyId, title, narration, sources, depth)); }
        catch { }
    }
    public static void Story(AdaptiveRouteStory story, string stage)
        => Record(stage, story.CanAutoplay ? "Eligible" : "Not eligible for autoplay",
            $"{story.Claims.Count} claims; {story.Sources.Count} sources; category {story.Category}; audience {story.AudienceSuitability}. Source links support the story as a whole; sentence-level verification is not independently measured.",
            story.StoryId, story.Title,
            story.Variants.OrderByDescending(v => v.EstimatedDurationSeconds).FirstOrDefault()?.Narration,
            story.Sources.Select(s => s.Url).OfType<string>().ToArray(), story.ResearchDepth);
}

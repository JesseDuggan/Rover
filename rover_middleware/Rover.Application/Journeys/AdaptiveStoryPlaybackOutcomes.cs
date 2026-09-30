namespace Rover.Application.Journeys;

/// <summary>
/// Explicit reported outcomes within a route pack, not a permanent event journal.
/// A story can have multiple outcomes across attempts; retries do not inflate counts.
/// </summary>
public sealed record AdaptiveStoryPlaybackOutcomes
{
    public IReadOnlySet<string> CompletedStoryIds { get; init; } = new HashSet<string>();
    public IReadOnlySet<string> SkippedStoryIds { get; init; } = new HashSet<string>();
    public IReadOnlySet<string> DismissedStoryIds { get; init; } = new HashSet<string>();
    public IReadOnlySet<string> InterruptedStoryIds { get; init; } = new HashSet<string>();
    public IReadOnlySet<string> FailedStoryIds { get; init; } = new HashSet<string>();

    public AdaptiveStoryPlaybackOutcomes Merge(AdaptiveStoryPlaybackOutcomes other) => new()
    {
        CompletedStoryIds = CompletedStoryIds.Concat(other.CompletedStoryIds).ToHashSet(StringComparer.OrdinalIgnoreCase),
        SkippedStoryIds = SkippedStoryIds.Concat(other.SkippedStoryIds).ToHashSet(StringComparer.OrdinalIgnoreCase),
        DismissedStoryIds = DismissedStoryIds.Concat(other.DismissedStoryIds).ToHashSet(StringComparer.OrdinalIgnoreCase),
        InterruptedStoryIds = InterruptedStoryIds.Concat(other.InterruptedStoryIds).ToHashSet(StringComparer.OrdinalIgnoreCase),
        FailedStoryIds = FailedStoryIds.Concat(other.FailedStoryIds).ToHashSet(StringComparer.OrdinalIgnoreCase)
    };

    public AdaptiveStoryPlaybackOutcomes Record(AdaptiveStoryPlaybackEvent playbackEvent) => playbackEvent.Kind switch
    {
        AdaptiveStoryPlaybackEventKind.Completed => this with { CompletedStoryIds = Add(CompletedStoryIds, playbackEvent.StoryId) },
        AdaptiveStoryPlaybackEventKind.Skipped => this with { SkippedStoryIds = Add(SkippedStoryIds, playbackEvent.StoryId) },
        AdaptiveStoryPlaybackEventKind.Dismissed => this with { DismissedStoryIds = Add(DismissedStoryIds, playbackEvent.StoryId) },
        AdaptiveStoryPlaybackEventKind.Interrupted => this with { InterruptedStoryIds = Add(InterruptedStoryIds, playbackEvent.StoryId) },
        AdaptiveStoryPlaybackEventKind.Failed => this with { FailedStoryIds = Add(FailedStoryIds, playbackEvent.StoryId) },
        _ => this
    };

    private static IReadOnlySet<string> Add(IReadOnlySet<string> values, string storyId)
    {
        var updated = values.ToHashSet(StringComparer.OrdinalIgnoreCase);
        updated.Add(storyId);
        return updated;
    }
}

using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public sealed record JourneyArea(double Latitude, double Longitude);
public sealed record JourneySection(int Sequence, JourneyArea Area, double StartRouteMeters,
    double EndRouteMeters, int WalkingSeconds);
public sealed record JourneyBrief(JourneyArea StartArea, JourneyArea EndArea, bool ReturnsToStart,
    int AvailableMinutes, int WalkingMinutes, string Pace, IReadOnlyList<JourneySection> Sections,
    IReadOnlyList<string> CoveredTopics);
public sealed record JourneyChapter(string StoryId, int Sequence, string Theme, string SegmentId);
public sealed record JourneyCollection(string Title, int NarrationSeconds, int WalkingSeconds,
    IReadOnlyList<JourneyChapter> Chapters, IReadOnlyList<string> UncoveredSegmentIds);

public static class JourneyCollectionBuilder
{
    // Coarse areas, not raw traces or precise private endpoints, leave the server.
    public static JourneyArea Area(GeoLocation point) => new(Math.Round(point.Latitude, 2), Math.Round(point.Longitude, 2));

    public static JourneyBrief Brief(WalkSession session, RouteStoryPlan plan, IReadOnlyList<AdaptiveRouteStory> existing)
    {
        var ordered = plan.Segments.OrderBy(segment => segment.SequenceNumber).ToArray();
        var route = session.Route.Coordinates;
        var start = route[0];
        var end = route[^1];
        // Group contiguous sections so long routes retain their endpoint and full time budget.
        var groupSize = Math.Max(1, (int)Math.Ceiling(ordered.Length / 12d));
        var sections = ordered.Chunk(groupSize).Select((group, index) => new JourneySection(
            index + 1, Area(group[group.Length / 2].Anchor), group[0].StartRouteMeters,
            group[^1].EndRouteMeters, group.Sum(segment => segment.EstimatedDurationSeconds))).ToArray();
        return new(Area(start), Area(end), WalkDistance(start, end) <= 50,
            session.AvailableMinutes, session.Route.DurationMinutes, session.WalkingPace.ToString(), sections,
            existing.Take(20).Select(story => story.Title[..Math.Min(story.Title.Length, 120)]).ToArray());
    }

    public static JourneyCollection Describe(RouteStoryPlan plan, IReadOnlyList<AdaptiveRouteStory> stories)
    {
        var chapters = stories.OrderBy(story => story.OpensAtRouteMeters).ThenBy(story => story.StoryId)
            .Select((story, index) => new JourneyChapter(story.StoryId, index + 1, story.Category, story.SegmentId)).ToArray();
        var covered = stories.Select(story => story.SegmentId).ToHashSet(StringComparer.Ordinal);
        return new("Stories along your walk",
            stories.Sum(story => story.Variants.Select(variant => variant.EstimatedDurationSeconds).DefaultIfEmpty(0).Max()),
            plan.Segments.Sum(segment => segment.EstimatedDurationSeconds), chapters,
            plan.Segments.Where(segment => !covered.Contains(segment.SegmentId)).Select(segment => segment.SegmentId).ToArray());
    }

    private static double WalkDistance(GeoLocation start, GeoLocation end) =>
        Rover.Application.Walks.RouteMath.DistanceMeters(start, end);
}

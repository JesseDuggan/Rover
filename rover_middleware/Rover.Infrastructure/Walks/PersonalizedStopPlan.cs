using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Application.Journeys;

namespace Rover.Infrastructure.Walks;

public static class PersonalizedStopPlan
{
    public static bool WasShown(CreateWalkCommand command, WalkStop stop) =>
        command.PreviousStopIds.Contains(stop.StopId) ||
        (stop.ProviderPlaceId is not null && command.PreviousStopIds.Contains(stop.ProviderPlaceId));

    public static WalkStop[] Select(CreateWalkCommand command, IEnumerable<WalkStop> candidates,
        IReadOnlyList<WalkStop> preferred, int limit)
    {
        var remaining = candidates.Where(s => WalkInterestPolicy.Allows(s, command.Interests))
            .DistinctBy(s => s.StopId).ToList();
        var selected = new List<WalkStop>();
        while (remaining.Count > 0 && selected.Count < limit)
        {
            var next = remaining.OrderBy(Cost).ThenBy(s => s.StopId, StringComparer.Ordinal).First();
            StoryInspection.Record("Candidate ranking", "Proposed", Explain(next), next.StopId, next.Name);
            selected.Add(next);
            remaining.Remove(next);
        }
        foreach (var candidate in remaining)
            StoryInspection.Record("Candidate ranking", "Outside stop limit", Explain(candidate), candidate.StopId, candidate.Name);
        return selected.ToArray();

        string Explain(WalkStop stop)
        {
            var distance = selected.Count == 0 ? RouteMath.DistanceMeters(command.StartingLocation, stop.Location)
                : selected.Min(s => RouteMath.DistanceMeters(s.Location, stop.Location));
            return $"Ranking cost: {Cost(stop):F0} (lower preferred). Nearest proposed stop/start: {distance:F0} m straight-line. " +
                $"Matched interests: {string.Join(", ", WalkInterestPolicy.MatchedInterests(stop, command.Interests))}. " +
                $"Same-category proposed stops: {selected.Count(s => WalkInterestPolicy.Group(s) == WalkInterestPolicy.Group(stop))}. " +
                $"Previously shown: {WasShown(command, stop)}. AI priority: {preferred.ToList().FindIndex(s => s.StopId == stop.StopId) + 1} (0 = not selected). Pedestrian time checked next.";
        }

        double Cost(WalkStop stop)
        {
            var distance = selected.Count == 0 ? RouteMath.DistanceMeters(command.StartingLocation, stop.Location)
                : selected.Min(s => RouteMath.DistanceMeters(s.Location, stop.Location));
            var repeats = selected.Count(s => WalkInterestPolicy.Group(s) == WalkInterestPolicy.Group(stop));
            var matched = WalkInterestPolicy.MatchedInterests(stop, command.Interests).Length > 0;
            var modelRank = preferred.ToList().FindIndex(s => s.StopId == stop.StopId);
            // Soft spacing penalties retain rural usability without stretching a city walk.
            return distance + Math.Max(0, distance - 650) * 2
                + (selected.Count > 0 && distance < 80 ? 250 : 0)
                + repeats * 500 + (matched ? 0 : 600)
                + (WasShown(command, stop) ? 1100 : 0)
                - (modelRank < 0 ? 0 : Math.Max(0, 700 - modelRank * 60));
        }
    }
}

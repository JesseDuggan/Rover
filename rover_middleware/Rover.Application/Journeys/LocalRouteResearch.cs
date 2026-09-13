using Rover.Application.LiveContext;

namespace Rover.Application.Journeys;

public sealed record LocalRouteResearchQuery(
    IReadOnlyList<RouteStorySegment> Segments,
    ApproximateLiveLocation Area,
    IReadOnlyList<string> PublicPlaceNames,
    IReadOnlyList<string> Interests,
    string Language);

public sealed record LocalRouteResearchResult(IReadOnlyList<AdaptiveRouteStory> Stories, string? Warning);

public interface ILocalRouteResearcher
{
    Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken);
}

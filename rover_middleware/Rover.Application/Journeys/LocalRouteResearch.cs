using Rover.Application.LiveContext;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public sealed record LocalRouteResearchQuery(
    IReadOnlyList<RouteStorySegment> Segments,
    ApproximateLiveLocation Area,
    IReadOnlyList<string> PublicPlaceNames,
    IReadOnlyList<string> Interests,
    string Language,
    IReadOnlyList<LocalResearchPublicPlace>? PublicPlaces = null,
    JourneyBrief? Journey = null);

public sealed record LocalResearchPublicPlace(string Name, string? Address, GeoLocation Location);

public sealed record LocalRouteResearchResult(IReadOnlyList<AdaptiveRouteStory> Stories, string? Warning);

public interface ILocalRouteResearcher
{
    Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken);
}

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
    JourneyBrief? Journey = null)
{
    public int? MaximumStories { get; init; }
    public string Audience { get; init; } = "GeneralTraveller";
    public StoryResearchQuestion? Question { get; init; }
    public bool AreaFirst { get; init; }
    public int SearchRadiusMeters { get; init; } = 1000;
    public IReadOnlyList<string> ExcludedStoryTitles { get; init; } = [];
    // Internal provider-built stories only; never included in model input.
    public IReadOnlyList<AdaptiveRouteStory> LibraryCandidates { get; init; } = [];
}

public sealed record LocalResearchPublicPlace(string Name, string? Address, GeoLocation Location);

public sealed record LocalRouteResearchResult(IReadOnlyList<AdaptiveRouteStory> Stories, string? Warning)
{
    public bool Failed { get; init; }
}

public interface ILocalRouteResearcher
{
    Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken);
}

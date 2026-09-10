namespace Rover.Application.LocationIntelligence;

public interface ICandidateObservationSearchProvider
{
    Task<CandidateObservationSearchResult> SearchAsync(
        CandidateObservationQuery query,
        CancellationToken cancellationToken);
}

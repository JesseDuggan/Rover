namespace Rover.Application.LocationIntelligence;

public interface ICandidateObservationResolutionService
{
    Task<CandidateObservationResolution> ResolveAsync(
        CandidateObservationQuery query,
        CancellationToken cancellationToken);
}

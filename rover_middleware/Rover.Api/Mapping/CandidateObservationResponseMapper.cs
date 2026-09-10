using Rover.Api.Contracts;
using Rover.Application.LocationIntelligence;

namespace Rover.Api.Mapping;

public static class CandidateObservationResponseMapper
{
    public static CandidateObservationResolutionResponse ToResponse(
        this CandidateObservationResolution resolution)
    {
        return new CandidateObservationResolutionResponse(
            resolution.Status.ToString(),
            resolution.SelectedPlaceId,
            resolution.Candidates.Select(candidate => new CandidateObservationMatchResponse(
                candidate.Place.ToResponse(),
                candidate.MatchConfidence,
                candidate.NameSimilarity,
                candidate.DistanceScore,
                candidate.HeadingScore,
                candidate.MatchReasons)).ToArray(),
            resolution.DiagnosticCode,
            resolution.Warnings);
    }
}

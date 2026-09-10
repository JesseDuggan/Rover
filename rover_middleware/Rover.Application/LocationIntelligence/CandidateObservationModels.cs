using Rover.Domain.Walks;

namespace Rover.Application.LocationIntelligence;

public enum CandidateObservationResolutionStatus
{
    Verified,
    Ambiguous,
    Unresolved
}

public sealed record CandidateObservationQuery(
    string RecognizedText,
    GeoLocation UserLocation,
    double? AccuracyMeters,
    double? HeadingDegrees,
    int RadiusMeters,
    string? RouteId,
    IReadOnlyCollection<string> NearbyPlaceIds);

public sealed record CandidateObservationSearchResult(
    string ProviderName,
    IReadOnlyList<LocationPlace> Places,
    IReadOnlyList<string> Warnings);

public sealed record CandidateObservationMatch(
    LocationPlace Place,
    double MatchConfidence,
    double NameSimilarity,
    double DistanceScore,
    double HeadingScore,
    IReadOnlyList<string> MatchReasons);

public sealed record CandidateObservationResolution(
    CandidateObservationResolutionStatus Status,
    string? SelectedPlaceId,
    IReadOnlyList<CandidateObservationMatch> Candidates,
    string DiagnosticCode,
    IReadOnlyList<string> Warnings);

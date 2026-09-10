namespace Rover.Api.Contracts;

public sealed record CandidateObservationResolveRequest(
    string? RecognizedText,
    double? Latitude,
    double? Longitude,
    double? AccuracyMeters,
    double? HeadingDegrees,
    int? RadiusMeters,
    string? RouteId,
    IReadOnlyList<string>? NearbyPlaceIds);

public sealed record CandidateObservationMatchResponse(
    LocationPlaceResponse Place,
    double MatchConfidence,
    double NameSimilarity,
    double DistanceScore,
    double HeadingScore,
    IReadOnlyList<string> MatchReasons);

public sealed record CandidateObservationResolutionResponse(
    string Status,
    string? SelectedPlaceId,
    IReadOnlyList<CandidateObservationMatchResponse> Candidates,
    string DiagnosticCode,
    IReadOnlyList<string> Warnings);

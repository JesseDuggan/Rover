namespace Rover.Api.Contracts;

public sealed record ProblemReportRequest(
    string? Category,
    string? Description,
    string? WalkSessionId,
    string? StopId,
    string? CorrelationId,
    string? AppVersion,
    string? BuildNumber,
    string? DeviceModel,
    string? OsVersion,
    string? ConnectivityState,
    bool? PreciseLocationAttached);

public sealed record ProblemReportResponse(
    string ProblemReportId,
    string Severity,
    DateTimeOffset ReceivedAtUtc,
    bool Queued);

public sealed record PostWalkFeedbackRequest(
    int? OverallRating,
    bool? DirectionsEasyToFollow,
    bool? StopsDetectedCorrectly,
    bool? NarrationEnjoyable,
    bool? AskRoverUseful,
    bool? WalkRightLength,
    bool? WouldTakeAnotherWalk,
    string? Comments,
    string? AppVersion,
    string? BuildNumber);

public sealed record PostWalkFeedbackResponse(
    string FeedbackId,
    string WalkSessionId,
    DateTimeOffset ReceivedAtUtc);

public sealed record CrashBreadcrumbRequest(
    string? Feature,
    string? Action,
    string? CorrelationId,
    string? SafeErrorCode,
    string? AppVersion,
    string? BuildNumber);

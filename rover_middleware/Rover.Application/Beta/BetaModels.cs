namespace Rover.Application.Beta;

public enum BetaIssueSeverity
{
    Critical,
    High,
    Medium,
    Low
}

public sealed record BetaConfigurationStatus(
    string EnvironmentName,
    string AppVersion,
    string BuildNumber,
    bool IsBeta,
    bool DevelopmentAuthenticationEnabled,
    bool DeveloperControlsEnabled,
    bool SimulationEnabled,
    bool RequiresHttpsEndpoints,
    bool SecretsConfiguredServerSide,
    bool MapboxConfigured,
    bool ElevenLabsConfigured,
    IReadOnlyList<string> Warnings);

public sealed record BetaDiagnosticsReport(
    string AppVersion,
    string BuildNumber,
    string ApiEnvironment,
    string ApiHealth,
    bool MapboxConfigured,
    bool ElevenLabsEnabled,
    bool ElevenLabsConfigured,
    string StorageMode,
    string RoutingMode,
    string DiscoveryMode,
    string LocalDiscoveryMode,
    string ConversationMode,
    long ApiRequestCount,
    long LocationUpdateCount,
    long RouteRecalculationCount,
    long DownloadedAudioBytes,
    long SpeechCacheHits,
    long SpeechCacheMisses,
    string? LastOperationName,
    long? LastOperationMilliseconds,
    string? LastSlowOperationName,
    long? LastSlowOperationMilliseconds,
    IReadOnlyList<string> SlowOperations,
    int BackgroundPendingCount,
    long BackgroundEnqueuedCount,
    long BackgroundCompletedCount,
    long BackgroundFailedCount,
    string? LastBackgroundWorkName,
    long? LastBackgroundWorkMilliseconds,
    string? LastBackgroundFailure,
    DateTimeOffset? LastSynchronizationUtc,
    string? LastSafeErrorCode);

public sealed record ProblemReportCommand(
    Guid? AccountId,
    string Category,
    string? Description,
    string? WalkSessionId,
    string? StopId,
    string? CorrelationId,
    string AppVersion,
    string BuildNumber,
    string DeviceModel,
    string OsVersion,
    string ConnectivityState,
    bool PreciseLocationAttached);

public sealed record ProblemReportReceipt(
    string ProblemReportId,
    BetaIssueSeverity Severity,
    DateTimeOffset ReceivedAtUtc,
    bool Queued);

public sealed record PostWalkFeedbackCommand(
    Guid? AccountId,
    string WalkSessionId,
    int OverallRating,
    bool? DirectionsEasyToFollow,
    bool? StopsDetectedCorrectly,
    bool? NarrationEnjoyable,
    bool? AskRoverUseful,
    bool? WalkRightLength,
    bool? WouldTakeAnotherWalk,
    string? Comments,
    string AppVersion,
    string BuildNumber);

public sealed record PostWalkFeedbackReceipt(
    string FeedbackId,
    string WalkSessionId,
    DateTimeOffset ReceivedAtUtc);

public sealed record CrashBreadcrumbCommand(
    string Feature,
    string Action,
    string? CorrelationId,
    string? SafeErrorCode,
    string AppVersion,
    string BuildNumber);

namespace Rover.Application.Beta;

public interface IBetaConfigurationService
{
    BetaConfigurationStatus GetStatus();
}

public interface IBetaDiagnosticsService
{
    BetaDiagnosticsReport GetReport();
    void RecordApiRequest();
    void RecordLocationUpdate();
    void RecordRouteRecalculation();
    void RecordAudioDownload(long bytes, bool cacheHit);
    void RecordOperation(string name, long elapsedMilliseconds, bool success);
    void RecordSynchronization(DateTimeOffset synchronizedAtUtc);
    void RecordSafeError(string safeErrorCode);
}

public interface IProblemReportService
{
    Task<ProblemReportReceipt> SubmitAsync(ProblemReportCommand command, CancellationToken cancellationToken);
}

public interface IPostWalkFeedbackService
{
    Task<PostWalkFeedbackReceipt> SubmitAsync(PostWalkFeedbackCommand command, CancellationToken cancellationToken);
    Task<bool> HasFeedbackAsync(string walkSessionId, CancellationToken cancellationToken);
}

public interface ICrashReportingService
{
    Task RecordBreadcrumbAsync(CrashBreadcrumbCommand command, CancellationToken cancellationToken);
}

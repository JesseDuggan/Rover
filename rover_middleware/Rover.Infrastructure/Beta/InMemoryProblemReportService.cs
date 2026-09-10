using Rover.Application.Beta;

namespace Rover.Infrastructure.Beta;

public sealed class InMemoryProblemReportService : IProblemReportService
{
    private readonly List<StoredProblemReport> _reports = new();
    private readonly TimeProvider _timeProvider;

    public InMemoryProblemReportService(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public Task<ProblemReportReceipt> SubmitAsync(ProblemReportCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var id = $"problem_{Guid.NewGuid():N}";
        var severity = SeverityFor(command.Category);
        var received = _timeProvider.GetUtcNow();
        var report = new StoredProblemReport(
            id,
            command with
            {
                Description = RedactionService.Redact(command.Description),
                DeviceModel = RedactionService.Redact(command.DeviceModel),
                OsVersion = RedactionService.Redact(command.OsVersion),
                ConnectivityState = RedactionService.Redact(command.ConnectivityState)
            },
            severity,
            received);
        lock (_reports)
        {
            _reports.Add(report);
        }

        return Task.FromResult(new ProblemReportReceipt(id, severity, received, false));
    }

    private static BetaIssueSeverity SeverityFor(string category)
    {
        return category.Trim().ToLowerInvariant() switch
        {
            "application crash or freeze" => BetaIssueSeverity.Critical,
            "login or account issue" => BetaIssueSeverity.High,
            "wrong directions" or "arrival not detected" => BetaIssueSeverity.High,
            "map issue" or "narration issue" or "ask rover issue" => BetaIssueSeverity.Medium,
            _ => BetaIssueSeverity.Low
        };
    }

    private sealed record StoredProblemReport(string Id, ProblemReportCommand Command, BetaIssueSeverity Severity, DateTimeOffset ReceivedAtUtc);
}

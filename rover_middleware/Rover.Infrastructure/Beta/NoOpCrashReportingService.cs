using Rover.Application.Beta;

namespace Rover.Infrastructure.Beta;

public sealed class NoOpCrashReportingService : ICrashReportingService
{
    private readonly List<CrashBreadcrumbCommand> _breadcrumbs = new();

    public Task RecordBreadcrumbAsync(CrashBreadcrumbCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_breadcrumbs)
        {
            _breadcrumbs.Add(command with
            {
                Feature = RedactionService.Redact(command.Feature),
                Action = RedactionService.Redact(command.Action),
                SafeErrorCode = RedactionService.Redact(command.SafeErrorCode)
            });
        }

        return Task.CompletedTask;
    }
}

using Microsoft.Extensions.Logging;
using Rover.Infrastructure.Journeys;

internal sealed class ResearchCaptureLogger : ILogger<OpenAILocalRouteResearcher>
{
    public List<(EventId EventId, string Message)> Entries { get; } = [];
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => true;
    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
        Func<TState, Exception?, string> formatter) => Entries.Add((eventId, formatter(state, exception)));
}

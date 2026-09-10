using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Conversation;

public sealed class AskRoverService : IAskRoverService
{
    private readonly IWalkSessionRepository _sessions;
    private readonly IRoverConversationProvider _provider;
    private readonly IConversationMemory _memory;
    private readonly TimeProvider _timeProvider;
    private readonly RoverConversationOptions _options;

    public AskRoverService(
        IWalkSessionRepository sessions,
        IRoverConversationProvider provider,
        IConversationMemory memory,
        TimeProvider timeProvider,
        RoverConversationOptions? options = null)
    {
        _sessions = sessions;
        _provider = provider;
        _memory = memory;
        _timeProvider = timeProvider;
        _options = options ?? new RoverConversationOptions();
    }

    public async Task<AskRoverResult> AskAsync(
        string walkSessionId,
        AskRoverCommand command,
        CancellationToken cancellationToken)
    {
        var session = await _sessions.GetByIdAsync(walkSessionId, cancellationToken)
            ?? throw new KeyNotFoundException($"Walk session '{walkSessionId}' was not found.");

        if (session.Status != WalkSessionStatus.InProgress)
        {
            throw new WalkLifecycleException("Ask Rover is available only while a walk is InProgress.");
        }

        var currentStop = ResolveCurrentStop(session, command.CurrentStopId);
        var conversationId = string.IsNullOrWhiteSpace(command.ConversationId)
            ? $"conv_{Guid.NewGuid():N}"
            : command.ConversationId.Trim();
        var recentTurns = _memory.GetRecentTurns(conversationId, _options.RecentTurnLimit);
        var context = BuildContext(session, command.CurrentLocation, currentStop, recentTurns);
        var answer = await _provider.AnswerAsync(context, command.QuestionText, cancellationToken);
        var createdAt = _timeProvider.GetUtcNow();
        var boundedAnswer = Bound(answer.AnswerText, _options.MaximumAnswerLength);
        var turn = new ConversationTurn(
            $"turn_{Guid.NewGuid():N}",
            command.QuestionText,
            boundedAnswer,
            createdAt);

        _memory.AddTurn(conversationId, turn, _options.RetainedTurnLimit);

        return new AskRoverResult(
            conversationId,
            turn.TurnId,
            boundedAnswer,
            createdAt,
            currentStop?.StopId,
            _provider.Name,
            ResolveSuggestedAction(command.QuestionText, answer.SuggestedAction),
            answer.SafetyNotice);
    }

    private static string ResolveSuggestedAction(string questionText, string? providerAction)
    {
        var question = questionText.Trim().ToLowerInvariant();
        if (question.Contains("quiet for ten minutes") || question.Contains("quiet for 10 minutes")) return "QuietStories";
        if (question.Contains("resume stories")) return "ResumeStories";
        if (question.Contains("tell me more stories like")) return "PreferSimilarStories";
        if (question.Contains("tell me more")) return "TellMore";
        if (question.Contains("short version")) return "ShortStory";
        if (question.Contains("more history")) return "PreferHistory";
        if (question.Contains("happening around here today") || question.Contains("around here today")) return "CurrentLocalInformation";
        if (question.Contains("fewer weather")) return "ReduceWeatherStories";
        if (question.Contains("don't tell me stories like") || question.Contains("do not tell me stories like")) return "DismissStoryCategory";
        if (question.StartsWith("skip this", StringComparison.Ordinal)) return "SkipStory";
        return string.IsNullOrWhiteSpace(providerAction) ? "Informational" : providerAction;
    }

    private RoverConversationContext BuildContext(
        WalkSession session,
        GeoLocation? currentLocation,
        WalkStop? currentStop,
        IReadOnlyList<ConversationTurn> recentTurns)
    {
        var visitedStops = session.Stops.Where(stop => stop.Visited).ToArray();
        var remainingStops = session.Stops.Where(stop => !stop.Visited).ToArray();

        return new RoverConversationContext(
            session.WalkSessionId,
            session.Status,
            currentLocation ?? session.LastKnownLocation,
            currentStop,
            session.NextStop,
            session.RouteSummary,
            session.TrackingState.EstimatedMinutesRemaining,
            session.Interests,
            session.WalkingPace,
            session.AccessibilityPreferences,
            visitedStops,
            remainingStops,
            currentStop?.Narration ?? string.Empty,
            recentTurns);
    }

    private static WalkStop? ResolveCurrentStop(WalkSession session, string? currentStopId)
    {
        if (string.IsNullOrWhiteSpace(currentStopId))
        {
            return session.NextStop;
        }

        var stop = session.Stops.FirstOrDefault(
            candidate => string.Equals(candidate.StopId, currentStopId, StringComparison.OrdinalIgnoreCase));
        if (stop is null)
        {
            throw new KeyNotFoundException($"Stop '{currentStopId}' was not found in this walk session.");
        }

        return stop;
    }

    private static string Bound(string value, int maximumLength)
    {
        var trimmed = value.Trim();
        if (trimmed.Length <= maximumLength)
        {
            return trimmed;
        }

        return trimmed[..maximumLength].TrimEnd() + "...";
    }
}

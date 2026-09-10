using System.Collections.Concurrent;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class InMemorySpeechUsageService : ISpeechUsageService
{
    private readonly ConcurrentDictionary<Guid, List<SpeechUsageEvent>> _events = new();
    private readonly ElevenLabsSpeechOptions _options;

    public InMemorySpeechUsageService(ElevenLabsSpeechOptions options)
    {
        _options = options;
    }

    public Task RecordAsync(SpeechUsageEvent usage, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var events = _events.GetOrAdd(usage.AccountId, _ => new List<SpeechUsageEvent>());
        lock (events)
        {
            events.Add(usage);
        }

        return Task.CompletedTask;
    }

    public Task<bool> CanRenderAsync(Guid accountId, SpeechPurpose purpose, int characterCount, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var today = DateTimeOffset.UtcNow.Date;
        var used = 0;
        if (_events.TryGetValue(accountId, out var events))
        {
            lock (events)
            {
                used = events
                    .Where(item => item.CreatedAtUtc.UtcDateTime.Date == today && item.Success)
                    .Sum(item => item.CharacterCount);
            }
        }

        return Task.FromResult(used + characterCount <= _options.DailyCharacterLimitPerUser);
    }
}

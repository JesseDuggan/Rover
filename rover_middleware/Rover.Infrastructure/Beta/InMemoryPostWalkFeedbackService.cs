using Rover.Application.Beta;

namespace Rover.Infrastructure.Beta;

public sealed class InMemoryPostWalkFeedbackService : IPostWalkFeedbackService
{
    private readonly Dictionary<string, PostWalkFeedbackReceipt> _feedbackByWalk = new(StringComparer.Ordinal);
    private readonly TimeProvider _timeProvider;

    public InMemoryPostWalkFeedbackService(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public Task<PostWalkFeedbackReceipt> SubmitAsync(PostWalkFeedbackCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (command.OverallRating is < 1 or > 5)
        {
            throw new ArgumentException("Overall rating must be between 1 and 5.");
        }

        lock (_feedbackByWalk)
        {
            if (_feedbackByWalk.TryGetValue(command.WalkSessionId, out var existing))
            {
                return Task.FromResult(existing);
            }

            var receipt = new PostWalkFeedbackReceipt($"feedback_{Guid.NewGuid():N}", command.WalkSessionId, _timeProvider.GetUtcNow());
            _feedbackByWalk[command.WalkSessionId] = receipt;
            return Task.FromResult(receipt);
        }
    }

    public Task<bool> HasFeedbackAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_feedbackByWalk)
        {
            return Task.FromResult(_feedbackByWalk.ContainsKey(walkSessionId));
        }
    }
}

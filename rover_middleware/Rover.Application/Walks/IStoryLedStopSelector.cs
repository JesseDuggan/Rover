using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record StoryLedSelection(IReadOnlyList<WalkStop> Stops, string Status);

public interface IStoryLedStopSelector
{
    bool Enabled { get; }
    Task<StoryLedSelection> SelectAsync(CreateWalkCommand command,
        IReadOnlyList<WalkStop> candidates, int maximumStops, CancellationToken cancellationToken);
}

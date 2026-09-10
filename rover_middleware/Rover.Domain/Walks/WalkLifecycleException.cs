namespace Rover.Domain.Walks;

public sealed class WalkLifecycleException : InvalidOperationException
{
    public WalkLifecycleException(string message)
        : base(message)
    {
    }
}

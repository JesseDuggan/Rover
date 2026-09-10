namespace Rover.Domain.Walks;

public enum WalkAdaptationType
{
    SkipStop,
    ShortenWalk,
    ExtendWalk,
    AddDiscovery,
    RejoinRoute,
    ReturnToStart,
    ContinueUnchanged
}

using Rover.Application.Adaptations;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Adaptations;

public class LocalNearbyDiscoveryProvider : INearbyDiscoveryProvider
{
    private readonly ILocalDiscoveryProvider _localDiscoveryProvider;

    public LocalNearbyDiscoveryProvider(ILocalDiscoveryProvider localDiscoveryProvider)
    {
        _localDiscoveryProvider = localDiscoveryProvider;
    }

    public Task<IReadOnlyList<NearbyDiscovery>> FindAsync(
        WalkSession session,
        GeoLocation currentLocation,
        string? interest,
        IReadOnlyCollection<string> dismissedDiscoveryIds,
        CancellationToken cancellationToken)
    {
        return FindCoreAsync(session, currentLocation, interest, dismissedDiscoveryIds, cancellationToken);
    }

    private async Task<IReadOnlyList<NearbyDiscovery>> FindCoreAsync(
        WalkSession session,
        GeoLocation currentLocation,
        string? interest,
        IReadOnlyCollection<string> dismissedDiscoveryIds,
        CancellationToken cancellationToken)
    {
        var explicitInterest = string.IsNullOrWhiteSpace(interest) ? null : interest.Trim();
        var interests = explicitInterest is null
            ? session.Interests
            : new[] { explicitInterest }.Concat(session.Interests).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var createWalkCommand = new CreateWalkCommand(
            currentLocation,
            Math.Max(15, session.AvailableMinutes),
            interests,
            session.WalkingPace,
            session.AccessibilityPreferences);
        var dismissed = dismissedDiscoveryIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var existing = session.Stops.Select(stop => stop.StopId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var stops = await _localDiscoveryProvider.FindCandidateStopsAsync(createWalkCommand, cancellationToken);

        return stops
            .Where(stop => !dismissed.Contains(stop.StopId))
            .Where(stop => !existing.Contains(stop.StopId))
            .Select(stop =>
            {
                var distance = (int)Math.Round(RouteMath.DistanceMeters(currentLocation, stop.Location));
                return new NearbyDiscovery(
                    stop.StopId,
                    stop.Name,
                    stop.Category,
                    stop.Location,
                    stop.Narration,
                    Math.Max(1, (int)Math.Ceiling(distance / 80d)),
                    distance,
                    stop.EstimatedVisitMinutes,
                    stop.ContentSource,
                    stop.SponsoredDisclosure,
                    null,
                    new[] { stop.Category, explicitInterest ?? string.Empty }.Where(value => !string.IsNullOrWhiteSpace(value)).ToArray(),
                    stop.Address,
                    stop.WebsiteUrl,
                    stop.PhoneNumber,
                    stop.MenuUrl,
                    stop.DiscoveryProviderName,
                    stop.ProviderPlaceId,
                    stop.SourceUrl,
                    stop.RequiredAttribution);
            })
            .ToArray();
    }
}

public sealed class MapboxNearbyDiscoveryProvider : LocalNearbyDiscoveryProvider
{
    public MapboxNearbyDiscoveryProvider(ILocalDiscoveryProvider localDiscoveryProvider)
        : base(localDiscoveryProvider)
    {
    }
}

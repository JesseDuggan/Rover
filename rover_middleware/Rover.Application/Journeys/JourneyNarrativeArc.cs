using System.Collections.Concurrent;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public enum NarrativeArcMomentType
{
    Opening,
    Theme,
    ContextSetting,
    Transition,
    Connection,
    Foreshadowing,
    ArrivalIntroduction,
    Recap
}

public sealed record NarrativeArcMoment(
    string MomentId,
    int SequenceNumber,
    NarrativeArcMomentType Type,
    string Text,
    IReadOnlyList<string> StoryPackIds,
    IReadOnlyList<string> EvidenceIds,
    string? StopId,
    string? RouteSegmentId,
    bool ContainsFactualContent);

public sealed record NarrativeArcValidation(
    bool IsValid,
    IReadOnlyList<string> Issues);

public sealed record JourneyNarrativeArc(
    string ArcId,
    string WalkSessionId,
    int RouteRevision,
    string Theme,
    DateTimeOffset GeneratedUtc,
    bool IsSparse,
    IReadOnlyList<NarrativeArcMoment> Moments,
    NarrativeArcValidation Validation);

public interface IJourneyNarrativeArcBuilder
{
    JourneyNarrativeArc Build(WalkSession session, IReadOnlyCollection<StoryPack> storyPacks, DateTimeOffset generatedUtc);
}

public interface IJourneyNarrativeArcRepository
{
    Task<JourneyNarrativeArc?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken);
    Task StoreAsync(JourneyNarrativeArc arc, CancellationToken cancellationToken);
}

public interface IJourneyNarrativeArcService
{
    Task<JourneyNarrativeArc?> RefreshAsync(WalkSession session, CancellationToken cancellationToken);
    Task<JourneyNarrativeArc?> AddStoryPackAsync(WalkSession session, StoryPack storyPack, CancellationToken cancellationToken);
    Task<JourneyNarrativeArc?> GetAsync(WalkSession session, CancellationToken cancellationToken);
}

public sealed class InMemoryJourneyNarrativeArcRepository : IJourneyNarrativeArcRepository
{
    private readonly ConcurrentDictionary<string, JourneyNarrativeArc> _arcs = new(StringComparer.OrdinalIgnoreCase);

    public Task<JourneyNarrativeArc?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _arcs.TryGetValue(Key(walkSessionId, routeRevision), out var arc);
        return Task.FromResult(arc);
    }

    public Task StoreAsync(JourneyNarrativeArc arc, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _arcs[Key(arc.WalkSessionId, arc.RouteRevision)] = arc;
        return Task.CompletedTask;
    }

    private static string Key(string walkSessionId, int routeRevision) => $"{walkSessionId}:{routeRevision}";
}

public sealed class JourneyNarrativeArcService : IJourneyNarrativeArcService
{
    private readonly Phase15Options _options;
    private readonly IJourneyNarrativeArcBuilder _builder;
    private readonly IJourneyNarrativeArcRepository _repository;
    private readonly TimeProvider _timeProvider;
    private readonly ConcurrentDictionary<string, ConcurrentDictionary<string, StoryPack>> _packs = new(StringComparer.OrdinalIgnoreCase);

    public JourneyNarrativeArcService(
        Phase15Options options,
        IJourneyNarrativeArcBuilder builder,
        IJourneyNarrativeArcRepository repository,
        TimeProvider timeProvider)
    {
        _options = options;
        _builder = builder;
        _repository = repository;
        _timeProvider = timeProvider;
    }

    public async Task<JourneyNarrativeArc?> RefreshAsync(WalkSession session, CancellationToken cancellationToken)
    {
        if (!Enabled) return null;
        var packs = _packs.TryGetValue(session.WalkSessionId, out var collected)
            ? collected.Values.ToArray()
            : Array.Empty<StoryPack>();
        var arc = _builder.Build(session, packs, _timeProvider.GetUtcNow());
        await _repository.StoreAsync(arc, cancellationToken);
        return arc;
    }

    public Task<JourneyNarrativeArc?> AddStoryPackAsync(WalkSession session, StoryPack storyPack, CancellationToken cancellationToken)
    {
        if (!Enabled || storyPack.Validation?.IsValid != true) return Task.FromResult<JourneyNarrativeArc?>(null);
        var storyId = storyPack.StoryId ?? storyPack.PlaceIdentity?.CanonicalPlaceId;
        if (string.IsNullOrWhiteSpace(storyId)) return Task.FromResult<JourneyNarrativeArc?>(null);
        var collected = _packs.GetOrAdd(session.WalkSessionId, _ => new ConcurrentDictionary<string, StoryPack>(StringComparer.OrdinalIgnoreCase));
        collected[storyId] = storyPack;
        return RefreshAsync(session, cancellationToken);
    }

    public async Task<JourneyNarrativeArc?> GetAsync(WalkSession session, CancellationToken cancellationToken)
    {
        if (!Enabled) return null;
        return await _repository.GetAsync(session.WalkSessionId, session.RouteRevision, cancellationToken)
            ?? await RefreshAsync(session, cancellationToken);
    }

    private bool Enabled => _options.Enabled && _options.NarrativeArcEnabled;
}

public sealed class DeterministicJourneyNarrativeArcBuilder : IJourneyNarrativeArcBuilder
{
    public JourneyNarrativeArc Build(WalkSession session, IReadOnlyCollection<StoryPack> storyPacks, DateTimeOffset generatedUtc)
    {
        var accepted = storyPacks
            .Where(pack => pack.Validation?.IsValid == true)
            .Where(pack => !pack.ExpiresUtc.HasValue || pack.ExpiresUtc > generatedUtc)
            .Where(pack => pack.EvidenceClaims.Any(claim =>
                claim.VerificationStatus == GroundingVerificationStatus.Verified
                && (!claim.ExpiresUtc.HasValue || claim.ExpiresUtc > generatedUtc)))
            .OrderBy(pack => StopSequence(session, pack))
            .ThenBy(pack => pack.StoryId ?? pack.PlaceIdentity?.CanonicalPlaceId, StringComparer.Ordinal)
            .ToArray();
        var theme = Theme(session);
        var moments = new List<NarrativeArcMoment>();
        Add(moments, NarrativeArcMomentType.Opening, $"Welcome to this walk. We will follow a {theme} thread as the route unfolds.");
        Add(moments, NarrativeArcMomentType.Theme, $"The journey theme is {theme}.");

        StoryPack? previous = null;
        foreach (var pack in accepted)
        {
            var packId = PackId(pack);
            var stop = ClosestStop(session, pack);
            var evidence = EvidenceFor(pack, generatedUtc);
            var availableEvidence = evidence.ToHashSet(StringComparer.OrdinalIgnoreCase);
            var name = pack.PlaceIdentity?.Name ?? stop?.Name ?? "the next stop";
            Add(moments, NarrativeArcMomentType.Foreshadowing, $"At {name}, the next story continues the journey's {theme} thread.", [packId], evidence, stop?.StopId, pack.GeographicAnchor?.RouteSegmentId);

            if (previous is not null)
            {
                var previousId = PackId(previous);
                var shared = previous.Categories.Intersect(pack.Categories).Cast<StoryCategory?>().FirstOrDefault();
                var transitionType = shared.HasValue ? NarrativeArcMomentType.Connection : NarrativeArcMomentType.Transition;
                var transition = !shared.HasValue
                    ? "Keep the previous story in mind as the walk moves to its next setting."
                    : $"Keep the previous story in mind; the next stop continues the {CategoryText(shared.Value)} thread.";
                Add(moments, transitionType, transition, [previousId, packId], EvidenceFor(previous, generatedUtc).Concat(evidence).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), stop?.StopId, pack.GeographicAnchor?.RouteSegmentId);
            }

            Add(moments, NarrativeArcMomentType.ArrivalIntroduction, $"You have reached {name}. Here is the next part of the journey.", [packId], evidence, stop?.StopId, pack.GeographicAnchor?.RouteSegmentId);
            var context = pack.Sections
                .Where(section => section.Availability == GroundingVerificationStatus.Verified)
                .SelectMany(section => section.Sentences)
                .FirstOrDefault(sentence => sentence.ContentType == StorySentenceContentType.Fact
                    && sentence.EvidenceIds.Count > 0
                    && sentence.EvidenceIds.All(availableEvidence.Contains));
            if (context is not null)
            {
                Add(moments, NarrativeArcMomentType.ContextSetting, context.Text, [packId], context.EvidenceIds, stop?.StopId, pack.GeographicAnchor?.RouteSegmentId, true);
            }
            previous = pack;
        }

        if (accepted.Length > 0)
        {
            var names = accepted.Select(pack => pack.PlaceIdentity?.Name).Where(name => !string.IsNullOrWhiteSpace(name)).Take(3).ToArray();
            var recapText = names.Length == 0
                ? $"This walk connected {accepted.Length} verified stories through its {theme} theme."
                : $"This walk connected {string.Join(", ", names)} through its {theme} theme.";
            Add(moments, NarrativeArcMomentType.Recap, recapText, accepted.Select(PackId).ToArray(), accepted.SelectMany(pack => EvidenceFor(pack, generatedUtc)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), factual: true);
        }
        else
        {
            Add(moments, NarrativeArcMomentType.Recap, "The walk is complete. No verified story connections were available for this route.");
        }

        var validation = Validate(moments, accepted, generatedUtc);
        return new JourneyNarrativeArc(
            $"{session.WalkSessionId}-r{session.RouteRevision}-arc",
            session.WalkSessionId,
            session.RouteRevision,
            theme,
            generatedUtc,
            accepted.Length < 2,
            moments,
            validation);
    }

    private static NarrativeArcValidation Validate(IReadOnlyList<NarrativeArcMoment> moments, IReadOnlyList<StoryPack> packs, DateTimeOffset now)
    {
        var issues = new List<string>();
        var packIds = packs.Select(PackId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var evidence = packs.SelectMany(pack => pack.EvidenceClaims)
            .Where(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified && (!claim.ExpiresUtc.HasValue || claim.ExpiresUtc > now))
            .Select(claim => claim.EvidenceId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var moment in moments)
        {
            if (moment.StoryPackIds.Any(id => !packIds.Contains(id))) issues.Add($"Moment {moment.MomentId} references an unknown Story Pack.");
            if (moment.EvidenceIds.Any(id => !evidence.Contains(id))) issues.Add($"Moment {moment.MomentId} references unavailable evidence.");
            if (moment.ContainsFactualContent && moment.EvidenceIds.Count == 0) issues.Add($"Factual moment {moment.MomentId} has no evidence.");
        }
        return new NarrativeArcValidation(issues.Count == 0, issues);
    }

    private static void Add(
        ICollection<NarrativeArcMoment> moments,
        NarrativeArcMomentType type,
        string text,
        IReadOnlyList<string>? packIds = null,
        IReadOnlyList<string>? evidenceIds = null,
        string? stopId = null,
        string? routeSegmentId = null,
        bool factual = false)
    {
        var sequence = moments.Count + 1;
        moments.Add(new NarrativeArcMoment($"arc-m{sequence}", sequence, type, text, packIds ?? Array.Empty<string>(), evidenceIds ?? Array.Empty<string>(), stopId, routeSegmentId, factual));
    }

    private static string Theme(WalkSession session)
    {
        var interests = session.Interests.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim().ToLowerInvariant()).Distinct().Take(2).ToArray();
        return interests.Length == 0 ? "local character" : string.Join(" and ", interests);
    }

    private static string PackId(StoryPack pack) => pack.StoryId ?? pack.PlaceIdentity?.CanonicalPlaceId ?? "unknown-pack";
    private static IReadOnlyList<string> EvidenceFor(StoryPack pack, DateTimeOffset now) => pack.EvidenceClaims
        .Where(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified
            && (!claim.ExpiresUtc.HasValue || claim.ExpiresUtc > now))
        .Select(claim => claim.EvidenceId)
        .Take(3)
        .ToArray();
    private static string CategoryText(StoryCategory category) => string.Concat(category.ToString().Select((character, index) => index > 0 && char.IsUpper(character) ? $" {char.ToLowerInvariant(character)}" : char.ToLowerInvariant(character).ToString()));

    private static int StopSequence(WalkSession session, StoryPack pack) => ClosestStop(session, pack)?.SequenceNumber ?? int.MaxValue;

    private static WalkStop? ClosestStop(WalkSession session, StoryPack pack)
    {
        if (pack.PlaceIdentity is null) return null;
        var point = new GeoLocation(pack.PlaceIdentity.Latitude, pack.PlaceIdentity.Longitude);
        return session.Stops.OrderBy(stop => RouteMath.DistanceMeters(stop.Location, point)).FirstOrDefault();
    }
}

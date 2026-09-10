namespace Rover.Application.LocationIntelligence;

public interface ILocationStoryContextService
{
    Task<LocationStoryContext> GetContextAsync(LocationContextQuery query, CancellationToken cancellationToken);
    Task<LocationStoryResult> CreateStoryAsync(LocationStoryRequest request, CancellationToken cancellationToken);
}

public interface ILocationContextProvider
{
    string Name { get; }
    Task<LocationContextProviderResult> GetContextAsync(LocationContextQuery query, CancellationToken cancellationToken);
}

public interface ILocationContextCachePolicy
{
    bool AllowsAggregateCaching { get; }
}

public interface ILocationContextCache
{
    bool TryGet<T>(string key, out T? value);
    void Set<T>(string key, T value, TimeSpan duration);
}

public interface ILocationPlaceResolver
{
    IReadOnlyList<LocationPlace> Resolve(IReadOnlyList<LocationPlace> places, LocationContextQuery query, DateTimeOffset now);
}

public interface ILocationStoryRankingService
{
    IReadOnlyList<LocationPlace> Rank(IReadOnlyList<LocationPlace> places, LocationContextQuery query, DateTimeOffset now);
}

public interface ILocationStorySynthesizer
{
    Task<LocationStoryResult> CreateStoryAsync(LocationStoryContext context, IReadOnlyCollection<string> selectedPlaceIds, string? narrationStyle, CancellationToken cancellationToken);
}

public interface IStoryPackFactory
{
    string SchemaVersion { get; }

    StoryPack Create(
        LocationStoryContext context,
        LocationStoryResult story,
        string? narrationStyle,
        IReadOnlyCollection<string> interests,
        DateTimeOffset now);
}

public interface IStoryGroundingValidator
{
    GroundingValidationResult Validate(StoryPack storyPack, DateTimeOffset now);
}

public interface IStoryPackRepository
{
    Task<LocationStoryResult?> GetAsync(StoryPackStorageKey key, CancellationToken cancellationToken);
    Task<bool> StoreAsync(StoryPackStorageKey key, LocationStoryResult story, CancellationToken cancellationToken);
}

public interface IEvidenceRepository
{
    Task<PersistedEvidenceSet?> GetAsync(string canonicalPlaceId, CancellationToken cancellationToken);
    Task<bool> StoreAsync(StoryPack storyPack, CancellationToken cancellationToken);
}

public interface IStoryPackPersistencePolicy
{
    StoryPackPersistenceDecision Prepare(LocationStoryResult story, DateTimeOffset now);
    StoryPackPersistenceDecision Prepare(StoryPack storyPack, DateTimeOffset now);
}

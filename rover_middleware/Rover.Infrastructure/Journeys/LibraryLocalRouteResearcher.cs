using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Rover.Application.Journeys;
using Rover.Application.Walks;

namespace Rover.Infrastructure.Journeys;

public sealed class LibraryLocalRouteResearcher(
    ILocalRouteResearcher researcher,
    FileSharedStoryLibrary library,
    SharedStoryLibraryOptions options,
    LocalRouteResearchOptions researchOptions,
    SharedStoryLibraryMetrics metrics,
    ILogger<LibraryLocalRouteResearcher> logger) : ILocalRouteResearcher
{
    public async Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken token)
    {
        if (!options.Enabled || query.Segments.Count == 0)
            return await researcher.ResearchAsync(query, token);
        if (!Path.IsPathFullyQualified(options.Directory))
            throw new InvalidOperationException("Shared story library needs an absolute persistent directory.");
        var language = query.Language.Trim().ToLowerInvariant();
        var target = query.Journey is null ? 3 : Math.Clamp((int)Math.Ceiling(query.Journey.WalkingMinutes / 3d),
            3, Math.Clamp(researchOptions.MaximumCollectionStories, 3, 12));
        if (query.MaximumStories is { } requested) target = Math.Clamp(requested, 1, target);
        if (query.Question is { } question) target = Math.Clamp(question.StoryCount, 1, 5);
        // Hash the full request context, not keywords. Never store the user's question text.
        var questionKey = query.Question is null ? null : Convert.ToHexString(SHA256.HashData(
            Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
            {
                policy = "question-v1", query.Question, language, query.SearchRadiusMeters,
                areas = query.Segments.Select(s => new {
                    startLat = Math.Round(s.Start.Latitude, 4), startLon = Math.Round(s.Start.Longitude, 4),
                    endLat = Math.Round(s.End.Latitude, 4), endLon = Math.Round(s.End.Longitude, 4)
                })
            }))));
        var first = query.Segments.OrderBy(segment => segment.SequenceNumber).First().Anchor;
        var key = string.Create(CultureInfo.InvariantCulture,
            $"{language}|{Math.Floor(first.Latitude * 100)}|{Math.Floor(first.Longitude * 100)}");
        FileStream? lease = null;
        IReadOnlyList<SharedStoryEntry> stored = [];
        try
        {
            // Recheck after acquiring the area lock, so a concurrent visitor reuses the first result.
            lease = await library.LockResearchAsync(key, token);
            await library.StoreAsync(language, query.LibraryCandidates, token);
            stored = await library.ReadAsync(token);
        }
        catch (Exception error) when (StorageFailure(error))
        {
            if (lease is not null) await lease.DisposeAsync();
            lease = null;
            metrics.Record("failure");
            logger.LogWarning("Shared story library unavailable ({Kind}); using live research.", error.GetType().Name);
        }
        await using var heldLease = lease;
        var excluded = query.ExcludedStoryTitles.Concat(query.Journey?.CoveredTopics ?? [])
            .Concat(query.LibraryCandidates.Select(story => story.Title))
            .Select(Normalize).ToHashSet(StringComparer.Ordinal);
        var reused = stored.Where(entry => entry.Language == language && entry.QuestionKey == questionKey
                && !excluded.Contains(Normalize(entry.Story.Title)))
            .Select(entry => Rebase(entry.Story, query))
            .Where(story => story is not null).Cast<AdaptiveRouteStory>()
            .Where(story => query.Question is not null || StoryInterestPolicy.Allows(story.Category, query.Interests))
            .OrderByDescending(story => InterestMatch(story.Category, query.Interests))
            .ThenBy(story => story.OpensAtRouteMeters)
            .DistinctBy(story => Normalize(story.Title)).Take(target).ToArray();
        // A partially cached collection is not a new answer to a multi-part question.
        if (questionKey is not null && reused.Length < target) reused = [];
        if (reused.Length > 0) metrics.Record("reused", reused.Length);
        if (reused.Length >= target && CoversRequestedLiveTopics(reused, query.Interests))
        {
            metrics.Record("avoided");
            logger.LogInformation("Shared story library reused {Count} stories; avoided local research.", reused.Length);
            return new(reused, $"Local research: reused {reused.Length} verified library stories.");
        }

        metrics.Record("research");
        var missing = Math.Max(1, target - reused.Length);
        LocalRouteResearchResult fresh;
        try
        {
            fresh = await researcher.ResearchAsync(query with
            {
                MaximumStories = missing,
                ExcludedStoryTitles = query.ExcludedStoryTitles.Concat(reused.Select(story => story.Title)).ToArray()
            }, token);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception)
        {
            metrics.Record("failure");
            logger.LogWarning("Shared story library live research failed; retained {Count} reusable stories.", reused.Length);
            return new(reused, "Local research failed; retained fresh library stories.") { Failed = true };
        }
        if (fresh.Warning is not null && fresh.Stories.Count == 0) metrics.Record("failure");
        try { await library.StoreAsync(language, fresh.Stories, token, questionKey); }
        catch (Exception error) when (StorageFailure(error))
        {
            metrics.Record("failure");
            logger.LogWarning("Shared story library could not save ({Kind}); live stories remain available.", error.GetType().Name);
        }
        logger.LogInformation("Shared story library reused {Reused}; researched {New}; requested {Requested}.",
            reused.Length, fresh.Stories.Count, missing);
        return new(reused.Concat(fresh.Stories)
            .Where(story => !excluded.Contains(Normalize(story.Title)))
            .DistinctBy(story => story.StoryId).DistinctBy(story => Normalize(story.Title)).ToArray(), fresh.Warning) { Failed = fresh.Failed };
    }

    private static AdaptiveRouteStory? Rebase(AdaptiveRouteStory story, LocalRouteResearchQuery query)
    {
        var segment = query.Segments.MinBy(segment =>
            RouteMath.DistanceToSegmentMeters(story.Anchor, segment.Start, segment.End))!;
        // More conservative than research discovery: reuse only within the walking corridor.
        var radius = query.Question is not null ? query.SearchRadiusMeters : 225;
        if (RouteMath.DistanceToSegmentMeters(story.Anchor, segment.Start, segment.End) > radius) return null;
        return story with { SegmentId = segment.SegmentId,
            OpensAtRouteMeters = segment.StartRouteMeters, ClosesAtRouteMeters = segment.EndRouteMeters };
    }

    private static string Normalize(string text) => text.Trim().ToLowerInvariant();
    private static bool InterestMatch(string category, IReadOnlyList<string> interests) =>
        interests.Any(interest => Normalize(interest) == Normalize(category) ||
            (category is "news" or "event" && Normalize(interest).Contains("event")));
    private static bool CoversRequestedLiveTopics(IReadOnlyList<AdaptiveRouteStory> stories, IReadOnlyList<string> interests) =>
        !interests.Any(interest => Normalize(interest).Contains("event") || Normalize(interest).Contains("news")) ||
        stories.Any(story => story.Category is "news" or "event");
    private static bool StorageFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or JsonException or NotSupportedException;
}

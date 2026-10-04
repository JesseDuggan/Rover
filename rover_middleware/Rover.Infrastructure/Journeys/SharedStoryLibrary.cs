using System.Diagnostics.Metrics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Rover.Application.Journeys;

namespace Rover.Infrastructure.Journeys;

public sealed class SharedStoryLibraryOptions
{
    public bool Enabled { get; set; }
    public string Directory { get; set; } = "";
    // Exact hosts only. Operators must verify server-storage and cross-user reuse rights.
    public string[] ApprovedSourceHosts { get; set; } = [];
    public int MaximumEntries { get; set; } = 2000;
}

public sealed class SharedStoryLibraryMetrics
{
    private static readonly Meter Meter = new("WalkAbout.SharedStories", "1.0");
    private static readonly Counter<long> Events = Meter.CreateCounter<long>("walkabout.shared_stories.events");
    private long _hits, _avoided, _research, _failures;
    public (long ReusedStories, long ResearchCallsAvoided, long ResearchCalls, long Failures) Snapshot =>
        (Interlocked.Read(ref _hits), Interlocked.Read(ref _avoided), Interlocked.Read(ref _research), Interlocked.Read(ref _failures));
    public void Record(string outcome, int count = 1)
    {
        switch (outcome)
        {
            case "reused": Interlocked.Add(ref _hits, count); break;
            case "avoided": Interlocked.Add(ref _avoided, count); break;
            case "research": Interlocked.Add(ref _research, count); break;
            case "failure": Interlocked.Add(ref _failures, count); break;
        }
        Events.Add(count, new KeyValuePair<string, object?>("outcome", outcome));
    }
}

public sealed record SharedStoryEntry(string Language, DateTimeOffset StoredUtc, AdaptiveRouteStory Story)
{
    public string? ResearchPolicy { get; init; }
}

// A mounted volume is required for persistence across deployments.
// File locks cover readers/writers in other processes using the same volume.
public sealed class FileSharedStoryLibrary(SharedStoryLibraryOptions options, TimeProvider clock)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private const string ResearchPolicy = "editorial-stories-v3";
    private string Root => Path.GetFullPath(options.Directory);
    private string Catalog => Path.Combine(Root, "stories-v1.json");

    public bool CanReuse(AdaptiveRouteStory? story)
    {
        var now = clock.GetUtcNow();
        if (story is null || story.Anchor is null || story.Sources is null ||
            story.Claims is null || story.Variants is null ||
            string.IsNullOrWhiteSpace(story.StoryId) || string.IsNullOrWhiteSpace(story.Title) ||
            story.Claims.Any(claim => claim is null || claim.SourceIds is null) ||
            story.Variants.Any(variant => variant is null || variant.ClaimIds is null) ||
            story.ExpiresUtc is not { } expiry || expiry <= now ||
            story.Sources.Count == 0 || story.Claims.Count == 0 || story.Variants.Count == 0 ||
            !double.IsFinite(story.Anchor.Latitude) || !double.IsFinite(story.Anchor.Longitude) ||
            Math.Abs(story.Anchor.Latitude) > 90 || Math.Abs(story.Anchor.Longitude) > 180)
            return false;
        var ttl = story.Category is "news" or "event" ? TimeSpan.FromMinutes(30) : TimeSpan.FromHours(6);
        foreach (var source in story.Sources)
        {
            if (source is null || string.IsNullOrWhiteSpace(source.SourceId) ||
                !StorySourceReusePolicy.AllowsServerReuse(source) ||
                source.RetrievedUtc > now || source.RetrievedUtc + ttl <= now ||
                !Uri.TryCreate(source.Url, UriKind.Absolute, out var uri) ||
                uri.Scheme != Uri.UriSchemeHttps ||
                !options.ApprovedSourceHosts.Contains(uri.IdnHost, StringComparer.OrdinalIgnoreCase))
                return false;
        }
        var sources = story.Sources.Select(source => source.SourceId).ToHashSet(StringComparer.Ordinal);
        var claims = story.Claims.Select(claim => claim.ClaimId).ToHashSet(StringComparer.Ordinal);
        return story.Claims.All(claim => !string.IsNullOrWhiteSpace(claim.Text) &&
                claim.SourceIds.Count > 0 && claim.SourceIds.All(sources.Contains)) &&
            story.Variants.All(variant => !string.IsNullOrWhiteSpace(variant.Narration) &&
                variant.ClaimIds.Count > 0 && variant.ClaimIds.All(claims.Contains));
    }

    public Task<FileStream> LockResearchAsync(string key, CancellationToken token) =>
        LockAsync($"research-{Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)))[..2]}.lock", token);

    private async Task<FileStream> LockAsync(string name, CancellationToken token)
    {
        System.IO.Directory.CreateDirectory(Root);
        var path = Path.Combine(Root, name);
        while (true)
        {
            token.ThrowIfCancellationRequested();
            try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException error) when ((error.HResult & 0xffff) is 11 or 32 or 33)
            {
                await Task.Delay(100, token);
            }
        }
    }

    public async Task<IReadOnlyList<SharedStoryEntry>> ReadAsync(CancellationToken token)
    {
        await using var gate = await LockAsync("catalog.lock", token);
        return await ReadUnlockedAsync(token);
    }

    private async Task<List<SharedStoryEntry>> ReadUnlockedAsync(CancellationToken token)
    {
        if (!File.Exists(Catalog)) return [];
        await using var stream = File.OpenRead(Catalog);
        // Bounded catalog; corrupt data is reported by the decorator, never used.
        if (stream.Length > 64 * 1024 * 1024) throw new IOException("Shared story catalog exceeds size limit.");
        var entries = await JsonSerializer.DeserializeAsync<List<SharedStoryEntry>>(stream, Json, token) ?? [];
        return entries.Where(entry => entry is not null && entry.ResearchPolicy == ResearchPolicy
                && !string.IsNullOrWhiteSpace(entry.Language) && CanReuse(entry.Story))
            .OrderByDescending(entry => entry.StoredUtc).Take(Math.Clamp(options.MaximumEntries, 1, 10000)).ToList();
    }

    public async Task StoreAsync(string language, IReadOnlyList<AdaptiveRouteStory> stories, CancellationToken token)
    {
        var eligible = stories.Where(CanReuse).ToArray();
        if (eligible.Length == 0) return;
        await using var gate = await LockAsync("catalog.lock", token);
        var previous = await ReadUnlockedAsync(token);
        var now = clock.GetUtcNow();
        // No route IDs, segment IDs, distances, requests, profiles or playback state are persisted.
        var added = eligible.Select(story => new SharedStoryEntry(language, now,
            story with { SegmentId = "", OpensAtRouteMeters = 0, ClosesAtRouteMeters = 0 })
            { ResearchPolicy = ResearchPolicy });
        var entries = added.Concat(previous)
            .DistinctBy(entry => (entry.Language, entry.Story.StoryId))
            .Take(Math.Clamp(options.MaximumEntries, 1, 10000)).ToArray();
        var temporary = $"{Catalog}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 16384, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(output, entries, Json, token);
                await output.FlushAsync(token);
            }
            File.Move(temporary, Catalog, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

using Microsoft.Extensions.Logging.Abstractions;
using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;

internal static class SharedStoryLibraryTests
{
    public static async Task QuestionIsolation()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock);
            var service = Service(fake, options, clock, new());
            var generic = Query("first");
            await service.ResearchAsync(generic, default);
            var question = generic with { MaximumStories = 1, Question = new(
                "How did this street get its name?", StoryQuestionScope.Street, StoryQuestionFormat.Single, 1, 180) };
            await service.ResearchAsync(question, default);
            Check(fake.Calls == 2, "Unrelated nearby stories cannot answer a question.");
            await Service(fake, options, clock, new()).ResearchAsync(question, default);
            Check(fake.Calls == 2, "The identical eligible answer survives a new service instance.");
            await service.ResearchAsync(question with { Question = question.Question! with { Text = "Who lived here?" } }, default);
            Check(fake.Calls == 3, "Different questions require different evidence.");
            await service.ResearchAsync(question with { Question = question.Question! with { Format = StoryQuestionFormat.ThenAndNow } }, default);
            Check(fake.Calls == 4, "Different answer formats are isolated.");
            await service.ResearchAsync(question with { Language = "de" }, default);
            Check(fake.Calls == 5, "Question languages are isolated.");
            var saved = await File.ReadAllTextAsync(Path.Combine(options.Directory, "stories-v1.json"));
            Check(!saved.Contains("How did this street") && !saved.Contains("Who lived here"),
                "Do not persist the visitor's raw question.");
        });
    }

    public static async Task ReuseAndPersistence()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock);
            var metrics = new SharedStoryLibraryMetrics();
            var first = await Service(fake, options, clock, metrics).ResearchAsync(Query("private-route-A"), default);
            Check(fake.Calls == 1 && first.Stories.Count == 3, "First visitor researches.");
            var second = await Service(fake, options, clock, metrics).ResearchAsync(Query("private-route-B", start: 900), default);
            Check(fake.Calls == 1 && second.Stories.Count == 3, "New service instance must reuse persisted stories.");
            Check(second.Stories.All(story => story.SegmentId == "private-route-B" && story.OpensAtRouteMeters == 900),
                "Reuse must rebase windows to the receiving route.");
            Check(metrics.Snapshot.ResearchCallsAvoided == 1 && metrics.Snapshot.ReusedStories == 3, "Reuse metrics.");
            var saved = await File.ReadAllTextAsync(Path.Combine(options.Directory, "stories-v1.json"));
            Check(!saved.Contains("private-route-A") && !saved.Contains("private-route-B"), "No route identifiers stored.");
            Check(second.Stories.All(story => story.Sources[0].Attribution == "Example archive"), "Attribution retained.");
            Check(second.Stories.All(story => story.Sources[0].Reuse?.LicenseId == "CC0-1.0"),
                "Source-specific license survives persistence.");
            Check(second.Stories.All(story => !story.Sources[0].AllowsOfflineUse),
                "Server reuse does not grant offline permission.");
        });
    }

    public static async Task FreshnessAndPermissions()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock);
            var service = Service(fake, options, clock, new());
            await service.ResearchAsync(Query("first"), default);
            clock.Now = clock.Now.AddHours(7);
            await service.ResearchAsync(Query("stale"), default);
            Check(fake.Calls == 2, "Expired history must be researched again.");
            options.ApprovedSourceHosts = [];
            await service.ResearchAsync(Query("revoked"), default);
            Check(fake.Calls == 3, "Revoked host permissions apply on reads.");
            var library = new FileSharedStoryLibrary(options, clock);
            options.ApprovedSourceHosts = ["www.wikidata.org"];
            var valid = Story("test", clock.Now);
            Check(library.CanReuse(valid), "Explicitly permitted sourced story reusable.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with { Reuse = null }] }),
                "Legacy cached stories without rights must be rejected.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with { ProviderName = "OnlineResearch" }] }),
                "A web citation cannot inherit structured-data permission.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with
                { Url = "https://www.wikidata.org/wiki/Wikidata:Copyright" }] }),
                "Non-entity pages are not CC0 structured data.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with
                { Reuse = valid.Sources[0].Reuse! with { LicenseId = "CC-BY-SA-4.0" } }] }),
                "Unsupported licenses fail closed.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with
                { Reuse = valid.Sources[0].Reuse! with { ProviderRecordId = "Q2" } }] }),
                "Rights must match the specific entity.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with
                { Reuse = valid.Sources[0].Reuse! with { PolicyVersion = "old-policy" } }] }),
                "Superseded policy must be rejected.");
            Check(StorySourceReusePolicy.FromLocationSource(new("OnlineResearch", "Q1",
                "https://www.wikidata.org/entity/Q1", "Attribution", "CC0", clock.Now, .8)) is null,
                "Only the structured provider can establish a grant.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with { Url = "https://archive.example.evil.test/a" }] }),
                "Host suffix spoof must not match.");
            Check(!library.CanReuse(valid with { Sources = [valid.Sources[0] with { ProviderName = "GooglePlaces" }] }),
                "Restricted providers excluded even on allowlisted host.");
            Check(!library.CanReuse(valid with { Claims = [new("bad", "Unsupported.", ["missing"], .8)] }),
                "Dangling evidence rejected.");
            var news = valid with { Category = "news" };
            clock.Now = clock.Now.AddMinutes(31);
            Check(!library.CanReuse(news), "News freshness is capped separately.");
        });
    }

    public static async Task MatchingAndTopUp()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock);
            var service = Service(fake, options, clock, new());
            var first = await service.ResearchAsync(Query("first"), default);
            var topUp = await service.ResearchAsync(Query("topup") with
                { ExcludedStoryTitles = [first.Stories[0].Title] }, default);
            Check(fake.LastMaximum == 1 && topUp.Stories.Count == 3, "Research only missing count.");
            Check(topUp.Stories.All(story => story.Title != first.Stories[0].Title), "Refresh must not recycle covered topics.");
            await service.ResearchAsync(Query("german") with { Language = "de" }, default);
            Check(fake.Calls == 3, "Languages are isolated.");
            await service.ResearchAsync(Query("distant", latitude: 49.5), default);
            Check(fake.Calls == 4, "Distant stories cannot be reused.");
            var live = await service.ResearchAsync(Query("events") with { Interests = ["current events"] }, default);
            Check(fake.Calls == 5, "Historical cache cannot suppress requested live research.");
        });
    }

    public static async Task ConcurrentVisitors()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock) { Delay = true };
            var one = Service(fake, options, clock, new());
            var two = Service(fake, options, clock, new());
            await Task.WhenAll(one.ResearchAsync(Query("one"), default), two.ResearchAsync(Query("two"), default));
            Check(fake.Calls == 1, "Concurrent visitors in same area must share one research result.");
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            try { await one.ResearchAsync(Query("cancel"), cancelled.Token); throw new Exception("Cancellation ignored."); }
            catch (OperationCanceledException) { }
        });
    }

    public static async Task FailuresAndDisabled()
    {
        await WithLibrary(async (options, clock) =>
        {
            var fake = new Researcher(clock);
            var metrics = new SharedStoryLibraryMetrics();
            var service = Service(fake, options, clock, metrics);
            await service.ResearchAsync(Query("first") with
                { LibraryCandidates = [Story("provider-candidate", clock.Now)] }, default);
            var persisted = await new FileSharedStoryLibrary(options, clock).ReadAsync(default);
            Check(persisted.Any(entry => entry.Story.StoryId == "provider-candidate"),
                "Provider-built story must reach shared storage.");
            fake.Fail = true;
            var result = await service.ResearchAsync(Query("topup") with { Interests = ["current events"] }, default);
            Check(result.Stories.Count == 3 && result.Warning!.Contains("failed"), "Failed top-up retains reusable stories.");
            Check(metrics.Snapshot.Failures == 1, "Research failure counted.");
            fake.Fail = false;
            await File.WriteAllTextAsync(Path.Combine(options.Directory, "stories-v1.json"),
                System.Text.Json.JsonSerializer.Serialize(new[] {
                    new SharedStoryEntry("en", clock.Now, Story("legacy-listing", clock.Now))
                }, new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web)));
            Check((await new FileSharedStoryLibrary(options, clock).ReadAsync(default)).Count == 0,
                "Stories from the old mixed research policy must not be reused.");
            await File.WriteAllTextAsync(Path.Combine(options.Directory, "stories-v1.json"),
                "[null,{\"language\":\"en\",\"story\":null}]");
            result = await service.ResearchAsync(Query("malformed"), default);
            Check(result.Stories.Count == 3, "Malformed entries must not prevent live research.");
            await File.WriteAllTextAsync(Path.Combine(options.Directory, "stories-v1.json"), "not json");
            result = await service.ResearchAsync(Query("corrupt"), default);
            Check(result.Stories.Count == 3, "Corrupt storage must not prevent live research.");
            options.Enabled = false;
            var calls = fake.Calls;
            await service.ResearchAsync(Query("disabled"), default);
            Check(fake.Calls == calls + 1, "Feature switch preserves previous live behavior.");
        });
    }

    private static LibraryLocalRouteResearcher Service(Researcher fake, SharedStoryLibraryOptions options,
        Clock clock, SharedStoryLibraryMetrics metrics) =>
        new(fake, new FileSharedStoryLibrary(options, clock), options, new(), metrics,
            NullLogger<LibraryLocalRouteResearcher>.Instance);

    private static LocalRouteResearchQuery Query(string segment, double start = 0, double latitude = 49.41) =>
        new([new(segment, 1, new(latitude, 8.71), new(latitude, 8.711), new(latitude, 8.7105),
            start, start + 100, 100, 90, false, [])],
            new ApproximateLiveLocation("Heidelberg", null, "DE", null), ["Public castle"], ["history"], "en");

    private static AdaptiveRouteStory Story(string id, DateTimeOffset now) =>
        new(id, "private-route-A", id, $"History {id}", RouteStoryIntent.HiddenHistory, "history",
            new(49.41, 8.7105), 0, 100,
            [new(AdaptiveStoryLength.Standard, 30, "An independently sourced historical fact.", [$"{id}-claim"])],
            [new($"{id}-claim", "An independently sourced historical fact.", [$"{id}-source"], .8)],
            [new($"{id}-source", "Wikidata", "Entity", "https://www.wikidata.org/entity/Q1", "Example archive", now, .8)
                { AllowsOfflineUse = false, Reuse = StorySourceReusePolicy.FromLocationSource(
                    new("Wikidata", "Q1", "https://www.wikidata.org/entity/Q1", "Example archive", "CC0", now, .8)) }], .8, now.AddHours(6));

    private static async Task WithLibrary(Func<SharedStoryLibraryOptions, Clock, Task> run)
    {
        var directory = Path.Combine(Path.GetTempPath(), $"walk-about-library-{Guid.NewGuid():N}");
        try
        {
            await run(new() { Enabled = true, Directory = directory, ApprovedSourceHosts = ["www.wikidata.org"] }, new());
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now = new(2026, 10, 3, 10, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Researcher(Clock clock) : ILocalRouteResearcher
    {
        public int Calls;
        public int? LastMaximum;
        public bool Delay, Fail;
        public async Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken token)
        {
            var call = Interlocked.Increment(ref Calls);
            LastMaximum = query.MaximumStories;
            if (Delay) await Task.Delay(150, token);
            if (Fail) throw new HttpRequestException("Unavailable");
            return new(Enumerable.Range(0, query.MaximumStories ?? 3)
                .Select(index => Story($"batch-{call}-{index}", clock.Now)).ToArray(), null);
        }
    }
}

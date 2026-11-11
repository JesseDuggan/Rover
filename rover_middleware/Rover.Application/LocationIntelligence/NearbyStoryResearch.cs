using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Application.Walks;

namespace Rover.Application.LocationIntelligence;

public static class NearbyStoryResearch
{
    public static async Task<LocationStoryResult> CreateAsync(
        ILocalRouteResearcher? researcher, LocationPlace? place,
        LocationStoryRequest request, DateTimeOffset now, CancellationToken cancellationToken,
        bool selectedDriveStop = false)
    {
        LocationStoryResult Empty(string status) => new(
            place?.Name ?? "Nearby story", "", null, place?.CanonicalId,
            [], [], 0, [], []) { ResearchStatus = status };

        if (place is null || request.SelectedPlaceIds.Count != 1
            || !request.SelectedPlaceIds.Contains(place.CanonicalId)
            || RouteMath.DistanceMeters(request.UserCoordinates, place.Coordinates) > 500)
            return Empty("empty");
        if (researcher is null) return Empty("failed");

        // A point-sized research area, not a fabricated walking route.
        var segment = new RouteStorySegment(
            "nearby", 0, place.Coordinates, place.Coordinates, place.Coordinates,
            0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery(
            [segment], new ApproximateLiveLocation(place.City, place.Region, place.CountryCode, null),
            [place.Name], request.Interests.ToArray(), "en",
            [new LocalResearchPublicPlace(place.Name, place.Address, place.Coordinates)])
        {
            ContentDepth = StoryPreparationPolicy.Depth(request.ContentDepth),
            MaximumStories = 1,
            Question = new StoryResearchQuestion(
                $"What is distinctive about {place.Name} at {place.Address}? Listed place types: {string.Join(", ", place.Categories)}. Verify its identity and choose a research angle appropriate to this exact site. " +
                (request.RouteGeometry.Count >= 2 ? FormattableString.Invariant($"This walking journey starts at {request.RouteGeometry[0].Latitude:F4},{request.RouteGeometry[0].Longitude:F4} and ends at {request.RouteGeometry[^1].Latitude:F4},{request.RouteGeometry[^1].Longitude:F4}. ") : "") +
                "For natural sites investigate landscape formation, ecology, local stewardship or cultural history. For museums consult collection and exhibition records. For performance venues check named productions in official programmes. For other places investigate their original purpose, people, or changes over time. Choose one specific, sourced detail that fits the walker’s interests. If the stop is part of a larger landmark, verify that relationship and explain its relevance when supported. Mention current activity only when a dated source confirms it is current. If no site-specific evidence is available, return no story. " +
                "Do not substitute nearby attractions or invent access, parking, opening hours or safety advice.",
                StoryQuestionScope.Street, StoryQuestionFormat.Single, 1, 90)
        };

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        // Reserve part of the existing request budget for a genuinely different search.
        var subjectTypes = string.Join(" ", place.Categories.Append(place.Name)).Replace('_', ' ');
        var commemorative = System.Text.RegularExpressions.Regex.IsMatch(subjectTypes,
            @"\b(plaque|marker|memorial|monument|stolperstein|mémorial|denkmal|placa|targa)\b",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        var retry = true; // Every kind of place gets the same bounded recovery opportunity.
        using var first = CancellationTokenSource.CreateLinkedTokenSource(timeout.Token);
        if (retry) first.CancelAfter(TimeSpan.FromSeconds(45));
        var initial = await Search(query, first.Token);
        if (!retry || (initial.ResearchStatus == "ready" && !IsGeneric(initial.ShortSpokenNarration) && (StoryPreparationPolicy.Depth(request.ContentDepth) != "deep" || initial.ShortSpokenNarration.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 80)) || timeout.IsCancellationRequested) return initial;
        var focus = commemorative
            ? "Look for an inscription, marker inventory or photograph identifying what is commemorated. Follow that person, object, image or event into archives. Explain one visible detail, distinguishing later replicas or approximate positions when evidence supports it."
            : "Search local-language archives, collections and primary histories under alternate or former names. Trace one specific person, event, natural feature or change documented at this exact attraction.";
        var followUp = new StoryResearchQuestion(
            $"At {place.Name}, {place.Address}, what can the walker notice? {focus} Connect the subject back to the named stop using cited evidence. Develop the evidence into a complete, connected story at the requested content depth, not a directory summary. Keep the entire single story in one cited paragraph. Identify the stop by its supplied name in a supported claim. Do not relocate events or infer a connection from proximity.",
            StoryQuestionScope.Street, StoryQuestionFormat.Single, 1, 90);
        var recovered = await Search(query with { Question = followUp }, timeout.Token);
        return recovered.ResearchStatus == "ready" ? recovered : initial;

        async Task<LocationStoryResult> Search(LocalRouteResearchQuery searchQuery, CancellationToken token)
        {
            LocalRouteResearchResult result;
            try
            {
                result = await researcher.ResearchAsync(searchQuery, token).WaitAsync(token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                return Empty("failed");
            }
            catch (Exception) when (!cancellationToken.IsCancellationRequested)
            {
                return Empty("failed");
            }
            cancellationToken.ThrowIfCancellationRequested();
            foreach (var story in result.Stories)
            {
                if (!story.CanAutoplay) continue;
                var variant = story.Variants.FirstOrDefault(v => v.Length == StoryPreparationPolicy.Length(request.ContentDepth))
                    ?? story.Variants.OrderByDescending(v => v.EstimatedDurationSeconds).FirstOrDefault();
                if (variant is null || string.IsNullOrWhiteSpace(variant.Narration) || ReportsMissingEvidence(variant.Narration)
                    || variant.ClaimIds.Count == 0 || story.ExpiresUtc <= now
                    || !double.IsFinite(story.Anchor.Latitude) || !double.IsFinite(story.Anchor.Longitude)
                    || RouteMath.DistanceMeters(place.Coordinates, story.Anchor) > 150
                    || !string.Join(" ", story.Claims.Select(c => c.Text)).Contains(place.Name, StringComparison.OrdinalIgnoreCase))
                    continue;
                var claims = story.Claims.Where(c => variant.ClaimIds.Contains(c.ClaimId)).ToArray();
                var sources = story.Sources.Where(s => claims.Any(c => c.SourceIds.Contains(s.SourceId))
                    && Uri.TryCreate(s.Url, UriKind.Absolute, out var uri)
                    && (uri.Scheme == "https" || uri.Scheme == "http")).ToArray();
                if (claims.Length != variant.ClaimIds.Distinct().Count()
                    || claims.Any(c => c.SourceIds.Count == 0
                        || c.SourceIds.Any(id => !sources.Any(s => s.SourceId == id))))
                    continue;
                // Research does not confer permission to persist third-party content.
                return new LocationStoryResult(
                    story.Title, variant.Narration, null, place.CanonicalId,
                    claims.Select(c => c.ClaimId).ToArray(),
                    sources.Select(s => new LocationSource(s.ProviderName, s.SourceId, s.Url,
                        s.Attribution, s.Reuse?.LicenseId, s.RetrievedUtc, s.Confidence)
                        { SourceTitle = s.Title, ExpiresUtc = story.ExpiresUtc }).ToArray(),
                    story.EvidenceScore, sources.Select(s => s.Attribution).Distinct().ToArray(), [])
                    { ResearchStatus = "ready" };
            }
            return Empty(result.Failed ? "failed" : "empty");
        }
    }

    private static bool IsGeneric(string text) =>
        System.Text.RegularExpressions.Regex.IsMatch(text, @"\b(rich in history|nestled in the heart|something for everyone)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    internal static bool ReportsMissingEvidence(string text) =>
        System.Text.RegularExpressions.Regex.IsMatch(text,
            @"\b(?:I|we) (?:could not|couldn['’]t|cannot|can['’]t|were unable to|was unable to) (?:verify|find|confirm|identify|establish)\b|\b(?:I|we) found no (?:evidence|record|source)\b",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant);
}

using Rover.Application.Journeys;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.LocationIntelligence;

public sealed record SelectedPlaceStoryFailure(string Code, string Reason);

// Diagnostics expose each failed predicate without relaxing evidence requirements.
public static class SelectedPlaceStoryGate
{
    public static IReadOnlyList<SelectedPlaceStoryFailure> Evaluate(
        AdaptiveRouteStory story, AdaptiveNarrationVariant? variant,
        string placeName, GeoLocation coordinates, DateTimeOffset now)
    {
        var failures = new List<SelectedPlaceStoryFailure>();
        void Add(bool failed, string code, string reason)
        { if (failed) failures.Add(new(code, reason)); }
        Add(!story.CanAutoplay, "autoplay_ineligible", "Audience or autoplay eligibility failed.");
        Add(story.ExpiresUtc <= now, "evidence_expired", "Story evidence has expired.");
        var finite = double.IsFinite(story.Anchor.Latitude) && double.IsFinite(story.Anchor.Longitude);
        Add(!finite, "anchor_nonfinite", "Story anchor contains a non-finite coordinate.");
        if (finite)
        {
            var distance = RouteMath.DistanceMeters(coordinates, story.Anchor);
            Add(distance > 150, "anchor_too_far", "Story anchor exceeds the selected-place distance limit of 150 m.");
        }
        Add(!string.Join(" ", story.Claims.Select(c => c.Text)).Contains(placeName, StringComparison.OrdinalIgnoreCase),
            "selected_name_missing", "Claims do not contain the supplied selected-place name. Check documented identity or aliases; do not infer equivalence.");
        if (variant is null)
        {
            failures.Add(new("variant_missing", "No narration variant is available."));
            return failures;
        }
        Add(string.IsNullOrWhiteSpace(variant.Narration), "narration_empty", "Selected narration is empty.");
        Add(NearbyStoryResearch.ReportsMissingEvidence(variant.Narration), "search_failure_narration", "Narration describes a failed search instead of a verified story.");
        Add(variant.ClaimIds.Count == 0, "claim_ids_empty", "Narration has no claim references.");
        var claims = story.Claims.Where(c => variant.ClaimIds.Contains(c.ClaimId)).ToArray();
        Add(claims.Length != variant.ClaimIds.Distinct().Count(), "claim_reference_mismatch", "Narration claim references are missing or duplicated in the story claims.");
        var sources = story.Sources.Where(s => Uri.TryCreate(s.Url, UriKind.Absolute, out var uri)
            && (uri.Scheme == "https" || uri.Scheme == "http")).ToArray();
        Add(claims.Any(c => c.SourceIds.Count == 0), "claim_sources_empty", "A selected claim has no source references.");
        Add(claims.Any(c => c.SourceIds.Any(id => !sources.Any(s => s.SourceId == id))),
            "source_reference_invalid", "A selected claim references a missing source or a source without an HTTP(S) URL.");
        return failures;
    }
}

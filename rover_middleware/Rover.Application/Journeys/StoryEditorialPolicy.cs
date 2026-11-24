using System.Text.RegularExpressions;
using Rover.Application.Walks;

namespace Rover.Application.Journeys;

public static class StoryEditorialPolicy
{
    public const string SentenceInstructions = " Label each spoken sentence narrativePurpose as story, source_administration or directory. story conveys an event, meaningful detail or necessary qualification. source_administration explains what a passage/source/record says or how a business identity was verified. directory merely lists the current business, licences, menu, directory membership or event-listing presence. A dated historic licensing dispute is story; confirming that today's premises hold a licence is directory. Prefer rewriting supported facts as story sentences and omit administrative sentences. Never relabel administration as story to fill length. ";
    public const string CollectionInstructions = " For a collection, choose complementary stories, not several versions of the same neighbourhood overview. At most one overview of the streetscape or shopping district. Give each further chapter a distinct evidenced episode, person, practice or natural process. Do not retell buildings and architectural styles already covered in another chapter. A shared street name alone does not make stories duplicates. Return fewer chapters when evidence offers no additional angle; never invent variety. Classify subjectScale as area for streets, districts and towns, or place for an individual building, business, monument or venue. Classify chapterRole as overview for any survey of a streetscape, architectural ensemble or civic landmarks; episode, tradition, landscape or biography for a specific distinct narrative. A museum building history is place, even if it mentions its street. A survey of several civic buildings is still overview. ";

    // Match evidence-administration language, not historic licensing events or disputes.
    public static bool IsDirectoryLanguage(string text) => Regex.IsMatch(text,
        @"\b(?:licensing|inspection|municipal|business|directory) records (?:confirm|verify|identify|show|establish)\b|\b(?:active|licensed|registered) (?:food premises|business at this address)\b|\b(?:in|local) directories\b|\b(?:the passage|the source)\b\b|\b(?:records|listings) (?:confirm|verify) (?:that |this |its |the )?(?:exact |current )?(?:address|identity|business|location)\b|\b(?:the evidence does not point|the evidence places|premises held licen[cs]es)\b|\b(?:BIA|BID|business association) listings\b|\b(?:shopping loop|local business circuit|association event material|event booklets that map)\b|\bappears? in [^.!?]{0,100}\b(?:listings|directories|directory|booklets)\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string? AreaChapterFailure(string? subjectScale, string? chapterRole, bool overviewAlreadyCovered) =>
        subjectScale != "area" ? "individual_place_or_unclassified" :
        chapterRole is not ("overview" or "episode" or "tradition" or "landscape" or "biography") ? "chapter_role_missing" :
        chapterRole == "overview" && overviewAlreadyCovered ? "area_overview_already_covered" : null;

    public static IReadOnlyList<AdaptiveRouteStory> DistinctChapters(IEnumerable<AdaptiveRouteStory> candidates, bool areaOnly = false)
    {
        var kept = new List<AdaptiveRouteStory>();
        foreach (var candidate in candidates)
        {
            if (areaOnly && (candidate.SubjectScale == "place" || candidate.ChapterRole == "overview" && kept.Any(s => s.ChapterRole == "overview")))
            {
                StoryInspection.Record("Story overlap", "Not retained", "Individual POI chapter or repeated area overview; kept neighbourhood context separate.", candidate.StoryId, candidate.Title);
                continue;
            }
            var words = Words(candidate);
            var duplicate = kept.FirstOrDefault(previous => {
                var prior = Words(previous);
                // Conservative lexical backstop. Semantic variety is planned in the existing AI call.
                return candidate.TemporalClassification != "time-sensitive" && previous.TemporalClassification != "time-sensitive"
                    && RouteMath.DistanceMeters(candidate.Anchor, previous.Anchor) <= 1000
                    && words.Count >= 12 && prior.Count >= 12
                    && words.Intersect(prior).Count() / (double)Math.Max(words.Count, prior.Count) >= .72;
            });
            if (duplicate is null) kept.Add(candidate);
            else StoryInspection.Record("Story overlap", "Not retained",
                $"Substantial narration overlap with '{duplicate.Title}'. Kept the earlier chapter; no replacement search or route change.", candidate.StoryId, candidate.Title);
        }
        return kept;
    }

    private static HashSet<string> Words(AdaptiveRouteStory story)
    {
        var text = story.Variants.OrderByDescending(v => v.Narration.Length).FirstOrDefault()?.Narration ?? "";
        var stop = new HashSet<string>("that this with from were have which their about there these those into when where while been more than also only through between around itself because instead along would could should".Split(' '));
        return Regex.Matches(text.ToLowerInvariant(), @"\p{L}{4,}").Select(m => m.Value)
            .Where(word => !stop.Contains(word)).ToHashSet(StringComparer.Ordinal);
    }
}

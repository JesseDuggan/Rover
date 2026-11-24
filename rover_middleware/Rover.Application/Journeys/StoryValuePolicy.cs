using System.Text.RegularExpressions;
namespace Rover.Application.Journeys;

public static class StoryValuePolicy
{
    public const string Instructions = " Assess story value independently of fame, venue type and word count. Set storyValueKind to local_episode, visible_detail, natural_process or community_connection only when the cited passage explains a distinctive, substantive detail at this exact place or area that fits the interests. A visible_detail must explain a feature's purpose or significance, not merely list benches, materials or amenities. A community_connection needs an actual local practice, person or change, not simply membership in a shopping strip. A business listing, menu, licence, branch identity or chain-wide background alone is directory_only. Use insufficient when evidence is too thin. For a positive category set storyValueEvidenceSentenceIndex to the zero-based index of the numbered evidence sentence containing that detail. Never paraphrase the supporting evidence. Leave storyValueEvidence null; the server resolves the index to exact cited text. For directory_only or insufficient use a null index. A small or ordinary place can qualify; no theatre, casino or landmark preference. ";
    public static string? Failure(string? kind, string? detail, string evidence)
    {
        if (kind is "directory_only" or "insufficient") return kind;
        if (StoryEditorialPolicy.IsDirectoryLanguage(detail ?? "")) return "directory_only";
        if (kind is not ("local_episode" or "visible_detail" or "natural_process" or "community_connection")) return "value_not_assessed";
        if (string.IsNullOrWhiteSpace(detail) || detail.Length < 20 || detail.Length > 1200) return "missing_value_evidence";
        return Normalize(evidence).Contains(Normalize(detail), StringComparison.Ordinal) ? null : "value_detail_not_in_evidence";
    }
    public static string Normalize(string text) => Regex.Replace(text, @"\s+", " ").Trim();
}

public static class GeographicEvidencePolicy
{
    public static string? Failure(string? area, string? connection, string evidence)
    {
        if (string.IsNullOrWhiteSpace(area) || area.Length > 120) return "area_name_missing_or_invalid";
        if (!StoryValuePolicy.Normalize(evidence).Contains(StoryValuePolicy.Normalize(area), StringComparison.OrdinalIgnoreCase)) return "area_name_not_in_cited_passage";
        if (string.IsNullOrWhiteSpace(connection) || connection.Length < 20) return "local_connection_missing_or_too_short";
        return StoryValuePolicy.Normalize(evidence).Contains(StoryValuePolicy.Normalize(connection), StringComparison.OrdinalIgnoreCase) ? null : "local_connection_not_in_cited_passage";
    }
}

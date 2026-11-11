using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

public sealed record SpokenStorySentence(string Text, string[]? EvidenceQuotes = null, int[]? EvidenceSentenceIndices = null);

// Checks provenance and presentation, not semantic entailment or historical truth.
public static class SpokenStoryDraft
{
    public static string[] EvidenceSentences(string evidence) => Regex.Split(evidence.Trim(), @"(?<=[.!?])\s+")
        .Where(s => !string.IsNullOrWhiteSpace(s)
            && !Regex.IsMatch(s, @"^\s*(Subject|Location|Title|Summary)\s*:", RegexOptions.IgnoreCase)).ToArray();
    public static bool TryPrepare(string evidence, SpokenStorySentence[]? sentences,
        IReadOnlyList<string> qualifications, out string text, bool isLegend = false)
        => TryPrepare(evidence, sentences, qualifications, out text, out _, isLegend);

    // Reasons contain only fixed codes and zero-based item indices, never provider text.
    public static bool TryPrepare(string evidence, SpokenStorySentence[]? sentences,
        IReadOnlyList<string> qualifications, out string text, out string reason, bool isLegend = false)
    {
        text = "";
        reason = "legend_qualification_missing";
        if (isLegend && qualifications.Count == 0) return false;
        reason = "edit_missing";
        if (sentences is null) return false;
        reason = "edit_empty";
        if (sentences.Length == 0) return false;
        reason = "sentence_count_out_of_range";
        if (sentences.Length < 4 || sentences.Length > 12) return false;
        var sourceSentences = EvidenceSentences(evidence);
        for (var index = 0; index < sentences.Length; index++)
        {
            var sentence = sentences[index];
            reason = $"sentence_missing:item_{index}";
            if (sentence is null) return false;
            reason = $"sentence_text_empty:item_{index}";
            if (string.IsNullOrWhiteSpace(sentence.Text)) return false;
            var quotes = sentence.EvidenceQuotes;
            if (sentence.EvidenceSentenceIndices is { } indices)
            {
                reason = $"invalid_evidence_indices:item_{index}";
                if (quotes is not null || indices.Length is < 1 or > 4
                    || indices.Any(i => i < 0 || i >= sourceSentences.Length)) return false;
                quotes = indices.Select(i => sourceSentences[i]).ToArray();
            }
            reason = $"quote_count_out_of_range:item_{index}";
            if (quotes is null || quotes.Length == 0 || quotes.Length > 4) return false;
            reason = $"sentence_too_long:item_{index}";
            if (sentence.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length > 35) return false;
            for (var quoteIndex = 0; quoteIndex < quotes.Length; quoteIndex++)
            {
                var quote = quotes[quoteIndex];
                reason = $"quote_empty_or_too_short:item_{index}:quote_{quoteIndex}";
                if (string.IsNullOrWhiteSpace(quote) || quote.Length < 12) return false;
                reason = $"quote_not_in_evidence:item_{index}:quote_{quoteIndex}";
                if (!evidence.Contains(quote, StringComparison.Ordinal)) return false;
            }
            // Prevent a new precise date or quantity appearing in the spoken edit.
            var support = string.Join(" ", quotes);
            reason = $"unsupported_numeric_token:item_{index}";
            if (Regex.Matches(sentence.Text, @"\d+(?:[.,]\d+)*(?:[\p{L}]+)?").Any(n =>
                !Regex.Matches(support, @"\d+(?:[.,]\d+)*(?:[\p{L}]+)?").Any(e => e.Value == n.Value))) return false;
            reason = $"forbidden_metadata_or_url:item_{index}";
            if (sentence.Text.Contains("http", StringComparison.OrdinalIgnoreCase)
                || Regex.IsMatch(sentence.Text, @"\b(?:latitude|longitude)\b|\bLocation\s*:", RegexOptions.IgnoreCase)) return false;
        }
        var draft = string.Join(" ", sentences.Select(s => s.Text.Trim()));
        reason = "draft_too_long";
        if (draft.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length > 250) return false;
        for (var index = 0; index < qualifications.Count; index++)
        {
            reason = $"qualification_missing:qualification_{index}";
            if (!draft.Contains(qualifications[index], StringComparison.Ordinal)) return false;
        }
        text = draft;
        reason = "accepted";
        return true;
    }
}

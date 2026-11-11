using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

public sealed record SpokenStorySentence(string Text, string[] EvidenceQuotes);

// Checks provenance and presentation, not semantic entailment or historical truth.
public static class SpokenStoryDraft
{
    public static bool TryPrepare(string evidence, SpokenStorySentence[]? sentences,
        IReadOnlyList<string> qualifications, out string text, bool isLegend = false)
    {
        text = "";
        if (isLegend && qualifications.Count == 0) return false;
        if (sentences is null || sentences.Length < 4 || sentences.Length > 12) return false;
        foreach (var sentence in sentences)
        {
            if (string.IsNullOrWhiteSpace(sentence.Text) || sentence.EvidenceQuotes is null
                || sentence.EvidenceQuotes.Length == 0 || sentence.EvidenceQuotes.Length > 4) return false;
            if (sentence.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length > 35) return false;
            if (sentence.EvidenceQuotes.Any(q => string.IsNullOrWhiteSpace(q) || q.Length < 12
                || !evidence.Contains(q, StringComparison.Ordinal))) return false;
            // Prevent a new precise date or quantity appearing in the spoken edit.
            var support = string.Join(" ", sentence.EvidenceQuotes);
            if (Regex.Matches(sentence.Text, @"\d+(?:[.,]\d+)*(?:[\p{L}]+)?").Any(n =>
                !Regex.Matches(support, @"\d+(?:[.,]\d+)*(?:[\p{L}]+)?").Any(e => e.Value == n.Value))) return false;
            if (sentence.Text.Contains("http", StringComparison.OrdinalIgnoreCase)
                || Regex.IsMatch(sentence.Text, @"\b(latitude|longitude|Location:)\b", RegexOptions.IgnoreCase)) return false;
        }
        var draft = string.Join(" ", sentences.Select(s => s.Text.Trim()));
        if (draft.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length > 250
            || qualifications.Any(q => !draft.Contains(q, StringComparison.Ordinal))) return false;
        text = draft;
        return true;
    }
}

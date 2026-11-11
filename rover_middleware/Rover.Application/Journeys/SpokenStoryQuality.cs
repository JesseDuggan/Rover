using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

public static class SpokenStoryQuality
{
    public const string Instructions = " Write for listening: use short, complete sentences, usually 12–25 words, with one main idea each. Avoid packing a whole history into two long sentences or joining facts with chains of semicolons. Use plain language and briefly explain specialist terms. Build around a visible feature, a supported human action or change, and why it matters. Avoid promotional adjectives and vague phrases such as records show unless the supported detail itself is given. Never add facts merely to improve rhythm. For deeper stories, add supported explanation beyond the standard opening; use five or more short sentences when the evidence warrants it, not padded repetition. Preserve uncertainty and source qualifications in all lengths. Keep citations attached when separating factual sentences. Each chapter MUST remain one paragraph containing all its sentences and citations. Short sentences do not mean separate paragraphs or a short synopsis. Do not output a separate introduction, summary or title paragraph before the full story. Before returning, split overloaded sentences within that same paragraph and retain every supported qualification.";

    // A review signal only: punctuation heuristics are not an evidence or safety gate.
    public static string? Review(string narration)
    {
        var lengths = Regex.Split(narration.Trim(), @"(?<=[.!?])\s+")
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length).ToArray();
        var longSentences = lengths.Count(n => n > 35);
        return longSentences == 0 ? null
            : $"sentence_overload: {longSentences} sentence(s) exceed 35 words; longest {lengths.Max()} words. Punctuation-based review signal, not a factual rejection.";
    }
}

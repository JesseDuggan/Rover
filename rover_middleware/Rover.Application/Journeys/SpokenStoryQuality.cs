using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

public static class SpokenStoryQuality
{
    public const string Instructions = " Write for listening as a knowledgeable local guide speaking to one curious walker, not as a heritage register, directory or institutional brochure. Choose one verified thread: a person doing something, an object with an unexpected purpose, a change of use, or a natural process. Open with the most interesting supported detail and name the place naturally, rather than announcing its designation or listing its architectural style. Make the opening a complete, qualified miniature story that works alone. Develop what happened, the concrete detail that makes it distinctive, and its supported consequence or connection to the surroundings. A sequence of unrelated facts is not a story. History and architecture can be explained through how people built, used or changed a place; do not manufacture an anecdote when only physical evidence is available. Use active verbs, plain language and short, complete sentences, usually 12 to 25 words, with one main idea each. Explain unfamiliar terms in everyday words, or omit the term when it adds nothing. Do not stack dates, names, collection inventories or designations. Mention official recognition only if it helps explain the story. Avoid register language such as civic role, heritage stewardship, material holdings, focal point and testament to; avoid generic openings such as nestled in or rich in history. End on a specific supported detail, change or observation that completes this story, not a summary praising the place's importance. Natural warmth is welcome; repeated theatrical hooks, exaggerated suspense and promotional language are not. Never invent dialogue, sensory atmosphere, motives, reactions, causation or connections to improve the telling. Do not claim you personally witnessed an event, or that the listener can see an interior, object or historic feature unless visibility is established. Present-day operation needs current evidence; describe documented past use as past. Preserve every necessary uncertainty, folklore attribution and source qualification in every length. Keep citations attached to the facts they support; style must never strengthen a disputed claim. For deeper stories, develop the same thread with additional supported explanation rather than repeating the opening. Aim for at least six concise sentences when the evidence warrants them; never pad or invent to reach a length. Each chapter MUST remain one paragraph containing all its sentences and citations. Short sentences do not mean separate paragraphs or a short synopsis. Do not output a separate introduction, summary or title paragraph before the full story. Before returning, check that the paragraph contains a memorable verified detail, explains it in ordinary speech and ends specifically. Remove catalogue-like filler and split overloaded sentences within that same paragraph without dropping qualifications.";

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

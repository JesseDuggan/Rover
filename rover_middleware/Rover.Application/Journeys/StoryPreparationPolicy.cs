namespace Rover.Application.Journeys;

// Shared by place, area, route and explicit-question research. Journey type is
// deliberately not an input: it must not change the quality of the evidence.
public static class StoryPreparationPolicy
{
    public const string Version = "shared-preparation-v1";

    public static string Depth(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "deep" or "deeper" or "deeper stories" => "deep",
        "quick" => "quick",
        "short" or "brief" or "short stories" or "brief stories" => "short",
        _ => "standard"
    };

    public static AdaptiveStoryLength Length(string? value) => Depth(value) switch
    {
        "deep" => AdaptiveStoryLength.Deep,
        "short" => AdaptiveStoryLength.Short,
        "quick" => AdaptiveStoryLength.Quick,
        _ => AdaptiveStoryLength.Standard
    };

    public static string Instructions(string? depth) =>
        "Use the selected interests to choose the story angle, not the type of journey. " +
        "First verify what the place actually is. Follow a specific person, former name, former use, visible detail or natural process into relevant primary or local sources. " +
        "For gaps, research the street, landscape or neighbourhood with a documented connection to this stretch. " +
        "Use local-language archives, museums, libraries, historical societies or reputable local journalism where useful. " +
        "Do not give theatres, casinos or famous attractions an automatic advantage. Research performances only at relevant venues; ecology and landscape at natural sites; collections at museums; people and changes of use at other places. " +
        "Verify dated current activities separately from history. Seek an illustrated catalogue or licensed subject image with its exact source and rights; never invent an image URL. " +
        "If the first evidence is only a generic directory description, use the remaining search budget for one targeted alternate-name or local-source search. Omit unsupported details and failed-search narration. " +
        (Depth(depth) == "deep"
            ? "The listener chose deeper stories: develop a specific verified episode with context, a memorable detail and why it matters. Aim for 120–180 spoken words when evidence supports them."
            : "Keep the spoken selection concise, but research it to the same evidential standard. Provide complete short and standard variants without removing necessary qualifications.");
}

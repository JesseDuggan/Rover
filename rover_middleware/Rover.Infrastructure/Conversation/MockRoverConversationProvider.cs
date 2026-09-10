using Rover.Application.Conversation;

namespace Rover.Infrastructure.Conversation;

public sealed class MockRoverConversationProvider : IRoverConversationProvider
{
    public string Name => "Mock";

    public Task<RoverConversationProviderResult> AnswerAsync(
        RoverConversationContext context,
        string questionText,
        CancellationToken cancellationToken)
    {
        var question = questionText.ToLowerInvariant();
        var stop = context.CurrentStop ?? context.NextStop;
        var stopName = stop?.Name ?? "this stop";
        var suggestedAction = SuggestedActionFor(question);
        var answer = question switch
        {
            var text when text.Contains("quiet for") =>
                "Optional stories are quiet for ten minutes. Navigation and arrival guidance stay active.",
            var text when text.Contains("resume stories") =>
                "Optional stories are available again.",
            var text when text.Contains("tell me more") =>
                $"Here is more about {stopName}: {stop?.Narration ?? context.RouteSummary}",
            var text when text.Contains("fewer weather") =>
                "I will reduce optional weather stories while keeping important journey-safety updates.",
            var text when text.Contains("skip") =>
                $"I can propose skipping {stopName}. Review the route impact before accepting it.",
            var text when text.Contains("short") || text.Contains("only have") =>
                "I can propose a shorter route that keeps completed stops and trims lower-priority remaining stops.",
            var text when text.Contains("coffee") || text.Contains("nearby") || text.Contains("find") =>
                "I can propose a nearby discovery and show the added time and distance before you add it.",
            var text when text.Contains("longer") || text.Contains("extend") =>
                "I can propose an optional extension. I will not add it unless you accept the route change.",
            var text when text.Contains("back") || text.Contains("return") =>
                "I can propose returning to the starting area and show the route impact before applying it.",
            var text when text.Contains("rejoin") =>
                "I can propose a rejoin route from your current location to the next sensible stop.",
            var text when text.Contains("story-style") || text.Contains("route or place") || text.Contains("while i walk") =>
                StoryContextAnswer(context, stop, stopName),
            var text when text.Contains("where") || text.Contains("next") =>
                $"You are focused on {stopName}. The next route action is informational only: keep following the planned walk and stay aware of crossings.",
            var text when text.Contains("history") || text.Contains("why") =>
                $"{stopName} is on this walk because {stop?.Narration ?? context.RouteSummary} Sponsored content, if present, stays disclosed in Rover.",
            var text when text.Contains("access") || text.Contains("stairs") || text.Contains("wheel") =>
                $"For accessibility, Rover is preserving your route preferences: {string.Join(", ", context.AccessibilityPreferences)}. I will not reroute you in Phase 5.",
            var text when text.Contains("sponsor") && stop?.SponsoredDisclosure is { Length: > 0 } =>
                $"This stop includes sponsored content: {stop.SponsoredDisclosure}",
            _ =>
                $"Mock Rover answer for {stopName}: {stop?.ShortDescription ?? context.RouteSummary} I can answer from the current walk context, but I do not use live events or weather in Phase 5."
        };

        return Task.FromResult(new RoverConversationProviderResult(
            answer,
            suggestedAction,
            "Stay aware of traffic, crossings, surfaces, and people around you."));
    }

    private static string StoryContextAnswer(RoverConversationContext context, Domain.Walks.WalkStop? stop, string stopName)
    {
        if (stop is null)
        {
            return $"You are on an active Rover walk. {context.RouteSummary}";
        }

        var address = string.IsNullOrWhiteSpace(stop.Address)
            ? string.Empty
            : $" The stop details list it near {stop.Address}.";
        var website = string.IsNullOrWhiteSpace(stop.WebsiteUrl)
            ? string.Empty
            : " A website is available in the stop card if you want to check hours or details.";
        return $"On the way to {stopName}, Rover has this grounded stop context: {stop.ShortDescription}.{address}{website}";
    }

    private static string SuggestedActionFor(string question)
    {
        if (question.Contains("quiet for")) return "QuietStories";
        if (question.Contains("resume stories")) return "ResumeStories";
        if (question.Contains("tell me more stories like")) return "PreferSimilarStories";
        if (question.Contains("tell me more")) return "TellMore";
        if (question.Contains("short version")) return "ShortStory";
        if (question.Contains("more history")) return "PreferHistory";
        if (question.Contains("happening around here") || question.Contains("around here today")) return "CurrentLocalInformation";
        if (question.Contains("fewer weather")) return "ReduceWeatherStories";
        if (question.Contains("don't tell me stories like") || question.Contains("do not tell me stories like")) return "DismissStoryCategory";
        if (question.Contains("story-style") || question.Contains("route or place") || question.Contains("while i walk")) return "Informational";
        if (question.Contains("skip")) return "SkipStop";
        if (question.Contains("short") || question.Contains("only have")) return "ShortenWalk";
        if (question.Contains("coffee") || question.Contains("nearby") || question.Contains("find")) return "AddDiscovery";
        if (question.Contains("longer") || question.Contains("extend")) return "ExtendWalk";
        if (question.Contains("back") || question.Contains("return")) return "ReturnToStart";
        if (question.Contains("rejoin")) return "RejoinRoute";
        return "Informational";
    }
}

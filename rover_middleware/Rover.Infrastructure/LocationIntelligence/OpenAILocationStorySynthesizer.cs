using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Infrastructure.Conversation;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class OpenAILocationStorySynthesizer : ILocationStorySynthesizer
{
    private readonly HttpClient _httpClient;
    private readonly OpenAIRoverConversationOptions _openAIOptions;
    private readonly LocationIntelligenceOptions _locationOptions;
    private readonly SafeFallbackLocationStorySynthesizer _fallback = new();

    public OpenAILocationStorySynthesizer(
        HttpClient httpClient,
        OpenAIRoverConversationOptions openAIOptions,
        LocationIntelligenceOptions locationOptions)
    {
        _httpClient = httpClient;
        _openAIOptions = openAIOptions;
        _locationOptions = locationOptions;
    }

    public async Task<LocationStoryResult> CreateStoryAsync(
        LocationStoryContext context,
        IReadOnlyCollection<string> selectedPlaceIds,
        string? narrationStyle,
        CancellationToken cancellationToken)
    {
        if (!_locationOptions.OpenAISynthesisEnabled
            || string.IsNullOrWhiteSpace(_openAIOptions.ApiKey)
            || string.IsNullOrWhiteSpace(_openAIOptions.Model))
        {
            return await _fallback.CreateStoryAsync(context, selectedPlaceIds, narrationStyle, cancellationToken);
        }

        var selected = context.RankedPlaces
            .Where(place => selectedPlaceIds.Count == 0 || selectedPlaceIds.Contains(place.CanonicalId, StringComparer.OrdinalIgnoreCase))
            .Take(4)
            .ToArray();
        var facts = selected
            .SelectMany(place => place.Facts.Select(fact => new PromptEvidence(
                place.CanonicalId,
                place.Name,
                fact.FactId,
                fact.FactType,
                fact.FactText,
                fact.ConfidenceScore,
                fact.Source.ProviderName)))
            .Where(fact => fact.confidence >= 0.6)
            .Concat(selected.Select(place => new PromptEvidence(
                place.CanonicalId,
                place.Name,
                $"{place.CanonicalId}:identity",
                "place_identity",
                IdentityText(place),
                place.ConfidenceScore,
                string.Join(", ", place.SourceReferences.Select(source => source.ProviderName).Distinct(StringComparer.OrdinalIgnoreCase)))))
            .Concat(selected.Where(place => place.DistanceFromUserMeters is not null).Select(place => new PromptEvidence(
                place.CanonicalId,
                place.Name,
                $"{place.CanonicalId}:relative-location",
                "inference",
                $"{place.Name} is {DistancePhrase(place.DistanceFromUserMeters!.Value)} to the {place.DirectionFromUser ?? "nearby"}.",
                place.ConfidenceScore,
                "Rover device location and mapped place coordinates")))
            .Take(16)
            .ToArray();
        if (facts.Length == 0)
        {
            return await _fallback.CreateStoryAsync(context, selectedPlaceIds, narrationStyle, cancellationToken);
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_openAIOptions.TimeoutSeconds, 3, 60)));
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _openAIOptions.ApiKey);
        if (!string.IsNullOrWhiteSpace(_openAIOptions.OrganizationId))
        {
            request.Headers.TryAddWithoutValidation("OpenAI-Organization", _openAIOptions.OrganizationId);
        }

        if (!string.IsNullOrWhiteSpace(_openAIOptions.ProjectId))
        {
            request.Headers.TryAddWithoutValidation("OpenAI-Project", _openAIOptions.ProjectId);
        }

        request.Content = JsonContent.Create(new
        {
            model = _openAIOptions.Model,
            input = new object[]
            {
                new
                {
                    role = "system",
                    content = """
                    You are Rover's location story writer.
                    Use only the supplied facts. Do not invent dates, names, legends, hours, distances, directions, accessibility details, events, or quotes.
                    A sourced map POI fact is verified local content. If only a POI name, category, address, distance, or direction is available, still produce a useful modest narration from those facts instead of saying there is not enough information.
                    Never apologize for thin context. Say what is known, keep it brief, and invite the walker to notice the place in front of them.
                    Return compact JSON only with: storyTitle, placeId, factIdsUsed, sections, confidence, warnings.
                    sections must contain cameraTeaser, arrival, and deeper. Each section contains a sentences array.
                    Each sentence must contain: sentenceId, text, contentType, evidenceIds, confidence.
                    contentType must be fact, inference, or unavailable. Every fact or inference sentence must cite one or more supplied evidence IDs.
                    factIdsUsed and sentence evidenceIds must contain only evidence IDs from the supplied facts.
                    Keep cameraTeaser under 40 words, arrival under 150 words, and deeper under 450 words. Do not pad a section when evidence is sparse; use an explicit "ROVER could not verify this yet" unavailable sentence instead.
                    Personalization may change evidence order, emphasis, vocabulary, and length. It must not change the facts.
                    """
                },
                new
                {
                    role = "user",
                    content = JsonSerializer.Serialize(new
                    {
                        userCoordinates = new { context.UserCoordinates.Latitude, context.UserCoordinates.Longitude },
                        context.SearchRadiusMeters,
                        narrationStyle,
                        weather = context.WeatherTimeContext?.Summary,
                        places = selected.Select(place => new
                        {
                            place.CanonicalId,
                            place.Name,
                            place.DistanceFromUserMeters,
                            place.DistanceFromRouteMeters,
                            place.EstimatedDetourMinutes,
                            place.DirectionFromUser,
                            place.StoryWorthinessReasons
                        }),
                        facts
                    })
                }
            },
            max_output_tokens = 1600
        });

        using var response = await _httpClient.SendAsync(request, timeout.Token);
        if (!response.IsSuccessStatusCode)
        {
            return (await _fallback.CreateStoryAsync(context, selectedPlaceIds, narrationStyle, cancellationToken)) with
            {
                Warnings = new[] { $"OpenAI story synthesis failed with status {(int)response.StatusCode}." }
            };
        }

        await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
        var text = ExtractOutputText(document.RootElement);
        if (string.IsNullOrWhiteSpace(text))
        {
            return await _fallback.CreateStoryAsync(context, selectedPlaceIds, narrationStyle, cancellationToken);
        }

        return ParseAndValidate(text, context, selected, facts.Select(fact => fact.factId).ToHashSet(StringComparer.OrdinalIgnoreCase))
            ?? await _fallback.CreateStoryAsync(context, selectedPlaceIds, narrationStyle, cancellationToken);
    }

    private static LocationStoryResult? ParseAndValidate(string text, LocationStoryContext context, IReadOnlyList<LocationPlace> selected, ISet<string> allowedFactIds)
    {
        try
        {
            using var json = JsonDocument.Parse(text);
            var root = json.RootElement;
            var factIds = root.TryGetProperty("factIdsUsed", out var factsElement) && factsElement.ValueKind == JsonValueKind.Array
                ? factsElement.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToArray()
                : Array.Empty<string>();
            if (factIds.Any(factId => !allowedFactIds.Contains(factId)))
            {
                return null;
            }

            var storySections = new List<GroundedStorySection>();
            if (root.TryGetProperty("sections", out var sectionsElement) && sectionsElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var sectionElement in sectionsElement.EnumerateArray())
                {
                    if (!Enum.TryParse<StorySectionType>(Read(sectionElement, "sectionType"), true, out var sectionType)
                        || !sectionElement.TryGetProperty("sentences", out var sectionSentences)
                        || sectionSentences.ValueKind != JsonValueKind.Array)
                    {
                        return null;
                    }

                    var parsedSentences = ParseSentences(sectionSentences, allowedFactIds, sectionType);
                    if (parsedSentences is null)
                    {
                        return null;
                    }

                    storySections.Add(new GroundedStorySection(sectionType, parsedSentences));
                }
            }
            else if (root.TryGetProperty("sentences", out var sentenceElement) && sentenceElement.ValueKind == JsonValueKind.Array)
            {
                var parsedSentences = ParseSentences(sentenceElement, allowedFactIds, StorySectionType.Arrival);
                if (parsedSentences is null)
                {
                    return null;
                }

                storySections.Add(new GroundedStorySection(StorySectionType.Arrival, parsedSentences));
            }
            else
            {
                return null;
            }

            if (storySections.Count == 0
                || storySections.GroupBy(section => section.SectionType).Any(group => group.Count() > 1)
                || storySections.SelectMany(section => section.Sentences).Any() is false)
            {
                return null;
            }

            var sentences = storySections.FirstOrDefault(section => section.SectionType == StorySectionType.Arrival)?.Sentences
                ?? storySections[0].Sentences;

            factIds = storySections.SelectMany(section => section.Sentences).SelectMany(sentence => sentence.EvidenceIds)
                .Concat(factIds)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            var placeId = root.TryGetProperty("placeId", out var placeElement) ? placeElement.GetString() : selected.FirstOrDefault()?.CanonicalId;
            var place = selected.FirstOrDefault(candidate => candidate.CanonicalId.Equals(placeId, StringComparison.OrdinalIgnoreCase)) ?? selected.FirstOrDefault();
            var sources = selected.SelectMany(candidate => candidate.Facts)
                .Where(fact => factIds.Contains(fact.FactId, StringComparer.OrdinalIgnoreCase))
                .Select(fact => fact.Source)
                .Concat(selected.Where(candidate => factIds.Contains($"{candidate.CanonicalId}:identity", StringComparer.OrdinalIgnoreCase)
                        || factIds.Contains($"{candidate.CanonicalId}:relative-location", StringComparer.OrdinalIgnoreCase))
                    .SelectMany(candidate => candidate.SourceReferences))
                .GroupBy(source => $"{source.ProviderName}:{source.ProviderRecordId}:{source.SourceUrl}", StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .ToArray();
            var warnings = root.TryGetProperty("warnings", out var warningElement) && warningElement.ValueKind == JsonValueKind.Array
                ? warningElement.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).ToArray()
                : Array.Empty<string>();

            return new LocationStoryResult(
                Read(root, "storyTitle") ?? place?.Name ?? "Nearby story",
                string.Join(" ", sentences.Select(sentence => sentence.Text)),
                storySections.FirstOrDefault(section => section.SectionType == StorySectionType.Deeper) is { } deeper
                    ? string.Join(" ", deeper.Sentences.Select(sentence => sentence.Text))
                    : Read(root, "tellMeMore"),
                place?.CanonicalId,
                factIds,
                sources,
                root.TryGetProperty("confidence", out var confidence) && confidence.ValueKind == JsonValueKind.Number ? Math.Clamp(confidence.GetDouble(), 0, 1) : 0.7,
                sources.Select(source => source.Attribution).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
                warnings)
            {
                SentenceGrounding = sentences,
                StorySections = storySections
            };
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? ExtractOutputText(JsonElement root)
    {
        if (root.TryGetProperty("output_text", out var outputText))
        {
            return outputText.GetString();
        }

        if (!root.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            foreach (var part in content.EnumerateArray())
            {
                if (part.TryGetProperty("text", out var text))
                {
                    return text.GetString();
                }
            }
        }

        return null;
    }

    private static string? Read(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static IReadOnlyList<GroundedStorySentence>? ParseSentences(
        JsonElement sentenceElement,
        ISet<string> allowedFactIds,
        StorySectionType sectionType)
    {
        var sentences = new List<GroundedStorySentence>();
        foreach (var item in sentenceElement.EnumerateArray())
        {
            var sentenceText = Read(item, "text");
            if (string.IsNullOrWhiteSpace(sentenceText))
            {
                return null;
            }

            var evidenceIds = item.TryGetProperty("evidenceIds", out var evidenceElement) && evidenceElement.ValueKind == JsonValueKind.Array
                ? evidenceElement.EnumerateArray().Where(value => value.ValueKind == JsonValueKind.String).Select(value => value.GetString()!).ToArray()
                : Array.Empty<string>();
            if (evidenceIds.Any(evidenceId => !allowedFactIds.Contains(evidenceId)))
            {
                return null;
            }

            if (!Enum.TryParse<StorySentenceContentType>(Read(item, "contentType"), true, out var contentType)
                || contentType != StorySentenceContentType.Unavailable && evidenceIds.Length == 0)
            {
                return null;
            }

            sentences.Add(new GroundedStorySentence(
                Read(item, "sentenceId") ?? $"{sectionType.ToString().ToLowerInvariant()}-{sentences.Count + 1}",
                sentenceText,
                contentType,
                evidenceIds,
                item.TryGetProperty("confidence", out var sentenceConfidence) && sentenceConfidence.ValueKind == JsonValueKind.Number
                    ? Math.Clamp(sentenceConfidence.GetDouble(), 0, 1)
                    : 0.7));
        }

        return sentences.Count == 0 ? null : sentences;
    }

    private static string IdentityText(LocationPlace place)
    {
        var category = place.Categories.FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(category) && !string.IsNullOrWhiteSpace(place.Address))
        {
            return $"{place.Name} is listed as {category} at {place.Address}.";
        }

        return !string.IsNullOrWhiteSpace(place.Address)
            ? $"{place.Name} is listed at {place.Address}."
            : string.IsNullOrWhiteSpace(category)
                ? $"{place.Name} is a mapped place."
                : $"{place.Name} is listed as {category}.";
    }

    private static string DistancePhrase(double meters)
        => meters < 1000 ? $"{Math.Round(meters)} meters away" : $"{Math.Round(meters / 1000, 1)} kilometers away";

    private sealed record PromptEvidence(
        string placeId,
        string placeName,
        string factId,
        string factType,
        string factText,
        double confidence,
        string source);
}

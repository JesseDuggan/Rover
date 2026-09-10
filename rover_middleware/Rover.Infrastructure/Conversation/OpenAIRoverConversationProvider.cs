using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.Conversation;

namespace Rover.Infrastructure.Conversation;

public sealed class OpenAIRoverConversationProvider : IRoverConversationProvider
{
    private readonly HttpClient _httpClient;
    private readonly OpenAIRoverConversationOptions _options;
    private readonly RoverPromptBuilder _promptBuilder;

    public OpenAIRoverConversationProvider(
        HttpClient httpClient,
        OpenAIRoverConversationOptions options,
        RoverPromptBuilder promptBuilder)
    {
        _httpClient = httpClient;
        _options = options;
        _promptBuilder = promptBuilder;
    }

    public string Name => "OpenAI";

    public async Task<RoverConversationProviderResult> AnswerAsync(
        RoverConversationContext context,
        string questionText,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            throw new InvalidOperationException("OpenAI conversation mode requires OPENAI_API_KEY.");
        }

        if (string.IsNullOrWhiteSpace(_options.Model))
        {
            throw new InvalidOperationException("OpenAI conversation mode requires OPENAI_MODEL.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 3, 60)));

        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        if (!string.IsNullOrWhiteSpace(_options.OrganizationId))
        {
            request.Headers.TryAddWithoutValidation("OpenAI-Organization", _options.OrganizationId);
        }

        if (!string.IsNullOrWhiteSpace(_options.ProjectId))
        {
            request.Headers.TryAddWithoutValidation("OpenAI-Project", _options.ProjectId);
        }

        var payload = new Dictionary<string, object?>
        {
            ["model"] = _options.Model,
            ["input"] = new object[]
            {
                new
                {
                    role = "system",
                    content = _promptBuilder.BuildSystemInstructions()
                },
                new
                {
                    role = "user",
                    content = $"Walk context:\n{_promptBuilder.BuildContext(context)}\n\nQuestion:\n{questionText}"
                }
            },
            ["max_output_tokens"] = 320
        };
        if (_options.WebSearchEnabled)
        {
            payload["tools"] = new object[]
            {
                new
                {
                    type = "web_search",
                    search_context_size = "low"
                }
            };
        }

        request.Content = JsonContent.Create(payload);

        using var response = await _httpClient.SendAsync(request, timeout.Token);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            throw new InvalidOperationException("OpenAI provider authorization failed.");
        }

        if ((int)response.StatusCode == 429)
        {
            throw new InvalidOperationException("OpenAI provider rate limit reached.");
        }

        if (!response.IsSuccessStatusCode)
        {
            var requestId = response.Headers.TryGetValues("x-request-id", out var values)
                ? values.FirstOrDefault()
                : null;
            throw new InvalidOperationException(
                string.IsNullOrWhiteSpace(requestId)
                    ? "OpenAI provider request failed."
                    : $"OpenAI provider request failed. Request ID: {requestId}");
        }

        await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
        var text = ExtractOutputText(document.RootElement);
        return new RoverConversationProviderResult(
            string.IsNullOrWhiteSpace(text)
                ? "I do not have enough information to answer that from this walk context."
                : text,
            "Informational",
            "Stay aware of traffic, crossings, surfaces, and people around you.");
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
}

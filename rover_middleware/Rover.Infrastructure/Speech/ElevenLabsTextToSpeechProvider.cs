using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class ElevenLabsTextToSpeechProvider : ITextToSpeechProvider
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ElevenLabsSpeechOptions _options;
    private readonly ILogger<ElevenLabsTextToSpeechProvider>? _logger;

    public ElevenLabsTextToSpeechProvider(IHttpClientFactory httpClientFactory, ElevenLabsSpeechOptions options,
        ILogger<ElevenLabsTextToSpeechProvider>? logger = null)
    {
        _httpClientFactory = httpClientFactory;
        _options = options;
        _logger = logger;
    }

    public string Name => "ElevenLabs";

    public async Task<RenderedSpeech> RenderAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken)
    {
        if (!_options.Enabled || string.IsNullOrWhiteSpace(_options.ApiKey) || string.IsNullOrWhiteSpace(_options.VoiceId) || string.IsNullOrWhiteSpace(_options.ModelId))
        {
            throw new InvalidOperationException("ElevenLabs is not configured.");
        }

        var client = _httpClientFactory.CreateClient("ElevenLabs");
        client.Timeout = TimeSpan.FromSeconds(Math.Clamp(_options.RequestTimeoutSeconds, 1, 60));
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://api.elevenlabs.io/v1/text-to-speech/{Uri.EscapeDataString(_options.VoiceId)}?output_format={Uri.EscapeDataString(_options.OutputFormat)}");
        request.Headers.TryAddWithoutValidation("xi-api-key", _options.ApiKey.Trim());
        request.Headers.TryAddWithoutValidation("X-Correlation-ID", correlationId);
        request.Content = JsonContent.Create(new
        {
            text = text.Text,
            model_id = _options.ModelId,
            voice_settings = new
            {
                stability = _options.Stability,
                similarity_boost = _options.Similarity,
                style = _options.Style,
                use_speaker_boost = _options.SpeakerBoost
            }
        });

        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var code = "unclassified";
            try
            {
                using var error = await JsonDocument.ParseAsync(
                    await response.Content.ReadAsStreamAsync(cancellationToken),
                    cancellationToken: cancellationToken);
                if (error.RootElement.ValueKind == JsonValueKind.Object
                    && error.RootElement.TryGetProperty("detail", out var detail)
                    && detail.ValueKind == JsonValueKind.Object
                    && detail.TryGetProperty("status", out var status)
                    && status.ValueKind == JsonValueKind.String)
                {
                    code = status.GetString() switch
                    {
                        "invalid_api_key" => "invalid_api_key",
                        "missing_api_key" => "missing_api_key",
                        "missing_permissions" => "missing_permissions",
                        "insufficient_permissions" => "insufficient_permissions",
                        "detected_unusual_activity" => "detected_unusual_activity",
                        "quota_exceeded" => "quota_exceeded",
                        "voice_not_found" => "voice_not_found",
                        "model_not_found" => "model_not_found",
                        _ => "unclassified"
                    };
                }
            }
            catch (JsonException) { }
            // Never log provider bodies, credentials or narration text.
            _logger?.LogWarning("ElevenLabs speech failed: HTTP {Status}; code={Code}. Check server key, TTS permissions, voice access and quota.",
                (int)response.StatusCode, code);
            throw new InvalidOperationException($"ElevenLabs request failed with HTTP {(int)response.StatusCode}; code={code}.");
        }

        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (bytes.Length == 0)
        {
            throw new InvalidOperationException("ElevenLabs returned an empty audio response.");
        }

        return new RenderedSpeech(bytes, "audio/mpeg", Name, false, false, correlationId);
    }
}

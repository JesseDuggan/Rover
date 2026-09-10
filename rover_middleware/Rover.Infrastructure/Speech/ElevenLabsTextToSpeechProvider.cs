using System.Net.Http.Json;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class ElevenLabsTextToSpeechProvider : ITextToSpeechProvider
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ElevenLabsSpeechOptions _options;

    public ElevenLabsTextToSpeechProvider(IHttpClientFactory httpClientFactory, ElevenLabsSpeechOptions options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options;
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
        request.Headers.TryAddWithoutValidation("xi-api-key", _options.ApiKey);
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
            throw new InvalidOperationException($"ElevenLabs request failed with HTTP {(int)response.StatusCode}.");
        }

        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (bytes.Length == 0)
        {
            throw new InvalidOperationException("ElevenLabs returned an empty audio response.");
        }

        return new RenderedSpeech(bytes, "audio/mpeg", Name, false, false, correlationId);
    }
}

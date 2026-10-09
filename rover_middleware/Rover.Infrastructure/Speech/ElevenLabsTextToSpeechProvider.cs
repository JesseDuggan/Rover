using System.Net.Http.Json;
using System.Net.WebSockets;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class ElevenLabsTextToSpeechProvider : ITextToSpeechProvider
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ElevenLabsSpeechOptions _options;
    private readonly ILogger<ElevenLabsTextToSpeechProvider>? _logger;
    private readonly IElevenLabsWebSocketFactory _webSocketFactory;

    public ElevenLabsTextToSpeechProvider(IHttpClientFactory httpClientFactory, ElevenLabsSpeechOptions options,
        ILogger<ElevenLabsTextToSpeechProvider>? logger = null,
        IElevenLabsWebSocketFactory? webSocketFactory = null)
    {
        _httpClientFactory = httpClientFactory;
        _options = options;
        _logger = logger;
        _webSocketFactory = webSocketFactory ?? new ElevenLabsWebSocketFactory();
    }

    public string Name => "ElevenLabs";

    public async Task<RenderedSpeech> RenderAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken)
    {
        if (!_options.Enabled || string.IsNullOrWhiteSpace(_options.ApiKey) || string.IsNullOrWhiteSpace(_options.VoiceId) || string.IsNullOrWhiteSpace(_options.ModelId))
        {
            throw new InvalidOperationException("ElevenLabs is not configured.");
        }

        if (_options.ModelId == "eleven_v4_turbo")
        {
            return await RenderDialogueAsync(text, correlationId, cancellationToken);
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
                    code = SafeErrorCode(status);
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

    private async Task<RenderedSpeech> RenderDialogueAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken)
    {
        if (!_options.OutputFormat.StartsWith("mp3_", StringComparison.Ordinal))
            throw new InvalidOperationException("ElevenLabs dialogue requires an MP3 output format for the mobile audio contract.");

        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.RequestTimeoutSeconds, 1, 60)));
        var token = deadline.Token;
        try
        {
            var uri = new Uri("wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input"
                + $"?model_id={Uri.EscapeDataString(_options.ModelId!)}&output_format={Uri.EscapeDataString(_options.OutputFormat)}");
            using var socket = await _webSocketFactory.ConnectAsync(uri, _options.ApiKey!.Trim(), correlationId, token);
            await SendFrameAsync(socket, new
            {
                voices = new[] { _options.VoiceId },
                voice_settings = new
                {
                    stability = _options.Stability,
                    similarity_boost = _options.Similarity
                }
            }, token);
            await SendFrameAsync(socket, new
            {
                inputs = new[] { new { text = text.Text, voice_id = _options.VoiceId, new_turn = false } }
            }, token);
            await SendFrameAsync(socket, new { close_socket = true }, token);

            using var audio = new MemoryStream();
            var buffer = new byte[16 * 1024];
            for (var messages = 0; messages < 1024; messages++)
            {
                using var message = new MemoryStream();
                WebSocketReceiveResult received;
                do
                {
                    received = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                    if (received.MessageType != WebSocketMessageType.Text)
                        throw DialogueFailure("incomplete_stream");
                    if (message.Length + received.Count > 4 * 1024 * 1024)
                        throw DialogueFailure("response_too_large");
                    message.Write(buffer, 0, received.Count);
                } while (!received.EndOfMessage);

                message.Position = 0;
                using var document = await JsonDocument.ParseAsync(message, cancellationToken: token);
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object)
                    throw DialogueFailure("invalid_response");
                if (root.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null
                    || root.TryGetProperty("message", out _) && root.TryGetProperty("code", out _))
                {
                    var code = root.TryGetProperty("code", out var errorCode) ? SafeErrorCode(errorCode) : "unclassified";
                    if (code == "unclassified") code = SafeErrorCode(error);
                    throw DialogueFailure(code);
                }
                if (root.TryGetProperty("audio", out var chunk) && chunk.ValueKind != JsonValueKind.Null)
                {
                    if (chunk.ValueKind != JsonValueKind.String)
                        throw DialogueFailure("invalid_response");
                    var bytes = Convert.FromBase64String(chunk.GetString()!);
                    if (audio.Length + bytes.Length > 16 * 1024 * 1024)
                        throw DialogueFailure("response_too_large");
                    audio.Write(bytes);
                }

                // A turn marker can precede encoder tail bytes. Publish only a complete session.
                if (root.TryGetProperty("is_final", out var final) && final.ValueKind == JsonValueKind.True)
                {
                    if (audio.Length == 0) throw DialogueFailure("empty_audio");
                    return new RenderedSpeech(audio.ToArray(), "audio/mpeg", Name, false, false, correlationId);
                }
            }
            throw DialogueFailure("response_too_large");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw DialogueFailure("timeout");
        }
        catch (WebSocketException)
        {
            throw DialogueFailure("connection_failed");
        }
        catch (Exception error) when (error is JsonException or FormatException)
        {
            throw DialogueFailure("invalid_response");
        }
    }

    private InvalidOperationException DialogueFailure(string code)
    {
        // Provider messages and close descriptions may contain credentials or narration text.
        _logger?.LogWarning("ElevenLabs dialogue speech failed: code={Code}. Check TTS permissions, voice/model access and quota.", code);
        return new InvalidOperationException($"ElevenLabs dialogue request failed; code={code}.");
    }

    private static Task SendFrameAsync(WebSocket socket, object payload, CancellationToken cancellationToken)
        => socket.SendAsync(new ArraySegment<byte>(JsonSerializer.SerializeToUtf8Bytes(payload)),
            WebSocketMessageType.Text, true, cancellationToken);

    private static string SafeErrorCode(JsonElement value)
        => value.ValueKind == JsonValueKind.String ? value.GetString() switch
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
        } : "unclassified";
}

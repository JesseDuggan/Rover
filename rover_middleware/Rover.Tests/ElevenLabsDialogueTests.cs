using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Rover.Application.Speech;
using Rover.Infrastructure.Speech;

internal static class ElevenLabsDialogueTests
{
    private const string Voice = "existing-walkabout-voice";
    private const string Secret = "test-private-key";
    private static readonly PreparedSpeechText Text = new("Welcome to Walkabout. Look around and discover the stories along your route.", SpeechPurpose.AdaptiveRouteStory, "en", "1");

    public static async Task ProtocolAndVoice()
    {
        var options = Options();
        var socket = new FakeSocket();
        var json = JsonSerializer.Serialize(new { audio = Convert.ToBase64String(new byte[] { 1, 2, 3 }) });
        socket.Enqueue(json[..10], end: false);
        socket.Enqueue(json[10..]);
        socket.Enqueue("{\"is_final_audio_for_turn\":true}");
        socket.Enqueue("{\"audio\":\"BAU=\",\"is_final\":true}");
        var factory = new FakeFactory(socket);
        var speech = await Provider(options, factory).RenderAsync(Text, "voice-check", default);
        Require(speech.Audio.SequenceEqual(new byte[] { 1, 2, 3, 4, 5 }), "All audio, including encoder tail bytes, must be retained.");
        Require(speech.ContentType == "audio/mpeg" && speech.Provider == "ElevenLabs"
            && !speech.UsedFallback && !speech.CacheHit && speech.CorrelationId == "voice-check", "The mobile speech contract must stay unchanged.");
        Require(factory.Uri?.AbsoluteUri == "wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input?model_id=eleven_v4_turbo&output_format=mp3_44100_128", "v4 Turbo must use the dialogue WebSocket.");
        Require(factory.Key == Secret && factory.CorrelationId == "voice-check", "Credentials and correlation must reach the connection factory.");
        Require(socket.Sent.Count == 3 && socket.Disposed, "A bounded single narration session must be disposed.");
        using var registration = JsonDocument.Parse(socket.Sent[0]);
        var root = registration.RootElement;
        Require(root.GetProperty("voices").EnumerateArray().Single().GetString() == Voice, "The existing voice must be preserved.");
        var settings = root.GetProperty("voice_settings");
        Require(settings.EnumerateObject().Count() == 2 && settings.GetProperty("stability").GetDouble() == 0.45
            && settings.GetProperty("similarity_boost").GetDouble() == 0.75, "Only approved supported voice settings belong in v4 requests.");
        using var input = JsonDocument.Parse(socket.Sent[1]);
        var line = input.RootElement.GetProperty("inputs").EnumerateArray().Single();
        Require(line.GetProperty("text").GetString() == Text.Text && line.GetProperty("voice_id").GetString() == Voice
            && !line.GetProperty("new_turn").GetBoolean(), "Narration must use the same voice and unchanged text.");
        Require(socket.Sent[2] == "{\"close_socket\":true}", "A short narration must be flushed, not wait for more text.");
        Require(socket.Sent.All(frame => !frame.Contains(Secret)), "Credentials must not be placed in dialogue frames.");
        Require(options.Style == 0 && options.SpeakerBoost && options.VoiceId == Voice, "Stored legacy settings must not be mutated.");
    }

    public static async Task LegacyModel()
    {
        var options = Options();
        options.ModelId = "eleven_multilingual_v2";
        using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
        {
            Require(request.Method == HttpMethod.Post && request.RequestUri?.AbsoluteUri == $"https://api.elevenlabs.io/v1/text-to-speech/{Voice}?output_format=mp3_44100_128", "Rollback must retain the legacy endpoint.");
            Require(request.Headers.GetValues("xi-api-key").Single() == Secret, "Legacy credentials must remain trimmed.");
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var settings = body.RootElement.GetProperty("voice_settings");
            Require(body.RootElement.GetProperty("model_id").GetString() == options.ModelId
                && body.RootElement.GetProperty("text").GetString() == Text.Text, "Legacy text and model must remain unchanged.");
            Require(settings.EnumerateObject().Count() == 4 && settings.GetProperty("stability").GetDouble() == 0.45
                && settings.GetProperty("similarity_boost").GetDouble() == 0.75
                && settings.GetProperty("style").GetDouble() == 0 && settings.GetProperty("use_speaker_boost").GetBoolean(), "Rollback must retain every existing voice setting.");
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(new byte[] { 9, 8, 7 }) };
        }));
        var factory = new FakeFactory(new FakeSocket());
        var speech = await new ElevenLabsTextToSpeechProvider(new SingleHttpClientFactory(client), options,
            webSocketFactory: factory).RenderAsync(Text, "legacy", default);
        Require(speech.Audio.SequenceEqual(new byte[] { 9, 8, 7 }) && factory.Calls == 0, "Legacy models must not open dialogue sessions.");
    }

    public static async Task SafeFailures()
    {
        foreach (var code in new[] { "missing_permissions", "quota_exceeded", "voice_not_found", "model_not_found", Secret })
        {
            var socket = new FakeSocket();
            socket.Enqueue(JsonSerializer.Serialize(new { error = "private-provider-message", code, message = Secret }));
            await ExpectFailure(() => Provider(Options(), new FakeFactory(socket)).RenderAsync(Text, "test", default),
                code == Secret ? "unclassified" : code);
            Require(socket.Disposed, "Rejected sessions must be disposed.");
        }
        var connection = new FakeFactory(new FakeSocket()) { FailConnect = true };
        await ExpectFailure(() => Provider(Options(), connection).RenderAsync(Text, "test", default), "connection_failed");
        var receiveFailure = new FakeSocket { FailReceive = true };
        await ExpectFailure(() => Provider(Options(), new FakeFactory(receiveFailure)).RenderAsync(Text, "test", default), "connection_failed");
        Require(receiveFailure.Disposed, "A failed receive must release its socket.");
    }

    public static async Task InvalidAndIncompleteStreams()
    {
        foreach (var (frame, code) in new[]
        {
            ("{\"is_final\":true}", "empty_audio"),
            ("{\"audio\":\"AQ==\"}", "incomplete_stream"),
            ("{\"audio\":\"not base64!\",\"is_final\":true}", "invalid_response"),
            ("{\"audio\":42}", "invalid_response"),
            ("[1,2,3]", "invalid_response"),
            ("broken json " + Secret, "invalid_response")
        })
        {
            var socket = new FakeSocket();
            socket.Enqueue(frame);
            await ExpectFailure(() => Provider(Options(), new FakeFactory(socket)).RenderAsync(Text, "test", default), code);
            Require(socket.Disposed, "Invalid sessions must be disposed without exposing partial audio.");
        }
        var binary = new FakeSocket();
        binary.Enqueue("not text", type: WebSocketMessageType.Binary);
        await ExpectFailure(() => Provider(Options(), new FakeFactory(binary)).RenderAsync(Text, "test", default), "incomplete_stream");
    }

    public static async Task Bounds()
    {
        var oversized = new FakeSocket();
        oversized.Enqueue(new string('x', 4 * 1024 * 1024 + 1));
        await ExpectFailure(() => Provider(Options(), new FakeFactory(oversized)).RenderAsync(Text, "test", default), "response_too_large");
        var manyMessages = new FakeSocket();
        for (var i = 0; i < 1024; i++) manyMessages.Enqueue("{}");
        await ExpectFailure(() => Provider(Options(), new FakeFactory(manyMessages)).RenderAsync(Text, "test", default), "response_too_large");
        var tooMuchAudio = new FakeSocket();
        var chunk = JsonSerializer.Serialize(new { audio = Convert.ToBase64String(new byte[1024 * 1024]) });
        for (var i = 0; i < 17; i++) tooMuchAudio.Enqueue(chunk);
        await ExpectFailure(() => Provider(Options(), new FakeFactory(tooMuchAudio)).RenderAsync(Text, "test", default), "response_too_large");
    }

    public static async Task DeadlinesAndCancellation()
    {
        var options = Options();
        options.RequestTimeoutSeconds = 1;
        var connecting = new FakeFactory(new FakeSocket()) { StallConnect = true };
        await ExpectFailure(() => Provider(options, connecting).RenderAsync(Text, "test", default), "timeout");
        var receiving = new FakeSocket { StallReceive = true };
        await ExpectFailure(() => Provider(options, new FakeFactory(receiving)).RenderAsync(Text, "test", default), "timeout");
        Require(receiving.Disposed, "A receive timeout must release the socket.");
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        var cancelled = new FakeSocket { StallReceive = true };
        try
        {
            await Provider(Options(), new FakeFactory(cancelled)).RenderAsync(Text, "test", cancellation.Token);
            throw new Exception("Caller cancellation must stop synthesis.");
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        Require(cancelled.Disposed, "Caller cancellation must dispose its connection.");
    }

    public static async Task CacheAndFallback()
    {
        var options = Options();
        var socket = new FakeSocket();
        socket.Enqueue("{\"audio\":\"AQID\",\"is_final\":true}");
        var factory = new FakeFactory(socket);
        var cache = new MemoryCache();
        var service = new RoverSpeechService(Provider(options, factory), new DevelopmentFakeSpeechProvider(), cache,
            new InMemorySpeechUsageService(options), options, TimeProvider.System);
        var command = new RenderSpeechCommand(Guid.NewGuid(), Text.Text, SpeechPurpose.StopNarration, "en", null, null, null) { CacheEligible = true };
        var first = await service.RenderAsync(command, "first", default);
        var cached = await service.RenderAsync(command, "second", default);
        Require(!first.UsedFallback && cached.CacheHit && factory.Calls == 1, "Repeat narration must use the cache without another synthesis call.");
        Require(cache.LastKey?.ModelId == "eleven_v4_turbo" && cache.LastKey.VoiceId == Voice, "Model and voice must remain in the cache key.");
        Require(!cache.Values.ContainsKey(cache.LastKey! with { ModelId = "eleven_multilingual_v2" }), "v4 and legacy cache entries must remain distinct.");

        var failure = new FakeSocket();
        failure.Enqueue("{\"audio\":\"AQID\"}");
        var failedCache = new MemoryCache();
        var fallback = new RoverSpeechService(Provider(options, new FakeFactory(failure)), new DevelopmentFakeSpeechProvider(), failedCache,
            new InMemorySpeechUsageService(options), options, TimeProvider.System);
        var result = await fallback.RenderAsync(command, "failure", default);
        Require(result.UsedFallback && result.FallbackReason?.Contains("incomplete_stream") == true
            && failedCache.Values.Count == 0, "Incomplete audio must fall back and never enter the narration cache.");
    }

    private static ElevenLabsSpeechOptions Options() => new()
    {
        Enabled = true, ApiKey = " " + Secret + " ", VoiceId = Voice, ModelId = "eleven_v4_turbo"
    };

    private static ElevenLabsTextToSpeechProvider Provider(ElevenLabsSpeechOptions options, FakeFactory factory)
        => new(new RejectHttpFactory(), options, webSocketFactory: factory);

    private static async Task ExpectFailure(Func<Task<RenderedSpeech>> action, string code)
    {
        try { await action(); }
        catch (InvalidOperationException error)
        {
            Require(error.Message == $"ElevenLabs dialogue request failed; code={code}."
                && !error.ToString().Contains(Secret) && !error.ToString().Contains("private-provider-message"), "Only safe diagnostic codes may leave the provider.");
            return;
        }
        throw new Exception("Invalid dialogue must not be accepted as complete narration.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private sealed class RejectHttpFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => throw new Exception("v4 Turbo must not use legacy REST synthesis.");
    }

    private sealed class FakeFactory(FakeSocket socket) : IElevenLabsWebSocketFactory
    {
        public Uri? Uri { get; private set; }
        public string? Key { get; private set; }
        public string? CorrelationId { get; private set; }
        public int Calls { get; private set; }
        public bool StallConnect { get; init; }
        public bool FailConnect { get; init; }
        public async Task<WebSocket> ConnectAsync(Uri uri, string apiKey, string correlationId, CancellationToken cancellationToken)
        {
            Calls++;
            Uri = uri;
            Key = apiKey;
            CorrelationId = correlationId;
            cancellationToken.ThrowIfCancellationRequested();
            if (FailConnect) throw new WebSocketException(Secret);
            if (StallConnect) await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return socket;
        }
    }

    private sealed class FakeSocket : WebSocket
    {
        private sealed record Frame(byte[] Bytes, WebSocketMessageType Type, bool End);
        private readonly Queue<Frame> _frames = new();
        private Frame? _current;
        private int _offset;
        public List<string> Sent { get; } = new();
        public bool Disposed { get; private set; }
        public bool StallReceive { get; init; }
        public bool FailReceive { get; init; }
        public override WebSocketCloseStatus? CloseStatus => WebSocketCloseStatus.NormalClosure;
        public override string? CloseStatusDescription => Secret;
        public override string? SubProtocol => null;
        public override WebSocketState State => Disposed ? WebSocketState.Closed : WebSocketState.Open;
        public void Enqueue(string json, bool end = true, WebSocketMessageType type = WebSocketMessageType.Text)
            => _frames.Enqueue(new Frame(Encoding.UTF8.GetBytes(json), type, end));
        public override void Abort() => Disposed = true;
        public override void Dispose() => Disposed = true;
        public override Task CloseAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken) => Task.CompletedTask;
        public override Task CloseOutputAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken) => Task.CompletedTask;
        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType messageType, bool endOfMessage, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Require(messageType == WebSocketMessageType.Text && endOfMessage, "Only complete JSON request frames should be sent.");
            Sent.Add(Encoding.UTF8.GetString(buffer));
            return Task.CompletedTask;
        }
        public override async Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (FailReceive) throw new WebSocketException(Secret);
            if (StallReceive) await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            if (_current is null && !_frames.TryDequeue(out _current))
                return new WebSocketReceiveResult(0, WebSocketMessageType.Close, true, CloseStatus, CloseStatusDescription);
            var count = Math.Min(buffer.Count, _current!.Bytes.Length - _offset);
            _current.Bytes.AsSpan(_offset, count).CopyTo(buffer.AsSpan());
            _offset += count;
            var finished = _offset == _current.Bytes.Length;
            var result = new WebSocketReceiveResult(count, _current.Type, finished && _current.End);
            if (finished) { _current = null; _offset = 0; }
            return result;
        }
    }

    private sealed class MemoryCache : IGeneratedAudioCache
    {
        public Dictionary<SpeechCacheKey, RenderedSpeech> Values { get; } = new();
        public SpeechCacheKey? LastKey { get; private set; }
        public Task<RenderedSpeech?> GetAsync(SpeechCacheKey key, string correlationId, CancellationToken cancellationToken)
            => Task.FromResult(Values.TryGetValue(key, out var value) ? value with { CacheHit = true, CorrelationId = correlationId } : null);
        public Task SetAsync(SpeechCacheKey key, RenderedSpeech speech, CancellationToken cancellationToken)
        {
            LastKey = key;
            Values[key] = speech;
            return Task.CompletedTask;
        }
    }
}

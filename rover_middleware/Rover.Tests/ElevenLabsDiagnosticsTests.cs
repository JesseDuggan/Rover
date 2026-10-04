using System.Net;
using System.Text;
using Rover.Application.Speech;
using Rover.Infrastructure.Speech;

internal static class ElevenLabsDiagnosticsTests
{
    public static async Task SafeFailures()
    {
        foreach (var code in new[] { "invalid_api_key", "missing_permissions", "quota_exceeded", "voice_not_found", "secret-provider-detail" })
        {
            using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
            {
                if (request.Headers.GetValues("xi-api-key").Single() != "test-key")
                    throw new Exception("The credential should be trimmed and sent using xi-api-key.");
                return new HttpResponseMessage(HttpStatusCode.Unauthorized)
                {
                    Content = new StringContent(
                        System.Text.Json.JsonSerializer.Serialize(new {
                            detail = new { status = code, message = "private-provider-message" }
                        }), Encoding.UTF8, "application/json")
                };
            }));
            var provider = new ElevenLabsTextToSpeechProvider(new SingleHttpClientFactory(client),
                new ElevenLabsSpeechOptions { Enabled = true, ApiKey = " test-key ",
                    VoiceId = "test-voice", ModelId = "test-model" });
            try
            {
                await provider.RenderAsync(new PreparedSpeechText("Test narration", SpeechPurpose.AdaptiveRouteStory, "en", "1"),
                    "test", default);
                throw new Exception("An unauthorized provider response must not be accepted as speech.");
            }
            catch (InvalidOperationException error)
            {
                var expected = code == "secret-provider-detail" ? "unclassified" : code;
                if (!error.Message.Contains("HTTP 401; code=" + expected)
                    || error.Message.Contains("private-provider-message")
                    || error.Message.Contains("test-key")
                    || error.Message.Contains("secret-provider-detail"))
                    throw new Exception("Only allowlisted error codes may leave the provider.");
            }
        }
    }
}

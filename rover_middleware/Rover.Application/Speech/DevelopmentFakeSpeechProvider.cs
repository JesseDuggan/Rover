using System.Text;

namespace Rover.Application.Speech;

public sealed class DevelopmentFakeSpeechProvider : ITextToSpeechProvider
{
    public string Name => "DevelopmentFake";

    public Task<RenderedSpeech> RenderAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var bytes = Encoding.UTF8.GetBytes($"ROVER FAKE AUDIO\nPurpose: {text.Purpose}\n{text.Text}");
        return Task.FromResult(new RenderedSpeech(bytes, "audio/mpeg", Name, false, false, correlationId));
    }
}

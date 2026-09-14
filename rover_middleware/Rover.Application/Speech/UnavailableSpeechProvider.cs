namespace Rover.Application.Speech;

public sealed class UnavailableSpeechProvider : ITextToSpeechProvider
{
    public string Name => "Unavailable";

    public Task<RenderedSpeech> RenderAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        throw new InvalidOperationException("Premium speech is not configured. Device voice remains available.");
    }
}

using System.Net.WebSockets;

namespace Rover.Infrastructure.Speech;

public interface IElevenLabsWebSocketFactory
{
    Task<WebSocket> ConnectAsync(Uri uri, string apiKey, string correlationId, CancellationToken cancellationToken);
}

public sealed class ElevenLabsWebSocketFactory : IElevenLabsWebSocketFactory
{
    public async Task<WebSocket> ConnectAsync(Uri uri, string apiKey, string correlationId, CancellationToken cancellationToken)
    {
        var socket = new ClientWebSocket();
        try
        {
            socket.Options.SetRequestHeader("xi-api-key", apiKey.Trim());
            socket.Options.SetRequestHeader("X-Correlation-ID", correlationId);
            await socket.ConnectAsync(uri, cancellationToken);
            return socket;
        }
        catch
        {
            socket.Dispose();
            throw;
        }
    }
}

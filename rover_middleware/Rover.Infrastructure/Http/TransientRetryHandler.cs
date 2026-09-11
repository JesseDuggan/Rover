using System.Net;

namespace Rover.Infrastructure.Http;

public sealed class TransientRetryHandler : DelegatingHandler
{
    private static readonly TimeSpan[] Delays =
    [
        TimeSpan.FromMilliseconds(200),
        TimeSpan.FromMilliseconds(600)
    ];

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        for (var attempt = 0; ; attempt++)
        {
            HttpResponseMessage? response = null;
            try
            {
                response = await base.SendAsync(request, cancellationToken);
                if (!ShouldRetry(response.StatusCode) || attempt >= Delays.Length)
                {
                    return response;
                }
            }
            catch (HttpRequestException) when (attempt < Delays.Length)
            {
            }
            catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested && attempt < Delays.Length)
            {
            }

            response?.Dispose();
            await Task.Delay(Delays[attempt], cancellationToken);
        }
    }

    private static bool ShouldRetry(HttpStatusCode statusCode)
        => statusCode is HttpStatusCode.RequestTimeout
            or HttpStatusCode.TooManyRequests
            or HttpStatusCode.BadGateway
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.GatewayTimeout
            || (int)statusCode >= 500;
}

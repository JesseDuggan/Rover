using System.Net;
using System.Net.Http.Headers;

namespace Rover.Infrastructure.Http;

// Store quota state only, never Google Places content or caller locations.
public sealed class GooglePlacesQuotaCooldown(TimeProvider clock)
{
    private readonly object _gate = new();
    private DateTimeOffset _until;

    public TimeSpan Remaining
    {
        get { lock (_gate) return _until > clock.GetUtcNow() ? _until - clock.GetUtcNow() : TimeSpan.Zero; }
    }

    public void Observe(RetryConditionHeaderValue? retryAfter)
    {
        lock (_gate)
        {
            var now = clock.GetUtcNow();
            var delay = retryAfter?.Delta ?? (retryAfter?.Date - now) ?? TimeSpan.FromMinutes(15);
            if (delay <= TimeSpan.Zero) delay = TimeSpan.FromMinutes(15);
            var until = now.Add(delay);
            if (until > _until) _until = until;
        }
    }
}

public sealed class GooglePlacesQuotaHandler(GooglePlacesQuotaCooldown cooldown) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var remaining = cooldown.Remaining;
        if (remaining > TimeSpan.Zero)
        {
            var blocked = new HttpResponseMessage(HttpStatusCode.TooManyRequests) { RequestMessage = request };
            blocked.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(Math.Ceiling(remaining.TotalSeconds)));
            blocked.Headers.Add("X-Rover-Quota-Cooldown", "true");
            return blocked;
        }
        var response = await base.SendAsync(request, cancellationToken);
        if (response.StatusCode == HttpStatusCode.TooManyRequests) cooldown.Observe(response.Headers.RetryAfter);
        return response;
    }
}

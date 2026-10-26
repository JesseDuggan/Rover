using Rover.Application.Drives;
using Rover.Domain.Walks;

namespace Rover.Api;

public static class ScenicDriveEndpoints
{
    public static void MapScenicDrives(this WebApplication app)
    {
        app.MapPost("/api/drive-stop-story", async (DriveStopStoryRequest request, DriveStopStoryService service, CancellationToken ct) =>
        {
            try { return Results.Ok(await service.CreateAsync(request, ct)); }
            catch (ArgumentException e) { return Results.Problem(e.Message, statusCode: 400); }
        }).RequireRateLimiting("scenic-drive");
        app.MapGet("/api/drive-places", async (string query, double lat, double lng, ScenicDriveService service, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(query) || query.Length > 256 || !ScenicDriveService.ValidLocation(new(lat, lng)))
                return Results.Problem("Enter a destination and a valid current location.", statusCode: 400);
            return Results.Ok(await service.SearchAsync(query, new GeoLocation(lat, lng), ct));
        });
        app.MapPost("/api/scenic-drives", async (DriveRequest request, ScenicDriveService service, CancellationToken ct) =>
        {
            if (!ScenicDriveService.ValidRequest(request))
                return Results.Problem("Choose a destination, 30-720 minutes, and 5-60 minutes per stop.", statusCode: 400);
            try { return Results.Ok(await service.PlanAsync(request, ct)); }
            catch (ArgumentException e) { return Results.Problem(e.Message, statusCode: 400); }
            catch (DrivingUnavailableException e) { return Results.Problem(e.Message, statusCode: 503); }
        }).RequireRateLimiting("scenic-drive");
    }
}

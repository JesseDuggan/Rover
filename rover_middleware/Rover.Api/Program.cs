using System.Diagnostics;
using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using Rover.Api.Contracts;
using Rover.Api.Mapping;
using Rover.Api.Responses;
using Rover.Api.Validation;
using Rover.Application.Accounts;
using Rover.Application.Adaptations;
using Rover.Application.Beta;
using Rover.Application.Conversation;
using Rover.Application.Commerce;
using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Application.LiveContext;
using Rover.Application.Performance;
using Rover.Application.Profiles;
using Rover.Application.Speech;
using Rover.Application.Walks;
using Rover.Domain.Profiles;
using Rover.Domain.Walks;
using Rover.Application;
using Rover.Infrastructure;
using Rover.Infrastructure.Walks;

LoadLocalEnvironmentFile();

var builder = WebApplication.CreateBuilder(args);

ConfigureRailwayPort(builder);
ValidateStartupConfiguration(builder);

builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddJsonConsole();

builder.Services.AddProblemDetails();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
    {
        var key = context.Request.Headers.TryGetValue("X-Rover-Dev-User", out var devUser) && !string.IsNullOrWhiteSpace(devUser)
            ? $"dev:{devUser}"
            : context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(
            key,
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = context.Request.Path.StartsWithSegments("/health") ? 120 : 60,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            });
    });
});

builder.Services.AddSingleton(new LocationTrackingOptions
{
    OffRouteDistanceMeters = builder.Configuration.GetValue("Rover:Location:OffRouteDistanceMeters", 65d),
    ArrivalAccuracyPaddingMeters = builder.Configuration.GetValue("Rover:Location:ArrivalAccuracyPaddingMeters", 10d),
    RequiredArrivalReadings = builder.Configuration.GetValue("Rover:Location:RequiredArrivalReadings", 1),
    RequiredOffRouteReadings = builder.Configuration.GetValue("Rover:Location:RequiredOffRouteReadings", 2),
    StaleReadingSeconds = builder.Configuration.GetValue("Rover:Location:StaleReadingSeconds", 120),
    MaximumAccuracyMeters = builder.Configuration.GetValue("Rover:Location:MaximumAccuracyMeters", 100d),
    ImpossibleJumpMeters = builder.Configuration.GetValue("Rover:Location:ImpossibleJumpMeters", 180d),
    ImpossibleJumpSeconds = builder.Configuration.GetValue("Rover:Location:ImpossibleJumpSeconds", 5),
    ManualArrivalExtraDistanceMeters = builder.Configuration.GetValue("Rover:Location:ManualArrivalExtraDistanceMeters", 65d)
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.AddCors(options =>
{
    options.AddPolicy("LocalFlutter", policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            policy.SetIsOriginAllowed(origin =>
            {
                if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
                {
                    return false;
                }

                if (uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                return IPAddress.TryParse(uri.Host.Trim('[', ']'), out var address)
                    && (IPAddress.IsLoopback(address) || IsPrivateIpv4(address));
            });
        }
        else
        {
            var allowedOrigins = builder.Configuration["Rover:Cors:AllowedOrigins"]?
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                ?? Array.Empty<string>();
            if (allowedOrigins.Length > 0)
            {
                policy.WithOrigins(allowedOrigins);
            }
        }

        policy.AllowAnyHeader().AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseExceptionHandler(exceptionApp =>
{
    exceptionApp.Run(async context =>
    {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/problem+json";
        await context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "Unexpected server error",
            Detail = "Rover could not complete the request."
        });
    });
});

app.Use(async (context, next) =>
{
    var stopwatch = Stopwatch.StartNew();
    var diagnostics = context.RequestServices.GetService<IBetaDiagnosticsService>();
    diagnostics?.RecordApiRequest();
    var correlationId = context.Request.Headers.TryGetValue("X-Correlation-ID", out var value) && !string.IsNullOrWhiteSpace(value)
        ? value.ToString()
        : Guid.NewGuid().ToString("n");
    context.Response.Headers["X-Correlation-ID"] = correlationId;
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    try
    {
        await next();
    }
    finally
    {
        stopwatch.Stop();
        diagnostics?.RecordOperation(
            $"{context.Request.Method} {context.Request.Path}",
            stopwatch.ElapsedMilliseconds,
            context.Response.StatusCode < 500);
    }
});

app.UseRateLimiter();

if (app.Environment.IsDevelopment())
{
    app.MapGet("/swagger/v1/swagger.json", () => Results.Json(OpenApiDocumentFactory.Create()))
        .WithName("OpenApiDocument");

    app.MapGet("/swagger", () => Results.Content(SwaggerUi.Html, "text/html"))
        .WithName("SwaggerUi");

    app.MapGet("/swagger/index.html", () => Results.Content(SwaggerUi.Html, "text/html"))
        .WithName("SwaggerUiIndex");
}

app.UseCors("LocalFlutter");

app.Use(async (context, next) =>
{
    if (!IsProtectedApiRequest(context))
    {
        await next();
        return;
    }

    if (IsAuthorizedBetaRequest(context, app.Environment, builder.Configuration))
    {
        await next();
        return;
    }

    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
    await context.Response.WriteAsJsonAsync(new ProblemDetails
    {
        Status = StatusCodes.Status401Unauthorized,
        Title = "Authentication required",
        Detail = "Rover beta API requests require a valid beta API key."
    });
});

app.MapGet("/health", (IConfiguration configuration) => Results.Ok(new HealthResponse(
        "Healthy",
        configuration["Rover:Build:Version"] ?? typeof(Program).Assembly.GetName().Version?.ToString() ?? "unknown")))
    .WithName("Health");

var locationIntelligence = app.MapGroup("/api");

locationIntelligence.MapPost("/commerce/hotel-rates/search", async (
    HotelRateSearchRequest? request,
    IHotelRateSearchService hotelRateSearchService,
    Rover.Infrastructure.Commerce.HotelRateOptions options,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = new[] { "Hotel-rate request is required." } });
    }

    try
    {
        var result = await hotelRateSearchService.SearchAsync(
            new HotelRateSearchQuery(
                request.HotelName,
                request.PlaceId,
                request.Latitude,
                request.Longitude,
                request.CheckInDate,
                request.CheckOutDate,
                request.Adults,
                request.Rooms,
                (request.Currency ?? options.DefaultCurrency).Trim().ToUpperInvariant()),
            cancellationToken);
        return Results.Ok(new HotelRateSearchResponse(
            result.Status.ToString(),
            result.ResolvedHotelName,
            result.CheckedAtUtc,
            result.Offers.Select(offer => new HotelRateOfferResponse(
                offer.ProviderName,
                offer.RoomName,
                offer.TotalAmount,
                offer.Currency,
                offer.IncludesTaxesAndFees,
                offer.Refundable,
                offer.BookingUri.ToString(),
                offer.Disclosure)).ToArray(),
            result.Message,
            result.Disclosure));
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["hotelRates"] = new[] { exception.Message } });
    }
});

locationIntelligence.MapGet("/location-context", async (
    double? lat,
    double? lng,
    int? radiusMeters,
    string? routeId,
    Guid? profileId,
    ILocationStoryContextService locationStoryContextService,
    LocationIntelligenceOptions options,
    CancellationToken cancellationToken) =>
{
    if (!TryCreateLocationContextQuery(lat, lng, radiusMeters, routeId, profileId, null, null, options, out var query, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var context = await locationStoryContextService.GetContextAsync(query!, cancellationToken);
        return Results.Ok(context.ToResponse());
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["locationContext"] = new[] { exception.Message } });
    }
});

locationIntelligence.MapPost("/location-observations/resolve", async (
    CandidateObservationResolveRequest? request,
    ICandidateObservationResolutionService resolutionService,
    LocationIntelligenceOptions options,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = new[] { "Observation request is required." } });
    }

    if (request.Latitude is null || request.Longitude is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["location"] = new[] { "Observation latitude and longitude are required." } });
    }

    try
    {
        var resolution = await resolutionService.ResolveAsync(
            new CandidateObservationQuery(
                request.RecognizedText ?? string.Empty,
                new GeoLocation(request.Latitude.Value, request.Longitude.Value),
                request.AccuracyMeters,
                request.HeadingDegrees,
                request.RadiusMeters ?? options.DefaultRadiusMeters,
                string.IsNullOrWhiteSpace(request.RouteId) ? null : request.RouteId.Trim(),
                request.NearbyPlaceIds?
                    .Where(id => !string.IsNullOrWhiteSpace(id))
                    .Select(id => id.Trim())
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Take(24)
                    .ToArray() ?? Array.Empty<string>()),
            cancellationToken);
        return Results.Ok(resolution.ToResponse());
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["observation"] = new[] { exception.Message } });
    }
});

locationIntelligence.MapPost("/location-story", async (
    Rover.Api.Contracts.LocationStoryRequest? request,
    ILocationStoryContextService locationStoryContextService,
    LocationIntelligenceOptions options,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = new[] { "Story request is required." } });
    }

    if (!TryCreateLocationContextQuery(request.Latitude, request.Longitude, request.RadiusMeters, request.RouteId, request.ProfileId, request.RouteGeometry, request.Interests, options, out var query, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var story = await locationStoryContextService.CreateStoryAsync(
            new Rover.Application.LocationIntelligence.LocationStoryRequest(
                query!.UserLocation,
                query.RadiusMeters,
                query.RouteId,
                query.ProfileId,
                query.RouteGeometry,
                query.Interests,
                request.SelectedPlaceIds ?? Array.Empty<string>(),
                request.NarrationStyle)
            {
                RouteSegmentId = request.RouteSegmentId,
                DirectionalContext = request.DirectionalContext
            },
            cancellationToken);
        return Results.Ok(story.ToResponse());
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["locationStory"] = new[] { exception.Message } });
    }
});

locationIntelligence.MapPost("/live-context", async (
    LiveContextRequest? request,
    ILiveJourneyContextService liveContextService,
    TimeProvider timeProvider,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = new[] { "Live-context request is required." } });
    }

    var starts = request.JourneyStartsUtc ?? timeProvider.GetUtcNow();
    var ends = request.JourneyEndsUtc ?? starts.AddHours(6);
    try
    {
        var context = await liveContextService.GetAsync(
            new LiveContextQuery(
                new GeoLocation(request.Latitude, request.Longitude),
                new ApproximateLiveLocation(request.City, request.Region, request.Country, request.TimeZone),
                starts,
                ends,
                request.Interests?.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray()
                    ?? Array.Empty<string>(),
                request.UserRequested),
            cancellationToken);
        return Results.Ok(context);
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["liveContext"] = new[] { exception.Message } });
    }
});

var auth = app.MapGroup("/api/auth");

auth.MapPost("/development/session", async (
    DevelopmentAuthRequest? request,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (!environment.IsDevelopment())
    {
        return Results.NotFound();
    }

    if (string.IsNullOrWhiteSpace(request?.Subject))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["subject"] = new[] { "Development subject is required." } });
    }

    var account = await accountService.CreateOrGetExternalAccountAsync(
        new ExternalIdentityCommand("Development", request.Subject, request.Email),
        cancellationToken);

    if (request.GuestProfileId is Guid profileId)
    {
        try
        {
            await accountService.LinkGuestProfileAsync(account.AccountId, new LinkGuestProfileCommand(profileId), cancellationToken);
        }
        catch (KeyNotFoundException)
        {
        }
    }

    return Results.Ok(new DevelopmentAuthResponse(account.AccountId, "Development", request.Subject.Trim(), request.Email, "X-Rover-Dev-User", request.Subject.Trim()));
});

var accounts = app.MapGroup("/api/accounts");

accounts.MapGet("/me", async (HttpContext httpContext, IAccountService accountService, IWebHostEnvironment environment, CancellationToken cancellationToken) =>
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return UnauthorizedProblem();
    }

    var account = await accountService.GetAsync(user.AccountId, cancellationToken);
    return account is null
        ? UnauthorizedProblem()
        : Results.Ok(new AccountResponse(account.AccountId, account.Status, account.ExternalIdentities.Select(identity => identity.Provider).ToArray(), account.GuestProfileLinks.Select(link => link.ProfileId).ToArray()));
});

accounts.MapPost("/link-guest", async (
    LinkGuestProfileRequest? request,
    HttpContext httpContext,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return UnauthorizedProblem();
    }

    if (request is null || request.ProfileId == Guid.Empty)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["profileId"] = new[] { "Profile id is required." } });
    }

    try
    {
        var result = await accountService.LinkGuestProfileAsync(user.AccountId, new LinkGuestProfileCommand(request.ProfileId), cancellationToken);
        return Results.Ok(new LinkGuestProfileResponse(result.AccountId, result.ProfileId, result.Linked, result.MergeSummary));
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ForbiddenProblem(exception.Message);
    }
});

accounts.MapGet("/export", async (HttpContext httpContext, IAccountService accountService, IWebHostEnvironment environment, CancellationToken cancellationToken) =>
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return UnauthorizedProblem();
    }

    var export = await accountService.ExportAsync(user.AccountId, cancellationToken);
    return Results.Ok(export);
});

accounts.MapDelete("/", async (HttpContext httpContext, IAccountService accountService, IWebHostEnvironment environment, CancellationToken cancellationToken) =>
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return UnauthorizedProblem();
    }

    await accountService.RequestDeletionAsync(user.AccountId, cancellationToken);
    return Results.NoContent();
});

var speech = app.MapGroup("/api/speech");

speech.MapPost("/render", async (
    RenderSpeechRequest? request,
    HttpContext httpContext,
    IAccountService accountService,
    IRoverSpeechService speechService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return UnauthorizedProblem();
    }

    if (request is null || string.IsNullOrWhiteSpace(request.Text))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["text"] = new[] { "Speech text is required." } });
    }

    if (!Enum.TryParse<SpeechPurpose>(request.Purpose, ignoreCase: true, out var purpose))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["purpose"] = new[] { "Speech purpose is required and must be StopNarration, AskRoverAnswer, WalkIntroduction, WalkRecap, or DiscoveryDescription." } });
    }

    try
    {
        var correlationId = httpContext.Response.Headers.TryGetValue("X-Correlation-ID", out var value)
            ? value.ToString()
            : Guid.NewGuid().ToString("n");
        var rendered = await speechService.RenderAsync(
            new RenderSpeechCommand(user.AccountId, request.Text, purpose, request.Locale, request.WalkSessionId, request.StopId, request.IdempotencyKey)
            {
                CacheEligible = request.CacheEligible == true,
                CacheExpiresUtc = request.CacheExpiresUtc,
                StoryId = request.StoryId,
                VariantId = request.VariantId
            },
            correlationId,
            cancellationToken);
        httpContext.RequestServices.GetService<IBetaDiagnosticsService>()?.RecordAudioDownload(rendered.Audio.Length, rendered.CacheHit);
        httpContext.Response.Headers["X-Rover-Speech-Provider"] = rendered.Provider;
        httpContext.Response.Headers["X-Rover-Speech-Cache"] = rendered.CacheHit ? "hit" : "miss";
        httpContext.Response.Headers["X-Rover-Speech-Fallback"] = rendered.UsedFallback ? "true" : "false";
        if (!string.IsNullOrWhiteSpace(rendered.FallbackReason))
        {
            httpContext.Response.Headers["X-Rover-Speech-Fallback-Reason"] = RedactionService.Redact(rendered.FallbackReason);
        }

        return Results.File(rendered.Audio, rendered.ContentType, enableRangeProcessing: true);
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["text"] = new[] { exception.Message } });
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

var beta = app.MapGroup("/api/beta");

beta.MapGet("/configuration", (IBetaConfigurationService configurationService) =>
{
    return Results.Ok(configurationService.GetStatus());
});

beta.MapGet("/diagnostics", (IBetaDiagnosticsService diagnosticsService) =>
{
    return Results.Ok(diagnosticsService.GetReport());
});

beta.MapGet("/local-discovery-options", async (
    double? latitude,
    double? longitude,
    ILocalDiscoveryProvider localDiscoveryProvider,
    CancellationToken cancellationToken) =>
{
    if (latitude is null or < -90 or > 90 || longitude is null or < -180 or > 180)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["location"] = new[] { "Latitude and longitude query parameters are required." } });
    }

    var origin = new GeoLocation(latitude.Value, longitude.Value);
    var command = new CreateWalkCommand(origin, 30, new[] { "coffee", "tea", "cakes", "burgers", "interesting sites" }, WalkingPace.Standard, Array.Empty<AccessibilityPreference>());
    string? discoveryError = null;
    IReadOnlyList<WalkStop> discoveredStops = Array.Empty<WalkStop>();

    try
    {
        discoveredStops = await localDiscoveryProvider.FindCandidateStopsAsync(command, cancellationToken);
    }
    catch (InvalidOperationException exception)
    {
        discoveryError = RedactionService.Redact(exception.Message);
    }

    var debugInfo = localDiscoveryProvider is MapboxLocalDiscoveryProvider mapboxLocalDiscoveryProvider
        ? mapboxLocalDiscoveryProvider.LastDebugInfo
        : LocalDiscoveryDebugInfo.Empty;
    var categoryCounts = debugInfo.CategoryResults
        .Select(ParseCategoryResult)
        .Where(result => result.Category.Length > 0)
        .ToDictionary(result => result.Category, result => result.Count, StringComparer.OrdinalIgnoreCase);
    var options = localDiscoveryProvider is MapboxLocalDiscoveryProvider
        ? new[]
        {
            DiscoveryOption("coffee", "Coffee", debugInfo, categoryCounts, "coffee", "cafe"),
            DiscoveryOption("tea", "Tea", debugInfo, categoryCounts, "tea_room", "cafe"),
            DiscoveryOption("cakes", "Cakes", debugInfo, categoryCounts, "bakery"),
            DiscoveryOption("burgers", "Burgers", debugInfo, categoryCounts, "burger", "restaurant"),
            DiscoveryOption("interesting sites", "Sites", debugInfo, categoryCounts, "tourist_attraction", "monument", "park")
        }
        : new[]
        {
            DiscoveryOptionFromStops("coffee", "Coffee", discoveredStops, "coffee", "cafe"),
            DiscoveryOptionFromStops("tea", "Tea", discoveredStops, "tea", "cafe"),
            DiscoveryOptionFromStops("cakes", "Cakes", discoveredStops, "bakery", "cake"),
            DiscoveryOptionFromStops("burgers", "Burgers", discoveredStops, "burger", "restaurant"),
            DiscoveryOptionFromStops("interesting sites", "Sites", discoveredStops, "tourist", "museum", "landmark", "park")
        };

    return Results.Ok(new
    {
        location = new { latitude = Math.Round(latitude.Value, 5), longitude = Math.Round(longitude.Value, 5) },
        provider = localDiscoveryProvider.GetType().Name,
        providerAttribution = discoveredStops.SelectMany(stop => stop.RequiredAttribution).Distinct(StringComparer.OrdinalIgnoreCase),
        discoveryError,
        radiusDegrees = debugInfo.RadiusDegrees,
        maximumDistanceMeters = debugInfo.MaximumDistanceMeters,
        options
    });
});

beta.MapGet("/mapbox-smoke-test", async (
    double? latitude,
    double? longitude,
    ILocalDiscoveryProvider localDiscoveryProvider,
    IWalkRouteProvider routeProvider,
    CancellationToken cancellationToken) =>
{
    if (latitude is null or < -90 or > 90 || longitude is null or < -180 or > 180)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["location"] = new[] { "Latitude and longitude query parameters are required." } });
    }

    var origin = new GeoLocation(latitude.Value, longitude.Value);
    var command = new CreateWalkCommand(origin, 30, new[] { "coffee", "tea", "bakery", "burgers", "interesting nearby sites" }, WalkingPace.Standard, Array.Empty<AccessibilityPreference>());
    IReadOnlyList<WalkStop> discoveredStops = Array.Empty<WalkStop>();
    string? discoveryError = null;
    string? routingError = null;
    WalkRoute? route = null;

    try
    {
        discoveredStops = await localDiscoveryProvider.FindStopsAsync(command, cancellationToken);
    }
    catch (InvalidOperationException exception)
    {
        discoveryError = RedactionService.Redact(exception.Message);
    }

    var routeStops = discoveredStops.Count >= 2
        ? discoveredStops.Take(3).ToArray()
        : MockWalkPlanner.CreateLocalWaypointStops(origin).Take(3).ToArray();

    try
    {
        route = await routeProvider.CreateRouteAsync(command, routeStops, cancellationToken);
    }
    catch (InvalidOperationException exception)
    {
        routingError = RedactionService.Redact(exception.Message);
    }

    return Results.Ok(new
    {
        location = new { latitude = Math.Round(latitude.Value, 5), longitude = Math.Round(longitude.Value, 5) },
        localDiscoveryProvider = localDiscoveryProvider.GetType().Name,
        routingProvider = routeProvider.ProviderName,
        poiCount = discoveredStops.Count,
        poiSample = discoveredStops.Take(5).Select(stop => new
        {
            stop.StopId,
            stop.Name,
            stop.Category,
            distanceMeters = (int)Math.Round(RouteMath.DistanceMeters(origin, stop.Location)),
            source = stop.ContentSource.ToString()
        }),
        localDiscoveryDebug = localDiscoveryProvider is MapboxLocalDiscoveryProvider mapboxLocalDiscoveryProvider
            ? mapboxLocalDiscoveryProvider.LastDebugInfo
            : null,
        discoverySucceeded = discoveredStops.Count > 0,
        discoveryError,
        directionsSucceeded = route is not null,
        routeGeometryPointCount = route?.Coordinates.Count ?? 0,
        routeDistanceMeters = route?.DistanceMeters,
        routeDurationMinutes = route?.DurationMinutes,
        routeVersion = route?.Version,
        routeLooksRoadSnapped = route is not null && route.Coordinates.Count > routeStops.Length + 1,
        routingError
    });
});

beta.MapPost("/problem-reports", async (
    ProblemReportRequest? request,
    HttpContext httpContext,
    IProblemReportService problemReportService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.Category))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["category"] = new[] { "Problem category is required." } });
    }

    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    var receipt = await problemReportService.SubmitAsync(
        new ProblemReportCommand(
            user?.AccountId,
            request.Category,
            request.Description,
            request.WalkSessionId,
            request.StopId,
            request.CorrelationId,
            request.AppVersion ?? "unknown",
            request.BuildNumber ?? "unknown",
            request.DeviceModel ?? "unknown",
            request.OsVersion ?? "unknown",
            request.ConnectivityState ?? "unknown",
            request.PreciseLocationAttached == true),
        cancellationToken);

    return Results.Accepted($"/api/beta/problem-reports/{receipt.ProblemReportId}", new ProblemReportResponse(receipt.ProblemReportId, receipt.Severity.ToString(), receipt.ReceivedAtUtc, receipt.Queued));
});

beta.MapPost("/crash-breadcrumbs", async (
    CrashBreadcrumbRequest? request,
    ICrashReportingService crashReportingService,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.Feature) || string.IsNullOrWhiteSpace(request.Action))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["breadcrumb"] = new[] { "Feature and action are required." } });
    }

    await crashReportingService.RecordBreadcrumbAsync(
        new CrashBreadcrumbCommand(
            request.Feature,
            request.Action,
            request.CorrelationId,
            request.SafeErrorCode,
            request.AppVersion ?? "unknown",
            request.BuildNumber ?? "unknown"),
        cancellationToken);
    return Results.Accepted();
});

var profiles = app.MapGroup("/api/profiles");

profiles.MapPost("/guest", async (CreateGuestProfileRequest? request, IProfileService profileService, CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.InstallationId))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["installationId"] = new[] { "Installation identifier is required." } });
    }

    try
    {
        var profile = await profileService.CreateOrGetGuestAsync(new CreateGuestProfileCommand(request.InstallationId), cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

profiles.MapGet("/{profileId:guid}", async (
    Guid profileId,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    var profile = await profileService.GetAsync(profileId, cancellationToken);
    return profile is null ? NotFoundProblem($"Profile '{profileId}' was not found.") : Results.Ok(profile.ToResponse());
});

profiles.MapPatch("/{profileId:guid}/preferences", async (
    Guid profileId,
    UpdateUserPreferencesRequest? request,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["body"] = new[] { "Preferences update body is required." } });
    }

    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.UpdatePreferencesAsync(
            profileId,
            new UpdateUserPreferencesCommand(request.Interests, request.WalkingPace, request.AccessibilityNeeds, request.DistanceUnits, request.DirectionVoiceEnabled, request.NarrationEnabled, request.SpeechRate, request.PreferredNarrationLength, request.PremiumVoiceEnabled, request.AskRoverVoiceEnabled, request.AutoPlayNarrationOnArrival, request.ResumeNarrationAfterNavigation, request.DeviceVoiceFallbackEnabled, request.SaveWalkHistory, request.ImproveRecommendations, request.LocationRetention)
            {
                StoryDensity = request.StoryDensity,
                ExcludedStoryCategories = request.ExcludedStoryCategories
            },
            cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapPost("/{profileId:guid}/saved-discoveries", async (
    Guid profileId,
    SaveDiscoveryRequest? request,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.DiscoveryId) || string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Category))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["discovery"] = new[] { "Discovery id, name and category are required." } });
    }

    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.SaveDiscoveryAsync(profileId, new SaveDiscoveryCommand(request.DiscoveryId, request.Name, request.Category, request.Source ?? "Rover"), cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapDelete("/{profileId:guid}/saved-discoveries/{discoveryId}", async (
    Guid profileId,
    string discoveryId,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.UnsaveDiscoveryAsync(profileId, discoveryId, cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapPost("/{profileId:guid}/preference-signals", async (
    Guid profileId,
    PreferenceSignalRequest? request,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.Topic) || string.IsNullOrWhiteSpace(request.Reason))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["signal"] = new[] { "Topic and reason are required." } });
    }

    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.RecordPreferenceSignalAsync(profileId, new PreferenceSignalCommand(request.Topic, request.Weight ?? 1, request.Reason), cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapPost("/{profileId:guid}/story-interactions", async (
    Guid profileId,
    StoryInteractionRequest? request,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["interaction"] = new[] { "Story interaction body is required." } });
    }

    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.RecordStoryInteractionAsync(
            profileId,
            new StoryInteractionCommand(
                request.EventId ?? string.Empty,
                request.StoryId ?? string.Empty,
                request.Category ?? string.Empty,
                request.Kind ?? string.Empty,
                request.OccurredAtUtc),
            cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["interaction"] = new[] { exception.Message } });
    }
});

profiles.MapDelete("/{profileId:guid}/learned-preferences/{topic}", async (
    Guid profileId,
    string topic,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.RemoveLearnedPreferenceAsync(profileId, topic, cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapPost("/{profileId:guid}/learned-preferences/reset", async (
    Guid profileId,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    try
    {
        var profile = await profileService.ResetLearningAsync(profileId, cancellationToken);
        return Results.Ok(profile.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
});

profiles.MapDelete("/{profileId:guid}", async (
    Guid profileId,
    HttpContext httpContext,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
    if (access is not null)
    {
        return access;
    }

    await profileService.DeleteAsync(profileId, cancellationToken);
    return Results.NoContent();
});

var walks = app.MapGroup("/api/walks");

walks.MapPost("/", async (
    CreateWalkRequest? request,
    IWalkSessionService walkService,
    IRoverWalkPrefetchService? prefetchService,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryCreateCommand(request, out var command, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var session = await walkService.CreateAsync(command!, cancellationToken);
        QueueWalkWarmup(prefetchService, session, "created");
        return Results.Created($"/api/walks/{session.WalkSessionId}", session.ToResponse());
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapGet("/{walkSessionId}", async (string walkSessionId, IWalkSessionService walkService, CancellationToken cancellationToken) =>
{
    var session = await walkService.GetAsync(walkSessionId, cancellationToken);
    return session is null
        ? NotFoundProblem($"Walk session '{walkSessionId}' was not found.")
        : Results.Ok(session.ToResponse());
});

walks.MapGet("/{walkSessionId}/stops", async (string walkSessionId, IWalkSessionService walkService, CancellationToken cancellationToken) =>
{
    var stops = await walkService.GetStopsAsync(walkSessionId, cancellationToken);
    return stops is null
        ? NotFoundProblem($"Walk session '{walkSessionId}' was not found.")
        : Results.Ok(stops.Select(stop => stop.ToResponse()));
});

walks.MapGet("/{walkSessionId}/next-stop", async (string walkSessionId, IWalkSessionService walkService, CancellationToken cancellationToken) =>
{
    var session = await walkService.GetAsync(walkSessionId, cancellationToken);
    return session is null
        ? NotFoundProblem($"Walk session '{walkSessionId}' was not found.")
        : Results.Ok(session.NextStop?.ToResponse());
});

walks.MapGet("/{walkSessionId}/narrative-arc", async (
    string walkSessionId,
    IWalkSessionService walkService,
    IJourneyNarrativeArcService narrativeArcService,
    Phase15Options phase15Options,
    CancellationToken cancellationToken) =>
{
    var session = await walkService.GetAsync(walkSessionId, cancellationToken);
    if (session is null)
    {
        return NotFoundProblem($"Walk session '{walkSessionId}' was not found.");
    }

    var enabled = phase15Options.Enabled && phase15Options.NarrativeArcEnabled;
    var arc = enabled ? await narrativeArcService.GetAsync(session, cancellationToken) : null;
    return Results.Ok(new { enabled, arc });
});

walks.MapPost("/{walkSessionId}/route-story-pack/generate", async (
    string walkSessionId,
    GenerateAdaptiveRouteStoryPackRequest? request,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    request ??= new GenerateAdaptiveRouteStoryPackRequest(null, null, null, false);
    try
    {
        var state = await routeStories.GenerateAsync(
            walkSessionId,
            new GenerateAdaptiveRouteStoryPackCommand(
                request.ProfileId,
                request.Audience,
                request.Language,
                request.ForceRefresh ?? false),
            cancellationToken);
        return Results.Accepted($"/api/walks/{walkSessionId}/route-story-pack/status", state);
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapGet("/{walkSessionId}/route-story-pack/status", async (
    string walkSessionId,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    try
    {
        var state = await routeStories.GetStatusAsync(walkSessionId, cancellationToken);
        return state is null
            ? Results.Ok(new { walkSessionId, status = AdaptiveRouteStoryPackStatus.Pending.ToString(), pack = (object?)null })
            : Results.Ok(state);
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapGet("/{walkSessionId}/route-story-pack", async (
    string walkSessionId,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    try
    {
        var pack = await routeStories.GetPackAsync(walkSessionId, cancellationToken);
        return pack is null
            ? NotFoundProblem("A route story pack has not been generated for the current route revision.")
            : Results.Ok(pack);
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/route-story-pack/next", async (
    string walkSessionId,
    NextAdaptiveRouteStoryRequest? request,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    if (request?.RouteProgressMeters is null or < 0)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["routeProgressMeters"] = ["Route progress must be zero or greater."] });
    }
    if (!Enum.TryParse<AdaptiveStoryLength>(request.PreferredLength ?? nameof(AdaptiveStoryLength.Standard), true, out var preferredLength))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["preferredLength"] = ["Preferred length must be Quick, Short, Standard, or Deep."] });
    }
    try
    {
        var selection = await routeStories.GetNextAsync(
            walkSessionId,
            new NextAdaptiveRouteStoryQuery(
                request.RouteProgressMeters.Value,
                request.SecondsUntilNextManeuver,
                preferredLength,
                request.ExcludedStoryIds ?? Array.Empty<string>()),
            cancellationToken);
        return Results.Ok(selection);
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/route-story-pack/ask", async (
    string walkSessionId,
    AdaptiveRouteStoryQuestionRequest? request,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.Question) || request.Question.Length > 500)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["question"] = ["Question is required and must be 500 characters or fewer."] });
    }
    try
    {
        return Results.Ok(await routeStories.AskAsync(
            walkSessionId,
            new AdaptiveRouteStoryQuestion(request.Question, Math.Max(0, request.RouteProgressMeters ?? 0), request.SecondsUntilNextManeuver),
            cancellationToken));
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapGet("/{walkSessionId}/route-story-pack/stories/{storyId}", async (
    string walkSessionId,
    string storyId,
    IAdaptiveRouteStoryPackService routeStories,
    CancellationToken cancellationToken) =>
{
    try
    {
        var story = await routeStories.GetStoryAsync(walkSessionId, storyId, cancellationToken);
        return story is null ? NotFoundProblem($"Route story '{storyId}' was not found.") : Results.Ok(story);
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/route-story-pack/playback-events", async (
    string walkSessionId,
    AdaptiveStoryPlaybackEventRequest? request,
    IAdaptiveRouteStoryPackService routeStories,
    TimeProvider timeProvider,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request?.StoryId)
        || !Enum.TryParse<AdaptiveStoryPlaybackEventKind>(request.Kind, true, out var kind))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["playbackEvent"] = ["A storyId and valid playback event kind are required."] });
    }
    try
    {
        await routeStories.RecordPlaybackAsync(
            walkSessionId,
            new AdaptiveStoryPlaybackEvent(request.StoryId, kind, request.OccurredUtc ?? timeProvider.GetUtcNow(), request.PositionSeconds),
            cancellationToken);
        return Results.NoContent();
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/start", async (
    string walkSessionId,
    IWalkSessionService walkService,
    IRoverWalkPrefetchService? prefetchService,
    CancellationToken cancellationToken) =>
{
    try
    {
        var session = await walkService.StartAsync(walkSessionId, cancellationToken);
        QueueWalkWarmup(prefetchService, session, "started");
        return Results.Ok(session.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/stops/{stopId}/arrive", async (
    string walkSessionId,
    string stopId,
    ArriveAtStopRequest? request,
    IWalkSessionService walkService,
    IRoverWalkPrefetchService? prefetchService,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryCreateLocation(request, out var currentLocation, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var session = await walkService.ArriveAtStopAsync(walkSessionId, stopId, currentLocation, cancellationToken);
        QueueWalkWarmup(prefetchService, session, "arrived");
        return Results.Ok(session.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/location", async (
    string walkSessionId,
    LocationUpdateRequest? request,
    HttpContext httpContext,
    IWalkSessionService walkService,
    IRoverWalkPrefetchService? prefetchService,
    TimeProvider timeProvider,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryCreateLocationUpdate(request, timeProvider.GetUtcNow(), out var command, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var result = await walkService.UpdateLocationAsync(walkSessionId, command!, cancellationToken);
        httpContext.RequestServices.GetService<IBetaDiagnosticsService>()?.RecordLocationUpdate();
        var session = await walkService.GetAsync(walkSessionId, cancellationToken);
        if (session is not null)
        {
            QueueWalkWarmup(prefetchService, session, "location");
        }

        return Results.Ok(result.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/ask", async (
    string walkSessionId,
    AskRoverRequest? request,
    IAskRoverService askRoverService,
    TimeProvider timeProvider,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryCreateAskRoverCommand(request, timeProvider.GetUtcNow(), out var command, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var result = await askRoverService.AskAsync(walkSessionId, command!, cancellationToken);
        return Results.Ok(result.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
    catch (OperationCanceledException)
    {
        return ConfigurationProblem("Conversation provider request timed out.");
    }
});

walks.MapPost("/{walkSessionId}/journey-narration/evaluate", async (
    string walkSessionId,
    JourneyNarrationEvaluateRequest? request,
    IWalkSessionService walkService,
    IJourneyNarrationOrchestrator narrationOrchestrator,
    IProfileService profileService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    HttpContext httpContext,
    TimeProvider timeProvider,
    CancellationToken cancellationToken) =>
{
    if (request is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = new[] { "Journey narration request is required." } });
    }

    if (request.Latitude is < -90 or > 90)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["latitude"] = new[] { "Latitude must be between -90 and 90." } });
    }

    if (request.Longitude is < -180 or > 180)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["longitude"] = new[] { "Longitude must be between -180 and 180." } });
    }

    var session = await walkService.GetAsync(walkSessionId, cancellationToken);
    if (session is null)
    {
        return NotFoundProblem($"Walk session '{walkSessionId}' was not found.");
    }

    GuestProfile? interactionProfile = null;
    if (request.ProfileId is { } profileId)
    {
        var access = await EnforceProfileAccessAsync(profileId, httpContext, accountService, environment, cancellationToken);
        if (access is not null)
        {
            return access;
        }
        interactionProfile = await profileService.GetAsync(profileId, cancellationToken);
        if (interactionProfile is null)
        {
            return NotFoundProblem($"Profile '{profileId}' was not found.");
        }
    }

    try
    {
        var decision = await narrationOrchestrator.EvaluateAsync(
            session,
            new JourneyNarrationQuery(
                new GeoLocation(request.Latitude, request.Longitude),
                request.GpsAccuracyMeters,
                request.HeadingDegrees,
                request.SpeedMetersPerSecond,
                request.AlreadyNarratedFactIds ?? Array.Empty<string>(),
                request.RequestedAtUtc ?? timeProvider.GetUtcNow())
            {
                RouteId = session.WalkSessionId,
                SecondsUntilNextManeuver = request.SecondsUntilNextManeuver,
                StoryDurationSeconds = request.StoryDurationSeconds,
                StoryDensity = request.StoryDensity ?? "highlights",
                PreferredStoryCategories = request.PreferredStoryCategories ?? Array.Empty<string>(),
                ExcludedStoryCategories = request.ExcludedStoryCategories ?? Array.Empty<string>(),
                RouteState = request.RouteState ?? "onRoute",
                UserAttentionAvailable = request.UserAttentionAvailable ?? true,
                RecentDirectInteraction = request.RecentDirectInteraction ?? false,
                ConnectivityAvailable = request.ConnectivityAvailable ?? true,
                AudioAlreadyQueued = request.AudioAlreadyQueued ?? false,
                BatterySaverEnabled = request.BatterySaverEnabled ?? false,
                ThermalState = request.ThermalState,
                InterruptedStoryId = request.InterruptedStoryId,
                InterruptedStoryRouteId = request.InterruptedStoryRouteId,
                InterruptedStoryExpiresUtc = request.InterruptedStoryExpiresUtc,
                InterruptedStoryStillRelevant = request.InterruptedStoryStillRelevant ?? false,
                LearnedCategoryScores = interactionProfile?.Preferences.ImproveRecommendations == true
                    ? interactionProfile.LearnedPreferences.ToDictionary(item => item.Topic, item => item.Score, StringComparer.OrdinalIgnoreCase)
                    : new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
            },
            cancellationToken);
        return Results.Ok(decision.ToResponse());
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["journeyNarration"] = new[] { exception.Message } });
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/adaptations/evaluate", async (
    string walkSessionId,
    WalkAdaptationEvaluateRequest? request,
    IWalkAdaptationService adaptationService,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryCreateAdaptationCommand(request, out var command, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var proposal = await adaptationService.EvaluateAsync(walkSessionId, command!, cancellationToken);
        return Results.Created($"/api/walks/{walkSessionId}/adaptations/{proposal.AdaptationId}", proposal.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
    catch (InvalidOperationException exception)
    {
        return ConfigurationProblem(exception.Message);
    }
});

walks.MapGet("/{walkSessionId}/adaptations/{adaptationId}", async (
    string walkSessionId,
    string adaptationId,
    IWalkAdaptationService adaptationService,
    CancellationToken cancellationToken) =>
{
    var proposal = await adaptationService.GetAsync(walkSessionId, adaptationId, cancellationToken);
    return proposal is null
        ? NotFoundProblem($"Adaptation '{adaptationId}' was not found.")
        : Results.Ok(proposal.ToResponse());
});

walks.MapPost("/{walkSessionId}/adaptations/{adaptationId}/accept", async (
    string walkSessionId,
    string adaptationId,
    WalkAdaptationAcceptRequest? request,
    IWalkAdaptationService adaptationService,
    IRoverWalkPrefetchService? prefetchService,
    CancellationToken cancellationToken) =>
{
    if (!WalkRequestValidation.TryGetRouteRevision(request, out var routeRevision, out var errors))
    {
        return Results.ValidationProblem(errors);
    }

    try
    {
        var session = await adaptationService.AcceptAsync(walkSessionId, adaptationId, routeRevision, cancellationToken);
        QueueWalkWarmup(prefetchService, session, "adapted");
        return Results.Ok(session.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/adaptations/{adaptationId}/reject", async (
    string walkSessionId,
    string adaptationId,
    IWalkAdaptationService adaptationService,
    CancellationToken cancellationToken) =>
{
    try
    {
        var proposal = await adaptationService.RejectAsync(walkSessionId, adaptationId, cancellationToken);
        return Results.Ok(proposal.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/feedback", async (
    string walkSessionId,
    PostWalkFeedbackRequest? request,
    HttpContext httpContext,
    IPostWalkFeedbackService feedbackService,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken) =>
{
    if (request?.OverallRating is null)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["overallRating"] = new[] { "Overall rating is required." } });
    }

    try
    {
        var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
        var receipt = await feedbackService.SubmitAsync(
            new PostWalkFeedbackCommand(
                user?.AccountId,
                walkSessionId,
                request.OverallRating.Value,
                request.DirectionsEasyToFollow,
                request.StopsDetectedCorrectly,
                request.NarrationEnjoyable,
                request.AskRoverUseful,
                request.WalkRightLength,
                request.WouldTakeAnotherWalk,
                RedactionService.Redact(request.Comments),
                request.AppVersion ?? "unknown",
                request.BuildNumber ?? "unknown"),
            cancellationToken);
        return Results.Accepted($"/api/walks/{walkSessionId}/feedback/{receipt.FeedbackId}", new PostWalkFeedbackResponse(receipt.FeedbackId, receipt.WalkSessionId, receipt.ReceivedAtUtc));
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["overallRating"] = new[] { exception.Message } });
    }
});

walks.MapGet("/{walkSessionId}/feedback/status", async (
    string walkSessionId,
    IPostWalkFeedbackService feedbackService,
    CancellationToken cancellationToken) =>
{
    return Results.Ok(new { walkSessionId, submitted = await feedbackService.HasFeedbackAsync(walkSessionId, cancellationToken) });
});

walks.MapPost("/{walkSessionId}/complete", async (string walkSessionId, IWalkSessionService walkService, CancellationToken cancellationToken) =>
{
    try
    {
        var session = await walkService.CompleteAsync(walkSessionId, cancellationToken);
        return Results.Ok(session.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

walks.MapPost("/{walkSessionId}/cancel", async (string walkSessionId, IWalkSessionService walkService, CancellationToken cancellationToken) =>
{
    try
    {
        var session = await walkService.CancelAsync(walkSessionId, cancellationToken);
        return Results.Ok(session.ToResponse());
    }
    catch (KeyNotFoundException exception)
    {
        return NotFoundProblem(exception.Message);
    }
    catch (WalkLifecycleException exception)
    {
        return ConflictProblem(exception.Message);
    }
});

app.Run();

static bool IsPrivateIpv4(IPAddress address)
{
    var bytes = address.GetAddressBytes();
    return bytes.Length == 4
        && (bytes[0] == 10
            || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31)
            || (bytes[0] == 192 && bytes[1] == 168));
}

static void ConfigureRailwayPort(WebApplicationBuilder builder)
{
    var port = Environment.GetEnvironmentVariable("PORT");
    if (string.IsNullOrWhiteSpace(port))
    {
        return;
    }

    if (!int.TryParse(port, out var parsedPort) || parsedPort <= 0 || parsedPort > 65535)
    {
        throw new InvalidOperationException("PORT must be a valid TCP port number.");
    }

    builder.WebHost.UseUrls($"http://0.0.0.0:{parsedPort}");
}

static bool IsProtectedApiRequest(HttpContext context)
{
    if (!context.Request.Path.StartsWithSegments("/api"))
    {
        return false;
    }

    return !context.Request.Path.Equals("/api/auth/development/session", StringComparison.OrdinalIgnoreCase);
}

static bool IsAuthorizedBetaRequest(HttpContext context, IWebHostEnvironment environment, IConfiguration configuration)
{
    if (environment.IsDevelopment()
        && context.Request.Headers.TryGetValue("X-Rover-Dev-User", out var devSubject)
        && !string.IsNullOrWhiteSpace(devSubject))
    {
        return true;
    }

    var configuredKey = Environment.GetEnvironmentVariable("ROVER_BETA_API_KEY")
        ?? configuration["Rover:Authentication:BetaApiKey"];
    if (string.IsNullOrWhiteSpace(configuredKey))
    {
        return false;
    }

    var suppliedKey = context.Request.Headers.TryGetValue("X-Rover-Beta-Key", out var headerKey)
        ? headerKey.ToString()
        : null;
    if (string.IsNullOrWhiteSpace(suppliedKey)
        && context.Request.Headers.TryGetValue("Authorization", out var authorization)
        && authorization.ToString().StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
    {
        suppliedKey = authorization.ToString()["Bearer ".Length..].Trim();
    }

    return FixedTimeEquals(configuredKey, suppliedKey);
}

static bool FixedTimeEquals(string expected, string? actual)
{
    if (string.IsNullOrWhiteSpace(actual))
    {
        return false;
    }

    var expectedBytes = System.Text.Encoding.UTF8.GetBytes(expected);
    var actualBytes = System.Text.Encoding.UTF8.GetBytes(actual);
    return System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(expectedBytes, actualBytes);
}

static void LoadLocalEnvironmentFile()
{
    if (string.Equals(Environment.GetEnvironmentVariable("ROVER_SKIP_ENV_LOCAL"), "true", StringComparison.OrdinalIgnoreCase))
    {
        return;
    }

    var candidates = new[]
    {
        Path.Combine(Directory.GetCurrentDirectory(), ".env.local"),
        Path.Combine(Directory.GetCurrentDirectory(), "..", ".env.local")
    };
    var path = candidates.Select(Path.GetFullPath).FirstOrDefault(File.Exists);
    if (path is null)
    {
        return;
    }

    foreach (var rawLine in File.ReadLines(path))
    {
        var line = rawLine.Trim();
        if (line.Length == 0 || line.StartsWith('#'))
        {
            continue;
        }

        var separator = line.IndexOf('=');
        if (separator <= 0)
        {
            continue;
        }

        var name = line[..separator].Trim();
        var value = line[(separator + 1)..].Trim();
        if ((value.StartsWith('"') && value.EndsWith('"')) || (value.StartsWith('\'') && value.EndsWith('\'')))
        {
            value = value[1..^1];
        }

        Environment.SetEnvironmentVariable(name, value, EnvironmentVariableTarget.Process);
    }
}

static object DiscoveryOption(string value, string label, LocalDiscoveryDebugInfo debugInfo, IReadOnlyDictionary<string, int> categoryCounts, params string[] categories)
{
    var categorySet = categories.ToHashSet(StringComparer.OrdinalIgnoreCase);
    var samples = debugInfo.CandidateSamples
        .Where(candidate => categorySet.Contains(candidate.SourceCategory))
        .GroupBy(candidate => candidate.StopId, StringComparer.OrdinalIgnoreCase)
        .Select(group => group.OrderBy(candidate => candidate.DistanceMeters).First())
        .OrderBy(candidate => candidate.DistanceMeters)
        .Take(5)
        .Select(candidate => new
        {
            candidate.StopId,
            candidate.Name,
            candidate.Category,
            candidate.DistanceMeters,
            candidate.Address,
            candidate.WebsiteUrl,
            candidate.PhoneNumber,
            candidate.MenuUrl
        })
        .ToArray();
    var count = CountCategories(categoryCounts, categories);
    return new { value, label, count, enabled = count > 0, samples };
}

static object DiscoveryOptionFromStops(string value, string label, IReadOnlyList<WalkStop> stops, params string[] categories)
{
    var matches = stops
        .Where(stop => categories.Any(category =>
            stop.Category.Contains(category, StringComparison.OrdinalIgnoreCase)
            || stop.Name.Contains(category, StringComparison.OrdinalIgnoreCase)))
        .Take(5)
        .Select(stop => new
        {
            stop.StopId,
            stop.Name,
            stop.Category,
            DistanceMeters = stop.DistanceFromPreviousStopMeters,
            stop.Address,
            stop.WebsiteUrl,
            stop.PhoneNumber,
            stop.MenuUrl
        })
        .ToArray();
    return new { value, label, count = matches.Length, enabled = matches.Length > 0, samples = matches };
}

static int CountCategories(IReadOnlyDictionary<string, int> categoryCounts, params string[] categories)
{
    return categories.Sum(category => categoryCounts.TryGetValue(category, out var count) ? count : 0);
}

static (string Category, int Count) ParseCategoryResult(string result)
{
    var parts = result.Split(':', 2, StringSplitOptions.TrimEntries);
    if (parts.Length != 2)
    {
        return (string.Empty, 0);
    }

    var match = System.Text.RegularExpressions.Regex.Match(parts[1], @"^\d+");
    return match.Success && int.TryParse(match.Value, out var count)
        ? (parts[0], count)
        : (parts[0], 0);
}

static void QueueWalkWarmup(IRoverWalkPrefetchService? prefetchService, WalkSession session, string reason)
{
    try
    {
        prefetchService?.TryQueueWalkWarmup(session, reason);
    }
    catch
    {
        // Background warmup must never block core walk flow.
    }
}

static IResult NotFoundProblem(string detail)
{
    return Results.Problem(new ProblemDetails
    {
        Status = StatusCodes.Status404NotFound,
        Title = "Resource not found",
        Detail = detail
    });
}

static IResult ConflictProblem(string detail)
{
    return Results.Problem(new ProblemDetails
    {
        Status = StatusCodes.Status409Conflict,
        Title = "Invalid walk lifecycle transition",
        Detail = detail
    });
}

static IResult ConfigurationProblem(string detail)
{
    return Results.Problem(new ProblemDetails
    {
        Status = StatusCodes.Status503ServiceUnavailable,
        Title = "Provider configuration error",
        Detail = detail
    });
}

static IResult UnauthorizedProblem()
{
    return Results.Problem(new ProblemDetails
    {
        Status = StatusCodes.Status401Unauthorized,
        Title = "Authentication required",
        Detail = "Sign in or use the explicit Development authentication header."
    });
}

static IResult ForbiddenProblem(string detail)
{
    return Results.Problem(new ProblemDetails
    {
        Status = StatusCodes.Status403Forbidden,
        Title = "Access denied",
        Detail = detail
    });
}

static bool TryCreateLocationContextQuery(
    double? latitude,
    double? longitude,
    int? radiusMeters,
    string? routeId,
    Guid? profileId,
    IReadOnlyList<RouteCoordinateResponse>? routeGeometry,
    IReadOnlyList<string>? interests,
    LocationIntelligenceOptions options,
    out LocationContextQuery? query,
    out Dictionary<string, string[]> errors)
{
    query = null;
    errors = new Dictionary<string, string[]>();
    if (latitude is null or < -90 or > 90)
    {
        errors["lat"] = new[] { "Latitude is required and must be between -90 and 90." };
    }

    if (longitude is null or < -180 or > 180)
    {
        errors["lng"] = new[] { "Longitude is required and must be between -180 and 180." };
    }

    var radius = radiusMeters ?? options.DefaultRadiusMeters;
    if (radius <= 0 || radius > options.MaxRadiusMeters)
    {
        errors["radiusMeters"] = new[] { $"Radius must be between 1 and {options.MaxRadiusMeters} meters." };
    }

    if (errors.Count > 0)
    {
        return false;
    }

    var route = routeGeometry?
        .Where(point => point.Latitude is >= -90 and <= 90 && point.Longitude is >= -180 and <= 180)
        .Select(point => new GeoLocation(point.Latitude, point.Longitude))
        .ToArray() ?? Array.Empty<GeoLocation>();
    var normalizedInterests = interests?
        .Where(interest => !string.IsNullOrWhiteSpace(interest))
        .Select(interest => interest.Trim())
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(12)
        .ToArray() ?? Array.Empty<string>();
    query = new LocationContextQuery(
        new GeoLocation(latitude!.Value, longitude!.Value),
        radius,
        string.IsNullOrWhiteSpace(routeId) ? null : routeId.Trim(),
        profileId,
        route,
        normalizedInterests);
    return true;
}

static async Task<IResult?> EnforceProfileAccessAsync(
    Guid profileId,
    HttpContext httpContext,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken)
{
    var user = await ResolveUserAsync(httpContext, accountService, environment, cancellationToken);
    if (user is null)
    {
        return null;
    }

    return await accountService.CanAccessProfileAsync(user.AccountId, profileId, cancellationToken)
        ? null
        : ForbiddenProblem("The authenticated account does not own this profile.");
}

static async Task<RoverRequestUser?> ResolveUserAsync(
    HttpContext httpContext,
    IAccountService accountService,
    IWebHostEnvironment environment,
    CancellationToken cancellationToken)
{
    if (environment.IsDevelopment()
        && httpContext.Request.Headers.TryGetValue("X-Rover-Dev-User", out var devSubject)
        && !string.IsNullOrWhiteSpace(devSubject))
    {
        var email = httpContext.Request.Headers.TryGetValue("X-Rover-Dev-Email", out var devEmail)
            ? devEmail.ToString()
            : null;
        var account = await accountService.CreateOrGetExternalAccountAsync(
            new ExternalIdentityCommand("Development", devSubject.ToString(), email),
            cancellationToken);
        return new RoverRequestUser(account.AccountId, "Development", devSubject.ToString());
    }

    return null;
}

static void ValidateStartupConfiguration(WebApplicationBuilder builder)
{
    if (builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing"))
    {
        return;
    }

    var missing = new List<string>();
    Require("Rover:Authentication:BetaApiKey", missing, "ROVER_BETA_API_KEY");
    Require("Rover:Cors:AllowedOrigins", missing);
    Require("Rover:Routing:Google:ApiKey", missing, "GOOGLE_ROUTES_API_KEY", "GOOGLE_PLACES_API_KEY");

    var storageMode = Environment.GetEnvironmentVariable("ROVER_STORAGE_MODE")
        ?? builder.Configuration["Rover:Storage:Mode"]
        ?? "InMemory";
    if (storageMode.Equals("PostgreSql", StringComparison.OrdinalIgnoreCase))
    {
        Require("Rover:Storage:PostgreSql:ConnectionString", missing, "DATABASE_URL", "ROVER_POSTGRES_CONNECTION_STRING");
    }

/*
    if (builder.Environment.IsEnvironment("Beta") || builder.Environment.IsStaging())
    {
        Require("ElevenLabs:ApiKey", missing, "ElevenLabs__ApiKey");
        Require("ElevenLabs:VoiceId", missing, "ElevenLabs__VoiceId");
        Require("ElevenLabs:ModelId", missing, "ElevenLabs__ModelId");
    }
*/
    if (missing.Count > 0)
    {
        throw new InvalidOperationException($"Rover cannot start outside Development until required configuration is present: {string.Join(", ", missing)}.");
    }

    void Require(string key, List<string> values, params string[] environmentVariables)
    {
        var configured = !string.IsNullOrWhiteSpace(builder.Configuration[key]);
        var fromEnvironment = environmentVariables.Any(variable =>
            !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(variable)));
        if (!configured && !fromEnvironment)
        {
            values.Add(key);
        }
    }
}

internal sealed record RoverRequestUser(Guid AccountId, string Provider, string Subject);

public partial class Program;

internal static class OpenApiDocumentFactory
{
    public static object Create()
    {
        return new
        {
            openapi = "3.0.1",
            info = new
            {
                title = "Rover API",
                version = "v1"
            },
            paths = new Dictionary<string, object>
            {
                ["/health"] = new
                {
                    get = new
                    {
                        tags = new[] { "Health" },
                        summary = "Returns the API health status.",
                        responses = new Dictionary<string, object>
                        {
                            ["200"] = new
                            {
                                description = "The service is healthy.",
                                content = new Dictionary<string, object>
                                {
                                    ["application/json"] = new
                                    {
                                        schema = new
                                        {
                                            type = "object",
                                            properties = new Dictionary<string, object>
                                            {
                                                ["service"] = new { type = "string", example = "Rover.Api" },
                                                ["status"] = new { type = "string", example = "Healthy" },
                                                ["checkedAtUtc"] = new { type = "string", format = "date-time" }
                                            },
                                            required = new[] { "service", "status", "checkedAtUtc" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                ["/api/speech/render"] = new
                {
                    post = new
                    {
                        tags = new[] { "Speech" },
                        summary = "Render premium Rover speech audio for narration and user-initiated answers.",
                        requestBody = new
                        {
                            required = true,
                            content = new Dictionary<string, object>
                            {
                                ["application/json"] = new
                                {
                                    example = new
                                    {
                                        text = "Welcome to Rover premium voice.",
                                        purpose = "WalkIntroduction",
                                        locale = "en-US",
                                        walkSessionId = "optional-walk-session-id",
                                        stopId = "optional-stop-id",
                                        idempotencyKey = "optional-idempotency-key"
                                    }
                                }
                            }
                        },
                        responses = new Dictionary<string, object>
                        {
                            ["200"] = new
                            {
                                description = "Rendered audio bytes.",
                                headers = new Dictionary<string, object>
                                {
                                    ["X-Rover-Speech-Provider"] = new { schema = new { type = "string" } },
                                    ["X-Rover-Speech-Cache"] = new { schema = new { type = "string", example = "hit" } },
                                    ["X-Rover-Speech-Fallback"] = new { schema = new { type = "string", example = "false" } }
                                },
                                content = new Dictionary<string, object>
                                {
                                    ["audio/mpeg"] = new
                                    {
                                        schema = new { type = "string", format = "binary" }
                                    }
                                }
                            },
                            ["400"] = new { description = "The speech request is invalid." },
                            ["401"] = new { description = "No Rover user context is available." },
                            ["503"] = new { description = "Speech provider configuration is unavailable." }
                        }
                    }
                },
                ["/api/commerce/hotel-rates/search"] = new
                {
                    post = new
                    {
                        tags = new[] { "Commerce" },
                        summary = "Search current hotel rates for an explicitly selected lodging candidate.",
                        requestBody = JsonExample(new
                        {
                            hotelName = "The Cove Country Inn",
                            placeId = "mapbox-place-id",
                            latitude = 44.678,
                            longitude = -76.397,
                            checkInDate = "2026-09-01",
                            checkOutDate = "2026-09-02",
                            adults = 2,
                            rooms = 1,
                            currency = "CAD"
                        }),
                        responses = new Dictionary<string, object>
                        {
                            ["200"] = new { description = "Current offers or a typed unavailable state returned." },
                            ["400"] = new { description = "The property, dates, occupancy, or currency are invalid." }
                        }
                    }
                },
                ["/api/location-context"] = new
                {
                    get = new
                    {
                        tags = new[] { "Location Intelligence" },
                        summary = "Get ranked nearby location context from enabled Rover backend providers.",
                        parameters = new object[]
                        {
                            new { name = "lat", @in = "query", required = true, schema = new { type = "number", format = "double" } },
                            new { name = "lng", @in = "query", required = true, schema = new { type = "number", format = "double" } },
                            new { name = "radiusMeters", @in = "query", required = false, schema = new { type = "integer", example = 1500 } },
                            new { name = "routeId", @in = "query", required = false, schema = new { type = "string" } },
                            new { name = "profileId", @in = "query", required = false, schema = new { type = "string", format = "uuid" } }
                        },
                        responses = StandardResponses("Ranked location context returned.")
                    }
                },
                ["/api/location-story"] = new
                {
                    post = new
                    {
                        tags = new[] { "Location Intelligence" },
                        summary = "Create a safe Rover story from selected verified location facts.",
                        requestBody = JsonExample(new
                        {
                            latitude = 44.678,
                            longitude = -76.395,
                            radiusMeters = 1500,
                            routeId = "optional-walk-session-id",
                            profileId = (string?)null,
                            interests = new[] { "history", "coffee" },
                            selectedPlaceIds = Array.Empty<string>(),
                            narrationStyle = "short-spoken"
                        }),
                        responses = StandardResponses("Location story returned.")
                    }
                },
                ["/api/live-context"] = new
                {
                    post = new
                    {
                        tags = new[] { "Journey Intelligence" },
                        summary = "Get independently expiring weather, event, and cited current information for a journey.",
                        requestBody = JsonExample(new
                        {
                            latitude = 44.678,
                            longitude = -76.395,
                            city = "Westport",
                            region = "Ontario",
                            country = "CA",
                            timeZone = "America/Toronto",
                            journeyStartsUtc = "2026-09-04T15:00:00Z",
                            journeyEndsUtc = "2026-09-04T21:00:00Z",
                            interests = new[] { "history", "music" },
                            userRequested = true
                        }),
                        responses = StandardResponses("Live journey context returned; individual provider failures remain typed in the response.")
                    }
                },
                ["/api/beta/configuration"] = SimpleGetPath("Beta", "Get private-beta configuration safety status."),
                ["/api/beta/diagnostics"] = SimpleGetPath("Beta", "Get privacy-safe private-beta diagnostics."),
                ["/api/beta/mapbox-smoke-test"] = new
                {
                    get = new
                    {
                        tags = new[] { "Beta" },
                        summary = "Run a sanitized Mapbox local discovery and walking-directions smoke test near a coordinate.",
                        parameters = new object[]
                        {
                            new { name = "latitude", @in = "query", required = true, schema = new { type = "number", format = "double" } },
                            new { name = "longitude", @in = "query", required = true, schema = new { type = "number", format = "double" } }
                        },
                        responses = StandardResponses("Sanitized Mapbox smoke-test result.")
                    }
                },
                ["/api/beta/problem-reports"] = new
                {
                    post = new
                    {
                        tags = new[] { "Beta" },
                        summary = "Submit a privacy-safe private-beta problem report.",
                        requestBody = JsonExample(new
                        {
                            category = "Map issue",
                            description = "Optional tester notes.",
                            walkSessionId = "optional-walk-session-id",
                            stopId = "optional-stop-id",
                            appVersion = "1.0.0-beta",
                            buildNumber = "9"
                        }),
                        responses = new Dictionary<string, object>
                        {
                            ["202"] = new { description = "Problem report accepted or queued." },
                            ["400"] = new { description = "Invalid report." }
                        }
                    }
                },
                ["/api/beta/crash-breadcrumbs"] = new
                {
                    post = new
                    {
                        tags = new[] { "Beta" },
                        summary = "Record a privacy-safe crash-reporting breadcrumb.",
                        requestBody = JsonExample(new
                        {
                            feature = "ActiveWalk",
                            action = "ManualArrivalTapped",
                            correlationId = "optional-correlation-id",
                            safeErrorCode = "optional-safe-error-code"
                        }),
                        responses = new Dictionary<string, object>
                        {
                            ["202"] = new { description = "Breadcrumb accepted." },
                            ["400"] = new { description = "Invalid breadcrumb." }
                        }
                    }
                },
                ["/api/walks"] = new
                {
                    post = new
                    {
                        tags = new[] { "Walks" },
                        summary = "Create a deterministic Union Square walk session.",
                        requestBody = new
                        {
                            required = true,
                            content = new Dictionary<string, object>
                            {
                                ["application/json"] = new
                                {
                                    example = new
                                    {
                                        latitude = 37.7880,
                                        longitude = -122.4075,
                                        availableMinutes = 60,
                                        interests = new[] { "architecture", "history", "coffee" },
                                        walkingPace = "Standard",
                                        accessibilityPreferences = new[] { "AvoidStairs" }
                                    }
                                }
                            }
                        },
                        responses = StandardResponses("Walk session created.")
                    }
                },
                ["/api/walks/{walkSessionId}"] = PathWithSession("Get a walk session."),
                ["/api/walks/{walkSessionId}/stops"] = PathWithSession("Get ordered stops for a walk session."),
                ["/api/walks/{walkSessionId}/next-stop"] = PathWithSession("Get the next unvisited stop."),
                ["/api/walks/{walkSessionId}/narrative-arc"] = PathWithSession("Get the disabled-by-default evidence-backed narrative arc for a walk."),
                ["/api/walks/{walkSessionId}/start"] = PostWithSession("Start a Ready walk."),
                ["/api/walks/{walkSessionId}/stops/{stopId}/arrive"] = new
                {
                    post = new
                    {
                        tags = new[] { "Walks" },
                        summary = "Mark the next stop as arrived.",
                        parameters = new object[]
                        {
                            SessionParameter(),
                            new { name = "stopId", @in = "path", required = true, schema = new { type = "string" } }
                        },
                        requestBody = new
                        {
                            required = false,
                            content = new Dictionary<string, object>
                            {
                                ["application/json"] = new
                                {
                                    example = new { latitude = 37.7880, longitude = -122.4075 }
                                }
                            }
                        },
                        responses = StandardResponses("Walk session updated.")
                    }
                },
                ["/api/walks/{walkSessionId}/location"] = new
                {
                    post = new
                    {
                        tags = new[] { "Walks" },
                        summary = "Submit a foreground location update for active-walk progress, off-route, and arrival detection.",
                        parameters = new[] { SessionParameter() },
                        requestBody = new
                        {
                            required = true,
                            content = new Dictionary<string, object>
                            {
                                ["application/json"] = new
                                {
                                    example = new
                                    {
                                        latitude = 37.7880,
                                        longitude = -122.4075,
                                        accuracyMeters = 12,
                                        headingDegrees = 90,
                                        speedMetersPerSecond = 1.2,
                                        recordedAtUtc = "2026-08-27T15:00:00Z"
                                    }
                                }
                            }
                        },
                        responses = StandardResponses("Location update accepted.")
                    }
                },
                ["/api/walks/{walkSessionId}/ask"] = new
                {
                    post = new
                    {
                        tags = new[] { "Conversation" },
                        summary = "Ask Rover a user-initiated question about the current walk context.",
                        parameters = new[] { SessionParameter() },
                        requestBody = new
                        {
                            required = true,
                            content = new Dictionary<string, object>
                            {
                                ["application/json"] = new
                                {
                                    example = new
                                    {
                                        questionText = "What is interesting about this stop?",
                                        currentStopId = "union-square-plaza",
                                        latitude = 37.7880,
                                        longitude = -122.4075,
                                        recordedAtUtc = "2026-08-27T15:00:00Z",
                                        conversationId = "optional-existing-conversation-id"
                                    }
                                }
                            }
                        },
                        responses = StandardResponses("Contextual answer returned.")
                    }
                },
                ["/api/walks/{walkSessionId}/journey-narration/evaluate"] = new
                {
                    post = new
                    {
                        tags = new[] { "Journey Intelligence" },
                        summary = "Evaluate whether Rover should play a route-aware contextual narration now.",
                        parameters = new[] { SessionParameter() },
                        requestBody = JsonExample(new
                        {
                            latitude = 44.678,
                            longitude = -76.395,
                            gpsAccuracyMeters = 12,
                            headingDegrees = 90,
                            speedMetersPerSecond = 1.2,
                            alreadyNarratedFactIds = Array.Empty<string>(),
                            requestedAtUtc = "2026-08-30T15:00:00Z"
                        }),
                        responses = StandardResponses("Journey narration decision returned.")
                    }
                },
                ["/api/walks/{walkSessionId}/adaptations/evaluate"] = AdaptationEvaluatePath(),
                ["/api/walks/{walkSessionId}/adaptations/{adaptationId}"] = AdaptationGetPath(),
                ["/api/walks/{walkSessionId}/adaptations/{adaptationId}/accept"] = AdaptationDecisionPath("Accept a proposed route adaptation and apply the route revision.", true),
                ["/api/walks/{walkSessionId}/adaptations/{adaptationId}/reject"] = AdaptationDecisionPath("Reject a proposed route adaptation.", false),
                ["/api/walks/{walkSessionId}/feedback"] = new
                {
                    post = new
                    {
                        tags = new[] { "Feedback" },
                        summary = "Submit skippable post-walk beta feedback.",
                        parameters = new[] { SessionParameter() },
                        requestBody = JsonExample(new
                        {
                            overallRating = 5,
                            directionsEasyToFollow = true,
                            stopsDetectedCorrectly = true,
                            narrationEnjoyable = true,
                            askRoverUseful = true,
                            walkRightLength = true,
                            wouldTakeAnotherWalk = true,
                            comments = "Optional comments"
                        }),
                        responses = new Dictionary<string, object>
                        {
                            ["202"] = new { description = "Feedback accepted." },
                            ["400"] = new { description = "Invalid feedback." }
                        }
                    }
                },
                ["/api/walks/{walkSessionId}/feedback/status"] = PathWithSession("Get whether post-walk feedback has already been submitted."),
                ["/api/walks/{walkSessionId}/complete"] = PostWithSession("Complete an InProgress walk after all stops are visited."),
                ["/api/walks/{walkSessionId}/cancel"] = PostWithSession("Cancel a Created, Ready, or InProgress walk.")
            }
        };
    }

    private static object PathWithSession(string summary)
    {
        return new
        {
            get = new
            {
                tags = new[] { "Walks" },
                summary,
                parameters = new[] { SessionParameter() },
                responses = StandardResponses("Successful response.")
            }
        };
    }

    private static object PostWithSession(string summary)
    {
        return new
        {
            post = new
            {
                tags = new[] { "Walks" },
                summary,
                parameters = new[] { SessionParameter() },
                responses = StandardResponses("Walk session updated.")
            }
        };
    }

    private static object SimpleGetPath(string tag, string summary)
    {
        return new
        {
            get = new
            {
                tags = new[] { tag },
                summary,
                responses = StandardResponses("Successful response.")
            }
        };
    }

    private static object JsonExample(object example)
    {
        return new
        {
            required = true,
            content = new Dictionary<string, object>
            {
                ["application/json"] = new { example }
            }
        };
    }

    private static object SessionParameter()
    {
        return new { name = "walkSessionId", @in = "path", required = true, schema = new { type = "string" } };
    }

    private static object AdaptationParameter()
    {
        return new { name = "adaptationId", @in = "path", required = true, schema = new { type = "string" } };
    }

    private static object AdaptationEvaluatePath()
    {
        return new
        {
            post = new
            {
                tags = new[] { "Adaptations" },
                summary = "Evaluate an adaptive route change and return a proposal without applying it.",
                parameters = new[] { SessionParameter() },
                requestBody = new
                {
                    required = true,
                    content = new Dictionary<string, object>
                    {
                        ["application/json"] = new
                        {
                            example = new
                            {
                                latitude = 37.7880,
                                longitude = -122.4075,
                                routeRevision = 1,
                                requestedType = "AddDiscovery",
                                interest = "coffee",
                                userRequest = "Find me coffee nearby",
                                dismissedDiscoveryIds = Array.Empty<string>()
                            }
                        }
                    }
                },
                responses = StandardResponses("Adaptation proposal created.")
            }
        };
    }

    private static object AdaptationGetPath()
    {
        return new
        {
            get = new
            {
                tags = new[] { "Adaptations" },
                summary = "Get an adaptation proposal by ID.",
                parameters = new object[] { SessionParameter(), AdaptationParameter() },
                responses = StandardResponses("Adaptation proposal returned.")
            }
        };
    }

    private static object AdaptationDecisionPath(string summary, bool requiresBody)
    {
        return new
        {
            post = new
            {
                tags = new[] { "Adaptations" },
                summary,
                parameters = new object[] { SessionParameter(), AdaptationParameter() },
                requestBody = requiresBody
                    ? new
                    {
                        required = true,
                        content = new Dictionary<string, object>
                        {
                            ["application/json"] = new { example = new { routeRevision = 1 } }
                        }
                    }
                    : null,
                responses = StandardResponses("Adaptation decision accepted.")
            }
        };
    }

    private static Dictionary<string, object> StandardResponses(string successDescription)
    {
        return new Dictionary<string, object>
        {
            ["200"] = new { description = successDescription },
            ["201"] = new { description = successDescription },
            ["400"] = new { description = "Validation ProblemDetails." },
            ["404"] = new { description = "Not found ProblemDetails." },
            ["409"] = new { description = "Lifecycle conflict ProblemDetails." }
        };
    }
}

internal static class SwaggerUi
{
    public const string Html = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Rover API Swagger</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        window.ui = SwaggerUIBundle({
          url: '/swagger/v1/swagger.json',
          dom_id: '#swagger-ui'
        });
      </script>
    </body>
    </html>
    """;
}

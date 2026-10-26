using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Rover.Infrastructure.Accounts;

namespace Rover.Api.Accounts;

public sealed record AccountOptions(bool Enabled, string Issuer, string ClientId, string RedirectUri, string DatabasePath, int ProfileLimit, int WalkLimit)
{
    public static AccountOptions Read(IConfiguration config) => new(
        config.GetValue<bool>("Rover:Accounts:Enabled"), config["Rover:Accounts:Issuer"] ?? "",
        config["Rover:Accounts:ClientId"] ?? "", config["Rover:Accounts:RedirectUri"] ?? "ai.myrover.rover://oauthredirect",
        config["Rover:Accounts:DatabasePath"] ?? "", config.GetValue("Rover:Accounts:ProfileLimit", 3), config.GetValue("Rover:Accounts:WalkLimit", 3));

    public void Validate()
    {
        if (!Enabled) return;
        if (!Uri.TryCreate(Issuer, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            !uri.Host.StartsWith("cognito-idp.", StringComparison.Ordinal) ||
            !(uri.Host.EndsWith(".amazonaws.com", StringComparison.Ordinal) || uri.Host.EndsWith(".amazonaws.com.cn", StringComparison.Ordinal)) ||
            uri.AbsolutePath.Length < 2 || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) ||
            string.IsNullOrWhiteSpace(ClientId) || RedirectUri != "ai.myrover.rover://oauthredirect" ||
            !Path.IsPathFullyQualified(DatabasePath) || ProfileLimit is < 1 or > 100 || WalkLimit is < 1 or > 100)
            throw new InvalidOperationException("Account settings require a Cognito issuer, public client ID, supported redirect, absolute persistent database path and valid library limits.");
    }
}

public static class PersonalLibraryEndpoints
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly HashSet<string> ProfileFields = ["interests", "walkingPace", "availableTime", "mobility", "contentDepth", "includePaidAttractions", "storyDensity", "excludedStoryCategories", "audioPreference", "distanceUnit", "language"];

    public static void AddPersonalLibrary(this IServiceCollection services, IConfiguration configuration)
    {
        var options = AccountOptions.Read(configuration);
        options.Validate();
        services.AddSingleton(options);
        services.AddAuthentication("WalkaboutAccount").AddJwtBearer("WalkaboutAccount", jwt =>
        {
            jwt.MapInboundClaims = false;
            jwt.IncludeErrorDetails = false;
            if (options.Enabled) jwt.Authority = options.Issuer;
            jwt.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true, ValidIssuer = options.Issuer, ValidateAudience = false,
                ValidateLifetime = true, ValidateIssuerSigningKey = true, RequireSignedTokens = true,
                ClockSkew = TimeSpan.FromSeconds(30), ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
                NameClaimType = "sub"
            };
            jwt.Events = new JwtBearerEvents
            {
                OnTokenValidated = context =>
                {
                    var principal = context.Principal!;
                    if (!options.Enabled || principal.FindFirstValue("token_use") != "access" ||
                        principal.FindFirstValue("client_id") != options.ClientId ||
                        string.IsNullOrEmpty(principal.FindFirstValue("sub")) ||
                        !(principal.FindFirstValue("scope") ?? "").Split(' ').Contains("openid"))
                        context.Fail("A user access token from the configured account client is required.");
                    return Task.CompletedTask;
                }
            };
        });
        services.AddAuthorization();
        if (options.Enabled) services.AddSingleton(new PersonalLibraryStore(options.DatabasePath, options.ProfileLimit, options.WalkLimit));
        if (options.Enabled) services.AddSingleton(new FriendsStore(options.DatabasePath));
        if (options.Enabled) {
            var sharing = new WalkSharingStore(options.DatabasePath);
            sharing.Cleanup();
            services.AddSingleton(sharing);
            services.AddSingleton(new SharedMediaProcessor());
        }
    }

    public static void MapPersonalLibrary(this WebApplication app)
    {
        var options = app.Services.GetRequiredService<AccountOptions>();
        app.MapGet("/api/account-library/config", () => Results.Ok(new
        {
            options.Enabled, issuer = options.Enabled ? options.Issuer : null,
            clientId = options.Enabled ? options.ClientId : null, options.RedirectUri,
            options.ProfileLimit, options.WalkLimit
        }));
        if (!options.Enabled) return;
        var group = app.MapGroup("/api/account-library").RequireAuthorization();
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "no-store";
            try { return await next(context); }
            catch (LibraryConflictException e) { return Results.Problem(statusCode: 409, title: e.Message); }
            catch (Exception e) when (e is ArgumentException or JsonException)
            { return Results.Problem(statusCode: 400, title: "Invalid library item."); }
        });
        group.MapGet("/{kind}", (string kind, ClaimsPrincipal user, PersonalLibraryStore store) =>
            ValidKind(kind) ? Results.Ok(store.List(Owner(user), kind)) : Results.NotFound());
        group.MapPut("/{kind}/{id:guid}", async (string kind, Guid id, HttpContext context, PersonalLibraryStore store) =>
        {
            if (!ValidKind(kind)) return Results.NotFound();
            // Bound chunked and ordinary bodies before parsing or writing to persistent storage.
            const int limit = 2_000_000;
            using var body = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await context.Request.Body.ReadAsync(buffer, context.RequestAborted)) > 0)
            {
                if (body.Length + read > limit) return Results.StatusCode(413);
                body.Write(buffer, 0, read);
            }
            var request = JsonSerializer.Deserialize<SaveLibraryRequest>(body.GetBuffer().AsSpan(0, (int)body.Length), Json);
            if (request is null || request.Data.ValueKind != JsonValueKind.Object) return Results.BadRequest();
            if (kind == "profiles") ValidateProfile(request.Data);
            else SavedWalkSnapshot.Validate(request.Data);
            return Results.Ok(store.Save(Owner(context.User), id, kind, request.Name, request.Data, request.Revision, request.IsDefault));
        });
        group.MapDelete("/{kind}/{id:guid}", (string kind, Guid id, int revision, ClaimsPrincipal user, PersonalLibraryStore store) =>
            !ValidKind(kind) ? Results.NotFound() : store.Delete(Owner(user), kind, id, revision) ? Results.NoContent() : Results.Conflict());
        group.MapPost("/walks/{id:guid}/preview", async (Guid id, ClaimsPrincipal user, PersonalLibraryStore store,
            Rover.Application.Walks.IWalkSessionRepository walks, CancellationToken ct) =>
        {
            var item = store.List(Owner(user), "walks").SingleOrDefault(x => x.Id == id);
            if (item is null) return Results.NotFound();
            var walk = SavedWalkSnapshot.Restore(item.Data);
            await walks.AddAsync(walk, ct);
            try
            {
                // Restoring a template creates a new session, so prepare stories just as for a new walk.
                app.Services.GetService<Rover.Application.Performance.IRoverWalkPrefetchService>()
                    ?.TryQueueWalkWarmup(walk, "created");
            }
            catch (Exception exception)
            {
                app.Logger.LogWarning(exception, "Saved walk story warmup could not be queued.");
            }
            return Results.Ok(Rover.Api.Mapping.WalkResponseMapper.ToResponse(walk));
        });
    }

    public static string Owner(ClaimsPrincipal user)
    {
        var issuer = user.FindFirstValue("iss");
        var subject = user.FindFirstValue("sub");
        if (user.Identity?.IsAuthenticated != true || string.IsNullOrEmpty(issuer) || string.IsNullOrEmpty(subject))
            throw new UnauthorizedAccessException();
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(issuer + "\n" + subject)));
    }

    private static bool ValidKind(string kind) => kind is "profiles" or "walks";
    public static void ValidateProfile(JsonElement data)
    {
        if (data.GetRawText().Length > 16000) throw new ArgumentException("Profile too large.");
        foreach (var field in data.EnumerateObject())
        {
            if (!ProfileFields.Contains(field.Name)) throw new ArgumentException("Unsupported profile field.");
            if (field.Name is "interests" or "excludedStoryCategories")
            {
                if (field.Value.ValueKind != JsonValueKind.Array || field.Value.GetArrayLength() > 30 ||
                    field.Value.EnumerateArray().Any(x => x.ValueKind != JsonValueKind.String || x.GetString()!.Length > 80))
                    throw new ArgumentException("Invalid interests.");
            }
            else if (field.Name == "includePaidAttractions")
            {
                if (field.Value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid paid preference.");
            }
            else if (field.Value.ValueKind != JsonValueKind.String || field.Value.GetString()!.Length > 80)
                throw new ArgumentException("Invalid preference.");
        }
    }
    private sealed record SaveLibraryRequest(string Name, JsonElement Data, int Revision = 0, bool IsDefault = false);
}

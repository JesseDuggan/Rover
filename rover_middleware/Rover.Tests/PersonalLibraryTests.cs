using System.Security.Claims;
using System.Text.Json;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using Rover.Api.Accounts;
using Rover.Api.Mapping;
using Rover.Domain.Walks;
using Rover.Infrastructure.Accounts;

internal static class PersonalLibraryTests
{
    private static readonly JsonElement Profile = JsonSerializer.SerializeToElement(new { interests = new[] { "History" }, walkingPace = "Easy" });
    private static string PathForTest() => Path.Combine(Path.GetTempPath(), "walkabout-library-tests", Guid.NewGuid().ToString("N"), "library.db");
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void Reject<T>(Action action) where T : Exception
    {
        try { action(); } catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }
    public static Task PersistenceAndOwnership()
    {
        var path = PathForTest();
        var store = new PersonalLibraryStore(path);
        var item = store.Save("alice", Guid.NewGuid(), "profiles", "City", Profile, 0, true);
        Check(store.List("bob", "profiles").Count == 0, "Account data leaked");
        Check(!store.Delete("bob", "profiles", item.Id, item.Revision), "Cross-account deletion");
        var restart = new PersonalLibraryStore(path);
        Check(restart.List("alice", "profiles").Single().Name == "City", "Data lost on restart");
        Reject<LibraryConflictException>(() => restart.Save("alice", item.Id, "profiles", "Stale", Profile, 0, false));
        Reject<LibraryConflictException>(() => restart.Save("alice", item.Id, "walks", "Wrong kind", Profile, 0, false));
        var second = restart.Save("alice", Guid.NewGuid(), "profiles", "Nature", Profile, 0, true);
        Check(restart.List("alice", "profiles").Count(x => x.IsDefault) == 1, "Multiple defaults");
        Check(restart.List("alice", "profiles").Single(x => x.Id == item.Id).Revision == 2, "Default update failed revision check");
        Check(restart.Delete("alice", "profiles", second.Id, second.Revision), "Delete failed");
        return Task.CompletedTask;
    }
    public static async Task AtomicLimits()
    {
        var store = new PersonalLibraryStore(PathForTest());
        var accepted = 0;
        await Task.WhenAll(Enumerable.Range(0, 12).Select(i => Task.Run(() =>
        {
            try { store.Save("alice", Guid.NewGuid(), "profiles", $"Profile {i}", Profile, 0, false); Interlocked.Increment(ref accepted); }
            catch (LibraryConflictException) { }
        })));
        Check(accepted == 3 && store.List("alice", "profiles").Count == 3, "Concurrent limit exceeded");
        var first = store.List("alice", "profiles")[0];
        store.Save("alice", first.Id, "profiles", "Renamed at cap", Profile, first.Revision, false);
        for (var i = 0; i < 3; i++) store.Save("alice", Guid.NewGuid(), "walks", $"Walk {i}", Profile, 0, false);
        Reject<LibraryConflictException>(() => store.Save("alice", Guid.NewGuid(), "walks", "Fourth", Profile, 0, false));
        store.Save("bob", Guid.NewGuid(), "profiles", "Independent", Profile, 0, false);
    }
    public static Task ValidationAndIdentity()
    {
        PersonalLibraryEndpoints.ValidateProfile(Profile);
        Reject<ArgumentException>(() => PersonalLibraryEndpoints.ValidateProfile(JsonSerializer.SerializeToElement(new { accountId = "other" })));
        Reject<ArgumentException>(() => PersonalLibraryEndpoints.ValidateProfile(JsonSerializer.SerializeToElement(new { interests = "History" })));
        var user = new ClaimsPrincipal(new ClaimsIdentity([new("iss", "issuer"), new("sub", "subject")], "test"));
        var other = new ClaimsPrincipal(new ClaimsIdentity([new("iss", "issuer"), new("sub", "Subject")], "test"));
        Check(PersonalLibraryEndpoints.Owner(user) != PersonalLibraryEndpoints.Owner(other), "Subjects must be case-sensitive");
        Reject<UnauthorizedAccessException>(() => PersonalLibraryEndpoints.Owner(new ClaimsPrincipal()));
        new AccountOptions(false, "", "", "", "", 3, 3).Validate();
        var valid = new AccountOptions(true, "https://cognito-idp.us-east-1.amazonaws.com/test-pool", "public-client", "ai.myrover.rover://oauthredirect", PathForTest(), 3, 3);
        valid.Validate();
        Check(AccountOptions.Read(new ConfigurationBuilder().Build()).RedirectUri == valid.RedirectUri, "Default callback must match mobile login");
        Reject<InvalidOperationException>(() => (valid with { Issuer = "https://example.com" }).Validate());
        Reject<InvalidOperationException>(() => (valid with { RedirectUri = "ai.myrover.rover:/oauthredirect" }).Validate());
        Reject<InvalidOperationException>(() => (valid with { RedirectUri = "https://ai.myrover.rover/oauthredirect" }).Validate());
        Reject<InvalidOperationException>(() => (valid with { RedirectUri = "ai.myrover.rover://oauthredirect/" }).Validate());
        return Task.CompletedTask;
    }
    public static Task ReplayResetsLifecycle()
    {
        var a = new GeoLocation(52.08, 4.31);
        var b = new GeoLocation(52.081, 4.312);
        var stop = new WalkStop("old-stop", 1, "Museum", b, "Description", "Narration", "History",
            Enum.GetValues<ContentType>()[0], Enum.GetValues<ContentSource>()[0], 5, 150, 30) { IsDestination = true };
        var route = new WalkRoute("old-route", "provider", "v1", DateTimeOffset.UtcNow, [a, b], new(a, b), 150, 3);
        var original = new WalkSession("old-session", a, DateTimeOffset.UtcNow, 30, 8, 150, "Museum walk", ["History"],
            Enum.GetValues<WalkingPace>()[0], [], [stop], route);
        var json = JsonSerializer.SerializeToElement(new { walk = original.ToResponse() }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var restored = SavedWalkSnapshot.Restore(json);
        Check(restored.WalkSessionId != original.WalkSessionId && restored.Route.RouteId != route.RouteId, "Reused stale session");
        Check(restored.VisitedStopCount == 0 && restored.StartedAtUtc is null && restored.Stops[0].StopId != stop.StopId, "Lifecycle not reset");
        Check(restored.Stops[0].IsDestination && restored.Route.Coordinates.SequenceEqual(route.Coordinates), "Route changed");
        Reject<ArgumentException>(() => SavedWalkSnapshot.Validate(Profile));
        return Task.CompletedTask;
    }

    public static async Task AuthenticationBoundary()
    {
        const string issuer = "https://cognito-idp.eu-west-1.amazonaws.com/test-pool";
        using var rsa = RSA.Create(2048);
        var key = new RsaSecurityKey(rsa) { KeyId = "local-test" };
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Rover:Accounts:Enabled"] = "true", ["Rover:Accounts:Issuer"] = issuer,
            ["Rover:Accounts:ClientId"] = "public-client", ["Rover:Accounts:DatabasePath"] = PathForTest()
        });
        builder.Services.AddPersonalLibrary(builder.Configuration);
        var warmup = new RecordingWarmup();
        builder.Services.AddSingleton<Rover.Application.Performance.IRoverWalkPrefetchService>(warmup);
        builder.Services.AddDataProtection().UseEphemeralDataProtectionProvider();
        builder.Services.AddSingleton<Rover.Application.Walks.IWalkSessionRepository, Rover.Infrastructure.Walks.InMemoryWalkSessionRepository>();
        builder.Services.PostConfigure<JwtBearerOptions>("WalkaboutAccount", options =>
        {
            var metadata = new OpenIdConnectConfiguration { Issuer = issuer };
            metadata.SigningKeys.Add(key);
            options.Configuration = metadata;
            options.ConfigurationManager = new Microsoft.IdentityModel.Protocols.StaticConfigurationManager<OpenIdConnectConfiguration>(metadata);
        });
        await using var app = builder.Build();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapPersonalLibrary();
        app.MapFriends();
        app.MapWalkSharing();
        await app.StartAsync();
        try
        {
            using var http = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
            Check((await http.GetAsync("/api/account-library/profiles")).StatusCode == HttpStatusCode.Unauthorized, "Anonymous library access");
            Check((await http.GetAsync("/api/friends/state")).StatusCode == HttpStatusCode.Unauthorized, "Anonymous friends access");
            Check((await http.GetAsync("/api/shared-walks")).StatusCode == HttpStatusCode.Unauthorized, "Anonymous shared walk access");
            var landing = await http.GetStringAsync("/invite");
            Check(landing.Contains("ai.myrover.rover.friends://friends/invite?code="), "Invitation deep-link mismatch");
            string Token(string client = "public-client", string use = "access", string tokenIssuer = issuer, bool expired = false, string subject = "alice") =>
                new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
                {
                    Issuer = tokenIssuer, Subject = new ClaimsIdentity([new("sub", subject), new("client_id", client), new("token_use", use), new("scope", "openid email")]),
                    IssuedAt = DateTime.UtcNow.AddHours(-2), NotBefore = DateTime.UtcNow.AddHours(-2),
                    Expires = expired ? DateTime.UtcNow.AddHours(-1) : DateTime.UtcNow.AddMinutes(10),
                    SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256)
                });
            foreach (var token in new[] { Token(client: "other-client"), Token(use: "id"), Token(tokenIssuer: "https://foreign.example"), Token(expired: true), "invalid.token.value" })
            {
                http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
                Check((await http.GetAsync("/api/account-library/profiles")).StatusCode == HttpStatusCode.Unauthorized, "Invalid token accepted");
                Check((await http.GetAsync("/api/friends/state")).StatusCode == HttpStatusCode.Unauthorized, "Friends accepted invalid token");
                Check((await http.GetAsync("/api/shared-walks")).StatusCode == HttpStatusCode.Unauthorized, "Sharing accepted invalid token");
            }
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token());
            Check((await http.GetAsync("/api/account-library/profiles")).StatusCode == HttpStatusCode.OK, "Valid access token rejected");
            Check((await http.PutAsJsonAsync("/api/friends/profile", new { username = "alice", displayName = "Alice" })).IsSuccessStatusCode, "Friends profile endpoint failed");
            Check((await http.GetAsync("/api/friends/state")).IsSuccessStatusCode, "Friends state endpoint failed");
            Check((await http.PutAsync("/api/friends/profile", new StringContent(new string('x', 4097)))).StatusCode == HttpStatusCode.RequestEntityTooLarge, "Friends body limit bypass");
            Check((await http.PostAsync("/api/friends/invites", null)).IsSuccessStatusCode, "Friends invite endpoint failed");
            var friends = app.Services.GetRequiredService<FriendsStore>();
            string OwnerFor(string sub) => PersonalLibraryEndpoints.Owner(new ClaimsPrincipal(new ClaimsIdentity([new("iss",issuer),new("sub",sub)],"test")));
            var bob = friends.SaveProfile(OwnerFor("bob"), "bob", "Bob");
            friends.Request(OwnerFor("alice"), bob.Id);
            friends.Act(OwnerFor("bob"), friends.State(OwnerFor("bob")).Connections.Single().RequestId!, "accept");
            var createShare = await http.PostAsJsonAsync("/api/shared-walks", new SharedWalkDraft("Shared route", false, [], [], [bob.Id]));
            Check(createShare.IsSuccessStatusCode, "Share draft failed");
            var shareId = (await createShare.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetString();
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(subject: "bob"));
            Check((await http.GetAsync($"/api/shared-walks/{shareId}")).StatusCode == HttpStatusCode.NotFound, "Draft exposed before consent");
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token());
            Check((await http.PostAsync($"/api/shared-walks/{shareId}/publish", null)).IsSuccessStatusCode, "Publishing failed");
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(subject: "bob"));
            Check((await http.GetAsync($"/api/shared-walks/{shareId}")).IsSuccessStatusCode, "Recipient access failed");
            Check((await http.DeleteAsync($"/api/shared-walks/{shareId}")).StatusCode == HttpStatusCode.NotFound, "Recipient deleted sender's share");
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token());
            Check((await http.DeleteAsync($"/api/shared-walks/{shareId}")).IsSuccessStatusCode, "Owner could not revoke share");
            var a = new GeoLocation(52.08, 4.31);
            var b = new GeoLocation(52.081, 4.312);
            var original = new WalkSession("saved-session", a, DateTimeOffset.UtcNow, 30, 8, 150,
                "Museum walk", ["History"], Enum.GetValues<WalkingPace>()[0], [],
                [new WalkStop("saved-stop", 1, "Museum", b, "Description", "Narration", "History",
                    Enum.GetValues<ContentType>()[0], Enum.GetValues<ContentSource>()[0], 5, 150, 30)],
                new WalkRoute("saved-route", "provider", "v1", DateTimeOffset.UtcNow, [a, b], new(a, b), 150, 3));
            var id = Guid.NewGuid();
            var saved = await http.PutAsJsonAsync($"/api/account-library/walks/{id}",
                new { name = "Museum", data = new { walk = original.ToResponse() } });
            Check(saved.IsSuccessStatusCode, "Could not save route fixture");
            var preview = await http.PostAsync($"/api/account-library/walks/{id}/preview", null);
            Check(preview.IsSuccessStatusCode, "Saved preview failed");
            var restored = await preview.Content.ReadFromJsonAsync<Rover.Api.Contracts.WalkSessionResponse>();
            Check(warmup.Calls.Count == 1 && warmup.Calls[0].Reason == "created", "Saved preview did not queue story creation");
            var queued = warmup.Calls[0].Walk;
            Check(queued.WalkSessionId == restored!.WalkSessionId && queued.WalkSessionId != original.WalkSessionId,
                "Warmup targeted the old session");
            var repository = app.Services.GetRequiredService<Rover.Application.Walks.IWalkSessionRepository>();
            Check(await repository.GetByIdAsync(queued.WalkSessionId, CancellationToken.None) is not null,
                "Restored session was not persisted");
            Check((await http.PostAsync($"/api/account-library/walks/{Guid.NewGuid()}/preview", null)).StatusCode == HttpStatusCode.NotFound,
                "Missing saved walk accepted");
            Check(warmup.Calls.Count == 1, "Missing walk queued work");
            warmup.ThrowOnQueue = true;
            Check((await http.PostAsync($"/api/account-library/walks/{id}/preview", null)).IsSuccessStatusCode,
                "Background queue failure blocked saved preview");
        }
        finally { await app.StopAsync(); }
    }

    private sealed class RecordingWarmup : Rover.Application.Performance.IRoverWalkPrefetchService
    {
        public List<(WalkSession Walk, string Reason)> Calls { get; } = [];
        public bool ThrowOnQueue { get; set; }
        public bool TryQueueWalkWarmup(WalkSession session, string reason)
        {
            if (ThrowOnQueue) throw new InvalidOperationException("Test queue unavailable");
            Calls.Add((session, reason));
            return true;
        }
        public Rover.Application.Performance.RoverBackgroundWorkStats GetStats() =>
            new(Calls.Count, Calls.Count, 0, 0, null, null, null);
    }
}

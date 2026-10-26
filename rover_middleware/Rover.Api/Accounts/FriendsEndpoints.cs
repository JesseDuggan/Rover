using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Rover.Infrastructure.Accounts;

namespace Rover.Api.Accounts;

public static class FriendsEndpoints
{
    public static void MapFriends(this WebApplication app)
    {
        if (!app.Services.GetRequiredService<AccountOptions>().Enabled) return;
        var group = app.MapGroup("/api/friends").RequireAuthorization(new AuthorizeAttribute { AuthenticationSchemes = "WalkaboutAccount" });
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "no-store";
            try {
                var store = context.HttpContext.RequestServices.GetRequiredService<FriendsStore>();
                store.Budget(PersonalLibraryEndpoints.Owner(context.HttpContext.User), "api", 90, 60);
                return await next(context);
            }
            catch (FriendsException e) { return Results.Problem(statusCode: e.Status, title: e.Message); }
            catch (JsonException) { return Results.Problem(statusCode: 400, title: "Invalid request."); }
        });
        group.MapGet("/state", (ClaimsPrincipal user, FriendsStore store) => Results.Ok(store.State(PersonalLibraryEndpoints.Owner(user))));
        group.MapPut("/profile", async (HttpContext context, FriendsStore store) => {
            var body = await Read(context); var owner = PersonalLibraryEndpoints.Owner(context.User);
            return Results.Ok(store.SaveProfile(owner, body.Username, body.DisplayName));
        });
        group.MapGet("/lookup", (string username, ClaimsPrincipal user, FriendsStore store) => {
            if (username.Length > 25) return Results.BadRequest();
            var member = store.Lookup(PersonalLibraryEndpoints.Owner(user), username);
            return member == null ? Results.NotFound() : Results.Ok(member);
        });
        group.MapPost("/requests", async (HttpContext context, FriendsStore store) => {
            var body = await Read(context); var owner = PersonalLibraryEndpoints.Owner(context.User);
            store.Budget(owner, "requests", 20);
            store.Request(owner, body.MemberId ?? ""); return Results.NoContent();
        });
        group.MapPost("/requests/{id:guid}/{action}", (Guid id, string action, ClaimsPrincipal user, FriendsStore store) => {
            store.Act(PersonalLibraryEndpoints.Owner(user), id.ToString("N"), action); return Results.NoContent();
        });
        group.MapPut("/blocks/{id:guid}", (Guid id, ClaimsPrincipal user, FriendsStore store) => {
            store.Block(PersonalLibraryEndpoints.Owner(user), id.ToString("N"), true); return Results.NoContent();
        });
        group.MapDelete("/blocks/{id:guid}", (Guid id, ClaimsPrincipal user, FriendsStore store) => {
            store.Block(PersonalLibraryEndpoints.Owner(user), id.ToString("N"), false); return Results.NoContent();
        });
        group.MapPost("/invites", (ClaimsPrincipal user, FriendsStore store) => {
            var owner = PersonalLibraryEndpoints.Owner(user); store.Budget(owner, "invites", 10);
            return Results.Ok(store.Invite(owner));
        });
        group.MapDelete("/invites", (ClaimsPrincipal user, FriendsStore store) => {
            store.RevokeInvite(PersonalLibraryEndpoints.Owner(user)); return Results.NoContent();
        });
        group.MapPost("/invites/resolve", async (HttpContext context, FriendsStore store) => {
            var body = await Read(context);
            if (body.Code?.Length != 48) return Results.BadRequest();
            return Results.Ok(store.ResolveInvite(PersonalLibraryEndpoints.Owner(context.User), body.Code));
        });
        group.MapPost("/reports", async (HttpContext context, FriendsStore store) => {
            var body = await Read(context); var owner = PersonalLibraryEndpoints.Owner(context.User);
            store.Budget(owner, "reports", 10);
            store.Report(owner, body.MemberId ?? "", body.Reason, body.Details); return Results.NoContent();
        });

        // No member data or access is exposed by this public installation/deep-link bridge.
        app.MapGet("/invite", (HttpContext context) => {
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers["Content-Security-Policy"] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            return Results.Content(InviteHtml, "text/html");
        });
    }
    private static async Task<FriendRequest> Read(HttpContext context)
    {
        using var body = new MemoryStream(); var buffer = new byte[1024]; int read;
        while ((read = await context.Request.Body.ReadAsync(buffer, context.RequestAborted)) > 0) {
            if (body.Length + read > 4096) throw new FriendsException(413, "Request too large.");
            body.Write(buffer, 0, read);
        }
        return JsonSerializer.Deserialize<FriendRequest>(body.GetBuffer().AsSpan(0, (int)body.Length), new JsonSerializerOptions(JsonSerializerDefaults.Web))
            ?? throw new FriendsException(400, "Invalid request.");
    }
    private sealed record FriendRequest(string? Username, string? DisplayName, string? MemberId, string? Code, string? Reason, string? Details);
    private const string InviteHtml = """
        <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Walkabout invitation</title><style>body{font:18px system-ui;margin:48px auto;padding:24px;max-width:520px;color:#173a35;background:#fff}a{display:inline-block;padding:14px 20px;background:#14675b;color:white;border-radius:6px}code{overflow-wrap:anywhere}h1{font-size:32px}</style>
        <h1>Walkabout</h1><h2>A friend invited you</h2><p>Sign in or create an account in Walkabout to review this invitation. Nothing is shared automatically.</p>
        <a id="open" hidden>Open Walkabout</a><p id="status"></p><p>If Walkabout is not installed yet, ask your invitation sender for the current app installation link. Keep this invitation and reopen it afterwards.</p>
        <script>const code=location.hash.slice(1);if(/^[a-f0-9]{48}$/.test(code)){const a=document.getElementById('open');a.href='ai.myrover.rover.friends://friends/invite?code='+code;a.hidden=false;document.getElementById('status').textContent='You can also paste this invitation link into Friends in the app.';}else{document.getElementById('status').textContent='This invitation link is invalid.';}</script></html>
        """;
}

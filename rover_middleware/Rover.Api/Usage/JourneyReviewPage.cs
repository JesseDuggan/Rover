using System.Net;
using System.Text.Json;
using System.Text;
using System.Security.Cryptography;

namespace Rover.Api.Usage;

public static class JourneyReviewPage
{
    static readonly SemaphoreSlim Running = new(1,1);
    public static void Map(WebApplication app)
    {
        app.MapGet("/admin/research-review", Show);
        app.MapPost("/admin/research-review", Run);
    }
    static bool Authorized(HttpContext h, IConfiguration c)
    {
        h.Response.Headers.CacheControl="no-store";
        h.Response.Headers["X-Robots-Tag"]="noindex, nofollow";
        if(UsagePage.Authorized(h,c["WALKABOUT_USAGE_PASSWORD"])) return true;
        h.Response.Headers.WWWAuthenticate="Basic realm=\"Walkabout usage\"";return false;
    }
    static string Folder(IConfiguration c) => Path.Combine(c["Usage:Directory"] ?? Path.Combine(
        Environment.GetEnvironmentVariable("RAILWAY_VOLUME_MOUNT_PATH") ?? "work","usage"),"reviews");
    static string E(string? s) => WebUtility.HtmlEncode(s??"");
    static IResult Show(HttpContext h,IConfiguration c,UsageStore store)
    {
        if(!Authorized(h,c))return Results.Unauthorized();
        var nonce=Guid.NewGuid().ToString("N");
        h.Response.Headers["Content-Security-Policy"]=$"default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'";
        var id=h.Request.Query["id"].ToString();
        if(id.Length>0) {
            if(!Guid.TryParseExact(id,"N",out _))return Results.BadRequest();
            var file=Path.Combine(Folder(c),id+".json");
            if(!File.Exists(file))return Results.NotFound();
            var report=JsonSerializer.Deserialize<JourneyReviewReport>(File.ReadAllText(file))!;
            var html=new StringBuilder("<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>Walkabout review</title><style>body{font:17px/1.5 system-ui;max-width:1000px;margin:32px auto;padding:20px;background:#f3f6f4;color:#18362d}article{background:white;padding:20px;margin:16px 0;border-radius:12px}pre{white-space:pre-wrap}a{color:#006d67}</style><a href='/admin/research-review'>New review</a><h1>Research review — proposals only</h1><p>No journey or story was changed. Confidence is automated, not independent historical verification.</p>");
            html.Append($"<p>{E(report.Context.City)} · {E(report.Status)} · {E(report.Created.ToString("u"))}</p><p>{E(report.Context.EvidenceOrigin)}</p><p>Interests: {E(string.Join(", ",report.Context.Interests))}. Depth: {E(report.Context.ContentDepth)}.</p><a href='/admin/journeys?walk={E(report.Walk)}'>Original journey</a> · <a href='/admin/journeys?request={E(report.ResearchTrace)}'>Research calls and evidence decisions</a><h2>Findings and suggested improvements</h2>");
            foreach(var f in report.Findings)html.Append($"<article><h3>{E(f.Title)}</h3><p><strong>Recorded evidence:</strong> {E(f.Evidence)}</p><p><strong>Suggestion:</strong> {E(f.Suggestion)}</p><small>{E(f.Code)}</small></article>");
            html.Append("<h2>Research proposals</h2>");
            foreach(var p in report.Proposals) {
                html.Append($"<article><h3>{E(p.Place)}</h3><p>{E(p.Status)}</p><p>{E(p.Question)}</p>");
                foreach(var reason in p.Rejections)html.Append($"<p>{E(reason)}</p>");
                foreach(var story in p.Stories) {
                    html.Append($"<h4>{E(story.Title)}</h4>");
                    foreach(var v in story.Variants)html.Append($"<blockquote>{E(v.Narration)}</blockquote>");
                    foreach(var source in story.Sources)if(InspectionDetails.Source(source.Url??"") is {} url)
                        html.Append($"<p><a href='{E(url)}' rel='noreferrer noopener'>{E(source.Title??source.ProviderName)}</a> · retrieved {E(source.RetrievedUtc.ToString("u"))}</p>");
                    html.Append($"<details><summary>Claims, source links and automated confidence</summary><pre>{E(JsonSerializer.Serialize(story,new JsonSerializerOptions{WriteIndented=true}))}</pre></details>");
                }html.Append("</article>");
            }
            var usage=store.Rows("SELECT count(*),coalesce(sum(usd),0),sum(usd IS NULL) FROM events WHERE at >= $since AND trace='"+report.ResearchTrace+"' AND kind='Model usage'",31,"");
            html.Append("<h2>Research cost visibility</h2><p>The trace shows provider attempts and model receipts. Prices are estimates; absent receipts or unpriced tools mean the full cost is unknown.</p>");
            if(usage.Count>0)html.Append($"<p>{E(usage[0][0])} model receipts · ${E(usage[0][1])} priced subtotal · {E(usage[0][2])} unpriced receipts.</p>");
            return Results.Content(html.Append("</html>").ToString(),"text/html");
        }
        var walk=h.Request.Query["walk"].ToString();
        if(!JourneyInspectionPage.ValidKey(walk))return Results.BadRequest();
        var example=JsonSerializer.Serialize(new JourneyReviewRequest(walk,"","","",["history","architecture"],"deep",[]),new JsonSerializerOptions{WriteIndented=true});
        return Results.Content("""
        <!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <title>Research and review · Walkabout</title><style>body{font:17px/1.5 system-ui;max-width:1000px;margin:32px auto;padding:20px;background:#f3f6f4;color:#18362d}textarea{width:100%;height:320px;font:15px monospace}button{padding:14px;font:inherit}pre{white-space:pre-wrap}a{color:#006d67}</style>
        <a href='/admin/journeys'>Journey inspector</a><h1>Research and review agent</h1>
        <p>Review a linked journey, identify weak drafts and investigate up to two recorded places. Findings and researched drafts are proposals for your approval. This tool never changes routes or published stories.</p>
        <p>Supply the journey's actual area, interests and depth. Leave Places empty for a review without paid research. To investigate, add up to two entries with Name, Latitude and Longitude. If the inspector uses a story title rather than the place name, include RecordedTitle to identify that record. Confirm the map coordinates and title-to-place association. These are administrator-supplied context, not automatically recovered profile preferences.</p>
        <p>Bound: 500 inspection records over 31 days; two research passes; 120 seconds overall. Each pass can make several provider calls. This is a request/time limit, not a guaranteed dollar cap.</p>
        <label for=context>Review context (JSON)</label>
        """+$"<textarea id=context>{E(example)}</textarea><p><button id=run>Run review</button></p><p id=status role=status></p><pre id=result></pre><script nonce='{nonce}'>"+"""
        document.getElementById('run').onclick=async()=>{
          const button=document.getElementById('run'),status=document.getElementById('status');button.disabled=true;
          status.textContent='Reviewing evidence and researching selected places…';
          try {const payload=JSON.parse(document.getElementById('context').value);
            const response=await fetch('/admin/research-review',{method:'POST',headers:{'Content-Type':'application/json','X-Walkabout-Review':'1'},body:JSON.stringify(payload)});
            if(!response.ok)throw Error(await response.text());
            const report=await response.json();document.getElementById('result').textContent=JSON.stringify(report,null,2);
            status.textContent='Review saved. No changes applied. ';
            const link=document.createElement('a');link.href='/admin/research-review?id='+report.id;link.textContent='Open saved report';status.append(link);
          }catch(e){status.textContent='Review not completed: '+e.message;}finally{button.disabled=false;}
        };
        </script></html>
        ""","text/html");
    }
    static async Task<IResult> Run(HttpContext h,IConfiguration c,JourneyReviewAgent agent,UsageStore store)
    {
        if(!Authorized(h,c))return Results.Unauthorized();
        // Browser cross-origin requests cannot supply this header without a preflight;
        // reject foreign origins too, including deployments with broad API CORS rules.
        if(h.Request.Headers["X-Walkabout-Review"]!="1")return Results.StatusCode(403);
        var origin=h.Request.Headers.Origin.ToString();
        // Railway terminates TLS before forwarding HTTP to the application.
        if(origin.Length>0 && (!Uri.TryCreate(origin,UriKind.Absolute,out var originUri) ||
            !originUri.Authority.Equals(h.Request.Host.Value,StringComparison.OrdinalIgnoreCase) ||
            (originUri.Scheme!="https" && originUri.Scheme!=h.Request.Scheme)))return Results.StatusCode(403);
        if(h.Request.ContentLength is null or > 8192)return Results.BadRequest("A JSON body of at most 8192 bytes is required.");
        JourneyReviewRequest? request;
        try {request=await h.Request.ReadFromJsonAsync<JourneyReviewRequest>(h.RequestAborted);} catch(JsonException){return Results.BadRequest("Invalid JSON.");}
        if(!JourneyReviewAgent.Valid(request))return Results.BadRequest("Supply a 16-character journey key, city, region, country, interests, depth (quick/standard/deep), and at most two valid places.");
        if(!await Running.WaitAsync(0,h.RequestAborted))return Results.Conflict("A review is already running. Wait for its report before starting another.");
        try {
            Directory.CreateDirectory(Folder(c));
            var revision=store.Rows("SELECT coalesce(max(rowid),0),count(*) FROM events WHERE at >= $since AND journey=$journey",31,request!.Walk);
            var fingerprint=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(request)+JsonSerializer.Serialize(revision))));
            var cache=Path.Combine(Folder(c),fingerprint+".cache");
            if(File.Exists(cache) && File.GetLastWriteTimeUtc(cache)>DateTime.UtcNow.AddMinutes(-15)) {
                var cachedId=File.ReadAllText(cache);
                if(Guid.TryParseExact(cachedId,"N",out _) && File.Exists(Path.Combine(Folder(c),cachedId+".json")))
                    return Results.Json(JsonSerializer.Deserialize<JourneyReviewReport>(File.ReadAllText(Path.Combine(Folder(c),cachedId+".json"))));
            }
            // Retention matches the inspector. Never remove files outside this dedicated directory.
            foreach(var old in Directory.EnumerateFiles(Folder(c)).Where(x=>x.EndsWith(".json")||x.EndsWith(".cache")))
                if(File.GetLastWriteTimeUtc(old)<DateTime.UtcNow.AddDays(-31))File.Delete(old);
            var report=await agent.RunAsync(request!,h.RequestAborted);
            var path=Path.Combine(Folder(c),report.Id+".json");
            await File.WriteAllTextAsync(path,JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}),h.RequestAborted);
            if(report.Status=="Complete") await File.WriteAllTextAsync(cache,report.Id,h.RequestAborted);
            return Results.Json(report);
        } catch(InvalidOperationException) {return Results.NotFound("No inspector evidence is available for this journey in the 31-day window.");}
        finally {Running.Release();}
    }
}

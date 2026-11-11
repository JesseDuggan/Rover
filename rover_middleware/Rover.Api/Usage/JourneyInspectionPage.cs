using System.Net;
using System.Text;
using System.Text.Json;

namespace Rover.Api.Usage;

public static class JourneyInspectionPage
{
    public static void Map(WebApplication app) => app.MapGet("/admin/journeys", Show);
    static string Time(string value) => $"<time datetime='{E(value.Replace(' ', 'T'))}Z' title='{E(value)} UTC'>{E(value)} UTC</time>";
    internal static bool ValidKey(string s) => s.Length == 0 || s.Length == 16 && s.All(char.IsAsciiHexDigit);
    static string E(string? s) => WebUtility.HtmlEncode(s ?? "");
    static string Link(string key,string id) => $"<a href='?{key}={E(id)}'>{E(id)}</a>";
    static IResult Show(HttpContext http, IConfiguration config, UsageStore store)
    {
        var nonce = Guid.NewGuid().ToString("N");
        http.Response.Headers.CacheControl="no-store";
        http.Response.Headers["X-Robots-Tag"]="noindex, nofollow";
        http.Response.Headers["Content-Security-Policy"]=$"default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
        if (!UsagePage.Authorized(http,config["WALKABOUT_USAGE_PASSWORD"])) {
            http.Response.Headers.WWWAuthenticate="Basic realm=\"Walkabout usage\", charset=\"UTF-8\"";
            return Results.Unauthorized();
        }
        var walk=http.Request.Query["walk"].ToString();
        var request=http.Request.Query["request"].ToString();
        var story=http.Request.Query["story"].ToString();
        if(!ValidKey(walk)||!ValidKey(request)||!ValidKey(story)) return Results.BadRequest();
        var search=http.Request.Query["q"].ToString().Trim();
        if(search.Length>120) return Results.BadRequest("Search is limited to 120 characters.");
        var where=" FROM events e WHERE at >= $since";
        // Keep all events in matching requests, including steps without a title.
        if(search.Length>0) where+=" AND EXISTS (SELECT 1 FROM events named WHERE (named.trace=e.trace OR (e.journey<>'' AND named.journey=e.journey)) AND named.at >= $since AND instr(lower(COALESCE(json_extract(CASE WHEN json_valid(named.details) THEN named.details ELSE '{}' END,'$.title'),'')),lower($search))>0)";
        if(walk.Length>0) where+=" AND journey=$journey";
        if(request.Length>0) where+=" AND trace='"+request+"'";
        if(story.Length>0) where+=" AND json_extract(CASE WHEN json_valid(details) THEN details ELSE '{}' END,'$.story')='"+story+"'";
        var html=new StringBuilder("""
        <!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <title>Journey &amp; story inspector · Walkabout</title><style>
        *{box-sizing:border-box}body{background:#f3f6f4;color:#18362d;font:16px/1.55 system-ui;margin:0}main{max-width:1200px;margin:auto;padding:28px 20px 80px}h1{font-size:2.2rem;line-height:1.2}h2{margin-top:32px}a{color:#006d67}nav{display:flex;gap:20px}.intro,article{background:white;border:1px solid #d6e3dc;padding:20px;border-radius:12px;margin:16px 0}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;background:white}th,td{text-align:left;border-bottom:1px solid #dde5e0;padding:10px;vertical-align:top}th{background:#e5eeea}small{color:#526b62}.badge{background:#e5eeea;border-radius:12px;padding:4px 10px;display:inline-block}.warn{border-left:5px solid #b46a20}summary{cursor:pointer;font-weight:600}blockquote{margin:18px 0;border-left:3px solid #6f9e8c;padding-left:18px}p{max-width:95ch}li,td{overflow-wrap:anywhere}input,button{font:inherit;padding:10px;border:1px solid #9eb9ac;border-radius:7px}input{max-width:100%}button{background:#e5eeea;cursor:pointer}
        </style><main><nav><a href="/admin/usage?days=7">API usage</a><a href="/admin/journeys">All journeys and stories</a></nav>
        <h1>How a walk becomes a story</h1><div class=intro><p>Discover places → choose stops → research evidence → validate → prepare narration → play.</p>
        <p id=time-zone>Times are shown in UTC until your browser converts them to your local time.</p><p>Last 7 days of recorded activity. Open a walk, request or story to follow its trail. A request is one operation; a walk can contain many requests. Open a journey title to see its stories and research together. “Unlinked” means the journey ID was unavailable—not that it was a separate walk.</p>
        <p>Detailed records begin with this release. Earlier activity has limited detail. “Accepted” means automated checks passed, not that a historian verified every fact. Missing playback events mean unknown, not unheard. This page observes decisions; it does not automatically train a model.</p></div>
        """);
        html.Append($"<form class=intro method=get><label for=place>Find a place or story</label> <input id=place name=q maxlength=120 value='{E(search)}' placeholder='Perth Museum, Dahlia'> <button type=submit>Find stories</button><p><small>Searches recorded place and story titles and includes the whole linked journey, not just the matching story. No match may mean a request has no title recorded yet.</small></p>");
        foreach(var filter in new[]{("walk",walk),("request",request),("story",story)})
            if(filter.Item2.Length>0) html.Append($"<input type=hidden name='{filter.Item1}' value='{E(filter.Item2)}'>");
        html.Append("</form>");
        if(walk.Length+request.Length+story.Length>0) html.Append($"<p class=badge>Filtered: {E(walk.Length>0?"walk "+walk:request.Length>0?"request "+request:"story "+story)}</p>");
        Table("Journeys",["Walk","Places and stories","Latest activity","Recorded events","Inspection events"],
            "SELECT journey,group_concat(DISTINCT NULLIF(json_extract(CASE WHEN json_valid(details) THEN details ELSE '{}' END,'$.title'),'')),datetime(max(at),'unixepoch'),count(*),sum(kind='Story inspection')"+where+" AND journey<>'' GROUP BY journey ORDER BY max(at) DESC LIMIT 50");
        Table("Research and preparation requests",["Request","Places and stories","Walk","Action","Inspection events","Provider attempts","Latest activity"],
            "SELECT trace,group_concat(DISTINCT NULLIF(json_extract(CASE WHEN json_valid(details) THEN details ELSE '{}' END,'$.title'),'')),CASE WHEN max(journey)='' THEN 'Unlinked' ELSE max(journey) END,max(action),sum(kind='Story inspection'),sum(kind='Provider call'),datetime(max(at),'unixepoch')"+where+" GROUP BY trace HAVING sum(kind IN ('Story inspection','Research'))>0 ORDER BY max(at) DESC LIMIT 60");
        Table("Failures and incomplete outcomes",["Stage","Outcome","Events"],
            "SELECT purpose,outcome,count(*)"+where+" AND (outcome IN ('Failed','Cancelled','Cancelled or timed out','Transport error','Rejected','No usable passages','No accepted stories','No verified story','empty','failed') OR (kind='API request' AND outcome GLOB '[45][0-9][0-9]')) GROUP BY purpose,outcome ORDER BY count(*) DESC LIMIT 30");
        html.Append("<h2>Story records and decisions</h2><p>Newest first; up to 150 records. Source URLs omit query strings for privacy, so some archive links may need the original link in the app. Prepared records show the longest available draft; the selected-place gate shows the chosen narration.</p>");
        var details=store.Rows("SELECT datetime(at,'unixepoch'),purpose,outcome,trace,journey,details"+where+" AND details<>'' ORDER BY at DESC,rowid DESC LIMIT 150",7,walk,search);
        if(details.Count==0) html.Append("<article>No detailed records for this selection yet. Create a fresh walk or generate Journey Lab stories to record the preparation steps.</article>");
        foreach(var row in details) {
            try {
                using var doc=JsonDocument.Parse(row[5]);var data=doc.RootElement;
                string Value(string key)=>data.TryGetProperty(key,out var v)&&v.ValueKind==JsonValueKind.String?v.GetString()??"":"";
                html.Append($"<article><small>{Time(row[0])} · Request {Link("request",row[3])}</small><h3>{E(row[1])}: {E(row[2])}</h3>");
                if(Value("title").Length>0) html.Append($"<h4>{E(Value("title"))}</h4>");
                if(ValidKey(Value("story"))&&Value("story").Length>0) html.Append($"<p>Story {Link("story",Value("story"))}</p>");
                html.Append($"<p>{E(Value("reason"))}</p><small>Depth: {E(Value("depth"))} · Policy: {E(Value("policy"))}</small>");
                if(Value("narration").Length>0) html.Append($"<details><summary>Read narration and inspect sources</summary><blockquote>{E(Value("narration"))}</blockquote>");
                if(data.TryGetProperty("sources",out var sources)&&sources.ValueKind==JsonValueKind.Array) {
                    html.Append("<ul>");foreach(var source in sources.EnumerateArray()) {
                        var url=source.GetString();if(url is not null && InspectionDetails.Source(url) is {} safe)
                            html.Append($"<li><a href='{E(safe)}' rel='noreferrer noopener'>{E(safe)}</a></li>");
                    }html.Append("</ul>");
                }
                if(Value("narration").Length>0) html.Append("</details>");html.Append("</article>");
            } catch(JsonException) { html.Append("<article>Legacy record could not be decoded.</article>"); }
        }
        if(walk.Length+request.Length+story.Length>0) Table("Tool and playback timeline",["Time","Activity","Provider","Purpose","Result","ms","Request"],
            "SELECT datetime(at,'unixepoch'),kind,provider,purpose,outcome,ms,trace"+where+" ORDER BY at,rowid LIMIT 300");
        html.Append("<h2>How we improve discovery</h2><p>Compare the same journey and interests before and after a change. Check whether local sources produced distinctive, relevant details, whether evidence was rejected correctly, and whether the narration actually played. Use those findings to change and test research rules. More calls alone do not indicate better stories.</p><p>Records are retained for 31 days. No raw prompts, user questions, credentials or GPS traces are collected by the story inspector. Public-place titles and generated narration can reveal the area of a walk; this page requires the administrator login.</p>");
        html.Append($"<script nonce='{nonce}'>" + """
        const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        document.getElementById('time-zone').textContent = 'Times shown in your local timezone: ' + zone + '. Hover over a time to see UTC.';
        document.querySelectorAll('time[datetime]').forEach(el => {
          const date = new Date(el.getAttribute('datetime'));
          if (!Number.isNaN(date.getTime())) el.textContent = new Intl.DateTimeFormat(undefined, {dateStyle:'medium', timeStyle:'medium'}).format(date);
        });
        </script></main></html>
        """);
        return Results.Content(html.ToString(),"text/html; charset=utf-8");
        void Table(string title,string[] headings,string sql) {
            var rows=store.Rows(sql,7,walk,search);html.Append($"<h2>{E(title)}</h2><div class=scroll><table><tr>");
            foreach(var h in headings) html.Append($"<th>{E(h)}</th>");html.Append("</tr>");
            foreach(var row in rows) {html.Append("<tr>");for(int i=0;i<row.Length;i++) {
                var key=headings[i] switch {"Walk"=>"walk","Request"=>"request",_=>""};
                if(headings[i]=="Places and stories" && ValidKey(row[0]) && row[0].Length>0) {
                    var target=headings[0]=="Walk"?"walk":"request";
                    var name=row[i]=="—"?"No place title recorded yet":row[i];
                    html.Append($"<td><a href='?{target}={E(row[0])}'>{E(name)}</a></td>");
                    continue;
                }
                html.Append("<td>"+(key.Length>0&&row[i].Length==16&&ValidKey(row[i])?Link(key,row[i]):headings[i] is "Time" or "Latest activity"?Time(row[i]):E(row[i]))+"</td>");
            }html.Append("</tr>");}html.Append("</table></div>");
            if(rows.Count==0) html.Append("<p>No recorded activity.</p>");
        }
    }
}

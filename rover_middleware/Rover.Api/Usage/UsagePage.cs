using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace Rover.Api.Usage;

public static class UsagePage
{
    public static void Map(WebApplication app) => app.MapGet("/admin/usage", Show);

    static bool Authorized(HttpContext http,string? password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < 24) return false;
        var header=http.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Basic ",StringComparison.OrdinalIgnoreCase) || header.Length>1024) return false;
        try {
            return CryptographicOperations.FixedTimeEquals(SHA256.HashData(Convert.FromBase64String(header[6..])),
                SHA256.HashData(Encoding.UTF8.GetBytes("admin:"+password)));
        } catch(FormatException) { return false; }
    }

    static IResult Show(HttpContext http, IConfiguration config, UsageStore store)
    {
        http.Response.Headers.CacheControl="no-store";
        http.Response.Headers["X-Robots-Tag"]="noindex, nofollow";
        http.Response.Headers["Content-Security-Policy"]="default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'";
        if (!Authorized(http,config["WALKABOUT_USAGE_PASSWORD"])) {
            http.Response.Headers.WWWAuthenticate="Basic realm=\"Walkabout usage\", charset=\"UTF-8\"";
            return Results.Unauthorized();
        }
        int days=http.Request.Query["days"].ToString() switch {"7"=>7,"30"=>30,_=>1};
        var journey=http.Request.Query["walk"].ToString();
        var trace=http.Request.Query["request"].ToString();
        static bool Valid(string s) => s.Length==0 || s.Length==16 && s.All(char.IsAsciiHexDigit);
        if (!Valid(journey)||!Valid(trace)) return Results.BadRequest();
        var filter = " FROM events WHERE at >= $since";
        if (journey.Length>0) filter += " AND (journey=$journey OR trace IN (SELECT trace FROM events WHERE journey=$journey AND at >= $since))";
        if (trace.Length>0) filter += " AND trace='"+trace+"'"; // Validated hex only.
        string Esc(string s) => WebUtility.HtmlEncode(s);
        string Ref(string key,string value) => $"<a href='?days={days}&amp;{key}={Esc(value)}'>{Esc(value)}</a>";
        var html = new StringBuilder("""
            <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Usage · Walkabout</title><style>
            *{box-sizing:border-box}body{margin:0;background:#f4f6f2;color:#192b26;font:16px/1.5 system-ui,sans-serif}main{max-width:1180px;margin:auto;padding:28px 20px 64px}
            header{border-bottom:2px solid #175646;padding-bottom:16px}h1{font-size:2.3rem;letter-spacing:-.04em;margin:.3em 0}h2{font-size:1.15rem;margin:28px 0 8px}
            nav a,a{color:#075348}nav{display:flex;gap:10px;flex-wrap:wrap}nav a{padding:6px 14px;border-radius:20px;border:1px solid #9baeaa;text-decoration:none}nav [aria-current]{background:#174e43;color:white}
            section{overflow:auto;background:white;border:1px solid #d6dfda;border-radius:10px}table{border-collapse:collapse;width:100%;font-size:.9rem}
            td,th{text-align:left;padding:9px 12px;border-bottom:1px solid #e9ece9}th{font-size:.8rem;background:#e8efea}p{max-width:90ch}.empty{padding:12px}small{color:#48635b}
            </style><main><header><small>Walkabout administration</small><h1>API and AI usage</h1><nav>
            """);
        foreach (var n in new[]{1,7,30}) html.Append($"<a {(days==n?"aria-current='page'":"")} href='?days={n}'>{(n==1?"Today":n+" days")}</a>");
        html.Append("</nav></header>");
        if (journey.Length+trace.Length>0) html.Append($"<p>Filtered to {(journey.Length>0?"walk "+Esc(journey):"request "+Esc(trace))}. <a href='?days={days}'>Show all activity</a></p>");
        void Table(string title,string[] headers,string sql) {
            html.Append($"<h2>{Esc(title)}</h2><section>");
            var rows=store.Rows(sql,days,journey);
            if(rows.Count==0) html.Append("<p class=empty>No recorded activity in this period.</p>");
            else {
                html.Append("<table><thead><tr>");
                foreach(var h in headers) html.Append($"<th>{Esc(h)}</th>");
                html.Append("</tr></thead><tbody>");
                foreach(var row in rows) {
                    html.Append("<tr>");
                    for(int i=0;i<row.Length;i++) {
                        var value=row[i];
                        var cell=headers[i] switch {
                            "Walk" when value.Length==16 => Ref("walk",value),
                            "Request" when value.Length==16 => Ref("request",value),
                            _ => Esc(value)
                        };
                        html.Append($"<td>{cell}</td>");
                    }
                    html.Append("</tr>");
                }
                html.Append("</tbody></table>");
            }
            html.Append("</section>");
        }
        Table("Overview",["App requests","Provider calls","OpenAI calls","Speech cache hits","Stories finished","Estimated AI USD"],
            "SELECT count(*) FILTER(WHERE kind='API request'),count(*) FILTER(WHERE kind='Provider call'),count(*) FILTER(WHERE kind='Provider call' AND provider='OpenAI'),count(*) FILTER(WHERE kind='Speech' AND outcome='Cache hit'),count(*) FILTER(WHERE kind='Story playback' AND outcome='Completed'),round(sum(usd),4)"+filter);
        Table("Calls by provider and purpose",["Provider","Purpose","App action","Calls","Failures","Average ms"],
            "SELECT provider,purpose,action,count(*),sum(outcome NOT GLOB '2[0-9][0-9]'),round(avg(ms))"+filter+" AND kind='Provider call' GROUP BY provider,purpose,action ORDER BY count(*) DESC LIMIT 100");
        Table("AI model usage",["Model","Purpose","Responses","Input tokens","Output tokens","Web searches","Estimated USD"],
            "SELECT model,purpose,count(*),sum(input),sum(output),sum(units),round(sum(usd),5)"+filter+" AND kind='Model usage' GROUP BY model,purpose ORDER BY sum(input+output) DESC");
        Table("Research, speech and listening",["Activity","Purpose","Result","Events","Items found","Speech characters"],
            "SELECT kind,purpose,outcome,count(*),sum(units) FILTER(WHERE kind='Research'),sum(units) FILTER(WHERE kind='Speech')"+filter+" AND kind IN ('Speech','Story playback','Research') GROUP BY kind,purpose,outcome ORDER BY count(*) DESC");
        Table("Provider calls over time",["Hour (UTC)","Provider calls","Failures"],
            "SELECT strftime('%Y-%m-%d %H:00',at,'unixepoch'),count(*),sum(outcome NOT GLOB '2[0-9][0-9]')"+filter+" AND kind='Provider call' GROUP BY 1 ORDER BY 1 DESC LIMIT 744");
        Table("Recent walks",["Walk","Last activity (UTC)","Stories finished","Estimated AI USD","USD per finish"],
            "SELECT journey,datetime(max(at),'unixepoch'),count(*) FILTER(WHERE kind='Story playback' AND outcome='Completed'),round(sum(usd),5),round(sum(usd)/nullif(count(*) FILTER(WHERE kind='Story playback' AND outcome='Completed'),0),5)"+filter+" AND journey<>'' GROUP BY journey ORDER BY max(at) DESC LIMIT 50");
        Table("Latest 200 events",["Time (UTC)","Activity","Provider","Purpose","App action","Result","ms","Request","Walk"],
            "SELECT datetime(at,'unixepoch'),kind,provider,purpose,action,outcome,ms,trace,journey"+filter+" ORDER BY at DESC,rowid DESC LIMIT 200");
        html.Append("""
            <h2>What is counted</h2><p>Collection starts with this release. Each outgoing HTTP attempt from the API’s managed clients counts once. Requests, model receipts and playback events are separate. Tap a request or walk ID to trace its activity. Background work and older app requests may have no walk ID. Offline playback, phone map SDK traffic and direct WebSocket calls are outside HTTP coverage.</p>
            <p>Estimates cover reported tokens at supported standard model rates and reported web searches. An em dash means pricing or usage is unavailable. Maps, speech, contract discounts and taxes are excluded. Compare estimates with your provider invoices. <a href="https://developers.openai.com/api/docs/pricing">OpenAI rates</a>.</p>
            """);
        if(store.Dropped>0) html.Append($"<p>{store.Dropped} events dropped since restart.</p>");
        return Results.Content(html.Append("</main></html>").ToString(),"text/html; charset=utf-8");
    }
}

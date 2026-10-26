using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Rover.Infrastructure.Accounts;

public sealed record SharedPoint(double Latitude, double Longitude);
public sealed record SharedMemory(string Id, string Kind, string Caption, SharedPoint? Location)
{
    public DateTimeOffset? CapturedAt { get; init; }
}
public sealed record SharedTrailPoint(DateTimeOffset At, double Latitude, double Longitude, int Segment);
public sealed record SharedStory(string Id, string Title, string Narration, string[] Sources, string? Notice, SharedPoint? Location);
public sealed record SharedWalkDraft(string Title, bool IncludeLocations, SharedPoint[] Route, SharedMemory[] Media, string[] Recipients)
{
    public string Audience { get; init; } = "selectedFriends";
    public SharedStory[] Stories { get; init; } = [];
    public bool IncludeReplay { get; init; }
    public SharedTrailPoint[] Trail { get; init; } = [];
}
public sealed record SharedWalk(string Id, string Title, string Sender, bool Owned, string Status, DateTimeOffset CreatedAt, SharedPoint[] Route, SharedMemory[] Media, string[] Recipients)
{
    public string[] UploadedMediaIds { get; init; } = [];
    public string Audience { get; init; } = "selectedFriends";
    public SharedStory[] Stories { get; init; } = [];
    public SharedTrailPoint[] Trail { get; init; } = [];
}

// Each grant is bound to the accepted friendship ID, not just the member ID.
// Removing/blocking and later befriending again cannot resurrect an old grant.
public sealed class WalkSharingStore
{
    private readonly string connectionString;
    public string MediaDirectory { get; }
    public WalkSharingStore(string databasePath)
    {
        connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath, DefaultTimeout = 15 }.ToString();
        MediaDirectory = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(databasePath))!, "shared-media");
        Directory.CreateDirectory(MediaDirectory);
        using var db = Open(); using var cmd = db.CreateCommand();
        cmd.CommandText = """
          CREATE TABLE IF NOT EXISTS shared_walks(id TEXT PRIMARY KEY, owner TEXT NOT NULL, data TEXT NOT NULL, state TEXT NOT NULL, created INTEGER NOT NULL);
          CREATE TABLE IF NOT EXISTS shared_walk_grants(share TEXT NOT NULL, member TEXT NOT NULL, edge TEXT NOT NULL, PRIMARY KEY(share,member));
          CREATE TABLE IF NOT EXISTS shared_walk_media(share TEXT NOT NULL, media TEXT NOT NULL, bytes INTEGER NOT NULL, PRIMARY KEY(share,media));
          CREATE INDEX IF NOT EXISTS shared_walk_owner ON shared_walks(owner);
          CREATE INDEX IF NOT EXISTS shared_walk_recipient ON shared_walk_grants(member);
          """;
        cmd.ExecuteNonQuery();
    }
    private SqliteConnection Open() { var db = new SqliteConnection(connectionString); db.Open(); return db; }
    private static SqliteCommand Cmd(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] args)
    { var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = sql; foreach (var (k,v) in args) cmd.Parameters.AddWithValue(k,v); return cmd; }
    private static int Run(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] args)
    { using var cmd = Cmd(db,tx,sql,args); return cmd.ExecuteNonQuery(); }
    private static object? Value(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] args)
    { using var cmd = Cmd(db,tx,sql,args); return cmd.ExecuteScalar(); }
    private T Transaction<T>(Func<SqliteConnection, SqliteTransaction,T> fn)
    { using var db=Open(); using var tx=db.BeginTransaction(deferred:false); var value=fn(db,tx); tx.Commit(); return value; }
    private static string Member(SqliteConnection db, SqliteTransaction tx, string owner) =>
        Value(db,tx,"SELECT id FROM community_members WHERE owner=$o",("$o",owner)) as string ?? throw new FriendsException(409,"Create your Friends profile first.");
    private const string ValidGrant = """
        (EXISTS(SELECT 1 FROM shared_walk_grants g JOIN friend_edges e ON e.id=g.edge
          WHERE g.share=w.id AND g.member=$me AND e.state='accepted'
          AND ((e.sender=w.owner AND e.recipient=$me) OR (e.recipient=w.owner AND e.sender=$me))
          AND NOT EXISTS(SELECT 1 FROM friend_blocks b WHERE (b.owner=w.owner AND b.target=$me) OR (b.owner=$me AND b.target=w.owner)))
        OR (json_extract(w.data,'$.Audience')='allFriends'
          AND EXISTS(SELECT 1 FROM friend_edges e WHERE e.state='accepted'
            AND ((e.sender=w.owner AND e.recipient=$me) OR (e.recipient=w.owner AND e.sender=$me)))
          AND NOT EXISTS(SELECT 1 FROM friend_blocks b WHERE (b.owner=w.owner AND b.target=$me) OR (b.owner=$me AND b.target=w.owner))))
        """;
    private static void Validate(SharedWalkDraft d)
    {
        if (d.Trail is null || d.Trail.Length > 4000 ||
            d.Trail.Any(p => p is null || p.Segment < 0 || p.Segment > 4000 ||
                !double.IsFinite(p.Latitude) || !double.IsFinite(p.Longitude) ||
                Math.Abs(p.Latitude) > 90 || Math.Abs(p.Longitude) > 180))
            throw new FriendsException(400, "Invalid GPS replay. Share up to 4000 recorded points.");
        foreach (var section in d.Trail.GroupBy(p => p.Segment))
        {
            DateTimeOffset? previous = null;
            foreach (var point in section)
            {
                if (previous.HasValue && (point.At <= previous || point.At - previous > TimeSpan.FromSeconds(60)))
                    throw new FriendsException(400, "GPS replay sections must be ordered without recording gaps.");
                previous = point.At;
            }
        }
        if (string.IsNullOrWhiteSpace(d.Title) || d.Title.Length>160 || d.Title.Any(char.IsControl) ||
            d.Route is null || d.Route.Length>4000 || d.Media is null || d.Media.Length>10 ||
            d.Audience is not ("selectedFriends" or "allFriends") ||
            d.Recipients is null || d.Recipients.Length >20 ||
            (d.Audience=="selectedFriends" && d.Recipients.Length==0) ||
            (d.Audience=="allFriends" && d.Recipients.Length!=0) || d.Recipients.Distinct().Count()!=d.Recipients.Length ||
            d.Recipients.Any(string.IsNullOrWhiteSpace) ||
            d.Media.Any(m=>m is null || !Guid.TryParseExact(m.Id,"N",out _) || m.Kind is not ("photo" or "video") || m.Caption is null || m.Caption.Length>500) ||
            d.Media.Select(m=>m.Id).Distinct().Count()!=d.Media.Length)
            throw new FriendsException(400,"Choose a title, up to 10 memories and 1-20 friends.");
        if (d.Stories is null || d.Stories.Length > 10 ||
            d.Stories.Any(s => s is null || !Guid.TryParseExact(s.Id, "N", out _) ||
                string.IsNullOrWhiteSpace(s.Title) || s.Title.Length > 200 ||
                string.IsNullOrWhiteSpace(s.Narration) || s.Narration.Length > 20000 ||
                s.Notice?.Length > 4000 || s.Sources is null || s.Sources.Length > 20 ||
                s.Sources.Any(url => url is null || url.Length > 2048 ||
                    !Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo))) ||
            d.Stories.Select(s => s.Id).Distinct().Count() != d.Stories.Length)
            throw new FriendsException(400, "Choose up to 10 stories with valid text and HTTPS sources.");
        foreach (var p in d.Route.Concat(d.Media.Where(m=>m.Location!=null).Select(m=>m.Location!))
            .Concat(d.Stories.Where(s => s.Location != null).Select(s => s.Location!)))
            if(p is null || !double.IsFinite(p.Latitude) || !double.IsFinite(p.Longitude) || Math.Abs(p.Latitude)>90 || Math.Abs(p.Longitude)>180)
                throw new FriendsException(400,"Invalid map location.");
    }
    public string Create(string owner, SharedWalkDraft draft) => Transaction((db,tx)=> {
        Validate(draft); var me=Member(db,tx,owner);
        if(Convert.ToInt32(Value(db,tx,"SELECT COUNT(*) FROM shared_walks WHERE owner=$me",("$me",me)))>=20)
            throw new FriendsException(409,"You have 20 shared walks or drafts. Remove one before sharing another.");
        var safe=draft with { Title=draft.Title.Trim(), Route=draft.IncludeLocations?draft.Route:[],
            Trail=draft.IncludeReplay && draft.IncludeLocations ? draft.Trail : [],
            Media=draft.Media.Select(m=>m with { Location=draft.IncludeLocations?m.Location:null,
                CapturedAt=draft.IncludeReplay && draft.IncludeLocations ? m.CapturedAt : null }).ToArray(),
            Stories=draft.Stories.Select(s=>s with { Location=draft.IncludeLocations?s.Location:null }).ToArray() };
        var id=Guid.NewGuid().ToString("N");
        Run(db,tx,"INSERT INTO shared_walks VALUES($id,$me,$data,'draft',$now)",("$id",id),("$me",me),("$data",JsonSerializer.Serialize(safe)),("$now",DateTimeOffset.UtcNow.ToUnixTimeSeconds()));
        foreach(var friend in draft.Recipients) {
            var edge=Value(db,tx,"""
                SELECT id FROM friend_edges WHERE state='accepted' AND ((sender=$me AND recipient=$f) OR (sender=$f AND recipient=$me))
                AND NOT EXISTS(SELECT 1 FROM friend_blocks WHERE (owner=$me AND target=$f) OR (owner=$f AND target=$me))
                """,("$me",me),("$f",friend)) as string;
            if(edge==null) throw new FriendsException(409,"One of the selected members is no longer your friend. Refresh Friends.");
            Run(db,tx,"INSERT INTO shared_walk_grants VALUES($id,$f,$e)",("$id",id),("$f",friend),("$e",edge));
        }
        return id;
    });
    private static SharedWalk Read(SqliteDataReader r,string me)
    {
        var d=JsonSerializer.Deserialize<SharedWalkDraft>(r.GetString(2))!;
        var owned=r.GetString(1)==me;
        return new(r.GetString(0),d.Title,r.GetString(5),owned,r.GetString(3),DateTimeOffset.FromUnixTimeSeconds(r.GetInt64(4)),d.Route,d.Media,owned?d.Recipients:[]) { Trail = d.Trail, Stories = d.Stories, Audience = r.GetString(3)=="private" ? "private" : d.Audience };
    }
    public IReadOnlyList<SharedWalk> List(string owner) => Transaction((db,tx)=> {
        var me=Member(db,tx,owner); var result=new List<SharedWalk>();
        using var cmd=Cmd(db,tx,$"SELECT w.id,w.owner,w.data,w.state,w.created,m.display_name FROM shared_walks w JOIN community_members m ON m.id=w.owner WHERE w.owner=$me OR (w.state='published' AND {ValidGrant}) ORDER BY w.created DESC LIMIT 200",("$me",me));
        using var r=cmd.ExecuteReader(); while(r.Read()) result.Add(Read(r,me)); return (IReadOnlyList<SharedWalk>)result;
    });
    private static SharedWalk Get(SqliteConnection db,SqliteTransaction tx,string owner,string id,bool onlyOwner=false)
    {
        var me=Member(db,tx,owner);
        using var cmd=Cmd(db,tx,$"SELECT w.id,w.owner,w.data,w.state,w.created,m.display_name FROM shared_walks w JOIN community_members m ON m.id=w.owner WHERE w.id=$id AND (w.owner=$me{(onlyOwner?"":$" OR (w.state='published' AND {ValidGrant})")})",("$me",me),("$id",id));
        using var r=cmd.ExecuteReader(); if(!r.Read()) throw new FriendsException(404,"Shared walk unavailable. Access may have been removed."); return Read(r,me);
    }
    public SharedWalk Get(string owner,string id) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id);
        var uploaded=new List<string>();
        using var cmd=Cmd(db,tx,"SELECT media FROM shared_walk_media WHERE share=$s",("$s",id));
        using var reader=cmd.ExecuteReader();
        while(reader.Read()) uploaded.Add(reader.GetString(0));
        return walk with { UploadedMediaIds=uploaded.ToArray() };
    });
    public SharedMemory UploadTarget(string owner,string id,string media) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id,true);
        if(walk.Status!="draft") throw new FriendsException(409,"This walk has already been shared.");
        if(Value(db,tx,"SELECT 1 FROM shared_walk_media WHERE share=$s AND media=$m",("$s",id),("$m",media))!=null)
            throw new FriendsException(409,"This memory is already uploaded.");
        return walk.Media.SingleOrDefault(m=>m.Id==media) ?? throw new FriendsException(404,"Memory unavailable.");
    });
    public void RegisterMedia(string owner,string id,string media,long bytes,long totalLimit) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id,true);
        if(walk.Status!="draft" || !walk.Media.Any(m=>m.Id==media)) throw new FriendsException(409,"Draft changed.");
        if(Value(db,tx,"SELECT 1 FROM shared_walk_media WHERE share=$s AND media=$m",("$s",id),("$m",media))!=null)
            throw new FriendsException(409,"This memory is already uploaded.");
        var used=Convert.ToInt64(Value(db,tx,"SELECT COALESCE(SUM(bytes),0) FROM shared_walk_media"));
        var mine=Convert.ToInt64(Value(db,tx,"SELECT COALESCE(SUM(m.bytes),0) FROM shared_walk_media m JOIN shared_walks w ON w.id=m.share WHERE w.owner=$me",("$me",Member(db,tx,owner))));
        if(bytes<=0 || bytes>64L*1024*1024 || used+bytes>totalLimit || mine+bytes>128L*1024*1024)
            throw new FriendsException(409,"Sharing storage is full. Remove older shared walks and try again.");
        return Run(db,tx,"INSERT INTO shared_walk_media VALUES($s,$m,$b)",("$s",id),("$m",media),("$b",bytes));
    });
    public void Publish(string owner,string id) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id,true);
        if(walk.Status!="draft") throw new FriendsException(409,"Only a new draft can be published. Create a new share to grant access again.");
        if(Convert.ToInt32(Value(db,tx,"SELECT COUNT(*) FROM shared_walk_media WHERE share=$s",("$s",id)))!=walk.Media.Length)
            throw new FriendsException(409,"Some memories have not finished uploading.");
        var me=Member(db,tx,owner);
        var valid=Convert.ToInt32(Value(db,tx,"""
            SELECT COUNT(*) FROM shared_walk_grants g JOIN friend_edges e ON e.id=g.edge WHERE g.share=$s AND e.state='accepted'
            AND NOT EXISTS(SELECT 1 FROM friend_blocks b WHERE (b.owner=$me AND b.target=g.member) OR (b.owner=g.member AND b.target=$me))
            """,("$s",id),("$me",me)));
        if(valid!=walk.Recipients.Length) throw new FriendsException(409,"Your friends changed. Delete this draft and select recipients again.");
        return Run(db,tx,"UPDATE shared_walks SET state='published' WHERE id=$s",("$s",id));
    });
    public void MakePrivate(string owner,string id) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id,true);
        if(walk.Status=="draft") throw new FriendsException(409,"This draft is already private.");
        Run(db,tx,"DELETE FROM shared_walk_grants WHERE share=$s",("$s",id));
        return Run(db,tx,"UPDATE shared_walks SET state='private' WHERE id=$s",("$s",id));
    });
    public string MediaPath(string id,SharedMemory m) => Path.Combine(MediaDirectory,$"{id}-{m.Id}.{(m.Kind=="video"?"mp4":"jpg")}");
    public (string Path,string Kind) ReadMedia(string owner,string id,string media) => Transaction((db,tx)=> {
        var walk=Get(db,tx,owner,id); var m=walk.Media.SingleOrDefault(m=>m.Id==media);
        if(m==null || Value(db,tx,"SELECT 1 FROM shared_walk_media WHERE share=$s AND media=$m",("$s",id),("$m",media))==null)
            throw new FriendsException(404,"Memory unavailable.");
        return (MediaPath(id,m),m.Kind);
    });
    public void Delete(string owner,string id)
    {
        var media=Transaction((db,tx)=> {
            var walk=Get(db,tx,owner,id,true);
            Run(db,tx,"DELETE FROM shared_walk_grants WHERE share=$s",("$s",id));
            Run(db,tx,"DELETE FROM shared_walk_media WHERE share=$s",("$s",id));
            Run(db,tx,"DELETE FROM shared_walks WHERE id=$s",("$s",id)); return walk.Media;
        });
        foreach(var m in media) { try { File.Delete(MediaPath(id,m)); } catch(IOException) { /* A reader may still hold a file; cleanup retries. */ } }
    }
    public void Cleanup()
    {
        var expired=Transaction((db,tx)=> {
            var result=new List<(string Owner,string Id)>();
            using var cmd=Cmd(db,tx,"SELECT m.owner,w.id FROM shared_walks w JOIN community_members m ON m.id=w.owner WHERE w.state='draft' AND w.created<$t",("$t",DateTimeOffset.UtcNow.AddDays(-1).ToUnixTimeSeconds()));
            using var r=cmd.ExecuteReader(); while(r.Read()) result.Add((r.GetString(0),r.GetString(1))); return result;
        });
        foreach(var (owner,id) in expired) Delete(owner,id);
        var kept=Transaction((db,tx)=> {
            var names=new HashSet<string>(); using var cmd=Cmd(db,tx,"SELECT share,media FROM shared_walk_media"); using var r=cmd.ExecuteReader();
            while(r.Read()) names.Add($"{r.GetString(0)}-{r.GetString(1)}"); return names;
        });
        foreach(var file in Directory.EnumerateFiles(MediaDirectory))
            if(!kept.Contains(Path.GetFileNameWithoutExtension(file)) && File.GetLastWriteTimeUtc(file)<DateTime.UtcNow.AddHours(-1))
                try { File.Delete(file); } catch(IOException) { }
    }
}

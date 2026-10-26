using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;

namespace Rover.Infrastructure.Accounts;

public sealed record MemberProfile(string Id, string Username, string DisplayName);
public sealed record MemberConnection(MemberProfile Member, string Status, string? RequestId);
public sealed record FriendsState(MemberProfile? Profile, IReadOnlyList<MemberConnection> Connections, IReadOnlyList<MemberProfile> Blocked);
public sealed record FriendInvite(string Code, DateTimeOffset ExpiresAtUtc);
public sealed class FriendsException(int status, string message) : Exception(message) { public int Status { get; } = status; }

// Cognito ownership never leaves this store. Public IDs are unrelated random UUIDs.
public sealed class FriendsStore
{
    private readonly string connectionString;
    private readonly TimeProvider clock;
    public FriendsStore(string path, TimeProvider? clock = null)
    {
        this.clock = clock ?? TimeProvider.System;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        connectionString = new SqliteConnectionStringBuilder { DataSource = path, DefaultTimeout = 15 }.ToString();
        using var db = Open();
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS community_members (
              id TEXT PRIMARY KEY, owner TEXT NOT NULL UNIQUE, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS friend_edges (
              a TEXT NOT NULL, b TEXT NOT NULL, id TEXT NOT NULL UNIQUE,
              sender TEXT NOT NULL, recipient TEXT NOT NULL, state TEXT NOT NULL,
              created INTEGER NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(a,b));
            CREATE TABLE IF NOT EXISTS friend_blocks (owner TEXT NOT NULL, target TEXT NOT NULL, PRIMARY KEY(owner,target));
            CREATE TABLE IF NOT EXISTS friend_invites (owner TEXT PRIMARY KEY, hash TEXT NOT NULL UNIQUE, expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS friend_budgets (owner TEXT NOT NULL, bucket TEXT NOT NULL, count INTEGER NOT NULL, expires INTEGER NOT NULL, PRIMARY KEY(owner,bucket));
            CREATE TABLE IF NOT EXISTS member_reports (id TEXT PRIMARY KEY, reporter TEXT NOT NULL, target TEXT NOT NULL,
              reason TEXT NOT NULL, details TEXT NOT NULL, created INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending');
            CREATE INDEX IF NOT EXISTS friend_edges_recipient ON friend_edges(recipient,state);
            CREATE INDEX IF NOT EXISTS friend_edges_sender ON friend_edges(sender,state);
            """;
        cmd.ExecuteNonQuery();
    }
    private SqliteConnection Open() { var db = new SqliteConnection(connectionString); db.Open(); return db; }
    private long Now => clock.GetUtcNow().ToUnixTimeSeconds();
    private static SqliteCommand Command(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] values)
    {
        var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = sql;
        foreach (var (name, value) in values) cmd.Parameters.AddWithValue(name, value);
        return cmd;
    }
    private static int Run(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] values)
    { using var cmd = Command(db, tx, sql, values); return cmd.ExecuteNonQuery(); }
    private static object? Scalar(SqliteConnection db, SqliteTransaction tx, string sql, params (string, object)[] values)
    { using var cmd = Command(db, tx, sql, values); return cmd.ExecuteScalar(); }
    private T Write<T>(Func<SqliteConnection, SqliteTransaction, T> action)
    {
        using var db = Open(); using var tx = db.BeginTransaction(deferred: false);
        var result = action(db, tx); tx.Commit(); return result;
    }
    private static MemberProfile ReadProfile(SqliteDataReader reader) => new(reader.GetString(0), reader.GetString(1), reader.GetString(2));
    private static MemberProfile? Find(SqliteConnection db, SqliteTransaction tx, string field, string value)
    {
        using var cmd = Command(db, tx, $"SELECT id,username,display_name FROM community_members WHERE {field}=$value", ("$value", value));
        using var reader = cmd.ExecuteReader(); return reader.Read() ? ReadProfile(reader) : null;
    }
    private static MemberProfile Me(SqliteConnection db, SqliteTransaction tx, string owner) =>
        Find(db, tx, "owner", owner) ?? throw new FriendsException(409, "Choose your member username first.");
    private static bool Blocked(SqliteConnection db, SqliteTransaction tx, string a, string b) =>
        Scalar(db, tx, "SELECT 1 FROM friend_blocks WHERE (owner=$a AND target=$b) OR (owner=$b AND target=$a)", ("$a", a), ("$b", b)) != null;
    private static MemberProfile Target(SqliteConnection db, SqliteTransaction tx, string me, string id)
    {
        if (id == me) throw new FriendsException(400, "Choose another member.");
        var target = Find(db, tx, "id", id);
        if (target == null || Blocked(db, tx, me, id)) throw new FriendsException(404, "Member unavailable.");
        return target;
    }
    private static (string, string) Pair(string a, string b) => string.CompareOrdinal(a, b) < 0 ? (a, b) : (b, a);
    public void Budget(string owner, string action, int limit, int seconds = 86400) => Write((db, tx) =>
    {
        var bucket = $"{action}:{Now / seconds}";
        Run(db, tx, "DELETE FROM friend_budgets WHERE expires < $now", ("$now", Now));
        var count = Convert.ToInt32(Scalar(db, tx, "SELECT count FROM friend_budgets WHERE owner=$owner AND bucket=$bucket", ("$owner", owner), ("$bucket", bucket)) ?? 0);
        if (count >= limit) throw new FriendsException(429, "Too many attempts. Please try again later.");
        return Run(db, tx, "INSERT INTO friend_budgets VALUES($owner,$bucket,1,$expires) ON CONFLICT(owner,bucket) DO UPDATE SET count=count+1",
            ("$owner", owner), ("$bucket", bucket), ("$expires", (Now / seconds + 1) * seconds));
    });
    public MemberProfile SaveProfile(string owner, string? username, string? displayName) => Write((db, tx) =>
    {
        username = (username ?? "").Trim().TrimStart('@').ToLowerInvariant();
        displayName = (displayName ?? "").Trim();
        if (!Regex.IsMatch(username, "^[a-z][a-z0-9_]{2,23}$") ||
            new[] { "admin", "administrator", "support", "walkabout", "moderator", "official" }.Contains(username))
            throw new FriendsException(400, "Use 3-24 letters, numbers or underscores, starting with a letter. This username may be reserved.");
        if (displayName.Length is < 1 or > 60 || displayName.Any(char.IsControl))
            throw new FriendsException(400, "Enter a display name of 1-60 characters.");
        var existing = Find(db, tx, "owner", owner);
        if (existing != null && existing.Username != username) throw new FriendsException(409, "Your username cannot be changed yet.");
        var claimed = Find(db, tx, "username", username);
        if (claimed != null && claimed.Id != existing?.Id) throw new FriendsException(409, "That username is already taken.");
        var member = new MemberProfile(existing?.Id ?? Guid.NewGuid().ToString("N"), username, displayName);
        Run(db, tx, "INSERT INTO community_members VALUES($id,$owner,$username,$name) ON CONFLICT(owner) DO UPDATE SET display_name=$name",
            ("$id", member.Id), ("$owner", owner), ("$username", username), ("$name", displayName));
        return member;
    });
    private static MemberConnection Connection(SqliteConnection db, SqliteTransaction tx, string me, MemberProfile target)
    {
        var (a, b) = Pair(me, target.Id);
        using var cmd = Command(db, tx, "SELECT id,sender,state FROM friend_edges WHERE a=$a AND b=$b", ("$a", a), ("$b", b));
        using var r = cmd.ExecuteReader();
        if (!r.Read() || r.GetString(2) == "closed") return new(target, "none", null);
        return new(target, r.GetString(2) == "accepted" ? "friend" : r.GetString(1) == me ? "outgoing" : "incoming", r.GetString(0));
    }
    public MemberConnection? Lookup(string owner, string username) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner);
        var target = Find(db, tx, "username", username.Trim().TrimStart('@').ToLowerInvariant());
        return target == null || target.Id == me.Id || Blocked(db, tx, me.Id, target.Id) ? null : Connection(db, tx, me.Id, target);
    });
    public FriendsState State(string owner) => Write((db, tx) =>
    {
        var me = Find(db, tx, "owner", owner);
        if (me == null) return new FriendsState(null, [], []);
        var members = new List<MemberProfile>();
        using (var cmd = Command(db, tx, "SELECT m.id,m.username,m.display_name FROM community_members m JOIN friend_edges e ON (e.sender=m.id OR e.recipient=m.id) WHERE (e.sender=$me OR e.recipient=$me) AND m.id<>$me AND e.state<>'closed' ORDER BY m.username", ("$me", me.Id)))
        using (var r = cmd.ExecuteReader()) { while (r.Read()) members.Add(ReadProfile(r)); }
        var connections = members.Where(m => !Blocked(db, tx, me.Id, m.Id)).Select(m => Connection(db, tx, me.Id, m)).ToList();
        var blocks = new List<MemberProfile>();
        using (var cmd = Command(db, tx, "SELECT m.id,m.username,m.display_name FROM community_members m JOIN friend_blocks b ON b.target=m.id WHERE b.owner=$me ORDER BY m.username", ("$me", me.Id)))
        using (var r = cmd.ExecuteReader()) { while (r.Read()) blocks.Add(ReadProfile(r)); }
        return new FriendsState(me, connections, blocks);
    });
    public void Request(string owner, string targetId) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner); var target = Target(db, tx, me.Id, targetId);
        var connection = Connection(db, tx, me.Id, target);
        if (connection.Status is "friend" or "outgoing") return 0;
        if (connection.Status == "incoming") throw new FriendsException(409, "This member already sent you a request. Accept it from Requests.");
        var (a, b) = Pair(me.Id, target.Id);
        var updated = Scalar(db, tx, "SELECT updated FROM friend_edges WHERE a=$a AND b=$b", ("$a", a), ("$b", b));
        if (updated != null && Now - Convert.ToInt64(updated) < 86400) throw new FriendsException(409, "Please wait 24 hours before requesting this member again.");
        foreach (var id in new[] { me.Id, target.Id })
        {
            var count = Convert.ToInt32(Scalar(db, tx, "SELECT COUNT(*) FROM friend_edges WHERE (sender=$id OR recipient=$id) AND state<>'closed'", ("$id", id)));
            if (count >= 200) throw new FriendsException(409, "The connection limit has been reached.");
        }
        return Run(db, tx, "INSERT INTO friend_edges VALUES($a,$b,$id,$sender,$recipient,'pending',$now,$now) ON CONFLICT(a,b) DO UPDATE SET id=$id,sender=$sender,recipient=$recipient,state='pending',created=$now,updated=$now",
            ("$a", a), ("$b", b), ("$id", Guid.NewGuid().ToString("N")), ("$sender", me.Id), ("$recipient", target.Id), ("$now", Now));
    });
    public void Act(string owner, string requestId, string action) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner); string sender, recipient, state;
        using (var cmd = Command(db, tx, "SELECT sender,recipient,state FROM friend_edges WHERE id=$id", ("$id", requestId)))
        using (var r = cmd.ExecuteReader())
        { if (!r.Read()) throw new FriendsException(404, "Request unavailable."); sender = r.GetString(0); recipient = r.GetString(1); state = r.GetString(2); }
        if ((me.Id != sender && me.Id != recipient) || Blocked(db, tx, sender, recipient)) throw new FriendsException(404, "Request unavailable.");
        var allowed = action switch {
            "accept" or "decline" => state == "pending" && me.Id == recipient,
            "cancel" => state == "pending" && me.Id == sender,
            "remove" => state == "accepted", _ => false };
        if (!allowed) throw new FriendsException(409, "This request changed. Refresh and try again.");
        return Run(db, tx, "UPDATE friend_edges SET state=$state,updated=$now WHERE id=$id",
            ("$state", action == "accept" ? "accepted" : "closed"), ("$now", Now), ("$id", requestId));
    });
    public void Block(string owner, string targetId, bool block) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner);
        if (targetId == me.Id || Find(db, tx, "id", targetId) == null) throw new FriendsException(404, "Member unavailable.");
        if (!block) return Run(db, tx, "DELETE FROM friend_blocks WHERE owner=$me AND target=$target", ("$me", me.Id), ("$target", targetId));
        Run(db, tx, "INSERT OR IGNORE INTO friend_blocks VALUES($me,$target)", ("$me", me.Id), ("$target", targetId));
        var (a,b) = Pair(me.Id, targetId);
        return Run(db, tx, "UPDATE friend_edges SET state='closed',updated=$now WHERE a=$a AND b=$b", ("$a", a), ("$b", b), ("$now", Now));
    });
    public bool AreFriends(string owner, string targetId) => Write((db, tx) =>
    {
        var me = Find(db, tx, "owner", owner); var target = Find(db, tx, "id", targetId);
        return me != null && target != null && !Blocked(db, tx, me.Id, targetId) && Connection(db, tx, me.Id, target).Status == "friend";
    });
    private static string Hash(string code) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(code)));
    public FriendInvite Invite(string owner) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner);
        var code = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        var expires = clock.GetUtcNow().AddDays(7);
        Run(db, tx, "INSERT INTO friend_invites VALUES($owner,$hash,$expires) ON CONFLICT(owner) DO UPDATE SET hash=$hash,expires=$expires",
            ("$owner", me.Id), ("$hash", Hash(code)), ("$expires", expires.ToUnixTimeSeconds()));
        return new FriendInvite(code, expires);
    });
    public void RevokeInvite(string owner) => Write((db, tx) => Run(db, tx, "DELETE FROM friend_invites WHERE owner=$owner", ("$owner", Me(db, tx, owner).Id)));
    public MemberConnection ResolveInvite(string owner, string code) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner);
        var id = Scalar(db, tx, "SELECT owner FROM friend_invites WHERE hash=$hash AND expires>$now", ("$hash", Hash(code)), ("$now", Now)) as string;
        if (id == null) throw new FriendsException(404, "This invitation has expired or been revoked.");
        return Connection(db, tx, me.Id, Target(db, tx, me.Id, id));
    });
    public void Report(string owner, string targetId, string? reason, string? details) => Write((db, tx) =>
    {
        var me = Me(db, tx, owner);
        if (me.Id == targetId || Find(db, tx, "id", targetId) == null) throw new FriendsException(404, "Member unavailable.");
        if (!new[] { "harassment", "hate", "impersonation", "spam", "other" }.Contains(reason) || details?.Length > 500)
            throw new FriendsException(400, "Choose a report reason and use at most 500 characters.");
        return Run(db, tx, "INSERT INTO member_reports(id,reporter,target,reason,details,created) VALUES($id,$me,$target,$reason,$details,$now)",
            ("$id", Guid.NewGuid().ToString("N")), ("$me", me.Id), ("$target", targetId), ("$reason", reason!), ("$details", details?.Trim() ?? ""), ("$now", Now));
    });
}

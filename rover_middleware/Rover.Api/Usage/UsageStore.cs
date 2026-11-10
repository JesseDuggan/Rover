using Microsoft.Data.Sqlite;
using System.Threading.Channels;

namespace Rover.Api.Usage;

public sealed record UsageEvent(string Kind, string Provider, string Purpose, string Outcome,
    string Action, string Trace, string Journey, long Ms = 0, long Input = 0, long Output = 0,
    double? Usd = null, string Model = "", long Units = 0)
{
    public long At { get; } = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
}

public sealed class UsageStore(IConfiguration config, ILogger<UsageStore> logger) : BackgroundService
{
    readonly Channel<UsageEvent> pending = Channel.CreateBounded<UsageEvent>(8192);
    readonly string directory = config["Usage:Directory"] ?? Path.Combine(
        Environment.GetEnvironmentVariable("RAILWAY_VOLUME_MOUNT_PATH") ?? "work", "usage");
    volatile bool initialized;
    long dropped;
    public long Dropped => Interlocked.Read(ref dropped);
    public void Record(UsageEvent evt) { if (!pending.Writer.TryWrite(evt)) Interlocked.Increment(ref dropped); }

    SqliteConnection Open()
    {
        Directory.CreateDirectory(directory);
        var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = Path.Combine(directory,"usage.db"), DefaultTimeout=5 }.ToString());
        db.Open();
        return db;
    }
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested) {
            try {
                using var db = Open();
                using var setup = db.CreateCommand();
                setup.CommandText = """
                    PRAGMA journal_mode=WAL;
                    CREATE TABLE IF NOT EXISTS events(at INTEGER, kind TEXT, provider TEXT, purpose TEXT, outcome TEXT, action TEXT, trace TEXT, journey TEXT, ms INTEGER, input INTEGER, output INTEGER, usd REAL, model TEXT, units INTEGER);
                    CREATE INDEX IF NOT EXISTS events_time ON events(at);
                    CREATE INDEX IF NOT EXISTS events_trace ON events(trace);
                    CREATE INDEX IF NOT EXISTS events_journey ON events(journey,at);
                    """;
                setup.ExecuteNonQuery();
                initialized = true;
                var nextPrune = DateTimeOffset.MinValue;
                while (await pending.Reader.WaitToReadAsync(token)) {
                    using var tx = db.BeginTransaction();
                    if (DateTimeOffset.UtcNow >= nextPrune) {
                        using var prune = db.CreateCommand();
                        prune.Transaction = tx;
                        prune.CommandText = "DELETE FROM events WHERE at < unixepoch('now','-31 days')";
                        prune.ExecuteNonQuery();
                        nextPrune = DateTimeOffset.UtcNow.AddHours(12);
                    }
                    using var insert = db.CreateCommand();
                    insert.Transaction = tx;
                    insert.CommandText = "INSERT INTO events VALUES($at,$kind,$provider,$purpose,$outcome,$action,$trace,$journey,$ms,$input,$output,$usd,$model,$units)";
                    for (var i=0;i<256 && pending.Reader.TryRead(out var e);i++) {
                        insert.Parameters.Clear();
                        object?[] values = [e.At,e.Kind,e.Provider,e.Purpose,e.Outcome,e.Action,e.Trace,e.Journey,e.Ms,e.Input,e.Output,e.Usd,e.Model,e.Units];
                        string[] keys = ["at","kind","provider","purpose","outcome","action","trace","journey","ms","input","output","usd","model","units"];
                        for(int k=0;k<keys.Length;k++) insert.Parameters.AddWithValue("$"+keys[k], values[k] ?? DBNull.Value);
                        insert.ExecuteNonQuery();
                        if(e.Kind=="API request" && e.Journey.Length>0) {
                            using var link=db.CreateCommand();
                            link.Transaction=tx;
                            link.CommandText="UPDATE events SET journey=$j WHERE trace=$t AND journey=''";
                            link.Parameters.AddWithValue("$j",e.Journey);
                            link.Parameters.AddWithValue("$t",e.Trace);
                            link.ExecuteNonQuery();
                        }
                    }
                    tx.Commit();
                }
                return;
            } catch (OperationCanceledException) when(token.IsCancellationRequested) { return; }
              catch (Exception ex) { logger.LogError(ex,"Usage storage unavailable"); await Task.Delay(5000, token); }
        }
    }

    public List<string[]> Rows(string sql, int days, string journey)
    {
        if (!initialized) return [];
        using var db = Open();
        using var query = db.CreateCommand();
        query.CommandText = sql;
        query.Parameters.AddWithValue("$since",new DateTimeOffset(DateTime.UtcNow.Date.AddDays(1-days)).ToUnixTimeSeconds());
        query.Parameters.AddWithValue("$journey",journey);
        using var reader = query.ExecuteReader();
        var data = new List<string[]>();
        while(reader.Read()) data.Add(Enumerable.Range(0,reader.FieldCount)
            .Select(i => reader.IsDBNull(i) ? "—" : Convert.ToString(reader.GetValue(i),System.Globalization.CultureInfo.InvariantCulture)!).ToArray());
        return data;
    }
}

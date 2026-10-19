using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Rover.Infrastructure.Accounts;

public sealed record LibraryItem(Guid Id, string Kind, string Name, JsonElement Data, int Revision, DateTimeOffset UpdatedAtUtc, bool IsDefault);
public sealed class LibraryConflictException(string message) : Exception(message);

// Each write takes a SQLite transaction before counting, so concurrent devices cannot exceed a cap.
public sealed class PersonalLibraryStore
{
    private readonly string connectionString;
    private readonly int profileLimit;
    private readonly int walkLimit;
    private readonly object writeGate = new();

    public PersonalLibraryStore(string path, int profileLimit = 3, int walkLimit = 3)
    {
        if (profileLimit < 1 || walkLimit < 1) throw new ArgumentOutOfRangeException(nameof(profileLimit));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        connectionString = new SqliteConnectionStringBuilder { DataSource = path, DefaultTimeout = 15 }.ToString();
        this.profileLimit = profileLimit;
        this.walkLimit = walkLimit;
        using var db = Open();
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS personal_library (
                owner TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
                name TEXT NOT NULL, data TEXT NOT NULL, revision INTEGER NOT NULL,
                updated TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(owner, id));
            CREATE UNIQUE INDEX IF NOT EXISTS one_default_profile
                ON personal_library(owner) WHERE kind='profiles' AND is_default=1;
            """;
        cmd.ExecuteNonQuery();
    }

    private SqliteConnection Open()
    {
        var db = new SqliteConnection(connectionString);
        db.Open();
        return db;
    }

    public IReadOnlyList<LibraryItem> List(string owner, string kind)
    {
        using var db = Open();
        using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT id,kind,name,data,revision,updated,is_default FROM personal_library WHERE owner=$owner AND kind=$kind ORDER BY updated DESC";
        cmd.Parameters.AddWithValue("$owner", owner);
        cmd.Parameters.AddWithValue("$kind", kind);
        using var reader = cmd.ExecuteReader();
        var result = new List<LibraryItem>();
        while (reader.Read()) result.Add(new(Guid.Parse(reader.GetString(0)), reader.GetString(1), reader.GetString(2),
            JsonSerializer.Deserialize<JsonElement>(reader.GetString(3)), reader.GetInt32(4), DateTimeOffset.Parse(reader.GetString(5)), reader.GetBoolean(6)));
        return result;
    }

    public LibraryItem Save(string owner, Guid id, string kind, string name, JsonElement data, int expectedRevision, bool isDefault)
    {
        lock (writeGate) return SaveCore(owner, id, kind, name, data, expectedRevision, isDefault);
    }

    private LibraryItem SaveCore(string owner, Guid id, string kind, string name, JsonElement data, int expectedRevision, bool isDefault)
    {
        if (kind is not ("profiles" or "walks") || id == Guid.Empty || expectedRevision < 0 ||
            string.IsNullOrWhiteSpace(name) || name.Trim().Length > 80 || data.ValueKind != JsonValueKind.Object)
            throw new ArgumentException("A name (1-80 characters) and valid item are required.");
        using var db = Open();
        using var tx = db.BeginTransaction(deferred: false);
        using var cmd = db.CreateCommand();
        cmd.Transaction = tx;
        cmd.Parameters.AddWithValue("$owner", owner);
        cmd.Parameters.AddWithValue("$id", id.ToString());
        cmd.Parameters.AddWithValue("$kind", kind);
        cmd.CommandText = "SELECT kind FROM personal_library WHERE owner=$owner AND id=$id";
        if (cmd.ExecuteScalar() is string existingKind && existingKind != kind)
            throw new LibraryConflictException("This ID belongs to another item type.");
        cmd.CommandText = "SELECT revision FROM personal_library WHERE owner=$owner AND id=$id AND kind=$kind";
        var previous = cmd.ExecuteScalar();
        if ((previous is null ? 0 : Convert.ToInt32(previous)) != expectedRevision)
            throw new LibraryConflictException("This item changed on another device. Refresh and try again.");
        if (previous is null)
        {
            cmd.CommandText = "SELECT COUNT(*) FROM personal_library WHERE owner=$owner AND kind=$kind";
            if (Convert.ToInt32(cmd.ExecuteScalar()) >= (kind == "profiles" ? profileLimit : walkLimit))
                throw new LibraryConflictException($"Your {kind} limit is reached. Delete an item before adding another.");
        }
        if (kind == "profiles" && isDefault)
        {
            cmd.CommandText = "UPDATE personal_library SET is_default=0, revision=revision+1 WHERE owner=$owner AND kind='profiles' AND is_default=1 AND id<>$id";
            cmd.ExecuteNonQuery();
        }
        var updated = DateTimeOffset.UtcNow;
        cmd.CommandText = """
            INSERT INTO personal_library(owner,id,kind,name,data,revision,updated,is_default)
            VALUES($owner,$id,$kind,$name,$data,$revision,$updated,$default)
            ON CONFLICT(owner,id) DO UPDATE SET name=$name,data=$data,revision=$revision,updated=$updated,is_default=$default;
            """;
        cmd.Parameters.AddWithValue("$name", name.Trim());
        cmd.Parameters.AddWithValue("$data", data.GetRawText());
        cmd.Parameters.AddWithValue("$revision", expectedRevision + 1);
        cmd.Parameters.AddWithValue("$updated", updated.ToString("O"));
        cmd.Parameters.AddWithValue("$default", kind == "profiles" && isDefault);
        cmd.ExecuteNonQuery();
        tx.Commit();
        return new(id, kind, name.Trim(), data.Clone(), expectedRevision + 1, updated, kind == "profiles" && isDefault);
    }

    public bool Delete(string owner, string kind, Guid id, int revision)
    {
        using var db = Open();
        using var cmd = db.CreateCommand();
        cmd.CommandText = "DELETE FROM personal_library WHERE owner=$owner AND kind=$kind AND id=$id AND revision=$revision";
        cmd.Parameters.AddWithValue("$owner", owner);
        cmd.Parameters.AddWithValue("$kind", kind);
        cmd.Parameters.AddWithValue("$id", id.ToString());
        cmd.Parameters.AddWithValue("$revision", revision);
        return cmd.ExecuteNonQuery() == 1;
    }
}

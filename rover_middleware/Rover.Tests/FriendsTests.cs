using System.Text.Json;
using Rover.Infrastructure.Accounts;

internal static class FriendsTests
{
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now = new(2026, 10, 23, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private static string PathForTest() => Path.Combine(Path.GetTempPath(), "walkabout-friends-tests", Guid.NewGuid().ToString("N"), "library.db");
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Reject(int status, Action action)
    {
        try { action(); } catch (FriendsException e) when (e.Status == status) { return; }
        throw new Exception($"Expected friends status {status}");
    }
    public static async Task Profiles()
    {
        var path = PathForTest(); var store = new FriendsStore(path);
        Check(store.State("new-owner").Profile == null, "Membership must be opt-in");
        Reject(409, () => store.Lookup("new-owner", "alice"));
        foreach (var name in new[] { "a", "admin", "a b", "1alice", new string('a', 25) })
            Reject(400, () => store.SaveProfile("new-owner", name, "Name"));
        Reject(400, () => store.SaveProfile("alice-private-sub", "alice", "bad\nname"));
        var alice = store.SaveProfile("alice-private-sub", " @ALICE ", "Alice");
        Check(alice.Username == "alice", "Username normalization");
        Reject(409, () => store.SaveProfile("bob", "Alice", "Bob"));
        Reject(409, () => store.SaveProfile("alice-private-sub", "alicia", "Alice"));
        Check(store.SaveProfile("alice-private-sub", "alice", "Alice Updated").Id == alice.Id, "Profile ID changed");
        Check(new FriendsStore(path).State("alice-private-sub").Profile!.DisplayName == "Alice Updated", "Restart lost profile");
        Check(!JsonSerializer.Serialize(store.State("alice-private-sub")).Contains("alice-private-sub"), "Private identity exposed");
        var claimed = 0;
        await Task.WhenAll(Enumerable.Range(0, 8).Select(i => Task.Run(() => {
            try { store.SaveProfile($"race-{i}", "same_name", "Name"); Interlocked.Increment(ref claimed); }
            catch (FriendsException e) when (e.Status == 409) { }
        })));
        Check(claimed == 1, "Concurrent username collision");
        Check(store.Lookup("alice-private-sub", "same") == null, "Lookup was not exact");
    }
    public static Task RequestsAndOwnership()
    {
        var clock = new Clock(); var path = PathForTest(); var store = new FriendsStore(path, clock);
        var a = store.SaveProfile("a", "alice", "Alice"); var b = store.SaveProfile("b", "bob", "Bob");
        store.SaveProfile("c", "carol", "Carol");
        Reject(400, () => store.Request("a", a.Id));
        store.Request("a", b.Id); var id = store.State("a").Connections.Single().RequestId!;
        store.Request("a", b.Id);
        Check(store.State("a").Connections.Single().RequestId == id, "Retry created a different request");
        Check(store.State("b").Connections.Single().Status == "incoming", "Request direction");
        Reject(409, () => store.Request("b", a.Id));
        Reject(409, () => store.Act("a", id, "accept"));
        Reject(409, () => store.Act("b", id, "cancel"));
        Reject(404, () => store.Act("c", id, "accept"));
        Check(!store.AreFriends("a", b.Id), "Pending request granted friendship");
        store.Act("b", id, "accept");
        Check(new FriendsStore(path, clock).AreFriends("a", b.Id) && store.AreFriends("b", a.Id), "Mutual friendship not persisted");
        Reject(404, () => store.Act("c", id, "remove"));
        store.Act("a", id, "remove");
        Check(!store.AreFriends("b", a.Id), "Removal did not revoke friendship");
        Reject(409, () => store.Request("a", b.Id));
        clock.Now = clock.Now.AddDays(1);
        store.Request("a", b.Id); var next = store.State("a").Connections.Single().RequestId!;
        Check(next != id, "Old request ID reused");
        Reject(404, () => store.Act("b", id, "accept"));
        store.Act("b", next, "decline");
        Check(store.State("a").Connections.Count == 0, "Declined request remained");
        clock.Now = clock.Now.AddDays(1);
        store.Request("a", b.Id); store.Act("a", store.State("a").Connections.Single().RequestId!, "cancel");
        Check(store.State("b").Connections.Count == 0, "Cancelled request remained");
        return Task.CompletedTask;
    }
    public static Task BlocksAndInvites()
    {
        var clock = new Clock(); var store = new FriendsStore(PathForTest(), clock);
        var a = store.SaveProfile("a", "alice", "Alice"); var b = store.SaveProfile("b", "bob", "Bob");
        var first = store.Invite("a");
        Check(first.Code.Length == 48 && store.ResolveInvite("b", first.Code).Member.Id == a.Id, "Invite resolution");
        Check(store.State("a").Connections.Count == 0 && !store.AreFriends("a", b.Id), "Invite auto-created relationship");
        var second = store.Invite("a"); Reject(404, () => store.ResolveInvite("b", first.Code));
        store.RevokeInvite("a"); Reject(404, () => store.ResolveInvite("b", second.Code));
        var expired = store.Invite("a"); clock.Now = clock.Now.AddDays(7);
        Reject(404, () => store.ResolveInvite("b", expired.Code));
        var active = store.Invite("a");
        store.Request("a", b.Id); var id = store.State("b").Connections.Single().RequestId!;
        store.Act("b", id, "accept"); store.Block("b", a.Id, true);
        Check(!store.AreFriends("a", b.Id) && !store.AreFriends("b", a.Id), "Block left authorization active");
        Check(store.Lookup("a", "bob") == null && store.Lookup("b", "alice") == null, "Block leaked lookup");
        Check(store.State("b").Blocked.Single().Id == a.Id && store.State("a").Blocked.Count == 0, "Block list ownership");
        Reject(404, () => store.Request("a", b.Id)); Reject(404, () => store.Act("a", id, "accept"));
        Reject(404, () => store.ResolveInvite("b", active.Code));
        store.Report("b", a.Id, "harassment", "Blocked member report");
        store.Block("b", a.Id, false);
        Check(!store.AreFriends("a", b.Id) && store.State("b").Connections.Count == 0, "Unblocking restored access");
        Check(store.ResolveInvite("b", active.Code).Status == "none", "Unblocking resurrected relationship");
        return Task.CompletedTask;
    }
    public static async Task BudgetsAndReports()
    {
        var clock = new Clock(); var path = PathForTest(); var store = new FriendsStore(path, clock);
        var accepted = 0;
        await Task.WhenAll(Enumerable.Range(0, 12).Select(_ => Task.Run(() => {
            try { store.Budget("a", "test", 3); Interlocked.Increment(ref accepted); }
            catch (FriendsException e) when (e.Status == 429) { }
        })));
        Check(accepted == 3, "Concurrent budget bypass");
        Reject(429, () => new FriendsStore(path, clock).Budget("a", "test", 3));
        store.Budget("b", "test", 3); clock.Now = clock.Now.AddDays(1); store.Budget("a", "test", 3);
        var a = store.SaveProfile("a", "alice", "Alice"); var b = store.SaveProfile("b", "bob", "Bob");
        Reject(400, () => store.Report("a", b.Id, "invalid", ""));
        Reject(400, () => store.Report("a", b.Id, "spam", new string('x', 501)));
        Reject(404, () => store.Report("a", a.Id, "spam", ""));
        store.Report("a", b.Id, "spam", "Example report");
    }
}

using System.Diagnostics;
using System.Text.Json;
using Rover.Infrastructure.Accounts;

internal static class WalkSharingTests
{
    private sealed class Clock:TimeProvider { public DateTimeOffset Now=DateTimeOffset.UtcNow;public override DateTimeOffset GetUtcNow()=>Now; }
    private static void Check(bool value,string message){if(!value)throw new Exception(message);}
    private static void Reject(int code,Action action){try{action();}catch(FriendsException e)when(e.Status==code){return;}throw new Exception($"Expected {code}");}
    private static (WalkSharingStore Shares,FriendsStore Friends,MemberProfile A,MemberProfile B,Clock Clock) Setup(){
        var path=Path.Combine(Path.GetTempPath(),"walkabout-sharing-tests",Guid.NewGuid().ToString("N"),"library.db");var clock=new Clock();var friends=new FriendsStore(path,clock);
        var a=friends.SaveProfile("a","alice","Alice");var b=friends.SaveProfile("b","bob","Bob");friends.SaveProfile("c","carol","Carol");
        friends.Request("a",b.Id);friends.Act("b",friends.State("b").Connections.Single().RequestId!,"accept");
        return(new WalkSharingStore(path),friends,a,b,clock);
    }
    private static SharedWalkDraft Draft(string recipient,bool located=false,params SharedMemory[] media)=>new("Test adventure",located,[new(43,7),new(43.01,7.01)],media,[recipient]);
    public static Task ConsentAndPrivacy(){
        ReplayConsent();
        AllFriendsAndRevocation();
        var (shares,friends,a,b,clock)=Setup();var m=new SharedMemory(Guid.NewGuid().ToString("N"),"photo","Caption",new(43,7));
        var id=shares.Create("a",Draft(b.Id,false,m));
        Check(shares.List("b").Count==0,"Draft leaked to recipient");Reject(404,()=>shares.Get("b",id));Reject(404,()=>shares.Get("c",id));
        var safe=shares.Get("a",id);Check(safe.Route.Length==0&&safe.Media[0].Location==null,"Hidden location retained");
        Reject(409,()=>shares.Publish("a",id));Reject(404,()=>shares.UploadTarget("b",id,m.Id));Reject(404,()=>shares.Delete("b",id));
        Check(shares.Get("a",id).UploadedMediaIds.Length==0,"Empty draft reports uploaded media");
        shares.RegisterMedia("a",id,m.Id,100,1000);
        Check(shares.Get("a",id).UploadedMediaIds.SequenceEqual(new[]{m.Id}),"Recovery does not report registered media");
        Reject(409,()=>shares.UploadTarget("a",id,m.Id));
        Reject(404,()=>shares.Get("b",id));
        shares.Publish("a",id);
        var received=shares.Get("b",id);Check(!received.Owned&&received.Recipients.Length==0,"Recipient identities exposed");
        Check(shares.ReadMedia("b",id,m.Id).Kind=="photo","Recipient cannot read attachment");Reject(404,()=>shares.ReadMedia("c",id,m.Id));
        friends.Block("b",a.Id,true);Reject(404,()=>shares.Get("b",id));Reject(404,()=>shares.ReadMedia("b",id,m.Id));
        friends.Block("b",a.Id,false);clock.Now=clock.Now.AddDays(2);friends.Request("a",b.Id);friends.Act("b",friends.State("b").Connections.Single().RequestId!,"accept");
        Reject(404,()=>shares.Get("b",id));Check(shares.List("b").Count==0,"Re-friending resurrected revoked grant");
        shares.Delete("a",id);Reject(404,()=>shares.Get("a",id));return Task.CompletedTask;
    }
    private static void ReplayConsent() {
        var (shares,friends,a,b,_) = Setup();
        var at = DateTimeOffset.UtcNow;
        SharedTrailPoint[] trail = [new(at,43,7,0),new(at.AddSeconds(10),43.0001,7,0)];
        var media = new SharedMemory(Guid.NewGuid().ToString("N"),"photo","Memory",new(43,7)) { CapturedAt=at };
        var draft = Draft(b.Id,true,media) with { Trail=trail };
        var privateId = shares.Create("a",draft);
        Check(shares.Get("a",privateId).Trail.Length==0 &&
            shares.Get("a",privateId).Media[0].CapturedAt is null,"Replay data leaked without explicit consent");
        var hidden = shares.Create("a",draft with { IncludeReplay=true, IncludeLocations=false });
        Check(shares.Get("a",hidden).Trail.Length==0,"Replay leaked with locations disabled");
        var id = shares.Create("a",draft with { IncludeReplay=true });
        Reject(404,()=>shares.Get("b",id));
        shares.RegisterMedia("a",id,media.Id,100,1000);
        shares.Publish("a",id);
        Check(shares.Get("b",id).Trail.Length==2 && shares.Get("b",id).Media[0].CapturedAt==at,"Consented replay missing");
        Reject(404,()=>shares.Get("c",id));
        shares.MakePrivate("a",id);
        Reject(404,()=>shares.Get("b",id));
        Reject(400,()=>shares.Create("a",draft with { Trail=[new(at,double.NaN,7,0)] }));
        Reject(400,()=>shares.Create("a",draft with { Trail=[trail[1],trail[0]] }));
        Reject(400,()=>shares.Create("a",draft with { Trail=[trail[0],new(at.AddMinutes(2),43,7,0)] }));
        Reject(400,()=>shares.Create("a",draft with { Trail=Enumerable.Repeat(trail[0],4001).ToArray() }));
    }
    private static void AllFriendsAndRevocation(){
        var (shares,friends,a,b,clock)=Setup();
        var media=new SharedMemory(Guid.NewGuid().ToString("N"),"video","Private original",null);
        var draft=Draft(b.Id,false,media) with { Audience="allFriends",Recipients=[] };
        var id=shares.Create("a",draft);
        Reject(404,()=>shares.Get("b",id));
        shares.RegisterMedia("a",id,media.Id,100,1000);
        shares.Publish("a",id);
        Check(shares.Get("b",id).Audience=="allFriends","Audience missing");
        Reject(404,()=>shares.Get("c",id));
        friends.Request("c",a.Id);
        friends.Act("a",friends.State("a").Connections.Single(c=>c.Status=="incoming").RequestId!,"accept");
        Check(shares.List("c").Count==1,"New accepted friend cannot see all-friends share");
        Reject(404,()=>shares.MakePrivate("b",id));
        friends.Block("b",a.Id,true);
        Reject(404,()=>shares.ReadMedia("b",id,media.Id));
        shares.MakePrivate("a",id);
        Check(shares.Get("a",id).Audience=="private","Owner private copy missing");
        Reject(404,()=>shares.Get("c",id));
        Reject(404,()=>shares.ReadMedia("c",id,media.Id));
        Check(shares.List("c").Count==0,"Private walk remains in inbox");
        Reject(409,()=>shares.Publish("a",id));
        Check(shares.ReadMedia("a",id,media.Id).Kind=="video","Owner media lost");
        Reject(400,()=>shares.Create("a",draft with {Audience="public"}));
        Reject(400,()=>shares.Create("a",draft with {Recipients=[b.Id]}));
        Reject(400,()=>shares.Create("a",draft with {Audience="selectedFriends"}));
    }
    public static Task ValidationAndQuotas(){
        var (shares,friends,a,b,_)=Setup();
        var story = new SharedStory(Guid.NewGuid().ToString("N"), "Place Massena", "A story to hear.",
            ["https://example.org/source"], "Historical accounts vary.", new(43,7));
        var storyDraft = Draft(b.Id) with { Stories = [story] };
        var storyId = shares.Create("a", storyDraft);
        Reject(404, () => shares.Get("b", storyId));
        shares.Publish("a", storyId);
        var sharedStory = shares.Get("b", storyId).Stories.Single();
        Check(sharedStory.Narration == story.Narration && sharedStory.Notice == story.Notice &&
            sharedStory.Sources.SequenceEqual(story.Sources), "Story content not preserved");
        Check(sharedStory.Location is null, "Story location leaked without consent");
        Reject(404, () => shares.Get("c", storyId));
        shares.Delete("a", storyId);
        Reject(404, () => shares.Get("b", storyId));
        var locatedStory = shares.Create("a", storyDraft with { IncludeLocations = true });
        Check(shares.Get("a", locatedStory).Stories.Single().Location == story.Location, "Consented story location missing");
        shares.Delete("a", locatedStory);
        Reject(400, () => shares.Create("a", storyDraft with { Stories = null! }));
        Reject(400, () => shares.Create("a", storyDraft with { Stories = [story, story] }));
        Reject(400, () => shares.Create("a", storyDraft with { Stories = [story with { Narration = new string('x',20001) }] }));
        Reject(400, () => shares.Create("a", storyDraft with { Stories = [story with { Sources = ["javascript:alert(1)"] }] }));
        var old = JsonSerializer.Deserialize<SharedWalkDraft>(JsonSerializer.Serialize(Draft(b.Id)).Replace(",\"Stories\":[]", ""))!;
        Check(old.Stories.Length == 0, "Old shares require a migration");
        Reject(409,()=>shares.Create("a",Draft("not-a-friend")));
        Reject(400,()=>shares.Create("a",Draft(b.Id) with {Title=""}));
        Reject(400,()=>shares.Create("a",Draft(b.Id) with {Recipients=[b.Id,b.Id]}));
        Reject(400,()=>shares.Create("a",Draft(b.Id) with {Route=[new(double.NaN,0)]}));
        var m=new SharedMemory(Guid.NewGuid().ToString("N"),"video","",null);
        Reject(400,()=>shares.Create("a",Draft(b.Id,false,m with{Id="../../file"})));
        var id=shares.Create("a",Draft(b.Id,true,m));shares.RegisterMedia("a",id,m.Id,100,100);
        Reject(409,()=>shares.RegisterMedia("a",id,m.Id,1,100));
        var second=shares.Create("a",Draft(b.Id,true,m));Reject(409,()=>shares.RegisterMedia("a",second,m.Id,1,100));
        shares.Delete("a",id);shares.RegisterMedia("a",second,m.Id,1,100);shares.Publish("a",second);
        Check(shares.Get("b",second).Route.Length==2,"Explicitly shared route missing");
        Reject(409,()=>shares.UploadTarget("a",second,m.Id));
        var third=shares.Create("a",Draft(b.Id));friends.Block("a",b.Id,true);Reject(409,()=>shares.Publish("a",third));
        return Task.CompletedTask;
    }
    public static async Task MediaProcessing(){
        var ffmpeg=Environment.GetEnvironmentVariable("TEST_FFMPEG")??"ffmpeg";var ffprobe=Environment.GetEnvironmentVariable("TEST_FFPROBE")??"ffprobe";
        var dir=Path.Combine(Path.GetTempPath(),"walkabout-media-tests",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
        async Task<string> Run(string exe,params string[] args){
            var start=new ProcessStartInfo(exe){UseShellExecute=false,RedirectStandardError=true,RedirectStandardOutput=true,CreateNoWindow=true};foreach(var arg in args)start.ArgumentList.Add(arg);
            using var process=Process.Start(start)!;var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();await process.WaitForExitAsync();
            if(process.ExitCode!=0)throw new Exception(await stderr);await stderr;return await stdout;
        }
        var input=Path.Combine(dir,"input.mp4");var output=Path.Combine(dir,"output.mp4");var jpeg=Path.Combine(dir,"input.jpg");
        await Run(ffmpeg,"-v","error","-f","lavfi","-i","color=c=red:s=320x240:d=1","-c:v","libx264","-metadata","location=+43.0000+007.0000/",input);
        await Run(ffmpeg,"-v","error","-f","lavfi","-i","color=c=blue:s=320x240","-frames:v","1",jpeg);
        var processor=new SharedMediaProcessor(ffmpeg,ffprobe);await processor.Process(input,output,"video",CancellationToken.None);
        var metadata=await Run(ffprobe,"-v","error","-show_entries","format_tags:stream_tags","-of","json",output);
        Check(!metadata.Contains("43.0000")&&!metadata.Contains("location",StringComparison.OrdinalIgnoreCase),"Video location metadata leaked");
        await processor.Process(jpeg,Path.Combine(dir,"clean.jpg"),"photo",CancellationToken.None);
        var bad=Path.Combine(dir,"bad.jpg");await File.WriteAllTextAsync(bad,"not media");
        try{await processor.Process(bad,Path.Combine(dir,"bad-output.jpg"),"photo",CancellationToken.None);throw new Exception("Invalid media accepted");}catch(FriendsException e)when(e.Status==400){}
        var longVideo=Path.Combine(dir,"long.mp4");await Run(ffmpeg,"-v","error","-f","lavfi","-i","color=c=black:s=16x16:r=1:d=62","-c:v","libx264",longVideo);
        try{await processor.Process(longVideo,Path.Combine(dir,"long-output.mp4"),"video",CancellationToken.None);throw new Exception("Long video accepted");}catch(FriendsException e)when(e.Status==400){}
    }
}

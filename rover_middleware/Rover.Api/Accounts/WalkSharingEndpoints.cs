using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Rover.Infrastructure.Accounts;

namespace Rover.Api.Accounts;

public static class WalkSharingEndpoints
{
    private static readonly SemaphoreSlim MediaGate=new(1,1);
    public static void MapWalkSharing(this WebApplication app)
    {
        if(!app.Services.GetRequiredService<AccountOptions>().Enabled) return;
        var group=app.MapGroup("/api/shared-walks").RequireAuthorization(new AuthorizeAttribute{AuthenticationSchemes="WalkaboutAccount"});
        group.AddEndpointFilter(async (context,next)=> {
            context.HttpContext.Response.Headers.CacheControl="no-store";
            context.HttpContext.Response.Headers["X-Content-Type-Options"]="nosniff";
            try {
                context.HttpContext.RequestServices.GetRequiredService<FriendsStore>().Budget(PersonalLibraryEndpoints.Owner(context.HttpContext.User),"sharing",90,60);
                return await next(context);
            } catch(FriendsException e) { return Results.Problem(statusCode:e.Status,title:e.Message); }
            catch(JsonException) { return Results.Problem(statusCode:400,title:"Invalid shared walk."); }
            catch(OperationCanceledException) { return Results.Problem(statusCode:408,title:"Upload timed out. Please try again."); }
        });
        group.MapGet("",(ClaimsPrincipal user,WalkSharingStore store)=>Results.Ok(store.List(PersonalLibraryEndpoints.Owner(user))));
        group.MapPost("",async (HttpContext context,WalkSharingStore store,FriendsStore friends)=> {
            var owner=PersonalLibraryEndpoints.Owner(context.User); friends.Budget(owner,"share-create",20);
            using var bytes=new MemoryStream(); var buffer=new byte[8192]; int read;
            while((read=await context.Request.Body.ReadAsync(buffer,context.RequestAborted))>0) {
                if(bytes.Length+read>2_000_000) throw new FriendsException(413,"Route is too large."); bytes.Write(buffer,0,read);
            }
            var draft=JsonSerializer.Deserialize<SharedWalkDraft>(bytes.GetBuffer().AsSpan(0,(int)bytes.Length),new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? throw new FriendsException(400,"Missing shared walk.");
            return Results.Ok(new{id=store.Create(owner,draft)});
        });
        group.MapGet("/{id:guid}",(Guid id,ClaimsPrincipal user,WalkSharingStore store)=>Results.Ok(store.Get(PersonalLibraryEndpoints.Owner(user),id.ToString("N"))));
        group.MapPost("/{id:guid}/private",(Guid id,ClaimsPrincipal user,WalkSharingStore store)=> {
            store.MakePrivate(PersonalLibraryEndpoints.Owner(user),id.ToString("N")); return Results.NoContent();
        });
        group.MapPost("/{id:guid}/publish",(Guid id,ClaimsPrincipal user,WalkSharingStore store)=> {
            store.Publish(PersonalLibraryEndpoints.Owner(user),id.ToString("N")); return Results.NoContent();
        });
        group.MapDelete("/{id:guid}",async (Guid id,ClaimsPrincipal user,WalkSharingStore store)=> {
            await MediaGate.WaitAsync(); try { store.Delete(PersonalLibraryEndpoints.Owner(user),id.ToString("N")); return Results.NoContent(); } finally { MediaGate.Release(); }
        });
        group.MapGet("/{id:guid}/media/{media:guid}",(Guid id,Guid media,ClaimsPrincipal user,WalkSharingStore store)=> {
            var file=store.ReadMedia(PersonalLibraryEndpoints.Owner(user),id.ToString("N"),media.ToString("N"));
            return File.Exists(file.Path)?Results.File(file.Path,file.Kind=="video"?"video/mp4":"image/jpeg",enableRangeProcessing:true):Results.NotFound();
        });
        group.MapPut("/{id:guid}/media/{media:guid}",async (Guid id,Guid media,HttpContext context,WalkSharingStore store,SharedMediaProcessor processor,IConfiguration config)=> {
            var owner=PersonalLibraryEndpoints.Owner(context.User); var share=id.ToString("N"); var memory=media.ToString("N");
            var target=store.UploadTarget(owner,share,memory);
            var max=target.Kind=="video"?64L*1024*1024:12L*1024*1024;
            if(context.Request.ContentLength>max) throw new FriendsException(413,"Photo limit is 12 MB; video limit is 64 MB.");
            var feature=context.Features.Get<IHttpMaxRequestBodySizeFeature>(); if(feature is {IsReadOnly:false}) feature.MaxRequestBodySize=max;
            if(!await MediaGate.WaitAsync(0,context.RequestAborted)) throw new FriendsException(429,"Another upload is processing. Please retry shortly.");
            var input=Path.Combine(store.MediaDirectory,$"{Guid.NewGuid():N}.upload"); var output=Path.Combine(store.MediaDirectory,$"{Guid.NewGuid():N}.processed");
            var destination=store.MediaPath(share,target); var moved=false; var registered=false;
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted); timeout.CancelAfter(TimeSpan.FromMinutes(4));
            try {
                store.Cleanup();
                await using(var file=new FileStream(input,FileMode.CreateNew,FileAccess.Write,FileShare.None,81920,true)) {
                    var buffer=new byte[81920]; long size=0; int read;
                    while((read=await context.Request.Body.ReadAsync(buffer,timeout.Token))>0) { size+=read; if(size>max) throw new FriendsException(413,"Memory is too large."); await file.WriteAsync(buffer.AsMemory(0,read),timeout.Token); }
                    if(size==0) throw new FriendsException(400,"Empty memory.");
                }
                await processor.Process(input,output,target.Kind,timeout.Token);
                File.Move(output,destination,overwrite:false); moved=true;
                store.RegisterMedia(owner,share,memory,new FileInfo(destination).Length,config.GetValue<long?>("Rover:Sharing:StorageLimitBytes") ?? 512L*1024*1024); registered=true;
                return Results.NoContent();
            } finally {
                try {
                    if(moved&&!registered) File.Delete(destination);
                    File.Delete(input); File.Delete(output);
                } finally { MediaGate.Release(); }
            }
        });
    }
}

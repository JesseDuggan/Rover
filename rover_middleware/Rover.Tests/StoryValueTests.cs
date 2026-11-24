using System.Net;
using System.Text.Json;
using Rover.Application.Journeys;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;
internal static class StoryValueTests
{
    public static async Task Evaluate()
    {
        if (!StoryEditorialPolicy.IsDirectoryLanguage("Municipal inspection records confirm that this exact address is an active food premises.")
            || !StoryEditorialPolicy.IsDirectoryLanguage("In local directories, it appears among local businesses.")
            || !StoryEditorialPolicy.IsDirectoryLanguage("The passage ties that oven to the menu.")
            || !StoryEditorialPolicy.IsDirectoryLanguage("It also notes that this location appears in business improvement area event listings.")
            || !StoryEditorialPolicy.IsDirectoryLanguage("It shows up as part of the shopping loop.")
            || StoryEditorialPolicy.IsDirectoryLanguage("A licensing dispute in 1910 closed the hall for a season."))
            throw new Exception("Editorial filtering must distinguish directory administration from historical events.");
        if (StoryEditorialPolicy.AreaChapterFailure("place", "biography", false) != "individual_place_or_unclassified"
            || StoryEditorialPolicy.AreaChapterFailure("area", "overview", true) != "area_overview_already_covered"
            || StoryEditorialPolicy.AreaChapterFailure("area", "tradition", true) != null)
            throw new Exception("Area role checks must keep a distinct tradition but not a second overview or standalone POI.");
        var anchor = new GeoLocation(-33.8, 151.2);
        AdaptiveRouteStory Chapter(string id, string text) => new(id, "area", id, id, RouteStoryIntent.NeighbourhoodHistory,
            "history", anchor, 0, 100, [new(AdaptiveStoryLength.Deep, 60, text, [id])],
            [new(id, text, ["source"], .9)], [], .9, DateTimeOffset.UtcNow.AddDays(1));
        var overview = "The harbour district grew beside warehouses and fishing workshops. Residents built stone terraces and narrow lanes linking markets with the waterfront. Trading families shaped its commercial architecture and shared public spaces.";
        var distinct = "The harbour district celebrates a spring lantern procession. Fishing families carry handmade lights through narrow lanes to remember sailors, while children learn traditional songs from their grandparents.";
        var chapters = StoryEditorialPolicy.DistinctChapters([Chapter("overview", overview), Chapter("renamed", overview + " Visitors can still see this today."), Chapter("festival", distinct)]);
        if (chapters.Count != 2 || chapters[1].StoryId != "festival") throw new Exception("Keep distinct local angles but suppress a renamed repeated overview.");
        const string detail="The former workshop became a school where local families learned to repair their fishing nets.";
        foreach(var kind in new[]{"local_episode","visible_detail","natural_process","community_connection"})
            if(StoryValuePolicy.Failure(kind,detail,detail)!=null)throw new Exception("Useful evidence rejected by topic");
        if(StoryValuePolicy.Failure("directory_only",detail,detail)==null || StoryValuePolicy.Failure("local_episode","An invented detail about a famous person.",detail)==null)
            throw new Exception("Directory or invented value accepted");
        if(GeographicEvidencePolicy.Failure("Town","The river shaped\n the old Town.","The river shaped the old Town.")!=null)
            throw new Exception("Formatting difference rejected cited geography");
        if(GeographicEvidencePolicy.Failure("Town","An unsupported connection to this Town.","The river shaped the old Town.")!="local_connection_not_in_cited_passage")
            throw new Exception("Paraphrased unsupported connection accepted");
        foreach(var (recover, dominated) in new[]{(true,false),(false,false),(true,true)}) {
            var calls=0;var decisions=new List<StoryInspectionEvent>();var previous=StoryInspection.Listener.Value;
            StoryInspection.Listener.Value=decisions.Add;
            try {
                using var client=new HttpClient(new RoutingHttpMessageHandler(request=> {
                    calls++;
                    var passage=detail+" Municipal inspection records confirm that this exact address is an active food premises. The official register supplies its operating identity. The archive preserves a photograph of the building and records of that change. The school gave neighbours a place to meet and share practical skills. These records document the building's former use without relying on its current business listing. Location: old workshop; latitude 44.9; longitude -76.25.";
                    if (dominated) passage = detail + " Municipal inspection records confirm this exact address is an active food premises. Local directories list the shop. The passage describes its current name. It also says this is a registered business. This shop appears in the shopping loop. The evidence places it in association event material. It appears in BIA listings. Location: old workshop; latitude 44.9; longitude -76.25.";
                    if(calls%2==1) {
                        var text=passage+" [1]";
                        return Response(new { status="completed",output=new[]{new {content=new[]{new {text,annotations=new[]{new {type="url_citation",start_index=passage.Length+1,end_index=passage.Length+4,url="https://archive.example/history",title="Archive"}}}}}}});
                    }
                    var card=new {evidenceIndex=0,title="A workshop became a school",kind="history",latitude=44.9,longitude=-76.25,locationEvidence="old workshop",audienceSuitability="family",
                        spokenSentences=SpokenStoryDraft.EvidenceSentences(passage).Select((t,i)=>new {text=t,evidenceSentenceIndices=new[]{i},narrativePurpose=t.Contains("official register")?"source_administration":StoryEditorialPolicy.IsDirectoryLanguage(t)?"directory":"story"}).ToArray(),
                        storyValueEvidenceSentenceIndex=0,
                        storyValueKind=calls==4 && recover ? "local_episode" : "directory_only",storyValueEvidence=detail};
                    return Response(new {status="completed",output=new[]{new {content=new[]{new {text=JsonSerializer.Serialize(new {stories=new[]{card},omitted=Array.Empty<object>()})}}}}});
                }));
                var point=new GeoLocation(44.9,-76.25);
                var researcher=new OpenAILocalRouteResearcher(client,new(){Enabled=true,ApiKey="test",Model="test"},TimeProvider.System);
                var result=await researcher.ResearchAsync(new([new("area",0,point,point,point,0,0,0,0,false,[])],new("Town",null,null,null),[],["history"],"en") {AreaFirst=true,RequireStoryValue=true},default);
                if(calls!=4 || result.Stories.Count!=(recover && !dominated?1:0))throw new Exception("Value recovery must stop after one alternate search");
                if(!decisions.Any(x=>x.Stage=="Story value" && x.Outcome=="Map only"))throw new Exception("Value rejection missing from inspector");
                if(recover && !dominated && result.Stories.Single().Variants.Any(v => (StoryEditorialPolicy.IsDirectoryLanguage(v.Narration) || v.Narration.Contains("official register")))) throw new Exception("Directory sentence survived automatic narration.");
                if(recover && !dominated && !result.Stories.Single().StoryValueVerified)throw new Exception("Value assessment missing from returned story");
            } finally {StoryInspection.Listener.Value=previous;}
        }
    }
    static HttpResponseMessage Response(object body)=>new(HttpStatusCode.OK){Content=new StringContent(JsonSerializer.Serialize(body))};
}

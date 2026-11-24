using System.Net;
using System.Text.Json;
using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;

internal static class ResearchParagraphTests
{
    public static async Task EvidenceLength()
    {
        foreach(var scenario in new (int Words,bool Valid,bool Accept)[]{(260,true,true),(600,true,true),(601,true,false),(14,true,false),(260,false,false)}) {
            var text=string.Join(" ",Enumerable.Repeat("documented",scenario.Words-5))+" Qualification remains disputed by historians.";
            var events=new List<StoryInspectionEvent>();var old=StoryInspection.Listener.Value;StoryInspection.Listener.Value=events.Add;
            var calls=0;
            try {
                using var client=new HttpClient(new RoutingHttpMessageHandler(request=>{
                    calls++;using var body=JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                    object result;
                    if(calls==1)result=new {status="completed",output=new[]{new{content=new[]{new{
                        text=text+" [1]",annotations=new[]{new{type="url_citation",start_index=text.Length+1,end_index=text.Length+4,
                            url=scenario.Valid?"https://archive.example/record":"http://127.0.0.1/private",title="Archive"}}
                    }}}}};
                    else {
                        var input=body.RootElement.GetProperty("input").GetString()!;
                        if(!input.Contains("Qualification remains disputed by historians."))
                            throw new Exception("Full qualification lost before spoken editing");
                        result=new{status="completed",output=new[]{new{content=new[]{new{text="{\"stories\":[],\"omitted\":[{\"evidenceIndex\":0,\"reason\":\"insufficient_evidence\"}]}"}}}}};
                    }
                    return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent(JsonSerializer.Serialize(result))};
                }));
                var researcher=new OpenAILocalRouteResearcher(client,new(){Enabled=true,ApiKey="test",Model="test"},TimeProvider.System);
                var point=new GeoLocation(44.9,-76.25);
                await researcher.ResearchAsync(new([new("test",0,point,point,point,0,0,0,0,false,[])],new ApproximateLiveLocation("Town","Region","Country",null),["Museum"],["history"],"en"){
                    MaximumStories=1,Question=new("History",StoryQuestionScope.Street,StoryQuestionFormat.Single,1,90)
                },default);
                if(calls!=(scenario.Accept?2:1))throw new Exception($"Incorrect extraction bound for {scenario}");
                var extraction=events.Single(x=>x.Stage=="Citation extraction");
                if(!extraction.Reason.Contains("allowed 15–600 words"))throw new Exception("Length diagnostics absent");
                if(scenario.Accept && !extraction.Reason.Contains("1 evidence paragraphs above 220"))throw new Exception("Extended evidence not recorded");
            } finally {StoryInspection.Listener.Value=old;}
        }
    }
}

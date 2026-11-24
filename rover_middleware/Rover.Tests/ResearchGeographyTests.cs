using System.Net;
using System.Text.Json;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;
using Rover.Application.Journeys;
internal static class ResearchGeographyTests
{
    public static async Task Resolve()
    {
        foreach(var (lat,lon,city,hood) in new[]{(43.65,-79.48,"Toronto","Bloor West Village"),(-27.47,153.02,"Brisbane","South Brisbane"),(35.68,139.76,"Chiyoda", "Marunouchi"),(44.9,-76.25,"Perth",(string?)null)}) {
            string Payload(double offset=0) => JsonSerializer.Serialize(new {status="OK",results=new[]{new {
                geometry=new {location=new {lat=lat+offset,lng=lon}},address_components=new[]{
                    new {long_name=city,types=new[]{"locality"}},new {long_name=hood??"",types=new[]{"neighborhood"}},
                    new {long_name="Street",types=new[]{"route"}},new {long_name="Country",types=new[]{"country"}}}
            }}});
            using var doc=JsonDocument.Parse(Payload());var result=ResearchGeography.Parse(doc.RootElement,new(lat,lon));
            if(result?.City!=city || result.Neighbourhood!=hood)throw new Exception("Geographic components lost");
            using var far=JsonDocument.Parse(Payload(.1));if(ResearchGeography.Parse(far.RootElement,new(lat,lon))!=null)throw new Exception("Distant result accepted without containing bounds");
            using var client=new HttpClient(new RoutingHttpMessageHandler(req=> {
                if(!req.Options.TryGetValue(new HttpRequestOptionsKey<string>("Walkabout.Usage.Purpose"),out var purpose)||purpose!="Resolve research neighbourhood")throw new Exception("Missing cost purpose");
                return new(HttpStatusCode.OK){Content=new StringContent(Payload())};
            }));
            var resolver=new ResearchGeography(client,new(){ApiKey="test"});
            if((await resolver.ResolveAsync(new(lat,lon),"en",default))?.City!=city)throw new Exception("Lookup failed");
            using var cancel=new CancellationTokenSource();cancel.Cancel();
            try {await resolver.ResolveAsync(new(lat,lon),"en",cancel.Token);throw new Exception("Cancellation swallowed");}catch(OperationCanceledException){}
        }
        using var broad=JsonDocument.Parse("""{"status":"OK","results":[{"geometry":{"location":{"lat":0,"lng":0}},"address_components":[{"long_name":"City","types":["locality"]},{"long_name":"Borough","types":["sublocality_level_1"]}]}]}""");
        var broadContext=ResearchGeography.Parse(broad.RootElement,new(0,0));
        if(broadContext?.Neighbourhood!=null || broadContext?.District!="Borough")throw new Exception("Borough mislabeled as neighbourhood");
        using var county=JsonDocument.Parse(broad.RootElement.GetRawText().Replace("locality", "administrative_area_level_2"));
        if(ResearchGeography.Parse(county.RootElement,new(0,0))?.City!=null)throw new Exception("County mislabeled as city");
        var geoCalls=0;var modelCalls=0;
        using var geoClient=new HttpClient(new RoutingHttpMessageHandler(_=> { geoCalls++; return new(HttpStatusCode.OK){Content=new StringContent(broad.RootElement.GetRawText())}; }));
        using var modelClient=new HttpClient(new RoutingHttpMessageHandler(request=> {
            modelCalls++;
            using var body=JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var input=body.RootElement.GetProperty("input").GetString()!;
            if(!input.Contains("Borough") || !input.Contains("resolvedGeography"))throw new Exception("Shared researcher lost geographic context");
            return new(HttpStatusCode.OK){Content=new StringContent("{\"status\":\"completed\",\"output\":[]}")};
        }));
        var point=new GeoLocation(0,0);
        var researcher=new OpenAILocalRouteResearcher(modelClient,new(){Enabled=true,ApiKey="test",Model="test"},TimeProvider.System,
            geography:new ResearchGeography(geoClient,new(){ApiKey="test"}));
        await researcher.ResearchAsync(new([new("area",0,point,point,point,0,0,0,0,false,[])],new(null,null,null,null),[],["history"],"en") {AreaFirst=true},default);
        if(geoCalls!=1 || modelCalls!=2)throw new Exception("Recovery repeated geographic lookup or lost bounded retry");
        using var denied=JsonDocument.Parse("{\"status\":\"REQUEST_DENIED\",\"results\":[]}");
        if(ResearchGeography.Parse(denied.RootElement,new(0,0))!=null)throw new Exception("Denied lookup fabricated locality");
        using var bounds=JsonDocument.Parse("""{"status":"OK","results":[{"geometry":{"location":{"lat":1,"lng":179},"bounds":{"southwest":{"lat":-2,"lng":170},"northeast":{"lat":2,"lng":-170}}},"address_components":[{"long_name":"Island","types":["locality"]}]}]}""");
        if(ResearchGeography.Parse(bounds.RootElement,new(0,-179))?.City!="Island")throw new Exception("Dateline bounds lost");
    }
}

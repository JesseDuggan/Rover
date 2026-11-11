using Rover.Application.Journeys;
using Rover.Application.Speech;

internal static class NarrationAddressTests
{
    public static Task PresentationOnly()
    {
        var cases = new Dictionary<string,string> {
            ["The museum at 11 Gore Street East opened in 1967."] = "The museum on Gore Street East opened in 1967.",
            ["At 3355 Las Vegas Boulevard South, the plaque recalls 1960."] = "On Las Vegas Boulevard South, the plaque recalls 1960.",
            ["The gallery is located at 12 King Street, postal code K7H 1H9."] = "The gallery is located on King Street.",
            ["In 1960 the band played 12 shows. Route 66 and Studio 54 are names."] = "In 1960 the band played 12 shows. Route 66 and Studio 54 are names.",
            ["Walk 150 metres along King Street to the bridge."] = "Walk 150 metres along King Street to the bridge.",
            ["The building is not at 12 King Street."] = "The building is not at 12 King Street.",
            ["The house may have opened in 1820; accounts disagree."] = "The house may have opened in 1820; accounts disagree."
        };
        foreach(var pair in cases) {
            var actual=NarrationAddressPolicy.ForStory(pair.Key);
            if(actual!=pair.Value) throw new Exception($"Unexpected narration: {actual}");
            if(NarrationAddressPolicy.ForStory(actual)!=actual) throw new Exception("Cleanup must be idempotent.");
        }
        foreach(var purpose in Enum.GetValues<SpeechPurpose>()) {
            var command=new RenderSpeechCommand(Guid.NewGuid(), "The museum at 11 Gore Street East opened in 1967.",purpose,"en-CA",null,null,null);
            var prepared=SpeechTextPreparer.Prepare(command,1000);
            if(prepared.Text.Contains("11 Gore") != (purpose==SpeechPurpose.AskRoverAnswer))
                throw new Exception("Story speech must omit addresses; explicit question answers retain them.");
            if(!command.Text.Contains("11 Gore")) throw new Exception("Source data was changed.");
        }
        return Task.CompletedTask;
    }
}

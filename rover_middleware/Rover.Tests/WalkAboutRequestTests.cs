using Rover.Api.Contracts;
using Rover.Api.Validation;

internal static class WalkAboutRequestTests
{
    public static Task Validation()
    {
        var request = new CreateWalkRequest(48.137, 11.575, 60, ["history"], "Standard", [])
        {
            NaturalRequest = "  Quiet streets and architecture  ",
            Companions = "Family", Environment = "Outdoor",
            RouteShape = "Different destination", IncludePaidAttractions = true
        };
        if (!WalkRequestValidation.TryCreateCommand(request, out var command, out _) ||
            command!.NaturalRequest != "Quiet streets and architecture" ||
            command.Companions != "Family" || command.Environment != "Outdoor" ||
            command.RouteShape != "Different destination" || !command.IncludePaidAttractions)
            throw new InvalidOperationException("Walk preferences were lost.");
        foreach (var invalid in new[] {
            request with { NaturalRequest = new string('x', 501) },
            request with { Companions = "invalid" },
            request with { Environment = "invalid" },
            request with { RouteShape = "invalid" } })
            if (WalkRequestValidation.TryCreateCommand(invalid, out _, out _))
                throw new InvalidOperationException("Invalid walk preferences accepted.");
        return Task.CompletedTask;
    }
}

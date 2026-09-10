namespace Rover.Application.Walks;

public sealed class LocationTrackingOptions
{
    public double OffRouteDistanceMeters { get; set; } = 65;
    public double ArrivalAccuracyPaddingMeters { get; set; } = 10;
    public int RequiredArrivalReadings { get; set; } = 1;
    public int RequiredOffRouteReadings { get; set; } = 2;
    public int StaleReadingSeconds { get; set; } = 120;
    public double MaximumAccuracyMeters { get; set; } = 100;
    public double ImpossibleJumpMeters { get; set; } = 1000;
    public int ImpossibleJumpSeconds { get; set; } = 5;
    public double ManualArrivalExtraDistanceMeters { get; set; } = 65;
}

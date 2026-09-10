namespace Rover.Application.Speech;

public sealed class ElevenLabsSpeechOptions
{
    public bool Enabled { get; set; }
    public string? ApiKey { get; set; }
    public string? VoiceId { get; set; }
    public string? ModelId { get; set; }
    public string OutputFormat { get; set; } = "mp3_44100_128";
    public double Stability { get; set; } = 0.45;
    public double Similarity { get; set; } = 0.75;
    public double Style { get; set; }
    public bool SpeakerBoost { get; set; } = true;
    public int RequestTimeoutSeconds { get; set; } = 20;
    public int MaximumCharactersPerRequest { get; set; } = 1800;
    public int DailyCharacterLimitPerUser { get; set; } = 12000;
    public int MonthlyCharacterLimit { get; set; } = 250000;
    public bool CacheEnabled { get; set; } = true;
    public bool FallbackEnabled { get; set; } = true;
    public string CacheDirectory { get; set; } = "work/generated-audio-cache";
    public int CacheRetentionHours { get; set; } = 168;
}

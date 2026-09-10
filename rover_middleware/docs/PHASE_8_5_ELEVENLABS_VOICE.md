# Phase 8.5 ElevenLabs Premium Rover Voice

The ElevenLabs API key belongs only in the ASP.NET Core middleware environment or AWS secret storage. It is never placed in Flutter, logs, source control, Swagger examples, or API responses.

## Local Configuration

Run the API with the safe development fake provider:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
$env:ROVER_STORAGE_MODE = "InMemory"
```

```powershell
$env:ElevenLabs__Enabled = "false"
```

```powershell
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

Run with ElevenLabs locally:

```powershell
$env:ElevenLabs__Enabled = "true"
```

```powershell
$env:ElevenLabs__ApiKey = "REPLACE_WITH_LOCAL_SECRET"
```

```powershell
$env:ElevenLabs__VoiceId = "REPLACE_WITH_VOICE_ID"
```

```powershell
$env:ElevenLabs__ModelId = "REPLACE_WITH_MODEL_ID"
```

```powershell
$env:ElevenLabs__OutputFormat = "mp3_44100_128"
```

```powershell
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

## Test Streaming Audio

Create a development identity:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5080/api/auth/development/session" -ContentType "application/json" -Body '{"subject":"voice-dev","email":"voice@example.test"}'
```

Render audio to a local MP3:

```powershell
Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:5080/api/speech/render" -Headers @{ "X-Rover-Dev-User" = "voice-dev"; "Accept" = "audio/mpeg" } -ContentType "application/json" -Body '{"text":"Welcome to Rover premium voice.","purpose":"WalkIntroduction","locale":"en-US"}' -OutFile ".\work\voice-test.mp3"
```

## Samsung RFGYA0RB5HY

```powershell
adb -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

```powershell
flutter run -d RFGYA0RB5HY --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=ROVER_DEV_USER=voice-dev --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

Open Profile, then Voice test. Use Stop sample, Ask sample, Intro sample, Pause, Resume, and Stop.

## Fallback Behavior

Rover uses device TTS when ElevenLabs is disabled, missing configuration, times out, rejects the request, exceeds local usage limits, or audio playback fails. Navigation and safety prompts continue to use immediate device TTS.

## Cache Strategy

Reusable narration is cached by normalized text hash, voice id, model id, output format, voice settings, locale, and content version. Personalized ASK ROVER answers are not cached by default.

## Cost Controls

Configured limits include maximum characters per request, per-user daily characters, monthly character budget placeholder, cache-first rendering, duplicate mobile idempotency keys, and provider fallback. Usage events record purpose, character count, cache hit/miss, success/failure, provider latency, account id, and timestamp. Raw narration text and secrets are not recorded in usage events.

## Key Rotation

Create a restricted ElevenLabs key for text-to-speech only if available in your account plan. Set account usage limits in ElevenLabs. Store staging keys in AWS Secrets Manager or Parameter Store, rotate by writing the new secret version, restarting the API task, verifying `/api/speech/render`, then disabling the old key.

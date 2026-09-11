# Rover Flutter

Flutter client for the Rover walking-tour experience.

## Phase 3 Middleware Connection

Phase 3 connects this Flutter app to the local ASP.NET Core Rover middleware in `../rover_middleware`. The app reads its API base URL from:

```powershell
--dart-define=ROVER_API_BASE_URL=<url>
```

No production API URL, API key, or secret is hardcoded in source control.

## Wireless LAN Development

The recommended physical-device workflow no longer requires USB reverse. Follow [docs/WIRELESS_LAN_DEVELOPMENT.md](docs/WIRELESS_LAN_DEVELOPMENT.md) to start the API on the private LAN, test it from the Samsung device, and launch Flutter with the laptop's current IPv4 address.

The canonical development API port is `5080`. Android emulator builds default to `http://10.0.2.2:5080`; Windows and local web builds default to `http://127.0.0.1:5080`; physical Android builds must supply `ROVER_API_BASE_URL`.

## Railway Beta API

Beta builds no longer depend on `adb reverse`, USB tethering, or the laptop development API. Build the app against the hosted Railway URL:

```powershell
flutter build appbundle --release `
  --dart-define=ROVER_API_ENVIRONMENT=beta `
  --dart-define=ROVER_BETA_API_BASE_URL=https://rover-api.up.railway.app `
  --dart-define=ROVER_BETA_API_KEY=<beta-api-key> `
  --dart-define=GOOGLE_MAPS_ANDROID_API_KEY=<android-restricted-key>
```

Use `ROVER_API_BASE_URL=http://127.0.0.1:5080` or `ROVER_API_BASE_URL=http://10.0.2.2:5080` only for local development. When Railway assigns the final HTTPS domain, replace `ROVER_BETA_API_BASE_URL` with that exact URL.

## Start The Middleware

From the repository root:

```powershell
cd SRC\rover_middleware
dotnet restore .\Rover.sln
dotnet build .\Rover.sln --configuration Release
dotnet test .\Rover.sln --configuration Release --no-build
.\run-rover-api-lan.ps1
```

The HTTP development port is shown in console output, for example:

```text
Now listening on: http://0.0.0.0:5080
```

## Flutter Launch Commands

Create your local Flutter environment file once:

```powershell
cd SRC\rover_flutter
Copy-Item .\.env.example .\.env.local
notepad .\.env.local
```

Set `GOOGLE_MAPS_ANDROID_API_KEY` to an Android-restricted Google Maps SDK key. Keep `MAPBOX_PUBLIC_TOKEN` only while validating the temporary fallback. Do not commit `.env.local`.

Android emulator:

```powershell
cd SRC\rover_flutter
flutter run --debug --dart-define=ROVER_API_BASE_URL=http://10.0.2.2:5080 --dart-define=GOOGLE_MAPS_ANDROID_API_KEY=<android-restricted-key>
```

Windows desktop:

```powershell
cd SRC\rover_flutter
flutter run -d windows --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=MAPBOX_PUBLIC_TOKEN=<public-token>
```

Chrome:

```powershell
cd SRC\rover_flutter
flutter run -d chrome --debug --dart-define=ROVER_API_BASE_URL=http://127.0.0.1:5080 --dart-define=MAPBOX_PUBLIC_TOKEN=<public-token>
```

Physical Android device on the same network:

```powershell
cd SRC\rover_flutter
flutter run --debug --dart-define-from-file=.env.local --dart-define=ROVER_API_BASE_URL=http://<LAPTOP_PRIVATE_IPV4>:5080
```

Physical Samsung beta testing should use the Railway HTTPS URL above. Use the LAN workflow only for local debugging on a private network.

Google Maps is the preferred Flutter renderer when `GOOGLE_MAPS_ANDROID_API_KEY` is present. The key is passed to the Android manifest from the existing `--dart-define-from-file=.env.local` build flow. Restrict it in Google Cloud to the Maps SDK for Android, the `ai.myrover.rover` package, and the signing-certificate SHA fingerprints used for each build type.

The mobile Maps SDK key is not the middleware `GOOGLE_PLACES_API_KEY`; keep those as separate restricted credentials. If the Google key is absent, ROVER temporarily falls back to Mapbox when `MAPBOX_PUBLIC_TOKEN` is valid, then to the development renderer. Set `ROVER_MAP_PROVIDER=mapbox` only for comparison testing.

Do not commit either provider key. Keep server-side routing and search credentials in middleware environment variables or .NET user secrets.

Minimum public token scopes for Flutter map display: Mapbox public style/tile access. Restrict the token to the Rover app bundle/package and expected hostnames where possible, rotate it if it is exposed, and never log token values.

## Phase 4 Location And Map Flow

Rover requests foreground location only when live navigation begins. The permission explanation shown to users is:

```text
Rover uses your location during an active walk to show your route, guide you to the next stop and detect when you arrive.
```

The app lets users review a walk without location permission. Live navigation requires foreground location, handles normal denial with retry, handles permanent denial with an Open Settings action, and stops the location stream when the walk completes, is cancelled, the controller is disposed, or tracking is disabled.

The active walk map displays the current route state, current position, stop order, progress, next-stop distance, remaining time and off-route warning as text so screen-reader and large-text users are not forced to rely on marker color alone. The debug-only simulated arrival control remains available in debug builds.

## Union Square Emulator Route

Use the simulated GPX route at:

```text
docs\fixtures\union_square_phase4_route.gpx
```

Android Emulator steps:

1. Start `Rover.Api` in mock mode.
2. Launch the Flutter app with `ROVER_API_BASE_URL=http://10.0.2.2:5207`.
3. Create the Union Square API ROAM and start the walk.
4. Open Android Emulator Extended Controls.
5. Choose Location.
6. Load `docs\fixtures\union_square_phase4_route.gpx`.
7. Replay the route.

The fixture is simulated test data. It begins near Union Square, enters each deterministic mock stop radius in order, includes a temporary off-route deviation, returns to the route and reaches the final stop.

## End-To-End Test Steps

1. Start `Rover.Api`.
2. Launch Flutter with the correct `ROVER_API_BASE_URL`.
3. Continue as guest if onboarding is not complete.
4. Go to Home and create an adventure request.
5. Use the clearly labelled Union Square test location if emulator GPS is unavailable.
6. Create the API ROAM from route preview.
7. Start the walk.
8. Review the next stop, narration, progress, remaining time, and content labels.
9. In debug builds, tap `Simulate arrival at next stop` for each ordered stop.
10. Complete the walk after every stop is visited.
11. Confirm the completion summary.

The simulated-arrival control is gated behind Flutter debug mode and is not shown in release builds.

## Troubleshooting

- Connection refused: confirm `Rover.Api` is running and the port matches `ROVER_API_BASE_URL`.
- Android emulator cannot reach `localhost`: use `http://10.0.2.2:5207`.
- Physical Android device cannot connect: use the computer LAN IP, confirm both devices are on the same network, and allow the firewall prompt for the middleware port.
- HTTP cleartext blocked: debug Android builds allow local cleartext traffic. Release network security is not weakened.
- Timeout: confirm the middleware health endpoint responds at `/health`.
- Missing Google map: confirm `.env.local` contains `GOOGLE_MAPS_ANDROID_API_KEY`, `ROVER_MAP_PROVIDER=google`, and that Maps SDK for Android is enabled for the key's Google Cloud project.
- Google map authorization error: confirm the key is restricted to package `ai.myrover.rover` and includes the SHA fingerprint of the installed APK's signing certificate.
- Mapbox fallback: pass `ROVER_MAP_PROVIDER=mapbox` with a valid `MAPBOX_PUBLIC_TOKEN` only during migration testing.
- Off-route warning: return to the planned route or review a Rejoin proposal before applying a route change.

## Phase 6 Adaptive Routing And Discovery

Active API walks show Route options. Rover can propose nearby discoveries, skipping the next stop, shortening, extending, rejoining, or returning to the starting area. The proposal card shows added time, distance, affected stops, sponsored labels, and Accept, Keep Current, or Dismiss actions.

Accepting a proposal refreshes the map line, stop markers, progress, next stop, and route revision. Dismissed discoveries are held in memory for the current walk only.

## Phase 6 Limitations

This phase uses deterministic mock discoveries and proposal logic. It does not add live places, weather, events, advertising billing, authentication, database persistence, background listening, background GPS or production deployment. Mapbox walking routes are not guaranteed wheelchair-accessible and may not fully represent stairs, hills, closures or restricted paths.

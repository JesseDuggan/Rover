# Rover Android Private Beta

## Release Signing Key

Create a release key only on a trusted developer machine:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\rover-release.jks" -alias rover-release -keyalg RSA -keysize 4096 -validity 10000
```

Store the keystore in a password manager or secure vault. Do not commit it.

Create `android/key.properties` locally:

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
@"
storePassword=replace-locally
keyPassword=replace-locally
keyAlias=rover-release
storeFile=C:\\Users\\jesse\\rover-release.jks
"@ | Set-Content ".\android\key.properties"
```

## Build An App Bundle

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
flutter pub get
flutter build appbundle --release --dart-define=ROVER_API_BASE_URL=https://staging-api.example.com --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN
```

## Google Play Internal Testing

1. Open Google Play Console.
2. Create the Rover app record.
3. Upload `build\app\outputs\bundle\release\app-release.aab`.
4. Add testers to an internal testing track.
5. Confirm the Mapbox token is application restricted for the Android package and signing certificate.
6. Share the internal testing opt-in link with testers.

## Samsung RFGYA0RB5HY Local Install

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
flutter install -d RFGYA0RB5HY
```

Collect logs:

```powershell
adb -s RFGYA0RB5HY logcat | Select-String "Rover|Mapbox|flutter"
```

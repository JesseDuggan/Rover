# Phase 8 Private Beta Readiness

Rover uses Amazon Cognito User Pools for staging identity, OAuth 2.0/OIDC authorization-code flow with PKCE for Flutter, and short-lived API access tokens. Authentication is behind application interfaces so Cognito can be replaced later.

Development authentication is explicit and only works when `ASPNETCORE_ENVIRONMENT=Development`. Use `X-Rover-Dev-User` to exercise authorization and ownership checks locally. This header is ignored outside Development.

## Local Development

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
$env:ROVER_STORAGE_MODE = "InMemory"
```

```powershell
dotnet run --project ".\Rover.Api\Rover.Api.csproj" --urls http://127.0.0.1:5080
```

Create a development account:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5080/api/auth/development/session" -ContentType "application/json" -Body '{"subject":"jesse-dev","email":"jesse@example.test"}'
```

Call an authenticated endpoint:

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:5080/api/accounts/me" -Headers @{ "X-Rover-Dev-User" = "jesse-dev" }
```

## Samsung Testing

```powershell
adb -s RFGYA0RB5HY reverse tcp:5080 tcp:5080
```

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter"
```

```powershell
.\run_rover_samsung.local.ps1
```

## Cognito Staging Configuration

Create a Cognito User Pool with an app client that has no client secret, supports authorization code with PKCE, and enables `openid`, `email`, and `profile` scopes. Set callback/logout URLs to app links such as `rover://auth/callback` and `rover://auth/logout`.

Required API settings for staging:

```powershell
$env:ASPNETCORE_ENVIRONMENT = "Staging"
$env:ROVER_STORAGE_MODE = "PostgreSql"
$env:Rover__Storage__PostgreSql__ConnectionString = "<from Secrets Manager>"
$env:Rover__Authentication__Cognito__Authority = "https://cognito-idp.<region>.amazonaws.com/<user-pool-id>"
$env:Rover__Authentication__Cognito__Audience = "<app-client-id>"
$env:Rover__Cors__AllowedOrigins = "https://staging.myrover.ai"
```

## Database Migrations

Phase 8 SQL initialization scripts live in `database/init`. PostgreSQL mode must not silently fall back to in-memory storage. Apply migrations with a reviewed migration runner in staging; do not apply destructive migrations automatically.

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
$env:ROVER_POSTGRES_PASSWORD = "choose-a-local-password"
```

```powershell
docker compose up -d
```

## Container Build

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware"
```

```powershell
docker build -t rover-api:phase8 .
```

## Terraform

Terraform was chosen over CDK because it is language-neutral, easy to validate in CI, and familiar for small AWS staging environments.

```powershell
cd "C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware\infra\terraform"
```

```powershell
terraform init
terraform plan -var='allowed_origins=["https://staging.myrover.ai"]' -var='container_image=replace-with-ecr-uri'
```

## Privacy Controls

Implemented local API foundations:

- Link guest profile to account
- Export account data as JSON
- Request account deletion and remove linked profile data
- Reset learned preferences on existing profile endpoints
- Delete saved discoveries on existing profile endpoints

## Remaining Credentialed Work

- Add live Cognito token validation package once NuGet connectivity is fixed.
- Complete EF Core/Npgsql repositories and generated migrations.
- Create ECS Fargate, ALB, RDS, alarms, and migration runner resources with AWS credentials.
- Configure protected GitHub staging environment secrets.

# ROVER Source of Truth

Railway deploys the API from `https://github.com/JesseDuggan/Rover`.
Use this Git checkout for subsequent API and Flutter changes and builds.
Do not deploy the older standalone `2026-08-27/.../SRC` tree over this checkout.

## Reconciliation (2026-09-13)

Merged the standalone tree's local research agent, online-source cache eligibility,
source links, research status, playback interruption fixes, on-device capability
timeouts, and regression tests. Preserved the repository's Railway port binding,
beta authentication, environment selection, startup validation, provider retries,
Dockerfile, and Railway configuration.

Flutter beta credentials are sent only to `/api/` paths on the configured API
origin, not to a different development override origin or the public health URL.

No secrets or local environment files were copied. Before building in this
checkout, configure its ignored Flutter `.env.local` with the approved client
configuration and beta access key. Keep provider keys on the API server only.

The debug build helper is `rover_flutter/build_rover_debug_railway.ps1`; supply
`-BuildNumber` greater than the version already installed. Its API target is
`https://rover-production-d220.up.railway.app`.

The server research agent requires both `ROVER_PHASE16_ENABLED=true` and
`ROVER_LOCAL_RESEARCH_ENABLED=true`, plus the server's `OPENAI_API_KEY`.
Existing Railway variables are not changed by this local reconciliation.

Story-Led Walk Planning is implemented as a separate opt-in server feature.
See rover_middleware/docs/STORY_LED_WALK_PLANNING.md for activation, safeguards,
first-version limits and testing. It is not enabled or deployed automatically.

Changes are local until reviewed, committed, and pushed. A push may trigger
Railway deployment; do not assume local tests changed the live service.

Validation: 150 backend tests and 172 Flutter tests passed in this checkout.
The Release API build succeeded with zero warnings and errors. No new APK was
built and no physical-device or live-provider testing was performed in this merge.

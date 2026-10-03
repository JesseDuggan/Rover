# Shared Story Library

## Scope

Local route research can now reuse sourced stories across visitors. Existing
per-walk route-pack storage and the separate shared location-intelligence cache
remain unchanged. The new library wraps `ILocalRouteResearcher`; it does not add
social publishing, uploads, or a Flutter UI.

Stories are matched by language and a 225-metre route corridor. Playback windows
are recalculated for the receiving route. Covered titles are excluded, interests
influence ranking, and requested current events cannot be satisfied solely by
historical stories. Research fills the missing story count. This is reuse, not
model training, and does not increase the existing research targets.

## Activation

Disabled by default. Before enabling, attach a persistent Railway volume and
confirm the API process can write to it. For a volume mounted at `/data`, set:

```text
ROVER_SHARED_STORIES_ENABLED=true
ROVER_SHARED_STORIES_DIRECTORY=/data/shared-stories
ROVER_SHARED_STORIES_APPROVED_HOSTS=www.wikidata.org
```

This initial policy supports only Wikidata structured entity facts built by the
Wikidata provider, with explicit CC0 rights metadata. The host allowlist is an
additional restriction, not a license grant. Public availability alone is not
approval. Ordinary web-search citations, even to Wikidata, are not eligible. Startup
rejects enabled configuration without an absolute directory and approved hosts.

The Railway volume and source approvals have not been verified by these local
tests. Deploying the API is required; rebuilding the APK is not. Disable the
feature flag to return to the existing live-research path.

## Data And Freshness

- Every source must pass the versioned structured-data reuse policy and the
  configured host allowlist. Mixed-source stories fail closed.
- Source rights include license ID and URL, rights reference URL, content scope,
  entity ID, and policy version. Missing metadata in older records is rejected.
- Wikidata entity URLs must match the recorded QID; help, discussion, and policy
  pages do not receive a structured-data grant. The provider normalizes canonical
  entity URLs to HTTPS. Provider identity, attribution and metadata are rechecked.
- Provider-built candidates enter the library before local research; titles
  already present in the current pack are excluded from the reuse result.
- Source citations, attribution, evidence references, language and place anchors
  are retained. Route segment IDs and playback distances are removed on storage.
- User profiles, requests, routes and listening histories are not stored here.
- Every read rechecks source approval and expiry. History has a six-hour source
  freshness cap; news/events have a 30-minute cap. Earlier story expiry wins.
- Reuse never extends expiry or changes `AllowsOfflineUse`; server reuse approval
  does not authorize downloading stories for offline use.
- The catalog defaults to 2,000 entries, configurable with
  `Rover:SharedStories:MaximumEntries` (bounded to 1-10,000).

## Reliability And Observability

Atomic catalog replacement and filesystem locks protect concurrent access.
Research requests in the same starting-area/language bucket coalesce when they
share the same filesystem. Separate volumes/regions do not coordinate, and
different starting buckets can still research overlapping areas. This is a
bounded first implementation, not a distributed database.

Storage failures fall back to live research. Failed top-ups retain eligible
cached stories. A syntactically corrupt catalog is not overwritten automatically:
disable the feature, preserve the damaged file for diagnosis, and remove or
rename `stories-v1.json` before re-enabling to rebuild the library.

Structured logs report reused and researched counts without user requests or GPS
coordinates. Meter `WalkAbout.SharedStories` exposes counter
`walkabout.shared_stories.events` with outcome tags `reused`, `avoided`,
`research`, and `failure`. Connecting a metrics exporter/dashboard is separate
deployment work; production cost savings have not yet been measured.

## Verification

The local test suite covers cross-visitor persistence and route rebasing,
language/distance matching, top-ups, covered-title exclusion, source revocation,
expiry, concurrent visitors, cancellation, corrupt storage, and disabled mode.
Tests use a fake researcher and make no paid provider calls.

## Initial Policy Limits

Wikidata structured data is CC0; other namespaces are not blanket CC0:
https://www.wikidata.org/wiki/Wikidata:Copyright
License: https://creativecommons.org/publicdomain/zero/1.0/

Wikipedia text, Commons images, commercial tours, municipal pages and local news
remain ineligible for this library. Future support needs the applicable
per-content rights and attribution workflow, not simply another host name.
No source is approved based on a model's assertion of its license.

The existing Wikidata provider supplies limited place/type facts. Existing story
quality filters still apply, so this release does not promise a large cached
narrative collection or measurable research savings. General online research
remains live and its target counts are unchanged. This change does not implement
license presentation for future share-alike content or image reuse.

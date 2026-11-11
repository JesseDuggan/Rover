# Sin City Secrets import audit

16 records imported; 13 unique physical destinations; 4 core walking anchors. No records discarded. Google results checked against supplied names and street addresses using the existing Journey Lab search endpoint. Pins are provider coordinates, not field-verified pedestrian entrances.

| ID | Name | Coordinates / status | Story attached | Section |
|---|---|---|---|---|
| LVAD001 | Golden Gate Hotel & Casino | 36.1711982, -115.1462426; google_resolved | chapter_01 | core |
| LVAD002 | Binion's Gambling Hall | 36.1713278, -115.1439639; google_resolved | chapter_04 | core |
| LVAD003 | Block 16 Historic Marker | 36.1724167, -115.1442500; historical_marker_with_google_site_match | chapter_02 | core |
| LVAD004 | Arizona Club Historic Site | 36.1724167, -115.1442500; shared_historical_geofence | chapter_03 | story_only |
| LVAD005 | The Mob Museum | 36.1728198, -115.1412395; google_resolved | chapter_07 | core |
| LVAD006 | The Underground Speakeasy | 36.1728228, -115.1412524; google_resolved | chapter_08 | optional |
| LVAD007 | Roxie's Historic Brothel | No pin: original site unverified; historical_audio_only | chapter_05 | story_only |
| LVAD008 | Burlesque Hall of Fame | 36.1601374, -115.1529585; google_resolved | chapter_06 | optional |
| LVAD009 | Historic Moulin Rouge Site | 36.1775488, -115.1534498; historic_site_google_address_match | Bonus Moulin Rouge story | optional |
| LVAD010 | Erotic Heritage Museum | 36.1299776, -115.1745976; google_resolved | None supplied; explicitly shown | optional |
| LVAD011 | Absinthe at Caesars Palace | 36.1155894, -115.1740309; google_resolved | None supplied; explicitly shown | optional |
| LVAD012 | Sapphire Las Vegas | 36.1347413, -115.1715930; google_resolved | None supplied; explicitly shown | nightlife |
| LVAD013 | Spearmint Rhino Las Vegas | 36.1289282, -115.1783956; google_resolved | None supplied; explicitly shown | nightlife |
| LVAD014 | Palomino Club | 36.1932607, -115.1313079; google_resolved | None supplied; explicitly shown | nightlife |
| LVAD015 | Larry Flynt's Hustler Club | 36.0801749, -115.1827961; google_resolved | None supplied; explicitly shown | nightlife |
| LVAD016 | Peppermint Hippo Las Vegas | 36.1521729, -115.1512590; google_resolved | None supplied; explicitly shown | nightlife |

## Resolution notes
- Arizona Club shares the supplied historical Block 16 marker coordinates. The Google site pin (36.1726440, -115.1439885) is retained separately and does not replace the marker.
- Roxie’s is successfully imported as audio-only, but its original physical site remains unresolved.
- The Underground has its own Google result but shares the Mob Museum destination and map pin.
- Moulin Rouge remains a demolished historical site despite Google returning a casino category.
- Absinthe’s address matches its official operator; the incorrect Google Manufacturer category is not used.
- Chapter 06 remains preserved and is also attached to Burlesque Hall of Fame. All eight original chapter texts and the bonus narration remain unchanged.
- Optional visits are selected on the catalogue map and opened individually in Google Maps. Rideshare cards open driving directions; they do not book transport or change the walking route.
- No new narration was invented for optional destinations without supplied stories.

## Google resolution evidence

- LVAD001: Golden Gate Hotel & Casino — 1 Fremont St, Las Vegas, NV 89101, USA — `ChIJP_e37KHDyIAR972mwUmavqE` — [Google Maps](https://maps.google.com/?cid=11654922527253642743&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD002: Binion's Gambling Hall & Hotel — 128 Fremont St, Las Vegas, NV 89101, USA — `ChIJ0xi2Y6DDyIARKxjXLpR-jjI` — [Google Maps](https://maps.google.com/?cid=3642988323495417899&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD003: Site of the historic Block 16 — 206 N 1st St, Las Vegas, NV 89101, USA — `ChIJScKxQtzDyIAR8e7hXROaClY` — [Google Maps](https://maps.google.com/?cid=6199937244999053041&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD005: The Mob Museum — 300 Stewart Ave, Las Vegas, NV 89101, USA — `ChIJ6dSwgwrDyIARnTLnwBzbNVU` — [Google Maps](https://maps.google.com/?cid=6140054583531483805&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD006: The Underground Speakeasy and Distillery — 300 Stewart Ave, Las Vegas, NV 89101, USA — `ChIJY7hFmwrDyIARjhIM4XlbK4M` — [Google Maps](https://maps.google.com/?cid=9451748821991953038&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD008: Burlesque Hall of Fame — 1027 S Main St #110, Las Vegas, NV 89101, USA — `ChIJV3uZDnXDyIARWKssPy2HUlA` — [Google Maps](https://maps.google.com/?cid=5787837099527678808&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD009: Moulin Rouge Hotel & Casino — 900 W Bonanza Rd, Las Vegas, NV 89106, USA — `ChIJR1OzVgDDyIARCIscadf0AM8` — [Google Maps](https://maps.google.com/?cid=14916191171869707016&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD010: Erotic Heritage Museum — 3275 S Sammy Davis Jr Dr, Las Vegas, NV 89109, USA — `ChIJ45Bz-RDEyIAR2JvO0wuegDg` — [Google Maps](https://maps.google.com/?cid=4071427836778290136&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD011: Absinthe — 3570 S Las Vegas Blvd, Las Vegas, NV 89109, USA — `ChIJP9t9ADvEyIARtKjA3vICJP4` — [Google Maps](https://maps.google.com/?cid=18312765226937788596&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD012: Sapphire — 3025 S Sammy Davis Jr Dr, Las Vegas, NV 89109, USA — `ChIJj8bp9xXEyIARCca4_DIUblw` — [Google Maps](https://maps.google.com/?cid=6660283108148430345&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD013: Spearmint Rhino Gentlemen's Club Las Vegas — 3340 S Highland Dr, Las Vegas, NV 89109, USA — `ChIJV3syXRrEyIARRrsuX85xHHY` — [Google Maps](https://maps.google.com/?cid=8510802526997494598&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD014: Palomino Las Vegas Gentlemen's Club — 1848 Las Vegas Blvd N, North Las Vegas, NV 89030, USA — `ChIJYdREcYjDyIARIpZCszHtMjc` — [Google Maps](https://maps.google.com/?cid=3977502218638235170&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD015: Larry Flynt's Hustler Club - Las Vegas Strip Club — 6007 Dean Martin Dr, Las Vegas, NV 89118, USA — `ChIJp30iVufFyIARaODDBJgLdoo` — [Google Maps](https://maps.google.com/?cid=9977174772028792936&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)
- LVAD016: Peppermint Hippo — 1531 S Las Vegas Blvd, Las Vegas, NV 89104, USA — `ChIJV1rlcgfDyIAR0lHAxrlktBw` — [Google Maps](https://maps.google.com/?cid=2068388877936120274&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA)

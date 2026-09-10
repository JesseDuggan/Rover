# ROVER Phase 11 Camera Commerce Checkpoint

## Delivered

- Camera Explorer identifies lodging candidates from verified place category and name data.
- A `Check rates` action appears only for lodging candidates.
- The user explicitly confirms check-in, check-out, adult, and room counts before a request is sent.
- Flutter and middleware use typed hotel-rate request, response, offer, status, and disclosure contracts.
- Rate offers are ordered by total amount, with tax-and-fee-inclusive offers preferred when totals match.
- Every offer supports provider and affiliate disclosure text.
- Camera Commerce activity is recorded in field and performance diagnostics without logging stay details or booking links.

## Current Provider State

No live booking provider is configured. The middleware returns `ProviderUnavailable` with zero offers and an explicit statement that ROVER did not estimate or fabricate a price. This is expected behavior until a commercial provider adapter and credentials are approved.

## Identification Boundary

This checkpoint uses ROVER's geospatial Camera Explorer candidates. It does not upload camera frames and does not claim camera-pixel recognition. A future visual-recognition provider can strengthen hotel identity through the existing explicit-capture boundary before rate search.

## Provider Adapter Requirements

A live adapter must implement `IHotelRateProvider` and return only current, bookable offers. It must:

- resolve the property confidently from provider place ID, name, and coordinates;
- return `AmbiguousProperty` instead of guessing when identity is uncertain;
- return total price for the full stay and state whether taxes and fees are included;
- include freshness, provider, cancellation/refundability, booking URL, and affiliate disclosure;
- avoid background rate searches and camera-frame uploads;
- honor provider terms, rate limits, attribution, privacy, and regional requirements.

## Field Validation

1. Point Camera Explorer at a hotel or inn candidate and select its label.
2. Confirm `Check rates` appears; confirm it does not appear for cafes or stores.
3. Open the sheet and change dates, adults, and rooms.
4. Select `Search rates`.
5. With the default configuration, confirm the polite unavailable message appears and no price is shown.
6. Confirm Camera Explorer remains active after closing the sheet.

## Next Decision

Select a booking partner and commercial model before implementing a live adapter. Compare geographic coverage, property-ID matching, taxes-and-fees semantics, deep-link support, affiliate disclosure rules, sandbox access, and production approval lead time.

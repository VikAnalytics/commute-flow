# CommuteFlow (SwiftUI, iOS 17+)

CommuteFlow is a native iOS app concept focused on transit-first property discovery:
- Apartments near a workplace with commute-aware sorting.
- Tourist stays (hotels/Airbnbs) ranked by transit access to major attractions.

This repo now supports live Google APIs (Places + Directions) with mock fallback when no API key is configured.

## What's implemented

- Clean MVVM structure (`Models`, `Services`, `ViewModels`, `Views`).
- App-level dependency injection in `Core` (`AppDependencies`, `LiveAppDependencies`).
- Protocol-driven service boundary (`TransitProviding`) for easy API replacement.
- Async loading + error handling with `LoadState` (`idle/loading/loaded/failed`).
- Split-screen layout:
  - Top: interactive `MapKit` map with route polylines.
  - Bottom: scrollable property cards with pricing, commute, and CTA button.
- Apartment screen:
  - Workplace field prefilled with `NCR Headquarters, Spring St NW`.
  - Mock properties including:
    - The Standard at Midtown
    - Skyhouse Buckhead
  - Sorting: Fastest Commute, Cheapest, Least Walking.
- Travel screen:
  - City field defaulted to Atlanta.
  - Major hubs:
    - Ponce City Market
    - Georgia Aquarium
    - Mercedes-Benz Stadium
  - Tourist stays with `Tourist Connectivity Score` (0-100).
- Live API integration in `TransitService`:
  - Google Places Nearby Search for apartments/hotels
  - Google Directions (transit mode) for commute times and route polylines
  - Place Details for provider website links

## File entry points

- App root: `CommuteFlow/CommuteFlowApp.swift`
- Tabs: `CommuteFlow/Views/RootTabView.swift`
- Transit service + Atlanta mock data: `CommuteFlow/Services/TransitService.swift`
- Dependency setup: `CommuteFlow/Core/AppDependencies.swift`
- Architecture notes: `ARCHITECTURE.md`

## Run in Xcode (recommended)

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   - `brew install xcodegen`
2. From repo root, generate project:
   - `xcodegen generate`
3. Open `CommuteFlow.xcodeproj` in Xcode.
4. Select an iPhone simulator and run.

## Configure real APIs (safe local setup)

CommuteFlow reads your Google key from either:
- Scheme environment variable: `COMMUTEFLOW_GOOGLE_API_KEY`
- Info.plist key: `COMMUTEFLOW_GOOGLE_API_KEY`

Optional backend proxy URL:
- `COMMUTEFLOW_BACKEND_BASE_URL` (e.g., `https://api.yourdomain.com`)

Recommended setup using xcconfig files:
1. Create `Config/Secrets.xcconfig`
2. Add your key:
   - `COMMUTEFLOW_GOOGLE_API_KEY=YOUR_KEY`
3. Regenerate project:
   - `xcodegen generate`
4. Run app in Debug

For local Release wiring, copy:
- `Config/ReleaseSecrets.example.xcconfig` -> `Config/ReleaseSecrets.xcconfig`
- set `COMMUTEFLOW_BACKEND_BASE_URL` to your Railway domain

`Config/Secrets.xcconfig` is gitignored and will not be committed.

## Production safety defaults

- Debug builds: direct Google API calls enabled (`COMMUTEFLOW_ALLOW_DIRECT_GOOGLE=YES`)
- Release builds: direct Google API calls disabled (`COMMUTEFLOW_ALLOW_DIRECT_GOOGLE=NO`)
- Release default prevents shipping client-side provider usage by accident.
- If `COMMUTEFLOW_BACKEND_BASE_URL` is set, app attempts backend endpoints first:
  - `POST /api/v1/apartments/search`
  - `POST /api/v1/travel/stays`

For production, route these calls through your backend proxy and keep provider keys server-side.

Required Google APIs to enable in Google Cloud:
- Places API
- Directions API
- Place Details API (same Places platform)

## Tests

- Unit tests included under `CommuteFlowTests` for live/fallback transit behavior.
- Run tests from Xcode with `Cmd+U`.

## Backend proxy service (production path)

Backend code lives in `backend/`.

### Local backend run

1. Create env file:
   - `cp backend/.env.example backend/.env`
2. Set `GOOGLE_MAPS_API_KEY` in `backend/.env`
3. Start backend:
   - `cd backend`
   - `npm run dev`
4. Health check:
   - `GET http://localhost:8080/healthz`

### Wire iOS app to backend

Set iOS build setting / env:
- `COMMUTEFLOW_BACKEND_BASE_URL=http://localhost:8080` (local)
- `COMMUTEFLOW_BACKEND_BASE_URL=https://api.yourdomain.com` (prod)

### API contract docs

- OpenAPI spec: `docs/backend-openapi.yaml`
- Release checklist: `docs/appstore-release-checklist.md`
- Railway deployment guide: `docs/railway-production-guide.md`

## Run in Xcode (manual fallback)

1. Create a new **iOS App** project in Xcode (SwiftUI, iOS 17+), named `CommuteFlow`.
2. Drag the `CommuteFlow` folder from this repo into your Xcode project navigator.
3. Ensure all files are added to the app target.
4. Build and run.

## Next integration steps

- Add user auth and per-user saved/favorite sync in backend.
- Add Redis cache for route/place responses.
- Add backend integration tests and synthetic uptime checks.
- Add Sentry/Datadog for backend + iOS runtime monitoring.

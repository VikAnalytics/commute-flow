# CommuteFlow Architecture

CommuteFlow uses a production-oriented, modular architecture that supports fast iteration now and controlled scale later.

## System Overview

CommuteFlow has two runtime paths:

1. **Client-direct path (Debug-friendly)**
   - iOS app calls Google Places/Directions APIs directly through `TransitService`.
2. **Backend-proxy path (Production-oriented)**
   - iOS app calls backend (`backend/`) endpoints.
   - Backend calls Google APIs server-side and returns normalized property/journey payloads.

The app prefers backend when `COMMUTEFLOW_BACKEND_BASE_URL` is configured.

## iOS Architecture

### 1) Composition Layer (`Core`)

- `AppDependencies` and `LiveAppDependencies` provide dependency injection at app root.
- `RootTabView` receives dependencies and passes services to features.

### 2) Presentation Layer (`Views` + `ViewModels`)

- SwiftUI views are UI-only: rendering, user input, and card/map interaction.
- View models (`ApartmentSearchViewModel`, `TravelConnectivityViewModel`) own:
  - load lifecycle via `LoadState` (`idle`, `loading`, `loaded`, `failed`)
  - filtering and sorting state
  - async orchestration with `TransitProviding`

### 3) Domain/Data Layer (`Models` + `Services`)

- Core models:
  - `Property`
  - `TouristHub`
  - sort/filter enums
- `Property` carries both compact and rich route metadata:
  - estimated commute time
  - `commuteBreakdown`
  - detailed `journeySegments`
  - optional polyline coordinates for map rendering
- `TransitProviding` is the service boundary.
- `TransitService` implements:
  - address/city resolution
  - live provider fetches
  - backend fetches
  - fallback generation
  - retry/backoff and analytics hooks

### 4) Persistence Layer (SwiftData)

- `RecentSearch` and `SavedProperty` are stored locally.
- Saved properties persist route metadata including journey segments.

## Backend Architecture (`backend/`)

### Stack

- Node.js + Express + TypeScript
- Zod request validation
- Axios Google client wrapper
- Helmet, CORS, rate limiting, structured logging

### Endpoints

- `GET /healthz`
- `POST /api/v1/apartments/search`
- `POST /api/v1/travel/stays`

### Response Contract

Backend returns normalized property objects with:

- pricing/rating metadata
- route timing
- polyline coordinates
- detailed journey segments (line/vehicle/headsign/stops when available)

## Interaction Flow

1. User enters workplace or city.
2. ViewModel calls `TransitProviding`.
3. Service resolves location context and fetches properties.
4. ViewModel applies local filters/sorts.
5. UI renders compact cards.
6. On card tap, UI reveals expanded journey segments and updates map focus/route overlays.

## Reliability + Safety

- Retry/backoff for transient upstream failures.
- Fallback mode when live providers fail or keys are unavailable.
- Release defaults disable direct client provider calls by default.
- Secrets are kept out of tracked config and intended for local/env injection.

## Scalability Roadmap

1. Add repository layer to merge providers and cache route matrices.
2. Introduce server-side caching (Redis) for repeated routes/place details.
3. Add user-level personalization and saved search sync.
4. Expand observability (metrics, traces, alerting).
5. Split feature modules further as product surface grows.

# CommuteFlow Architecture

This project is set up to stay simple now and scale later.

## Current architecture (already implemented)

- **UI Layer (`Views`)**
  - SwiftUI screens and reusable card/map components.
  - No network logic in views.
- **Presentation Layer (`ViewModels`)**
  - Holds UI state (`idle`, `loading`, `loaded`, `failed`).
  - Calls services using async methods.
  - Handles sorting and screen-level presentation logic.
- **Domain/Data Layer (`Models`, `Services`)**
  - `Property`, `TouristHub`, and sort enums.
  - `TransitProviding` protocol for API abstraction.
  - `TransitService` supports live Google Places/Directions + mock fallback.
  - Optional backend proxy integration via `COMMUTEFLOW_BACKEND_BASE_URL`.
  - Built-in retry/backoff for transient provider/network errors.
  - Basic analytics hooks for API success/failure/fallback events.
- **Backend Layer (`backend/`)**
  - Express + TypeScript proxy service with schema validation.
  - Endpoints for apartments and travel stays backed by Google APIs.
  - Rate limiting, structured logging, and health checks.
- **Composition Layer (`Core`)**
  - `AppDependencies` and `LiveAppDependencies`.
  - Centralized dependency injection for swapping mocks/live APIs.

## Why this is future-proof

- Protocol-based service contracts allow replacing implementations without touching UI.
- Async API boundaries (`async throws`) support real network work and retry behavior.
- Central DI container keeps test and production wiring clean.
- Load-state model avoids fragile boolean combinations in view models.
- Release-safe defaults prevent accidental direct provider usage in production.
- Test target validates live-mode and fallback-mode behavior.

## Next scalable milestones

1. Add backend proxy endpoints and move provider keys fully server-side.
2. Add listing providers (apartments/hotels) behind protocols.
3. Introduce a repository layer to merge transit + listing data.
4. Add caching (memory + persistent) for route matrix responses.
5. Add unit tests for view models and API adapters.
6. Add feature modules as the app grows (e.g., `ApartmentsFeature`, `TravelFeature`).

# CommuteFlow Setup Guide

This document contains all local setup, API wiring, and deployment-oriented run instructions.

## Prerequisites

- macOS with Xcode
- Homebrew
- Node.js 20+ and npm

Install XcodeGen:

- `brew install xcodegen`

## iOS App Setup

1. Generate the project:
   - `xcodegen generate`
2. Open `CommuteFlow.xcodeproj` in Xcode.
3. Select an iPhone simulator.
4. Run the app.

## API Configuration (Safe Local)

CommuteFlow reads runtime values from environment variables or Info.plist keys:

- `COMMUTEFLOW_GOOGLE_API_KEY`
- `COMMUTEFLOW_BACKEND_BASE_URL` (optional)

Recommended local approach:

1. Create `Config/Secrets.xcconfig`
2. Add:
   - `COMMUTEFLOW_GOOGLE_API_KEY=YOUR_KEY`
   - `COMMUTEFLOW_BACKEND_BASE_URL=http://localhost:8080` (optional)
3. Regenerate project:
   - `xcodegen generate`
4. Run in Debug.

For release/local production wiring, create:

- `Config/ReleaseSecrets.xcconfig`

With:

- `COMMUTEFLOW_BACKEND_BASE_URL=https://your-railway-domain.up.railway.app`

`Config/Secrets.xcconfig` and `Config/ReleaseSecrets.xcconfig` should remain untracked.

## Backend Setup (Proxy Service)

Backend code lives in `backend/`.

1. Copy env template:
   - `cp backend/.env.example backend/.env`
2. Set provider key in `backend/.env`:
   - `GOOGLE_MAPS_API_KEY=YOUR_SERVER_KEY`
3. Start backend:
   - `cd backend`
   - `npm install`
   - `npm run dev`
4. Verify health:
   - `http://localhost:8080/healthz`

## Wire App to Backend

Set:

- `COMMUTEFLOW_BACKEND_BASE_URL=http://localhost:8080` (local)
- `COMMUTEFLOW_BACKEND_BASE_URL=https://your-railway-domain.up.railway.app` (prod)

When backend URL is present, app attempts backend endpoints first:

- `POST /api/v1/apartments/search`
- `POST /api/v1/travel/stays`

## Build Safety Defaults

- Debug builds: direct Google calls enabled by default.
- Release builds: direct Google calls disabled by default.

This protects against accidentally shipping client-side provider usage in production.

## Required Google APIs

- Places API
- Directions API
- Place Details API

## Testing

- iOS unit tests: `CommuteFlowTests`
- Run from Xcode with `Cmd+U`
- Backend checks:
  - `npm run typecheck`
  - `npm run build`

## Deployment References

- OpenAPI: `docs/backend-openapi.yaml`
- Railway guide: `docs/railway-production-guide.md`
- App Store checklist: `docs/appstore-release-checklist.md`

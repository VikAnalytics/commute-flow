# CommuteFlow App Store Checklist

## Backend and security

- [ ] Deploy backend service with HTTPS (TLS 1.2+).
- [ ] Store `GOOGLE_MAPS_API_KEY` only on backend.
- [ ] Set iOS `COMMUTEFLOW_ALLOW_DIRECT_GOOGLE=NO` for Release.
- [ ] Set iOS `COMMUTEFLOW_BACKEND_BASE_URL=https://api.yourdomain.com`.
- [ ] Enable backend rate limiting and request logs.
- [ ] Add monitoring/alerts (latency, 5xx rate, quota usage).

## iOS release readiness

- [ ] Remove or hide all debug-only UI.
- [ ] Confirm fallback behavior when backend is unavailable.
- [ ] Test on multiple devices/simulators.
- [ ] Add Privacy Manifest entries for network use if required.
- [ ] Fill App Privacy labels in App Store Connect.
- [ ] Add localized App Store screenshots and metadata.

## Quality gates

- [ ] `Cmd+U` test suite passes in CI.
- [ ] Release build succeeds without direct Google usage.
- [ ] Smoke test apartment/travel/saved flows.
- [ ] Validate key user paths with no crashes.

## Submission

- [ ] Archive in Xcode (Release config).
- [ ] Upload build to App Store Connect.
- [ ] Complete TestFlight internal testing.
- [ ] Submit for App Review.

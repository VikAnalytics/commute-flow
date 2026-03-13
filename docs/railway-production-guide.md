# Railway Production Guide

## 1) Push repository to GitHub

- Ensure `.env` and `Config/Secrets.xcconfig` are not committed.
- Push current branch to your GitHub repo.

## 2) Create Railway project

1. Login to Railway.
2. Create project from GitHub repo.
3. Railway should detect `railway.toml` and build using `backend/Dockerfile`.

## 3) Set Railway environment variables

Required:
- `GOOGLE_MAPS_API_KEY` = backend server key
- `NODE_ENV` = `production`
- `PORT` = `8080`

Recommended:
- `ALLOWED_ORIGINS` = your app/web origins (comma-separated)

## 4) Verify deployment

- Open deployed URL: `https://<railway-domain>/healthz`
- Expect: `{"status":"ok","service":"commuteflow-backend","env":"production"}`

## 5) Wire iOS app to production backend

Set Release config:
- `COMMUTEFLOW_BACKEND_BASE_URL=https://<railway-domain>`
- `COMMUTEFLOW_ALLOW_DIRECT_GOOGLE=NO`

Debug can still use local backend URL when needed.

## 6) Production smoke checks

- Apartments search returns non-mock properties.
- Travel search returns non-mock stays.
- Saved/favorites still function.
- When backend is unavailable, app fallback behavior is user-safe.

## 7) Security checklist

- Use dedicated backend Google key (not iOS key).
- Restrict backend key by API and Railway egress rules if available.
- Enable billing alerts and quota limits in Google Cloud.
- Rotate keys periodically.

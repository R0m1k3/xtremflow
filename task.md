# Fix Docker Database & Proxy Issues

## Context

1. SQLite database read-only error on login (permissions)
2. Xtream proxy 401 Unauthorized errors

## Master Plan

- [x] Analyze database readonly error → volume permissions mismatch
- [x] Create `entrypoint.sh` with gosu for privilege drop
- [x] Update `Dockerfile` to use entrypoint
- [x] Analyze proxy 401 errors → broken mount in apiRouter
- [x] Remove duplicate `/api/xtream` mount from `server.dart`
- [ ] Rebuild and deploy

## Changes Made

- `entrypoint.sh`: Fixes /app/data permissions at startup, then runs as xtremuser
- `Dockerfile`: Added gosu, ENTRYPOINT, removed USER directive
- `server.dart`: Removed broken /api/xtream mount that was blocking proxy

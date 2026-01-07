# Fix Docker & Proxy Issues

## Completed

- [x] Database permissions (`entrypoint.sh` + `Dockerfile`)
- [x] Proxy 401 errors (removed broken mount in `server.dart`)
- [x] Proxy chunked encoding error (buffered response in `proxy_handler.dart`)

## Changes

| File | Change |
|------|--------|
| `entrypoint.sh` | NEW - fixes /app/data permissions, runs as xtremuser via gosu |
| `Dockerfile` | Added gosu, ENTRYPOINT |
| `bin/server.dart` | Removed broken /api/xtream mount, added logging |
| `bin/api/proxy_handler.dart` | Changed from streaming to buffered response |

## Deploy

```bash
git add .
git commit -m "fix: database permissions + proxy errors"
git push && docker compose up --build -d
```

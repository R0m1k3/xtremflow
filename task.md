# Fix Docker Database Permissions

## Context

SQLite database in Docker container is read-only due to volume permissions mismatch between root and xtremuser.

## Current Focus

Implementation complete - ready for rebuild and deploy.

## Master Plan

- [x] Analyze the error and identify root cause
- [x] Create entrypoint.sh script to fix permissions at startup
- [x] Update Dockerfile to use entrypoint script with gosu
- [ ] Rebuild and deploy to test

## Progress Log

- Identified `SqliteException(8): attempt to write a readonly database` error
- Root cause: Docker volume created with different permissions than xtremuser
- Created `entrypoint.sh` with chown fix and gosu privilege drop
- Updated Dockerfile: added gosu, ENTRYPOINT, removed USER directive

# XtremFlow Development

Context: Developing a high-performance IPTV Web App with Flutter and Docker.

Current Focus: Resuming development after environment fix.

Master Plan:

## 🧹 Housekeeping

- [x] Commit pending changes in `xtream_service.dart` (Timeout increase).

## 🎥 Player Debugging (CRITICAL)

- [ ] **Fix VOD Playback**: User reports VOD is not playing.
  - [x] Check VOD URL generation in `xtream_service.dart`. (Fixed upstream URL to include extension)
  - [x] Check `web/player.html` compatibility with VOD formats. (HLS/Direct support verified)
  - [x] Verify `PlayerScreen` logic for VOD StreamType. (Correctly passes extension)
  - [x] Update `streaming_handler.dart` to handle extensions dynamically. (Done)
    - [x] Rebuild Docker Image to apply backend changes.
    - [x] Restart Docker containers.
    - [x] Verify VOD playback. (Failed)
    - [ ] **Phase 2 Debugging**:
      - [x] Analyze Docker logs for FFmpeg/Proxy errors. (Found 404/4XX on MKV)
      - [x] Implement backend auto-detection of extension via Xtream API.
        - [x] Restart Docker containers.
        - [x] Restart Docker containers.
        - [x] Verify VOD playback. (Backend Fallback active)
    - [ ] **Clean Reinstall** (User Request):
      - [x] Stop and Remove Containers (`down`).
      - [/] Force Rebuild and Start (`up --build`).

## 🎥 Player Improvements (Active Context)

- [ ] Review `player_screen.dart` controls logic.
- [ ] **Goal**: Enhance VOD/Series controls vs Live TV controls.
  - *Context*: User wants skip/prev buttons to change channels only for Live TV? Need clarification on VOD behavior.

## 📦 Backlog

- [x] Resolve ModuleNotFoundError: No module named 'rich' (Done)
- [x] Update Docker Image (Timeout increase)

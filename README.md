# XtremFlow - IPTV Web Application

High-performance, containerized IPTV Web Application using Flutter Web and Xtream Codes API.

## Features

✅ **Local Authentication System**
- Default admin user (`admin`/`admin`)
- Secure salt-based password hashing (SHA-256)
- No public signup - private app only

✅ **Multi-Playlist Management**
- Centralized Xtream credentials management
- Playlist assignment to users
- Easy switching between playlists

✅ **High-Performance Dashboard (60fps)**
- Category-based pagination (100 items/page for Live TV, 50 for Movies)
- Lazy loading with `ListView.builder` / `GridView.builder`
- Image caching with `cached_network_image`

✅ **Live TV with EPG**
- Electronic Program Guide (EPG) overlay
- "Now & Next" program display
- Real-time progress bar

✅ **VOD & Series**
- Movies and Series organized by categories
- Grid layout with posters
- Optimized ratings display (1 decimal place)

✅ **Docker Deployment**
- Multi-stage build with Flutter and Dart
- Custom Dart Server (`bin/server.dart`)
- **FFmpeg Transcoding** for mobile compatibility
- **Cache Management** system for temporary files
- External network support (`nginx_default`)

## Tech Stack

- **Framework**: Flutter Web
- **State Management**: Riverpod
- **Local Database**: Hive (Web IndexedDB) with AES encryption
- **Networking**: Dio with cache interceptors
- **Routing**: GoRouter with auth guards
- **Video Player**: `video_player` + `chewie`
- **UI**: Google Fonts, Material Design 3

## Prerequisites

- Docker & Docker Compose
- Existing `nginx_default` network (for reverse proxy routing)
- Flutter SDK (for local development only)

## Quick Start (Docker)

### 1. Build the Docker image

```bash
docker-compose build
```

### 2. Start the container

```bash
docker-compose up -d
```

### 3. Access via reverse proxy

Configure your reverse proxy (Nginx/Traefik) to route traffic to:
- **Container**: `xtremflow`
- **Internal Port**: `8080`
- **Network**: `nginx_default`

Example Nginx configuration:

```nginx
location /iptv {
    proxy_pass http://xtremflow:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### 4. Login

- **URL**: `http://your-domain/iptv`
- **Default Credentials**:
  - Username: `admin`
  - Password: `admin`

⚠️ **Change the admin password immediately after first login!**

## Local Development

### Install dependencies

```bash
flutter pub get
```

### Generate Hive adapters (if modified)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Run web app

```bash
flutter run -d chrome
```

## Project Structure

```
lib/
├── core/
│   ├── database/
│   │   └── hive_service.dart          # Hive initialization & encryption
│   ├── models/
│   │   ├── app_user.dart              # User model (Hive)
│   │   ├── playlist_config.dart       # Playlist credentials (Hive)
│   │   └── iptv_models.dart          # Channel, VOD, Series, EPG models
│   ├── router/
│   │   └── app_router.dart           # GoRouter configuration
│   └── utils/
│       └── crypto_utils.dart         # Password hashing utilities
├── features/
│   ├── auth/
│   │   ├── providers/
│   │   │   └── auth_provider.dart    # Authentication state
│   │   └── screens/
│   │       └── login_screen.dart
│   ├── admin/
│   │   └── screens/
│   │       └── admin_panel.dart      # User & Playlist CRUD
│   └── iptv/
│       ├── services/
│       │   └── xtream_service.dart   # Xtream API client
│       ├── providers/
│       │   └── xtream_provider.dart  # Riverpod providers
│       ├── screens/
│       │   └── player_screen.dart    # Video player
│       └── widgets/
│           ├── live_tv_tab.dart      # Live TV with pagination
│           ├── movies_tab.dart       # Movies grid
│           ├── series_tab.dart       # Series grid
│           └── epg_overlay.dart      # EPG display
└── main.dart
```

## Security Features

### Password Storage
- **Algorithm**: SHA-256 with random UUID-based salt
- **Format**: `salt:hash` (stored in Hive)
- **Legacy Support**: Fallback to unsalted comparison for migration

### Database Encryption
- **Hive AES Cipher** (256-bit key)
- Key stored in `FlutterSecureStorage`
- Automatic key generation on first run

### Authentication Flow
1. User enters credentials
2. System retrieves stored hash
3. Input password is hashed with same salt
4. Constant-time comparison prevents timing attacks

## Performance Optimizations

### Memory Management (20k+ channels)
- **Grouping**: Channels organized by category
- **Pagination**: 100 items per page (Live TV), 50 per page (Movies)
- **Lazy Loading**: Only render visible items
- **Image Caching**: Disk/memory cache with `cached_network_image`

### Network Optimization
- **Dio Cache Interceptor**: 1-hour cache for API responses
- **EPG Cache**: 5-minute refresh for program data
- **Hive Disk Store**: Persistent cache across sessions

### Rendering (60fps Target)
- `ListView.builder` with fixed `itemExtent`
- `AutomaticKeepAliveClientMixin` for tab state
- Expansion panels for category navigation
- Grid with fixed `crossAxisCount` and `childAspectRatio`

## Xtream API Integration

### Supported Endpoints

| Endpoint | Purpose | Caching |
|----------|---------|---------|
| `player_api.php` | Authentication | 1 hour |
| `get_live_streams` | Live TV channels | 1 hour |
| `get_vod_streams` | Movies | 1 hour |
| `get_series` | Series | 1 hour |
| `get_short_epg` | EPG data | 5 minutes |

### Stream URL Formats

```dart
// Live TV
http://[dns]/live/[username]/[password]/[stream_id].m3u8

// Movies
http://[dns]/movie/[username]/[password]/[stream_id].[container_extension]

// Series
http://[dns]/series/[username]/[password]/[stream_id].[container_extension]
```

## Docker Configuration

### Dockerfile (Multi-Stage)

**Stage 1: Builder**
- Base: `cirrusci/flutter:stable`
- Build: `flutter build web --release --web-renderer html`

**Stage 2: Runtime**
- Base: `dart:stable`
- Server: `dhttpd --host 0.0.0.0 --port 8080`
- Size: ~150MB (compressed)

### docker-compose.yml

```yaml
services:
  iptv-web:
    build: .
    container_name: xtremflow
    restart: unless-stopped
    networks:
      - nginx_default

networks:
  nginx_default:
    external: true
```

**No port mapping** - Access via reverse proxy only.

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs xtremflow

# Verify network exists
docker network ls | grep nginx_default

# Create network if missing
docker network create nginx_default
```

### Login fails with admin/admin
- Check Hive database initialization in logs
- Verify `HiveService.init()` completed successfully
- Default admin is seeded only if `users` box is empty

### EPG not displaying
- EPG is optional and gracefully degrades
- Check if Xtream server supports `get_short_epg`
- Verify stream has `epg_channel_id`

### Performance issues (FPS drops)
- Reduce `_itemsPerPage` constant (currently 100 for Live TV)
- Disable image caching temporarily
- Check browser DevTools Performance tab

## License

Proprietary - Private Use Only

## Support

For Xtream API documentation, consult your IPTV provider.

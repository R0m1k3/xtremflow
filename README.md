# XtremFlow IPTV Web Application

High-performance Flutter Web IPTV application with Xtream Codes API integration, local authentication, and Docker deployment.

## Features

- **Local Authentication**: Private admin panel (default: `admin/admin`)
- **Multi-Playlist Support**: Manage multiple Xtream providers
- **Admin Panel**: Full CRUD for users and playlists
- **Live TV / Movies / Series**: Lazy-loaded grids with infinite scroll
- **Memory Optimized**: Handles 20k+ channels without freezing
- **Docker Deployment**: Single command deployment with external network support

## Quick Start

### Local Development (Requires Flutter SDK)

```bash
# Install dependencies
flutter pub get

# Run web app
flutter run -d chrome
```

### Docker Deployment

```bash
# Build and run
docker-compose up -d

# View logs
docker-compose logs -f iptv-web
```

**Prerequisites**:
- Docker external network `nginx_default` must exist
- Configure reverse proxy to route traffic to container

## Default Credentials

- Username: `admin`
- Password: `admin`

**Important**: Change default password after first login via Admin Panel.

## Architecture

- **Frontend**: Flutter Web (CanvasKit renderer)
- **State Management**: Riverpod
- **Database**: Hive with AES encryption
- **Networking**: Dio with caching
- **Video Player**: MediaKit
- **Deployment**: Multi-stage Docker with dhttpd

## Admin Panel

Access at `/admin` route (admin users only):
- Create/Edit/Delete users
- Manage Xtream playlist credentials
- Assign playlists to users

## Performance

- 60fps target with CanvasKit renderer
- Pagination: 100 items per request
- Image caching with `cached_network_image`
- Request caching: 10-minute TTL

## Security

- SHA-256 password hashing
- AES-256 Hive encryption
- Secure storage for encryption keys
- No credentials in code

## License

Private use only.

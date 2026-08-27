# XtremFlow — Application Web IPTV

Application IPTV auto-hébergée : frontend Flutter Web + serveur Dart natif, empaquetés dans une seule image Docker. Se connecte à un abonnement Xtream Codes et ajoute le magnétoscope (enregistrements planifiés, season passes), l'EPG avec repli XMLTV, et le transcodage FFmpeg à la demande.

## Fonctionnalités

- **Live TV, Films, Séries** : catalogues Xtream avec catégories, recherche, favoris, reprise de lecture
- **Guide TV (EPG)** : panneau de l'abonné en priorité, repli automatique sur un dump XMLTV quand le panneau est figé
- **Enregistrements TV** : planification depuis le guide, capture FFmpeg (`-c copy`), reprise après coupure amont ou redémarrage du serveur, fusion automatique des parties
- **Season Passes** : enregistrement automatique de toutes les diffusions d'une émission (scan EPG toutes les 4 h)
- **Transcodage à la demande** : `source | high | medium | low` (live et VOD), `source` = zéro transcodage ; NVENC optionnel
- **Multi-utilisateurs** : comptes locaux (bcrypt), playlists par utilisateur, panneau d'administration

## Stack

| Couche | Techno |
|---|---|
| Frontend | Flutter Web (Riverpod, GoRouter), players HTML (hls.js / mpegts.js vendorisés) |
| Backend | Dart compilé en natif (`dart compile exe`), shelf |
| Base | SQLite côté serveur (`/app/data/xtremflow.db`) |
| Capture/Transcodage | FFmpeg (build BtbN, NVENC inclus) |
| Conteneur | Debian slim multi-stage, port **8089** |

## Démarrage rapide (Docker)

```bash
docker-compose up -d --build
# Application sur http://localhost:8089
```

Au premier démarrage, un compte `admin` est créé avec un **mot de passe aléatoire affiché une seule fois dans les logs** (`docker logs xtremflow`), sauf si `ADMIN_INITIAL_PASSWORD` est défini. Changez-le après la première connexion.

### Variables d'environnement (docker-compose.yml)

| Variable | Défaut | Rôle |
|---|---|---|
| `RECORDINGS_PATH` | `./data/recordings` | Dossier hôte des enregistrements |
| `TZ` | `Europe/Paris` | Fuseau du conteneur (les enregistrements sont stockés en UTC) |
| `MAX_CONCURRENT_RECORDINGS` | `2` | Enregistrements simultanés |
| `EPG_XMLTV_URLS` | dump FR | Sources XMLTV de repli (vide = aucun appel sortant) |
| `NVIDIA_GPU` | `false` | Transcodage NVENC |
| `ADMIN_INITIAL_PASSWORD` | *(généré)* | Mot de passe initial du compte admin |
| `MIN_FREE_DISK_MB` | `500` | Espace libre minimal pour démarrer une capture |
| `RECORDINGS_QUOTA_GB` | `0` (off) | Quota du dossier d'enregistrements (rotation des plus anciens terminés) |
| `TRUSTED_PROXIES` | loopback + RFC1918 | IPs de reverse proxy dont `X-Forwarded-For` est honoré |

## Développement local

```bash
# Frontend
flutter pub get
flutter analyze && flutter test
flutter run -d chrome        # nécessite le backend lancé pour les routes /api

# Backend
cd bin
dart pub get
dart analyze && dart test
dart run server.dart --port 8089 --path ../build/web
```

Le build Windows natif est documenté dans `BUILD.md`.

## Structure du projet

```
bin/                    Serveur Dart
├── server.dart         Point d'entrée, routage, arrêt gracieux
├── api/                Handlers HTTP (auth, playlists, recordings, EPG, proxy…)
├── services/           Scheduler d'enregistrement, sessions FFmpeg, XMLTV
├── database/           SQLite (schéma, migrations)
├── middleware/         Auth (session), sécurité (rate limit, honeypot, logs redactés)
└── test/               Tests backend (dart test)

lib/                    Frontend Flutter
├── core/               Modèles, thème, router, clients API
├── features/           auth / admin / iptv (desktop)
└── mobile/             Variantes d'écrans mobiles

web/                    Players HTML + libs vendorisées (hls.js, mpegts.js)
```

## Sécurité

- Mots de passe **bcrypt** (migration lazy depuis les anciens hashes au login)
- Les credentials Xtream ne quittent jamais le serveur : passerelle `/api/xtream-api` et proxy `/api/xtream` (authentifié par session) avec injection côté serveur
- Redaction des credentials dans tous les logs ; anti-SSRF avec revalidation des redirections
- Cookie de session HttpOnly ; rate limiting global + limite de tentatives de login par IP

## CI / Publication

`ci.yml` (analyze + tests + build web/backend) tourne sur chaque PR et push main ; `docker-publish.yml` publie `ghcr.io/r0m1k3/xtremflow:latest` **uniquement après une CI verte** sur main.

## Dépannage

- **Logs** : `docker logs xtremflow` (les URLs y sont redactées)
- **Mot de passe admin perdu** : supprimer le volume `xtremflow-data` recrée la base et affiche un nouveau mot de passe (⚠ efface utilisateurs et historique d'enregistrements)
- **EPG vide** : vérifier `EPG_XMLTV_URLS` et que la chaîne a un `epg_channel_id` ; l'en-tête `X-Epg-Source` des réponses `/api/epg/<id>` indique la source utilisée
- **Enregistrement échoué** : bouton « Logs » sur la ligne de l'enregistrement ; la raison (`error_reason`) est affichée sous le titre

## Licence

Propriétaire — usage privé uniquement.

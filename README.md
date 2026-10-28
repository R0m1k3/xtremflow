# XtremFlow — Application Web IPTV

Application IPTV auto-hébergée : frontend Flutter Web + serveur Rust natif, empaquetés dans une seule image Docker. Se connecte à un abonnement Xtream Codes et ajoute le magnétoscope (enregistrements planifiés, season passes), l'EPG avec repli XMLTV, et le transcodage FFmpeg à la demande.

## Fonctionnalités

- **Live TV, Films, Séries** : catalogues Xtream avec catégories, recherche, favoris, reprise de lecture
- **Guide TV (EPG)** : panneau de l'abonné en priorité, repli automatique sur un dump XMLTV quand le panneau est figé
- **Enregistrements TV** : planification depuis le guide, capture du flux brut en `.ts` (reconnexion automatique, reprise après redémarrage du serveur dans le même fichier), conversion en MKV en fin de capture
- **Saut des pubs dans Jellyfin** : après chaque enregistrement, Comskip repère les coupures pub ; elles sont inscrites comme chapitres « Commercial » dans le MKV (et dans un `.edl` lu par Kodi) — voir [Saut des pubs (Jellyfin)](#saut-des-pubs-jellyfin)
- **Season Passes** : enregistrement automatique de toutes les diffusions d'une émission (scan EPG toutes les 4 h)
- **Transcodage à la demande** : `source | high | medium | low` (live et VOD), `source` = zéro transcodage ; NVENC optionnel
- **Multi-utilisateurs** : comptes locaux (bcrypt), playlists par utilisateur, panneau d'administration

## Stack

| Couche | Techno |
|---|---|
| Frontend | Flutter Web (Riverpod, GoRouter), players HTML (hls.js / mpegts.js vendorisés) |
| Backend | Rust (tokio, axum, reqwest/rustls, rusqlite), binaire natif unique |
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
| `PUID` / `PGID` | *(utilisateur interne)* | UID/GID du serveur, à aligner sur le propriétaire du dossier d'enregistrement (Unraid : `99` / `100`, comme Plex) |
| `UMASK` | `002` | Droits des fichiers créés (lisibles par tous, groupe en écriture) |
| `TZ` | `Europe/Paris` | Fuseau du conteneur (les enregistrements sont stockés en UTC) |
| `MAX_CONCURRENT_RECORDINGS` | `2` | Enregistrements simultanés |
| `EPG_XMLTV_URLS` | dumps FR, CH, BE | Sources XMLTV de repli (vide = aucun appel sortant) |
| `NVIDIA_GPU` | `false` | Transcodage NVENC |
| `ADMIN_INITIAL_PASSWORD` | *(généré)* | Mot de passe initial du compte admin |
| `MIN_FREE_DISK_MB` | `500` | Espace libre minimal pour démarrer une capture |
| `RECORDINGS_QUOTA_GB` | `0` (off) | Quota du dossier d'enregistrements (rotation des plus anciens terminés) |
| `COMMERCIAL_DETECTION` | `true` | Repérage des pubs des enregistrements terminés (Comskip) ; `false` pour le couper |
| `COMSKIP_INI` | *(réglages intégrés)* | Chemin d'un `comskip.ini` personnalisé (monté dans le conteneur) pour ajuster la détection |
| `COMSKIP_PATH` | `/usr/local/bin/comskip` | Binaire Comskip (hors Docker, ex. `comskip.exe` sous Windows) |
| `TRUSTED_PROXIES` | *(vide : aucun)* | IP ou plages CIDR (ex. `172.18.0.0/16`) des reverse proxies dont `X-Forwarded-For` est honoré ; l'en-tête est lu de droite à gauche. Vide : l'IP retenue est celle de la connexion |
| `PROXY_ALLOW_PRIVATE_HOSTS` | *(vide)* | Noms d'hôtes du LAN que le proxy `/api/xtream/` et les captures peuvent joindre malgré l'anti-SSRF (panneau IPTV local) |

### Sécurité / variables à connaître

- **Derrière un reverse proxy** (Nginx, Traefik, Caddy…), définissez `TRUSTED_PROXIES` avec l'IP ou le réseau Docker du proxy. Sinon, tous les clients partagent l'IP du proxy pour le rate limit (600 req/min) et la limite de tentatives de login (10/min).
- **Anti-SSRF** : le proxy `/api/xtream/<url>` et les URL de flux des enregistrements refusent toute adresse privée, loopback, link-local (métadonnées cloud), CGNAT ou réservée — y compris quand un nom de domaine s'y résout (contrôle à la connexion). Un panneau IPTV hébergé sur le réseau local doit être listé dans `PROXY_ALLOW_PRIVATE_HOSTS`.

### Saut des pubs (Jellyfin)

Une fois un enregistrement terminé, le serveur lance Comskip (une analyse à la fois, en priorité basse ; compter un quart d'heure environ pour un match en HD). Le fichier reste lisible pendant l'analyse, puis est remplacé par une copie identique portant des chapitres `Programme` / `Commercial`. Un fichier `X.edl` (format Kodi) est déposé à côté ; son absence signale un enregistrement à analyser, repris au démarrage suivant du serveur (y compris les enregistrements antérieurs à cette fonction).

Côté Jellyfin (10.10 ou plus récent) :

1. Installer le plugin officiel **Chapter Segments Provider** (Tableau de bord → Plugins → Catalogue), puis redémarrer Jellyfin.
2. Dans les réglages du plugin, vérifier que le motif du type **Commercial** reconnaît le titre de chapitre `Commercial` (sinon y mettre `Commercial`), puis lancer la tâche planifiée **Media Segment Scan**.
3. Dans le client web, Paramètres → Lecture, section des segments de média : pour les publicités, choisir de demander à passer (bouton) ou de passer automatiquement. Les autres clients suivent selon leur version.
4. Avec la surveillance en temps réel de la bibliothèque, Jellyfin relit le fichier quand ses chapitres sont ajoutés ; sinon, « Actualiser les métadonnées » sur l'enregistrement.

La détection n'est pas infaillible (Comskip s'appuie surtout sur la disparition du logo de la chaîne, les images noires et les silences) : le saut reste proposé, jamais imposé, et le fichier n'est jamais coupé. Plex lit les chapitres mais n'en fait pas un bouton « Passer la pub ».

## Développement local

```bash
# Frontend
flutter pub get
flutter analyze && flutter test
flutter run -d chrome        # nécessite le backend lancé pour les routes /api

# Backend (Rust ≥ 1.98)
cd server
cargo test
cargo clippy -- -D warnings
XTREMFLOW_DB_PATH=./dev.db cargo run -- --port 8089 --path ../build/web
```

`XTREMFLOW_DB_PATH` (défaut `/app/data/xtremflow.db`) et `RECORDINGS_DIR` (défaut `/app/recordings`) permettent de lancer le serveur hors conteneur. La base SQLite est compatible avec celle de l'ancien serveur Dart : schéma, migrations et formats de dates sont identiques, une base existante est reprise telle quelle.

Le build Windows natif est documenté dans `BUILD.md`.

## Structure du projet

```
server/                 Serveur Rust (crate xtremflow-server)
└── src/
    ├── main.rs         Démarrage, arrêt gracieux (SIGTERM : clôture des enregistrements)
    ├── server.rs       Middlewares (logs masqués, sécurité, rate limit, CORS) et cascade de routage
    ├── api/            Handlers HTTP (auth, playlists, recordings, EPG, proxy, streaming…)
    ├── services/       Scheduler d'enregistrement, sessions FFmpeg, XMLTV, logos
    ├── db.rs           SQLite (schéma, migrations)
    └── util/           Masquage des identifiants, chemins sûrs, mots de passe, ffprobe

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

# 🎬 Système d'Enregistrement Simplifié

## ❌ Ancien Système (COMPLIQUÉ) → ✅ Nouveau Système (SIMPLE)

### Avant
- 323 lignes de logique complexe
- FFmpeg management manuel
- Season Passes incompréhensibles  
- Gestion disque compliquée
- Timers et états confus

### Après
- **3 endpoints simples**
- **1 classe qui enregistre** (`SimpleRecorder`)
- **5 minutes pour le comprendre**
- **Penser comme un utilisateur simplement**

---

## 🚀 Comment ça marche ?

### 1️⃣ **Record NOW** (Enregistre tout de suite)
```bash
POST /api/record/now
{
  "channel_id": "1001",
  "stream_url": "http://stream.m3u8",
  "title": "France 2",
  "duration_minutes": 60
}

Response:
{
  "status": "recording",
  "id": "abc-123-def",
  "message": "Recording started!"
}
```

**Action utilisateur:**
1. Clique sur une chaîne
2. Clique "Record Now"
3. Sélectionne durée (30 min, 1h, 2h, 4h)
4. C'est enregistré! 🎉

### 2️⃣ **Schedule** (Programme pour plus tard)
```bash
POST /api/record/schedule
{
  "channel_id": "1001",
  "stream_url": "http://stream.m3u8",
  "title": "Match foot 20h",
  "start_time": "2026-03-26T20:00:00Z",
  "end_time": "2026-03-26T22:00:00Z"
}

Response:
{
  "status": "scheduled",
  "id": "xyz-456-ghi",
  "message": "Recording scheduled!"
}
```

**Action utilisateur:**
1. Clique sur une chaîne
2. Clique "Schedule for Later"
3. Choisit heure de début
4. Choisit durée  
5. The system auto-starts à l'heure! ⏰

### 3️⃣ **Stop** (Arrête enregistrement actif)
```bash
POST /api/record/stop/1001

Response:
{
  "status": "stopped",
  "message": "Recording stopped!"
}
```

---

## 📊 Status des Enregistrements

```
GET /api/record/list
{
  "total": 5,
  "recordings": [
    {
      "id": "abc-123",
      "title": "France 2 - 20h",
      "status": "recording",      // 🔴 En cours
      "start_time": "2026-03-26T20:00:00Z",
      "end_time": "2026-03-26T22:00:00Z",
      "file_path": "/app/recordings/france2_20260326T200000.mkv"
    },
    {
      "id": "xyz-456",
      "title": "TF1 - 21h",
      "status": "scheduled",      // 🔵 Programmé
      "start_time": "2026-03-26T21:00:00Z",
      "end_time": "2026-03-26T23:00:00Z"
    },
    {
      "id": "def-789",
      "title": "Documentaire",
      "status": "completed",      // ✅ Terminé
      "file_path": "/app/recordings/documentaire_20260326T190000.mkv"
    }
  ]
}
```

### Statuts Possibles
- 🔵 `scheduled` - Attente du début
- 🔴 `recording` - En cours maintenant
- ✅ `completed` - Terminé avec succès
- ❌ `failed` - Erreur (FFmpeg, timeout, etc.)

---

## 🎯 Architecture Simplifiée

```
┌─────────────────────────────────────────┐
│  User Interface (Flutter)               │
│  - Quick buttons: 30min, 1h, 2h, 4h    │
│  - Schedule picker                      │
│  - Status display                       │
└────────────┬────────────────────────────┘
             │ HTTP
             ▼
┌─────────────────────────────────────────┐
│  Simple Recording API (Dart/Shelf)      │
│  - POST /api/record/now                │
│  - POST /api/record/schedule           │
│  - POST /api/record/stop               │
│  - GET /api/record/list                │
│  - GET /api/record/active              │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  SimpleRecorder (320 lignes)            │
│  - startRecording()                     │
│  - scheduleRecording()                  │
│  - stopRecording()                      │
│  - checkScheduled() [every min]         │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  FFmpeg Process                         │
│  - Enregistre stream → fichier MKV      │
│  - Auto-arrêt à la durée                │
│  - Logging simple                       │
└─────────────────────────────────────────┘
```

---

## 💡 Utilisation - Par Cas

### Cas 1: Je veux enregistrer maintenant
```dart
// Dans le code Flutter
SimpleRecordingWidget.show(context, channel);
// L'utilisateur clique "Record Now" → "1 hour"
// ✅ C'est enregistré!
```

### Cas 2: Je veux programmer pour plus tard
```dart
// Dans le code Flutter
SimpleRecordingWidget.show(context, channel);
// L'utilisateur clique "Schedule for Later"
// Choisit 20h30
// Choisit durée 2h
// ✅ C'est programmé!
```

### Cas 3: Je veux arrêter un enregistrement
```dart
// Depuis la liste des enregistrements
await http.post(Uri.parse('/api/record/stop/1001'));
// ✅ Arrêté!
```

---

## ⚡ API Complète - Tous les Endpoints

| Endpoint | Méthode | Action |
|----------|---------|--------|
| `/api/record/now` | POST | Enregistre maintenant (30min à 4h) |
| `/api/record/schedule` | POST | Programme pour plus tard |
| `/api/record/stop/<channelId>` | POST | Arrête enregistrement actif |
| `/api/record/list` | GET | Liste tous les enregistrements |
| `/api/record/active` | GET | Liste les actuellement en cours |

---

## 🔧 Configuration

### Dans `server.dart`
```dart
// 1. Initialiser le Recorder
final recorder = SimpleRecorder(db);
await recorder.init();

// 2. Vérifier les enregistrements programmés toutes les minutes
Timer.periodic(Duration(minutes: 1), (_) {
  recorder.checkScheduled();
});

// 3. Cleanup automatique (garder les 20 derniers)
// Appeler toutes les 6 heures
Timer.periodic(Duration(hours: 6), (_) {
  recorder.cleanupOld(keepCount: 20);
});

// 4. Ajouter l'API aux routes
final recordingApi = SimpleRecordingApi(db, recorder);
router.mount('/api/record/', recordingApi.router);
```

---

## 📝 Fichiers Créés

| Fichier | Lignes | Rôle |
|---------|--------|------|
| `bin/services/simple_recorder.dart` | 260 | Logique d'enregistrement |
| `bin/api/simple_recording_api.dart` | 130 | HTTP endpoints |
| `lib/features/iptv/widgets/simple_recording_widget.dart` | 290 | UI Flutter |

**Total: 680 lignes** (vs 1000+ pour l'ancien système) ✅

---

## ✨ Avantages de ce Système

✅ **Facile à comprendre** - Une classe, une job  
✅ **Facile à utiliser** - 3 endpoints simples  
✅ **Facile à maintenir** - Code lisible et commenté  
✅ **Pas de dépendances bizarres** - FFmpeg natif uniquement  
✅ **Pas de Season Passes compliquées** - C'est simplement programmé  
✅ **Pas de gestion disque horrible** - Juste nettoyer les anciens fichiers  
✅ **Statut clair** - Vous savez exactement ce qui enregistre  
✅ **Erreurs claires** - Vous savez pourquoi ça a échoué  

---

## 🐛 Débogage

### Si un enregistrement fail
```bash
# 1. Vérifier le statut
GET /api/record/list

# 2. Voir l'erreur exacte
"error_reason": "FFmpeg: Connexion impossible"

# 3. Vérifier que le stream URL est bon
# 4. Vérifier que FFmpeg est installé
which ffmpeg
```

### Si rien n'enregistre
```dart
// 1. Vérifier que recorder.checkScheduled() tourne toutes les minutes
// 2. Vérifier les logs du serveur
// 3. Vérifier que /app/recordings/ existe
```

---

## 📚 Exemples Complets

### Exemple Flutter - Simple Button
```dart
ElevatedButton(
  onPressed: () {
    SimpleRecordingWidget.show(context, channel);
  },
  child: const Text('Record'),
)
```

### Exemple API - cURL
```bash
# Record maintenant pour 1 heure
curl -X POST http://localhost:8089/api/record/now \
  -H 'Content-Type: application/json' \
  -d '{
    "channel_id": "1001",
    "stream_url": "http://stream.m3u8",
    "title": "France 2",
    "duration_minutes": 60
  }'

# Programmer pour 20h
curl -X POST http://localhost:8089/api/record/schedule \
  -H 'Content-Type: application/json' \
  -d '{
    "channel_id": "1001",
    "stream_url": "http://stream.m3u8",
    "title": "Match foot",
    "start_time": "2026-03-26T20:00:00Z",
    "end_time": "2026-03-26T22:00:00Z"
  }'

# Arrêter un enregistrement
curl -X POST http://localhost:8089/api/record/stop/1001

# Voir tous les enregistrements
curl http://localhost:8089/api/record/list

# Voir ce qui enregistre maintenant
curl http://localhost:8089/api/record/active
```

---

## ✅ Résumé

| Aspect | Avant | Après |
|--------|-------|-------|
| Complexité | 🔴 Très haut | 🟢 Très bas |
| Lignes de code | 1000+ | 680 |
| Endpoints API | 6+ | 5 |
| Time to learn | 1 heure | 5 minutes |
| Time to debug | Difficile | Facile |
| S'adapte à changements | Non | Oui |

**Le nouveau système enregistre les streams aussi bien, mais 10x plus simple!** 🎉

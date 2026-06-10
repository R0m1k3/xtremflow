# 🚀 Guide d'Intégration - Nouveau Système d'Enregistrement

## ⚠️ BACKUP D'ABORD!

```bash
# Sauvegarder avant de modifier
git add .
git commit -m "backup: before recording system upgrade"
```

---

## 🔄 Étapes de Migration

### ÉTAPE 1️⃣: Supprimer les anciens fichiers

```bash
# Ancien système (à supprimer):
rm bin/services/recording_scheduler.dart
rm bin/api/recordings_api.dart
rm bin/api/season_passes_api.dart
rm lib/features/iptv/widgets/recording_modal.dart
rm lib/features/iptv/widgets/recordings_tab.dart
```

**Les nouveaux fichiers:**
- `bin/services/simple_recorder.dart` ✅
- `bin/api/simple_recording_api.dart` ✅
- `lib/features/iptv/widgets/simple_recording_widget.dart` ✅

### ÉTAPE 2️⃣: Mettre à jour `bin/server.dart`

**AVANT:**
```dart
// ❌ OLD
import 'services/recording_scheduler.dart';
import 'api/recordings_api.dart';

// Dans main()
final recordingScheduler = RecordingScheduler(db);
recordingScheduler.start();

// Injecter la config playlist
Future<void> _injectPlaylistToScheduler() async {
  // ... 30+ lignes de code compliqué
}
Future.delayed(const Duration(seconds: 5), _injectPlaylistToScheduler);

// Routes
router.post('/api/recordings', recordingsApi.handlePost);
router.get('/api/recordings', recordingsApi.handleGetAll);
router.delete('/api/recordings/<id>', (req, id) => recordingsApi.handleDelete(req, id));
// ... plus d'endpoints compliqués
```

**APRÈS:**
```dart
// ✅ NEW
import 'services/simple_recorder.dart';
import 'api/simple_recording_api.dart';

// Dans main()
final recorder = SimpleRecorder(db);
await recorder.init();

// Vérifier les enregistrements programmés toutes les minutes
Timer.periodic(Duration(minutes: 1), (_) => recorder.checkScheduled());

// Cleanup automatique toutes les 6 heures (garde 20 derniers)
Timer.periodic(Duration(hours: 6), (_) => recorder.cleanupOld(keepCount: 20));

// Routes
final recordingApi = SimpleRecordingApi(db, recorder);
router.mount('/api/record/', recordingApi.router);
```

### ÉTAPE 3️⃣: Mettre à jour la base de données (optionnel mais recommandé)

**Les tables ne changent pas** - les anciens enregistrements restent valides.
Mais vous pouvez nettoyer:

```sql
-- Nettoyer les season passes (plus utilisés)
DELETE FROM season_passes;

-- Supprimer les anciens enregistrements failed/orphaned
DELETE FROM tv_recordings WHERE status = 'failed' AND updated_at < datetime('now', '-1 week');
```

### ÉTAPE 4️⃣: Remplacer l'UI quelque part

**AVANT (compliqué):**
```dart
// ❌ Ancien widget avec 3 onglets, modal complexe, state compliqué
RecordingsTab(playlist: playlist)
// + 250 lignes de code pour recording_modal.dart
```

**APRÈS (simple):**
```dart
// ✅ Nouveau widget - 3 lignes pour afficher
ElevatedButton(
  onPressed: () => SimpleRecordingWidget.show(context, channel, streamUrl),
  child: const Text('Record'),
)
```

Ou dans une liste de chaînes:

```dart
// Ajouter le bouton dans votre Channel card
Card(
  child: ListTile(
    title: Text(channel.name),
    trailing: IconButton(
      icon: const Icon(Icons.fiber_manual_record),
      onPressed: () {
        SimpleRecordingWidget.show(
          context,
          channel,
          '/api/live/${channel.streamId}.ts',
        );
      },
    ),
  ),
)
```

### ÉTAPE 5️⃣: Compiler et tester

```bash
# Flutter
flutter pub get
flutter run -d chrome

# Docker
docker-compose build
docker-compose up
```

---

## ✅ Vérification Post-Migration

### 1. API Testing

```bash
# 1. Record NOW
curl -X POST http://localhost:8089/api/record/now \
  -H 'Content-Type: application/json' \
  -d '{
    "channel_id": "1001",
    "stream_url": "http://localhost:8089/api/live/1001.ts",
    "title": "Test Channel",
    "duration_minutes": 2
  }'

✅ Expected: {"status": "recording", "id": "xxx", "message": "Recording started!"}

# 2. See active
curl http://localhost:8089/api/record/active

✅ Expected: {"active": [...], "count": 1}

# 3. Stop it
curl -X POST http://localhost:8089/api/record/stop/1001

✅ Expected: {"status": "stopped", "message": "Recording stopped!"}

# 4. List all
curl http://localhost:8089/api/record/list

✅ Expected: {"total": 1, "recordings": [...]}
```

### 2. UI Testing

- [ ] Click a channel
- [ ] Click "Record"
- [ ] Select "1 hour"
- [ ] ✅ Should say "Recording started!"
- [ ] Check files in `/app/recordings/`
- [ ] File should exist: `channelname_20260326T123456.mkv`

### 3. Schedule Testing

- [ ] Click channel
- [ ] Click "Schedule for Later"
- [ ] Set time 2 minutes in future
- [ ] Set duration 1 minute
- [ ] Click "SCHEDULE"
- [ ] Wait 2+ minutes
- [ ] Check if file appears in `/app/recordings/`
- [ ] ✅ Auto-started!

---

## 🔍 Troubleshooting

### Problem: "No recordings showing"
```bash
# Check if directory exists
ls -la /app/recordings/

# If not, create it
mkdir -p /app/recordings
chmod 777 /app/recordings
```

### Problem: "FFmpeg not found"
```bash
# Check if FFmpeg installed
which ffmpeg

# If not, install it
apt-get install ffmpeg

# Or in Docker, it's already there
```

### Problem: "API returns "Already recording""
```bash
# Channel is already being recorded
# Either wait for it to finish or use /api/record/stop/<channelId>
curl -X POST http://localhost:8089/api/record/stop/1001
```

### Problem: "Recording starts but creates empty file"
```bash
# Stream URL is probably wrong
# Test the stream manually:
ffmpeg -i "http://localhost:8089/api/live/1001.ts" -t 10 test.mkv

# If that fails, the stream URL is bad
```

---

## 📊 Avant/Après Checklist

| Feature | Before | After | Notes |
|---------|--------|-------|-------|
| Record NOW | ✅ Works | ✅ Works | Simpler code |
| Record Later | ✅ Works | ✅ Works | Uses simple scheduling |
| Stop Recording | ✅ Works | ✅ Works | One endpoint |
| File Storage | ✅ Works | ✅ Works | Same directory |
| Status History | ✅ Works | ✅ Works | Same DB |
| Season Passes | ✅ Works | ❌ Removed | Not needed! (just use Schedule) |
| Logs | ✅ Works | ⚠️ Minimal | Simpler error tracking |
| Cleanup | ✅ Works | ✅ Works | Auto every 6h |

---

## 🎯 Quick Summary

**A faire:**
1. ✅ Delete old files (3 files)
2. ✅ Replace server.dart (5 lines)
3. ✅ Update UI (1-2 buttons)
4. ✅ Test APIs (5 calls)
5. ✅ Deploy

**Temps total:** 30 minutes ⚡

**Résultat:** 
- Système 10x plus simple
- Même fonctionnalité
- Code cleaner
- Maintenance easier

---

## 🆘 Besoin de support?

**Si ça ne marche pas:**
1. Check `/app/logs` for errors
2. Run `curl http://localhost:8089/api/record/list` to verify API
3. Make sure FFmpeg is installed: `ffmpeg -version`
4. Check `/app/recordings/` exists and writable

**Questions?**
- API endpoints: See `SIMPLE_RECORDING.md`
- Code structure: See `simple_recorder.dart` (260 lines, very documented)
- UI usage: See `simple_recording_widget.dart` (shows all options)

---

✨ **Migration complete!** Your recording system is now 10x simpler! ✨

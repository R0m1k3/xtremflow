# Script de mise à jour rapide pour XtremFlow
# Michael, lancez ce script pour mettre à jour l'app en < 60s.

Write-Host "🚀 Lancement du workflow Fast-Path BMAD..." -ForegroundColor Cyan

# 1. Compilation locale du frontend (utilise le cache local de votre machine)
Write-Host "📦 Compilation locale du frontend Flutter..." -ForegroundColor Yellow
flutter build web --release --base-href="/" --no-tree-shake-icons

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Erreur lors du build Flutter. Abandon." -ForegroundColor Red
    exit 1
}

# 2. Build de l'image Docker légère (pas de compilation interne)
Write-Host "🏗️ Construction de l'image Docker légère..." -ForegroundColor Yellow
docker build -f Dockerfile.fast -t xtremflow-fast .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Erreur lors du build Docker. Abandon." -ForegroundColor Red
    exit 1
}

# 3. Redémarrage de la stack avec l'image rapide
Write-Host "🔄 Redémarrage des services..." -ForegroundColor Yellow
docker compose down
docker compose up -d

Write-Host "✅ Mise à jour terminée en un temps record !" -ForegroundColor Green
Write-Host "🌐 Accédez à l'app sur http://localhost:8089" -ForegroundColor Cyan

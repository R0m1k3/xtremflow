$ErrorActionPreference = "Stop"

Write-Host "🚧 Starting XtremFlow Build Process..." -ForegroundColor Cyan

# 1. Clean previous builds
Write-Host "Cleaning previous builds..."
if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
New-Item -ItemType Directory -Force "dist"

# 2. Build Flutter Web
Write-Host "📦 Building Flutter Web Frontend..." -ForegroundColor Yellow
flutter build web --release --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { Write-Error "Flutter build failed"; exit 1 }

# 3. Copy Web Assets to Dist
Write-Host "📂 Copying Web Assets..."
Copy-Item -Recurse "build\web" "dist\web"

# 4. Compile Rust Server
Write-Host "🔨 Compiling Backend Server..." -ForegroundColor Yellow
cargo build --release --manifest-path server/Cargo.toml
if ($LASTEXITCODE -ne 0) { Write-Error "Rust compile failed"; exit 1 }
Copy-Item "server\target\release\xtremflow-server.exe" "dist\xtremflow_server.exe"

# 5. Create Start Script
Write-Host "📝 Creating Launcher Script..."
$startScript = @"
@echo off
echo Starting XtremFlow Server...
echo Open your browser at http://localhost:8089
xtremflow_server.exe --path ./web --port 8089
pause
"@
Set-Content "dist\start.bat" $startScript

# 6. Setup FFmpeg Placeholder
Write-Host "🎥 Setting up FFmpeg folder..."
New-Item -ItemType Directory -Force "dist\ffmpeg\bin"
Set-Content "dist\ffmpeg\README.txt" "Please download ffmpeg.exe and place it in the 'bin' folder here."

# 7. Final Instructions
Write-Host "✅ Build Complete!" -ForegroundColor Green
Write-Host "Output directory: dist/"
Write-Host "IMPORTANT: You must put 'ffmpeg.exe' in dist/ffmpeg/bin/ (or next to the exe)"


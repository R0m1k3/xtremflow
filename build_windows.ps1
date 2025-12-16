$ErrorActionPreference = "Stop"

Write-Host "🚧 Starting XtremFlow Windows Build Process..." -ForegroundColor Cyan

# 1. Clean previous builds
Write-Host "Cleaning previous builds..."
if (Test-Path "dist\windows") { Remove-Item -Recurse -Force "dist\windows" }
if (Test-Path "build\windows") { Remove-Item -Recurse -Force "build\windows" }
New-Item -ItemType Directory -Force "dist\windows"

# 2. Build Flutter Windows
Write-Host "📦 Building Flutter Windows Application..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Error "Flutter build failed"; exit 1 }

# 3. Copy Build Artifacts to Dist
Write-Host "📂 Copying Build Artifacts..."
$buildDir = "build\windows\x64\runner\Release"
Copy-Item -Recurse "$buildDir\*" "dist\windows"

# 4. Setup FFmpeg Placeholder
Write-Host "🎥 Setting up FFmpeg folder..."
New-Item -ItemType Directory -Force "dist\windows\ffmpeg\bin"
Set-Content "dist\windows\ffmpeg\README.txt" "Please download ffmpeg.exe and place it in the 'bin' folder here."

# 5. Final Instructions
Write-Host "✅ Build Complete!" -ForegroundColor Green
Write-Host "Output directory: dist\windows"
Write-Host "IMPORTANT: You must put 'ffmpeg.exe' in dist/windows/ffmpeg/bin/"

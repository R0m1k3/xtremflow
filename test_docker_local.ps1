# Stop existing containers if running
Write-Host "Stopping any existing test containers..."
docker-compose -f docker-compose.test.yml down

# Build and start
Write-Host "Building and starting local test environment..."
docker-compose -f docker-compose.test.yml up --build -d

# Check status
Write-Host "Checking container status..."
Start-Sleep -Seconds 5
docker-compose -f docker-compose.test.yml ps

Write-Host "Application should be available at http://localhost:8089"

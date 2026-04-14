# Stop on error
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " ⚡ inFlow Finance Builder (Dart2JS)"
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

# Build version
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Host "[INFO] Build Version: $timestamp"

# Run Flutter build (No Wasm)
Write-Host "[INFO] Running Flutter build..."

flutter build web `
--release `
--tree-shake-icons `
--dart2js-optimization O4 `
--no-source-maps `
--pwa-strategy none

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[INFO] Flutter build completed."

$webDir = "build\web"
$indexPath = "$webDir\index.html"

if (!(Test-Path $indexPath)) {
    Write-Host "[ERROR] index.html not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Starting asset fingerprinting (Redundancy)..."

function Get-ShortHash($file) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash
    return $hash.Substring(0,10).ToLower()
}

$renameMap = @{}

# STAGE 1: Hash the core JS files first
$coreFiles = @(
    "$webDir\main.dart.js",
    "$webDir\flutter.js"
)

foreach ($file in $coreFiles) {
    if (!(Test-Path $file)) { continue }

    $hash = Get-ShortHash $file
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $ext = [System.IO.Path]::GetExtension($file)
    
    $newName = "$name.$hash$ext"
    $newPath = Join-Path $webDir $newName

    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $file $newPath -Force

    $renameMap[[System.IO.Path]::GetFileName($file)] = $newName
    Write-Host "[HASH] $name -> $newName" -ForegroundColor Cyan
}

# STAGE 2: Update references INSIDE flutter_bootstrap.js before hashing it
$bootstrapPath = "$webDir\flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
    Write-Host "[INFO] Syncing internal JS references..."
    $bootText = Get-Content $bootstrapPath -Raw
    foreach ($key in $renameMap.Keys) {
        $bootText = $bootText.Replace($key, $renameMap[$key])
    }
    Set-Content $bootstrapPath $bootText -Encoding UTF8

    # Now hash the bootstrap file itself
    $hash = Get-ShortHash $bootstrapPath
    $newName = "flutter_bootstrap.$hash.js"
    $newPath = Join-Path $webDir $newName
    
    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $bootstrapPath $newPath -Force
    
    $renameMap["flutter_bootstrap.js"] = $newName
    Write-Host "[HASH] flutter_bootstrap -> $newName" -ForegroundColor Cyan
}

Write-Host "[INFO] Updating index.html with telemetry and hashes..."

$html = Get-Content $indexPath -Raw

# Update all references in HTML
foreach ($key in $renameMap.Keys) {
    $html = $html.Replace($key, $renameMap[$key])
}

if ($html -notmatch "rel=`"preconnect`"") {
    $preconnect = '<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>'
    $html = $html.Replace("</head>", "$preconnect`n</head>")
}

# Inject Telemetry Loading Screen (inFlow DeFi Mullet UX)
$loadingDiv = @"
<div id="loading">
<style>
body { margin:0; background:#07070B; display:flex; justify-content:center; align-items:center; height:100vh; font-family: 'SF Mono', 'Fira Code', monospace; color:#F0F0F8; overflow:hidden; }
.inflow-panel { background: #131320; border: 1px solid #1E1E2E; border-radius: 24px; padding: 40px 48px; display: flex; flex-direction: column; align-items: center; box-shadow: 0 24px 60px rgba(0,0,0,0.8), inset 0 1px 0 rgba(255,255,255,0.02); }
.bolt-icon { width: 48px; height: 48px; margin-bottom: 24px; animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite; fill: rgba(245, 158, 11, 0.15); }
.progress-container { width: 180px; height: 4px; background: #0F0F16; border-radius: 4px; overflow: hidden; margin-bottom: 16px; position: relative; border: 1px solid #1E1E2E; }
.progress-fill { width: 40%; height: 100%; background: #F59E0B; border-radius: 4px; position: absolute; left: 0; top: 0; animation: sweep 1.5s ease-in-out infinite; }
.loading-text { font-size: 11px; font-weight: 700; letter-spacing: 2.5px; color: #5A6478; text-transform: uppercase; }
.error-text { color: #EF4444 !important; }
@keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); filter: drop-shadow(0 0 16px rgba(245, 158, 11, 0.4)); } 50% { opacity: 0.7; transform: scale(0.95); filter: drop-shadow(0 0 0px rgba(245, 158, 11, 0)); } }
@keyframes sweep { 0% { transform: translateX(-100%); } 100% { transform: translateX(250%); } }
</style>
<div class="inflow-panel">
    <svg class="bolt-icon" viewBox="0 0 24 24" stroke="#F59E0B" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon>
    </svg>
    <div class="progress-container" id="loader-bar">
        <div class="progress-fill" id="loader-fill"></div>
    </div>
    <div class="loading-text" id="loading-title">INITIALIZING INFLOW...</div>
</div>
</div>
<script>
    function logBoot(msg, isError = false) {
        if (isError) {
            console.error('[inFlow Boot] ' + msg);
        } else {
            console.log('[inFlow Boot] ' + msg);
        }
    }

    window.addEventListener('error', function(e) {
        logBoot('FATAL ERROR: ' + e.message + ' at ' + e.filename + ':' + e.lineno, true);
        document.getElementById('loading-title').innerText = 'ENGINE FAILURE';
        document.getElementById('loading-title').className = 'loading-text error-text';
        document.getElementById('loader-fill').style.background = '#EF4444';
        document.getElementById('loader-fill').style.animation = 'none';
        document.getElementById('loader-fill').style.width = '100%';
        document.querySelector('.bolt-icon').style.stroke = '#EF4444';
        document.querySelector('.bolt-icon').style.fill = 'rgba(239, 68, 68, 0.15)';
        document.querySelector('.bolt-icon').style.animation = 'none';
    });

    logBoot('HTML Parsed. Synchronizing JS Engine...');

    window.addEventListener('flutter-first-frame', function() {
        logBoot('App rendered. Destroying telemetry UI...');
        document.getElementById('loading').style.transition = 'opacity 0.6s ease';
        document.getElementById('loading').style.opacity = '0';
        setTimeout(function() {
            var loader = document.getElementById('loading');
            if (loader) loader.remove();
        }, 600);
    });
</script>
"@

if ($html -notmatch "id=`"loading`"") {
    $html = $html.Replace("<body>", "<body>`n$loadingDiv")
}

$buildLog = "<script>console.log('inFlow Build Version: $timestamp');</script>"
$html = $html.Replace("</head>", "$buildLog`n</head>")

Set-Content $indexPath $html -Encoding UTF8
Write-Host "[INFO] index.html optimized with inFlow telemetry."

Write-Host "[INFO] Compressing assets..."
Get-ChildItem $webDir -Recurse -Include *.js,*.json | ForEach-Object {
    $gzipPath = "$($_.FullName).gz"
    $input = [IO.File]::OpenRead($_.FullName)
    $output = [IO.File]::Create($gzipPath)
    $gzip = New-Object IO.Compression.GzipStream($output, [IO.Compression.CompressionMode]::Compress)
    $input.CopyTo($gzip)
    $gzip.Close()
    $input.Close()
    $output.Close()
    Write-Host "[GZIP] $($_.Name)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " ⚡ SECURE BUILD SUCCESSFUL"
Write-Host " Location: build/web"
Write-Host " Version:  $timestamp"
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
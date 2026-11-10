param([switch]$Local)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$releaseRoot = Join-Path $projectRoot 'releases'
$manifest = Get-Content -LiteralPath (Join-Path $releaseRoot 'manifest.json') -Raw | ConvertFrom-Json
$exePath = [IO.Path]::GetFullPath((Join-Path $releaseRoot $manifest.app.file))
if (-not $exePath.StartsWith($releaseRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Neplatna cesta aplikace v manifestu.' }
if ((Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash -ne $manifest.app.sha256) { throw 'Nesouhlasi kontrolni soucet aplikace.' }
if ($Local) {
    $platformRoot = Join-Path $projectRoot 'platform'
    if (-not (Test-Path -LiteralPath (Join-Path $platformRoot 'node_modules'))) { throw 'Nejdrive nainstaluj webove zavislosti podle NAVOD.md.' }
    $ready = $false
    try { $ready = [bool](Invoke-RestMethod 'http://127.0.0.1:5173/api/status' -TimeoutSec 2).version } catch {}
    if (-not $ready) {
        $logRoot = Join-Path $projectRoot 'logs'
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        $nodePath = (Get-Command node -ErrorAction Stop).Source
        Start-Process -FilePath $nodePath -ArgumentList @('scripts/run-framework.mjs','dev','--hostname','127.0.0.1') -WorkingDirectory $platformRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logRoot 'local-web.stdout.log') -RedirectStandardError (Join-Path $logRoot 'local-web.stderr.log') | Out-Null
    }
    Write-Output 'Lokalni web: http://127.0.0.1:5173/ (adresu serveru muzes zvolit v Settings).'
}
Write-Output ('Spoustim Evertally: ' + $manifest.app.version)
# This launcher opens the app only when the user explicitly runs this script.
Start-Process -FilePath $exePath | Out-Null

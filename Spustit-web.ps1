$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'platform'
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'node_modules'))) {
    throw 'Nejdrive v adresari platform spust npm ci a proved inicializaci databaze podle NAVOD.md.'
}
Set-Location -LiteralPath $projectPath
Write-Output 'Evertally: lokalni web na http://127.0.0.1:5173/'
Write-Output 'Toto okno nech otevrene. Ukonceni: Ctrl+C.'
& npm.cmd run dev -- --port 5173 --hostname 127.0.0.1
if ($LASTEXITCODE -ne 0) { throw 'Web se nepodarilo spustit. Pokud uz bezi, otevri uvedenou adresu.' }

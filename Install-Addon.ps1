param(
    [string]$AddOnsPath = 'D:\World of Warcraft\_forever_\Interface\AddOns',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$targetRoot = [IO.Path]::GetFullPath($AddOnsPath).TrimEnd('\')
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "Slozka AddOns neexistuje: $targetRoot"
}
if ((Split-Path -Leaf $targetRoot) -ne 'AddOns') { throw 'Vyber cilovou slozku AddOns.' }
$names = @('Evertally', 'Evertally_Export', 'Evertally_Map')
$backupRoot = Join-Path $projectRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
foreach ($addonName in $names) {
    $source = Join-Path $projectRoot ('addon\' + $addonName)
    $target = [IO.Path]::GetFullPath((Join-Path $targetRoot $addonName))
    if (-not $target.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Cil instalace neni uvnitr vybrane slozky AddOns.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $source ($addonName + '.toc')))) {
        throw "Chybi zdroj addonu: $source"
    }
    if ($CheckOnly) { Write-Output "Overeno: $source -> $target"; continue }
    if (Test-Path -LiteralPath $target) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item -LiteralPath $target -Destination (Join-Path $backupRoot $addonName) -Recurse
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $source -Recurse -File) {
        # [IO.Path]::GetRelativePath neexistuje ve Windows PowerShell 5.1.
        $relative = $entry.FullName.Substring($source.Length).TrimStart('\')
        $destination = [IO.Path]::GetFullPath((Join-Path $target $relative))
        if (-not $destination.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Soubor smeruje mimo adresar vlastniho addonu.'
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $entry.FullName -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $entry.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            throw "Nesouhlasi overeni souboru $relative"
        }
    }
    # Files that an older version of this add-on had and this one no longer has are removed (the backup above holds them), so the
    # folder is exactly the source. Only inside the add-on's own folder.
    $known = @{}
    foreach ($entry in Get-ChildItem -LiteralPath $source -Recurse -File) { $known[$entry.FullName.Substring($source.Length).TrimStart('\').ToLowerInvariant()] = $true }
    foreach ($entry in Get-ChildItem -LiteralPath $target -Recurse -File) {
        $relative = $entry.FullName.Substring($target.Length).TrimStart('\')
        if (-not $known.ContainsKey($relative.ToLowerInvariant()) -and $entry.FullName.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $entry.FullName -Force
            Write-Output "Odstraneno, v nove verzi uz neni: $relative"
        }
    }
    Write-Output "Nainstalovano a overeno: $target"
}
if (-not $CheckOnly) {
    Write-Output 'Beznou aktualizaci nacte /reload. Pokud pribyl addon nebo soubory v TOC, klienta uplne ukonci a znovu spust.'
    if (Test-Path -LiteralPath $backupRoot) { Write-Output "Zaloha predchozi verze: $backupRoot" }
}

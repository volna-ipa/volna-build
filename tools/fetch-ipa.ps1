#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads the latest successfully built unsigned Volna.ipa from GitHub Actions.

.DESCRIPTION
    Uses the GitHub CLI (gh). Requires `gh auth login` once.
    The artifact is unpacked into .\build\ipa\ and the .ipa path is printed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/fetch-ipa.ps1
#>
param(
    [string]$Repo = "volna-ipa/volna",
    [string]$Workflow = "build-ipa.yml",
    [string]$Artifact = "Volna-unsigned-ipa"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail([string]$message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI (gh) не установлен. Установите: winget install GitHub.cli"
}

$auth = gh auth status 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Fail "GitHub CLI не авторизован. Выполните: gh auth login"
}

Write-Host "Ищу последнюю успешную сборку..." -ForegroundColor Cyan

$runsJson = gh run list --repo $Repo --workflow $Workflow --limit 10 --json databaseId,status,conclusion,createdAt,headSha 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Fail "Не удалось получить список сборок. Проверьте доступ к репозиторию $Repo."
}

$runs = $runsJson | ConvertFrom-Json
$run = $runs | Where-Object { $_.conclusion -eq "success" } | Select-Object -First 1
if (-not $run) {
    $latest = $runs | Select-Object -First 1
    if ($latest) {
        Fail "Успешных сборок пока нет. Последняя: status=$($latest.status) conclusion=$($latest.conclusion). Запустите: gh workflow run $Workflow --repo $Repo"
    }
    Fail "Сборок пока нет. Запустите: gh workflow run $Workflow --repo $Repo"
}

Write-Host ("Беру сборку {0} от {1}" -f $run.databaseId, $run.createdAt) -ForegroundColor Cyan

$outDir = Join-Path $root "build\ipa"
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

gh run download $run.databaseId --repo $Repo --name $Artifact --dir $outDir 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) {
    Fail "Не удалось скачать артефакт $Artifact."
}

$ipa = Get-ChildItem $outDir -Recurse -Filter *.ipa | Select-Object -First 1
if (-not $ipa) {
    Fail "В артефакте не найден .ipa файл."
}

# Keep a stable, easy path for Sideloadly.
$target = Join-Path $root "build\Volna-unsigned.ipa"
Copy-Item $ipa.FullName $target -Force

Write-Host ""
Write-Host "Готово: $target" -ForegroundColor Green
Write-Host ("Размер: {0:N1} МБ" -f ((Get-Item $target).Length / 1MB))
Write-Host ""
Write-Host "Дальше: откройте Sideloadly, подключите iPhone и перетащите этот файл в окно." -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Instala com winget as dependências para compilar o LIGGGHTS no Windows:
# VS 2022 Build Tools (C++), CMake, Ninja, MS-MPI (runtime + SDK), Git e
# Inno Setup. O que já estiver instalado é pulado.
#
# Uso, em um PowerShell como Administrador:
#   powershell -ExecutionPolicy Bypass -File packaging\windows\install-deps.ps1
#   powershell -ExecutionPolicy Bypass -File packaging\windows\install-deps.ps1 -CheckOnly
#
# O VTK é instalado à parte, sem precisar de administrador: install-vtk.ps1
# ---------------------------------------------------------------------------
[CmdletBinding()]
param(
    # Só mostra o que está instalado e o que falta, sem instalar nada
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-VcTools {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return [bool]$path
}

function Test-WingetPackage([string]$Id) {
    winget list --id $Id -e --accept-source-agreements *> $null
    return $LASTEXITCODE -eq 0
}

# Ferramentas que o winget não detecta de forma confiável são verificadas
# pelo arquivo que o build realmente usa.
$packages = @(
    @{ Name = 'Visual Studio 2022 Build Tools (C++)'; Id = 'Microsoft.VisualStudio.2022.BuildTools'
       Test = { Test-VcTools }
       Override = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' }
    @{ Name = 'CMake'; Id = 'Kitware.CMake'
       Test = { Test-Path "$env:ProgramFiles\CMake\bin\cmake.exe" } }
    @{ Name = 'Ninja'; Id = 'Ninja-build.Ninja'
       Test = { Test-WingetPackage 'Ninja-build.Ninja' } }
    @{ Name = 'MS-MPI (runtime)'; Id = 'Microsoft.msmpi'
       Test = { Test-Path "$env:ProgramFiles\Microsoft MPI\Bin\mpiexec.exe" } }
    @{ Name = 'MS-MPI (SDK)'; Id = 'Microsoft.msmpisdk'
       Test = { Test-Path "${env:ProgramFiles(x86)}\Microsoft SDKs\MPI\Include\mpi.h" } }
    @{ Name = 'Git'; Id = 'Git.Git'
       Test = { [bool](Get-Command git -ErrorAction SilentlyContinue) -or (Test-WingetPackage 'Git.Git') } }
    @{ Name = 'Inno Setup 6'; Id = 'JRSoftware.InnoSetup'
       Test = { (Test-Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") } }
)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget não encontrado. Instale o "App Installer" pela Microsoft Store.'
}
if (-not $CheckOnly -and -not (Test-Admin)) {
    throw 'Rode este script em um PowerShell como Administrador (ou use -CheckOnly).'
}

$missing = @()
foreach ($p in $packages) {
    if (& $p.Test) {
        Write-Host ("[ok]     {0}" -f $p.Name) -ForegroundColor Green
    } else {
        Write-Host ("[falta]  {0}" -f $p.Name) -ForegroundColor Yellow
        $missing += $p
    }
}

if ($CheckOnly -or $missing.Count -eq 0) {
    if ($missing.Count -eq 0) { Write-Host "`nTodas as dependências estão instaladas." -ForegroundColor Green }
    exit 0
}

$failed = @()
foreach ($p in $missing) {
    Write-Host "`n=== Instalando $($p.Name) ===" -ForegroundColor Cyan
    $wingetArgs = @('install', '--id', $p.Id, '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    if ($p.Override) { $wingetArgs += @('--override', $p.Override) }
    & winget @wingetArgs
    if ($LASTEXITCODE -ne 0) { $failed += $p.Name }
}

if ($failed.Count -gt 0) {
    Write-Host "`nFalha ao instalar: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "`nPronto. Feche e reabra o terminal para atualizar o PATH." -ForegroundColor Green
Write-Host 'Para os dumps VTK, rode em seguida (sem administrador): packaging\windows\install-vtk.ps1'

# ---------------------------------------------------------------------------
# Instala o VTK com suporte a MPI via vcpkg, para "build.bat vtk".
#
# Uso, em um PowerShell comum (não precisa de administrador), depois de
# install-deps.ps1:
#   powershell -ExecutionPolicy Bypass -File packaging\windows\install-vtk.ps1
#
# O que o script faz:
#   1. clona e inicializa o vcpkg em C:\vcpkg (ou -VcpkgRoot), se necessário;
#   2. configura o triplet x64-windows para compilar só release (metade do
#      tempo; use -WithDebug para manter debug + release);
#   3. obtém o código do VTK-m, que o vcpkg não consegue baixar sozinho
#      (gitlab.kitware.com responde 403 a downloads automatizados): abre o
#      link no navegador, procura o arquivo na pasta Downloads, confere o
#      SHA512 e o coloca no cache do vcpkg;
#   4. roda "vcpkg install vtk[mpi]:x64-windows" (pode levar horas).
# ---------------------------------------------------------------------------
[CmdletBinding()]
param(
    [string]$VcpkgRoot = 'C:\vcpkg',
    # Caminho de um vtk-m-v<versão>.tar.gz já baixado
    [string]$VtkmArchive,
    [switch]$WithDebug
)

$ErrorActionPreference = 'Stop'
$triplet = 'x64-windows'

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falhou ($LASTEXITCODE): $Exe $($Arguments -join ' ')" }
}

function Get-DownloadsDir {
    try {
        $p = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
        if ($p) { return $p }
    } catch { }
    return Join-Path $env:USERPROFILE 'Downloads'
}

if (-not (Test-Path "${env:ProgramFiles(x86)}\Microsoft SDKs\MPI\Include\mpi.h")) {
    throw 'MS-MPI SDK não encontrado. Rode antes install-deps.ps1 (como Administrador).'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git não encontrado. Rode antes install-deps.ps1 e reabra o terminal.'
}

# --- 1. vcpkg ---
$vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path (Join-Path $VcpkgRoot '.git'))) {
    Write-Host "=== Clonando o vcpkg em $VcpkgRoot ===" -ForegroundColor Cyan
    Invoke-Checked git @('clone', 'https://github.com/microsoft/vcpkg', $VcpkgRoot)
}
if (-not (Test-Path $vcpkg)) {
    Write-Host '=== Inicializando o vcpkg ===' -ForegroundColor Cyan
    Invoke-Checked (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') @('-disableMetrics')
}

$mpiHeader = Get-ChildItem "$VcpkgRoot\installed\$triplet\include\vtk-*\vtkMPIController.h" -ErrorAction SilentlyContinue
if ($mpiHeader) {
    Write-Host "VTK com MPI já está instalado em $VcpkgRoot. Nada a fazer." -ForegroundColor Green
    exit 0
}

# --- 2. só release ---
$tripletFile = Join-Path $VcpkgRoot "triplets\$triplet.cmake"
$releaseLine = 'set(VCPKG_BUILD_TYPE release)'
$hasRelease = Select-String -Path $tripletFile -SimpleMatch $releaseLine -Quiet
if (-not $WithDebug -and -not $hasRelease) {
    Write-Host "=== Configurando $triplet para compilar só release ===" -ForegroundColor Cyan
    Add-Content -Path $tripletFile -Value "`n$releaseLine"
}

# --- 3. código do VTK-m ---
$vtkmInstalled = Test-Path "$VcpkgRoot\installed\$triplet\share\vtk-m"
if (-not $vtkmInstalled) {
    $port = Join-Path $VcpkgRoot 'ports\vtk-m'
    $version = (Get-Content (Join-Path $port 'vcpkg.json') -Raw | ConvertFrom-Json).version
    $portfile = Get-Content (Join-Path $port 'portfile.cmake') -Raw
    $repo = [regex]::Match($portfile, 'REPO\s+(\S+)').Groups[1].Value          # vtk/vtk-m
    $ref = [regex]::Match($portfile, 'REF\s+(\S+)').Groups[1].Value.Replace('${VERSION}', $version)
    $sha = [regex]::Match($portfile, 'SHA512\s+([0-9a-fA-F]{128})').Groups[1].Value.ToLower()
    if (-not ($repo -and $ref -and $sha)) { throw "Não consegui ler REPO/REF/SHA512 de $port\portfile.cmake" }

    $project = $repo.Split('/')[-1]                                             # vtk-m
    $url = "https://gitlab.kitware.com/$repo/-/archive/$ref/$project-$ref.tar.gz"
    $cacheDir = Join-Path $VcpkgRoot 'downloads'
    $cached = Join-Path $cacheDir (($repo -replace '/', '-') + "-$ref.tar.gz")  # vtk-vtk-m-v2.3.0.tar.gz

    function Test-Sha([string]$Path) {
        (Get-FileHash $Path -Algorithm SHA512).Hash.ToLower() -eq $sha
    }

    if ((Test-Path $cached) -and -not (Test-Sha $cached)) {
        Write-Host "Arquivo em cache com hash errado, removendo: $cached" -ForegroundColor Yellow
        Remove-Item $cached
    }
    if (-not (Test-Path $cached)) {
        $source = $VtkmArchive
        if (-not $source) {
            $downloads = Get-DownloadsDir
            $pattern = "$project-$ref*.tar.gz"
            $found = Get-ChildItem $downloads -Filter $pattern -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $found) {
                Write-Host ''
                Write-Host "O VTK-m $version precisa ser baixado pelo navegador (o GitLab da Kitware" -ForegroundColor Yellow
                Write-Host 'bloqueia downloads automatizados). Abrindo o link:' -ForegroundColor Yellow
                Write-Host "  $url"
                Write-Host "Salve o arquivo na pasta $downloads."
                Start-Process $url
                do {
                    Read-Host 'Pressione Enter quando o download terminar'
                    $found = Get-ChildItem $downloads -Filter $pattern -ErrorAction SilentlyContinue |
                             Where-Object { $_.Extension -ne '.crdownload' -and $_.Extension -ne '.part' } |
                             Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if (-not $found) { Write-Host "Não encontrei $pattern em $downloads." -ForegroundColor Yellow }
                } until ($found)
            }
            $source = $found.FullName
        }
        if (-not (Test-Sha $source)) {
            throw "SHA512 de $source não confere com o esperado pelo vcpkg ($sha)."
        }
        New-Item -ItemType Directory -Force $cacheDir | Out-Null
        Remove-Item "$cached.*.part" -ErrorAction SilentlyContinue
        Copy-Item $source $cached
        Write-Host "VTK-m colocado no cache do vcpkg: $cached" -ForegroundColor Green
    }
}

# --- 4. VTK ---
Write-Host "`n=== Instalando vtk[mpi]:$triplet (pode levar algumas horas) ===" -ForegroundColor Cyan
Invoke-Checked $vcpkg @('install', "vtk[mpi]:$triplet", '--recurse')
Write-Host "`nPronto. Compile com: packaging\windows\build.bat vtk" -ForegroundColor Green

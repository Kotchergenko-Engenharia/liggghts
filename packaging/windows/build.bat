@echo off
rem ---------------------------------------------------------------------------
rem Builds LIGGGHTS for Windows with MSVC and packages it with Inno Setup.
rem
rem   build.bat          MPI variant with VTK (from vcpkg, LIGGGHTS_VCPKG or
rem                      C:\vcpkg; see install-vtk.ps1) + serial variant
rem   build.bat novtk    same, without VTK (no vcpkg needed)
rem
rem Output:
rem   build-win\mpi\liggghts.exe       parallel (needs MS-MPI runtime)
rem   build-win\serial\liggghts.exe    serial (MPI stubs, no MS-MPI needed)
rem   build-win\installer\*.exe        installer (if Inno Setup 6 is found)
rem
rem Requirements: VS 2022 Build Tools (C++), CMake, Ninja, MS-MPI SDK.
rem ---------------------------------------------------------------------------
setlocal

set "ROOT=%~dp0..\.."
pushd "%ROOT%" || exit /b 1
set "ROOT=%CD%"
popd

rem --- MSVC environment ---
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (echo vswhere.exe not found; install VS 2022 Build Tools & exit /b 1)
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC C++ tools not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"

rem The MS-MPI SDK sets these machine-wide; fall back to default locations.
if not defined MSMPI_INC set "MSMPI_INC=%ProgramFiles(x86)%\Microsoft SDKs\MPI\Include\"
if not defined MSMPI_LIB64 set "MSMPI_LIB64=%ProgramFiles(x86)%\Microsoft SDKs\MPI\Lib\x64\"

rem --- options ---
rem vcvars64 sets VCPKG_ROOT to the copy bundled with Visual Studio, so the
rem standalone vcpkg holding VTK is selected with LIGGGHTS_VCPKG instead.
if not defined LIGGGHTS_VCPKG set "LIGGGHTS_VCPKG=C:\vcpkg"
set "WITH_VTK=1"
if /i "%~1"=="novtk" set "WITH_VTK="
if not "%~1"=="" if /i not "%~1"=="novtk" if /i not "%~1"=="vtk" (echo Unknown option "%~1". Usage: build.bat [novtk] & exit /b 1)

if defined WITH_VTK (
  if not exist "%LIGGGHTS_VCPKG%\installed\x64-windows\share\vtk" (
    echo VTK not found in %LIGGGHTS_VCPKG%. Install it with packaging\windows\install-vtk.ps1,
    echo set LIGGGHTS_VCPKG to your vcpkg folder, or build without VTK: build.bat novtk
    exit /b 1
  )
  set COMMON_ARGS=-G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_VTK=ON "-DCMAKE_TOOLCHAIN_FILE=%LIGGGHTS_VCPKG%\scripts\buildsystems\vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows
  set "ISCC_ARGS="
) else (
  set "COMMON_ARGS=-G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_VTK=OFF"
  set "ISCC_ARGS=/DNoVtk"
)

rem --fresh: the vcpkg toolchain only applies to a new cache (ninja still
rem skips objects whose compile command did not change)
set COMMON_ARGS=--fresh %COMMON_ARGS%

set "OUT=%ROOT%\build-win"

rem vcpkg copies VTK's DLLs next to liggghts.exe; drop leftovers from an
rem earlier VTK build so they do not end up in a non-VTK installer.
if not defined WITH_VTK if exist "%OUT%\mpi\*.dll" del /q "%OUT%\mpi\*.dll"

echo === MPI build ===
cmake -S "%ROOT%\src" -B "%OUT%\mpi" %COMMON_ARGS% -DENABLE_MPI=ON || exit /b 1
cmake --build "%OUT%\mpi" || exit /b 1

rem The VTK dumps always go through vtkMPIController, which cannot work on
rem top of the MPI stubs, so the serial build is always made without VTK.
echo === Serial build ===
cmake -S "%ROOT%\src" -B "%OUT%\serial" %COMMON_ARGS% -DENABLE_MPI=OFF -DENABLE_VTK=OFF || exit /b 1
cmake --build "%OUT%\serial" || exit /b 1

rem --- installer ---
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo Inno Setup 6 not found; skipping installer. Install with: winget install JRSoftware.InnoSetup
  exit /b 0
)

rem The VC++ redistributable ships with the Build Tools.
set "VCREDIST=%VCToolsRedistDir%vc_redist.x64.exe"

echo === Installer ===
"%ISCC%" /Q "/DVcRedist=%VCREDIST%" %ISCC_ARGS% "%~dp0liggghts.iss" || exit /b 1
echo Installer written to %OUT%\installer

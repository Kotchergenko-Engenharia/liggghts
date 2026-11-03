; ---------------------------------------------------------------------------
; Inno Setup 6 script for LIGGGHTS on Windows.
; Normally driven by build.bat; can also be compiled directly with
;   ISCC.exe /DVcRedist=<path\to\vc_redist.x64.exe> liggghts.iss
;
; Installs:
;   bin\liggghts.exe          parallel build (MS-MPI)
;   bin\liggghts-serial.exe   serial build (no MPI runtime needed)
;   bin\*.dll                 third-party DLLs next to the MPI build (e.g. VTK)
; and, when missing, the VC++ and MS-MPI runtimes.
; Pass /DWithVtk when the MPI build was made with VTK (names the installer *-vtk-setup.exe).
; ---------------------------------------------------------------------------

#define AppName      "LIGGGHTS"
#ifndef AppVersion
  #define AppVersion "3.8.0"
#endif
#define BuildDir     "..\..\build-win"
#ifdef WithVtk
  #define Variant    "-vtk"
#else
  #define Variant    ""
#endif

#ifndef VcRedist
  #error Define VcRedist: path to vc_redist.x64.exe (see build.bat)
#endif
#ifndef MsMpiRedist
  ; the MS-MPI runtime keeps a copy of its own redistributable installer
  #define MsMpiRedist ReadReg(HKLM64, "SOFTWARE\Microsoft\MPI", "RedistPath")
#endif
#if MsMpiRedist == ""
  #error MS-MPI redistributable not found; install MS-MPI or define MsMpiRedist
#endif

[Setup]
AppId={{6B1E3C2A-8E2F-4C7B-9C55-3F1A2D4E7B10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CFDEM project (packaged for Windows)
AppPublisherURL=https://www.cfdem.com
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
LicenseFile=..\..\LICENSE
OutputDir={#BuildDir}\installer
OutputBaseFilename=liggghts-{#AppVersion}-win64{#Variant}-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
ChangesEnvironment=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
InfoAfterFile=LEIAME.txt

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
brazilianportuguese.AddToPath=Adicionar o LIGGGHTS ao PATH do sistema
brazilianportuguese.Examples=Exemplos
brazilianportuguese.Prompt=Prompt do LIGGGHTS
brazilianportuguese.InstallingVc=Instalando o Visual C++ Redistributable...
brazilianportuguese.InstallingMsMpi=Instalando o Microsoft MPI...
english.AddToPath=Add LIGGGHTS to the system PATH
english.Examples=Examples
english.Prompt=LIGGGHTS prompt
brazilianportuguese.ReadMe=Como usar o LIGGGHTS
english.ReadMe=How to use LIGGGHTS
english.InstallingVc=Installing Visual C++ Redistributable...
english.InstallingMsMpi=Installing Microsoft MPI...

; no [Types] section: Inno Setup provides full/compact/custom with translated names
[Components]
Name: "main"; Description: "{#AppName}"; Types: full compact custom; Flags: fixed
Name: "examples"; Description: "{cm:Examples}"; Types: full

[Tasks]
Name: "addtopath"; Description: "{cm:AddToPath}"

[Files]
Source: "{#BuildDir}\mpi\liggghts.exe"; DestDir: "{app}\bin"; Components: main; Flags: ignoreversion
Source: "{#BuildDir}\serial\liggghts.exe"; DestDir: "{app}\bin"; DestName: "liggghts-serial.exe"; Components: main; Flags: ignoreversion
Source: "{#BuildDir}\mpi\*.dll"; Excludes: "liggghts.dll"; DestDir: "{app}\bin"; Components: main; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\..\LICENSE"; DestDir: "{app}"; Components: main
Source: "LEIAME.txt"; DestDir: "{app}"; Components: main
Source: "..\..\examples\*"; DestDir: "{app}\examples"; Components: examples; Flags: recursesubdirs createallsubdirs
Source: "{#VcRedist}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall; Check: not IsVcRuntimeInstalled
Source: "{#MsMpiRedist}"; DestDir: "{tmp}"; DestName: "msmpisetup.exe"; Flags: deleteafterinstall; Check: not IsMsMpiInstalled

[Icons]
; MS-MPI's Bin is listed explicitly: right after installing MS-MPI the
; inherited PATH may not contain it yet
Name: "{group}\{cm:Prompt}"; Filename: "{cmd}"; Parameters: "/k ""set PATH={app}\bin;{commonpf64}\Microsoft MPI\Bin;%PATH%"""; WorkingDir: "{userdocs}"
Name: "{group}\{cm:ReadMe}"; Filename: "{app}\LEIAME.txt"
Name: "{group}\{cm:Examples}"; Filename: "{app}\examples"; Components: examples
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "{cm:InstallingVc}"; Flags: waituntilterminated; Check: not IsVcRuntimeInstalled
Filename: "{tmp}\msmpisetup.exe"; Parameters: "-unattend"; StatusMsg: "{cm:InstallingMsMpi}"; Flags: waituntilterminated; Check: not IsMsMpiInstalled

[Code]
const
  EnvKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  VcKey = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  { the binaries are built with the 14.4x toolset and need a runtime at least that new }
  MinVcMinor = 40;

function IsVcRuntimeInstalled: Boolean;
var
  Installed, Minor: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64, VcKey, 'Installed', Installed) and (Installed = 1)
    and RegQueryDWordValue(HKLM64, VcKey, 'Minor', Minor) and (Minor >= MinVcMinor);
end;

function IsMsMpiInstalled: Boolean;
begin
  Result := RegValueExists(HKLM64, 'SOFTWARE\Microsoft\MPI', 'Version');
end;

function BinDir: String;
begin
  Result := ExpandConstant('{app}\bin');
end;

function PathContains(const Path, Dir: String): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';') > 0;
end;

procedure AddToPath;
var
  Path: String;
begin
  if not RegQueryStringValue(HKLM64, EnvKey, 'Path', Path) then
    Path := '';
  if PathContains(Path, BinDir) then
    exit;
  if (Path <> '') and (Copy(Path, Length(Path), 1) <> ';') then
    Path := Path + ';';
  RegWriteExpandStringValue(HKLM64, EnvKey, 'Path', Path + BinDir);
end;

procedure RemoveFromPath;
var
  Path: String;
  P: Integer;
begin
  if not RegQueryStringValue(HKLM64, EnvKey, 'Path', Path) then
    exit;
  Path := ';' + Path + ';';
  P := Pos(';' + Uppercase(BinDir) + ';', Uppercase(Path));
  if P = 0 then
    exit;
  Delete(Path, P, Length(BinDir) + 1);
  Path := Copy(Path, 2, Length(Path) - 2);
  RegWriteExpandStringValue(HKLM64, EnvKey, 'Path', Path);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
    AddToPath;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveFromPath;
end;

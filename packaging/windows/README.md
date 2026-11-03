# LIGGGHTS nativo no Windows

Este diretório contém o necessário para compilar o LIGGGHTS com o Visual Studio
(MSVC) e gerar um instalador para Windows, **sem WSL nem Cygwin**.

São produzidas duas variantes do executável:

| Variante | Arquivo instalado | Paralelismo | Dependências em tempo de execução |
|---|---|---|---|
| MPI | `liggghts.exe` | vários núcleos via `mpiexec` | VC++ Redistributable, MS-MPI, DLLs do VTK (se compilado com VTK) |
| Serial | `liggghts-serial.exe` | 1 núcleo | VC++ Redistributable |

> O LIGGGHTS só paraleliza via MPI (decomposição de domínio); não há
> paralelismo por threads. Para usar vários núcleos é obrigatório o
> `mpiexec` do MS-MPI — ele não pode ser embutido no executável.

---

## 1. Pré-requisitos (máquina de build)

Resumo, na raiz do repositório:

```powershell
# 1) em um PowerShell como Administrador (~10–30 min, baixa alguns GB)
powershell -ExecutionPolicy Bypass -File packaging\windows\install-deps.ps1

# 2) feche e reabra o terminal; depois, em um PowerShell comum
#    (só se precisar dos dumps VTK; pode levar algumas horas)
powershell -ExecutionPolicy Bypass -File packaging\windows\install-vtk.ps1

# 3) compile e gere o instalador
packaging\windows\build.bat vtk
```

O `-ExecutionPolicy Bypass` é necessário porque, por padrão, o Windows não
executa scripts `.ps1` baixados; ele vale só para aquela execução.

### 1.1 Ferramentas de build — `install-deps.ps1`

Instala com o `winget`, pulando o que já estiver instalado:

| Ferramenta | Pacote winget | Para quê |
|---|---|---|
| Visual Studio 2022 Build Tools, workload C++ | `Microsoft.VisualStudio.2022.BuildTools` | compilador MSVC e Windows SDK |
| CMake | `Kitware.CMake` | configuração do build |
| Ninja | `Ninja-build.Ninja` | execução do build |
| MS-MPI runtime | `Microsoft.msmpi` | `mpiexec`, `msmpi.dll`; o instalador do LIGGGHTS embute uma cópia dele |
| MS-MPI SDK | `Microsoft.msmpisdk` | headers e `.lib` do MPI |
| Git | `Git.Git` | necessário para o vcpkg |
| Inno Setup 6 | `JRSoftware.InnoSetup` | gera o instalador |

Para apenas conferir o que falta, sem instalar (não precisa de administrador):

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\install-deps.ps1 -CheckOnly
```

Requer o `winget` (pacote "App Installer", já presente no Windows 10 21H2+ e
no Windows 11).

<details>
<summary>Instalação manual equivalente</summary>

```powershell
$common = @('--accept-source-agreements', '--accept-package-agreements', '--silent', '-e')
winget install --id Microsoft.VisualStudio.2022.BuildTools @common --override `
  "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
winget install --id Kitware.CMake @common
winget install --id Ninja-build.Ninja @common
winget install --id Microsoft.msmpi @common
winget install --id Microsoft.msmpisdk @common
winget install --id Git.Git @common
winget install --id JRSoftware.InnoSetup @common
```

</details>

### 1.2 VTK (opcional, para os dumps `*/vtk` e `*/vtm`) — `install-vtk.ps1`

O LIGGGHTS usa o módulo MPI do VTK em todos os dumps VTK, então o VTK precisa
ser compilado **com a feature `mpi`**. O script, que não precisa de
administrador:

1. clona e inicializa o vcpkg em `C:\vcpkg` (outro lugar: `-VcpkgRoot <pasta>`);
2. configura o triplet `x64-windows` para compilar só release, o que reduz
   o tempo quase pela metade (para manter debug também: `-WithDebug`);
3. obtém o código do **VTK-m**: o `vtk[mpi]` depende dele, e o GitLab da
   Kitware responde 403 a downloads automatizados. O script abre o link no
   navegador, espera você salvar o arquivo na pasta Downloads, confere o
   SHA512 e o coloca no cache do vcpkg. Se já tiver o arquivo, passe
   `-VtkmArchive <caminho\vtk-m-v2.3.0.tar.gz>`;
4. roda `vcpkg install "vtk[mpi]:x64-windows" --recurse`.

Pode ser executado de novo sem problemas: o que já foi feito é pulado.

A compilação é longa: além do VTK, o vcpkg compila VTK-m, HDF5, SEACAS e
outras dependências, o que leva algumas horas (com debug, cerca do dobro).
Se o vcpkg estiver em outro lugar que não `C:\vcpkg`, defina
`LIGGGHTS_VCPKG` antes de rodar o `build.bat`.

> A linha `set(VCPKG_BUILD_TYPE release)` é adicionada a um arquivo do
> próprio vcpkg (`triplets\x64-windows.cmake`); se um `git pull` no vcpkg
> reclamar dele, rode `git -C C:\vcpkg checkout triplets\x64-windows.cmake`
> e rode o `install-vtk.ps1` de novo.

---

## 2. Compilando

Na raiz do repositório, em qualquer terminal (o script carrega o ambiente do
MSVC sozinho):

```bat
packaging\windows\build.bat        :: sem VTK
packaging\windows\build.bat vtk    :: com VTK (variante MPI)
```

O script:

1. localiza o Visual Studio via `vswhere` e carrega o `vcvars64.bat`;
2. configura e compila a variante MPI em `build-win\mpi`;
3. configura e compila a variante serial em `build-win\serial` (sempre sem VTK);
4. se o Inno Setup 6 estiver instalado, gera `build-win\installer\liggghts-<versão>-win64-setup.exe`
   (ou `...-win64-vtk-setup.exe` com `build.bat vtk`).

Sem `vtk`, o script apaga DLLs que tenham sobrado em `build-win\mpi` de uma
build anterior com VTK, para que não entrem no instalador.

Saídas:

```
build-win\mpi\liggghts.exe          variante MPI (+ DLLs do VTK copiadas pelo vcpkg)
build-win\serial\liggghts.exe       variante serial
build-win\installer\*.exe           instalador
```

`build-win/` está no `.gitignore`.

### Compilando manualmente (sem o script)

No "x64 Native Tools Command Prompt for VS 2022":

```bat
cmake -S src -B build-win\mpi -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_VTK=OFF
cmake --build build-win\mpi

cmake -S src -B build-win\serial -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_MPI=OFF -DENABLE_VTK=OFF
cmake --build build-win\serial
```

Com VTK, acrescente à variante MPI:

```
-DENABLE_VTK=ON "-DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows
```

---

## 3. Instalador (Inno Setup)

Script: [`liggghts.iss`](liggghts.iss). O instalador:

- instala `liggghts.exe`, `liggghts-serial.exe` e as DLLs de terceiros em `C:\Program Files\LIGGGHTS\bin`;
- instala o **Visual C++ Redistributable** silenciosamente, apenas se não houver
  um runtime 14.40+ na máquina;
- instala o **MS-MPI** silenciosamente, apenas se ele ainda não estiver
  instalado (o `liggghts.exe` e as DLLs do VTK dependem do `msmpi.dll`);
- opcionalmente adiciona `bin\` ao `PATH` do sistema (removido na desinstalação);
- instala os exemplos (componente opcional) e cria atalhos no Menu Iniciar;
- tem interface em português e inglês e exibe a licença GPL.

Os instaladores das dependências são embutidos a partir da máquina de build,
sem download durante a instalação:

| Dependência | Origem |
|---|---|
| `vc_redist.x64.exe` | `%VCToolsRedistDir%` (Build Tools do VS) — passado pelo `build.bat` via `/DVcRedist=` |
| `msmpisetup.exe` | registro `HKLM\SOFTWARE\Microsoft\MPI\RedistPath` (o runtime do MS-MPI guarda uma cópia do próprio instalador) |

Para compilar o `.iss` diretamente:

```bat
"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" /DVcRedist=<caminho\vc_redist.x64.exe> packaging\windows\liggghts.iss
```

Parâmetros opcionais: `/DAppVersion=x.y.z`, `/DMsMpiRedist=<caminho\msmpisetup.exe>`,
`/DWithVtk` (só muda o nome do instalador para `*-vtk-setup.exe`; as DLLs do
VTK entram sempre que estiverem em `build-win\mpi`).

---

## 4. Uso na máquina de destino

```bat
:: serial
liggghts-serial -in in.script

:: paralelo, 8 processos
mpiexec -n 8 liggghts -in in.script
```

Sem o instalador, copie os executáveis (e as DLLs ao lado do `liggghts.exe`) e
instale manualmente:

- [Visual C++ Redistributable 2015–2022 x64](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- MS-MPI runtime (`msmpisetup.exe -unattend`) — só para a variante MPI

Para conferir de quais DLLs um executável depende:

```bat
dumpbin /dependents build-win\serial\liggghts.exe
```

---

## 5. Alterações no código-fonte

O repositório já trazia suporte parcial a MSVC (`#ifdef _WIN32` nos pontos
específicos de POSIX, cabeçalhos substitutos em `src/WINDOWS/extra/`, flags MSVC
no `CMakeLists.txt`). Foram necessárias as alterações abaixo.

### 5.1 `src/CMakeLists.txt` — conflito de nome `liggghts.lib`

No Windows, a biblioteca estática (`liggghts_static`) e a *import library* da
DLL (`liggghts_shared`) eram ambas geradas como `liggghts.lib`, e o Ninja
recusava o build (`multiple rules generate liggghts.lib`).

- A biblioteca estática passa a se chamar `liggghts_static.lib` no Windows.
- A DLL usa `WINDOWS_EXPORT_ALL_SYMBOLS`, já que o código não marca símbolos
  com `__declspec(dllexport)`; sem isso a DLL não teria *import library*.

### 5.2 Remoção de `src/WINDOWS/extra/stdint.h` e `inttypes.h`

Eram cópias do projeto *msinttypes*, para MSVC anterior a 2010 (que não tinha
esses cabeçalhos). Como `WINDOWS/extra` entra no *include path*, eles
sobrepunham os cabeçalhos do MSVC atual, e a STL falhava em `<xlocnum>` com
`'PTRDIFF_MAX': identificador não declarado` em praticamente todos os arquivos.
O MSVC 2015+ já fornece ambos.

### 5.3 `src/error_special.h` — ponteiro inválido (bug multiplataforma)

`SpecialMessages::generate_message()` retornava `c_str()` de uma
`std::string` local, que é destruída no retorno da função. No Linux o texto
costumava sair correto por acaso; no MSVC as mensagens de erro exibiam lixo.
A mensagem agora é guardada em um membro (`msg_`).

### 5.4 `src/CMakeLists.txt` — build sem MPI (`-DENABLE_MPI=OFF`)

O CMake anunciava "Using MPI stubs", mas não compilava `src/STUBS/mpi.c` nem
adicionava `src/STUBS` ao *include path*, então o build serial não funcionava
(em nenhuma plataforma). Agora, com MPI desligado, `STUBS/mpi.c` entra no
alvo `liggghts_obj` e `STUBS` é adicionado aos includes.

### 5.5 Arquivos novos

| Arquivo | Função |
|---|---|
| `packaging/windows/install-deps.ps1` | instala as ferramentas de build via winget |
| `packaging/windows/install-vtk.ps1` | instala o vcpkg e o VTK com MPI |
| `packaging/windows/build.bat` | build das duas variantes + instalador |
| `packaging/windows/liggghts.iss` | script do Inno Setup |
| `packaging/windows/LEIAME.txt` | guia do usuário final, exibido pelo instalador |
| `packaging/windows/README.md` | este documento |
| `.gitignore` | ignora `build-win/` |
| `.gitattributes` | mantém CRLF nos scripts de `packaging/` |

---

## 6. Limitações conhecidas

- **Variante serial sem VTK.** Todos os dumps baseados na biblioteca VTK
  (`custom/vtk`, `custom/vtm`, `mesh/vtk`, `mesh/vtm`, `atom/vtk`,
  `local/gran/vtk`) usam `vtkMPIController` e os writers paralelos, o que não
  funciona sobre os *stubs* de MPI. Na variante serial use `dump custom`,
  `dump mesh/stl` ou os dumps VTK que não dependem da biblioteca
  (`decomposition/vtk`, `euler/vtk`). Suportar VTK na variante serial exige
  alterar esses dumps para usar `vtkDummyController` e os writers não
  paralelos quando compilado sem MPI.
- **DLLs do VTK.** Com VTK, as DLLs copiadas pelo vcpkg para `build-win\mpi`
  precisam acompanhar o `liggghts.exe` (o instalador já as inclui).
- **`liggghts.dll`** (biblioteca compartilhada, usada pelo wrapper Python) é
  compilada, mas não é incluída no instalador.
- **Licença.** O LIGGGHTS é GPL: ao distribuir os executáveis, o código-fonte
  correspondente (incluindo estas alterações) deve estar disponível aos
  usuários.
- O instalador foi gerado e compilado, mas ainda precisa ser validado numa
  máquina Windows limpa (instalação do VC++/MS-MPI, `PATH`, desinstalação).

---

## 7. Solução de problemas

| Sintoma | Causa / solução |
|---|---|
| `Could NOT find VTK (missing: VTK_DIR)` | Use `build.bat vtk`. O script usa `cmake --fresh`, pois o toolchain do vcpkg só é aplicado a um cache novo. |
| `Could not find toolchain file: "C:\Program"` | O `vcvars64.bat` define `VCPKG_ROOT` apontando para o vcpkg embutido no Visual Studio. O script usa `LIGGGHTS_VCPKG` (padrão `C:\vcpkg`); defina-o se o seu vcpkg estiver em outro lugar. |
| `vtkMPIController.h: No such file or directory` | O VTK foi instalado sem MPI. Rode o `install-vtk.ps1`, ou `vcpkg install "vtk[mpi]:x64-windows" --recurse`. |
| vcpkg: `curl operation failed with response code 403` ao baixar `vtk-m` de `gitlab.kitware.com` | O GitLab da Kitware bloqueia downloads automatizados, e `vtk[mpi]` exige o VTK-m. O `install-vtk.ps1` resolve isso; manualmente: baixe pelo navegador `https://gitlab.kitware.com/vtk/vtk-m/-/archive/v2.3.0/vtk-m-v2.3.0.tar.gz`, salve como `C:\vcpkg\downloads\vtk-vtk-m-v2.3.0.tar.gz` (confira o SHA512 em `C:\vcpkg\ports\vtk-m\portfile.cmake`) e rode o `vcpkg install` de novo. |
| `'PTRDIFF_MAX': identificador não declarado` | Cabeçalhos antigos em `src/WINDOWS/extra` (veja 5.2). |
| `multiple rules generate liggghts.lib` | Veja 5.1. |
| `ERROR: Invalid dump style` ao rodar | O script usa um dump VTK e o executável foi compilado sem VTK (ou é a variante serial). |
| `msmpi.dll não encontrado` | Instale o runtime do MS-MPI ou use `liggghts-serial.exe`. |

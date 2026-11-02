<#
.SYNOPSIS
    Instala y configura GitHub CLI (gh) portable para usarlo desde DSH.

.DESCRIPTION
    Instalador idempotente, sin permisos de administrador y sin instaladores MSI:

      1. descarga la release oficial de GitHub CLI (o la ultima estable),
      2. verifica su SHA256 contra el archivo de checksums de la release,
      3. copia gh.exe a una carpeta del usuario y comprueba el PATH,
      4. actualiza el bloque gestionado de $DSH_HOME\AGENTS.md con la ruta,
         la version y el login reales,
      5. opcionalmente inicia el login web (el usuario solo autoriza en GitHub).

    No escribe tokens en ningun archivo: la credencial queda en el Administrador
    de credenciales de Windows (keyring) via gh.

.PARAMETER Version
    Version a instalar (por defecto 2.102.0). Usa 'latest' para la ultima estable.

.PARAMETER InstallDir
    Carpeta destino de gh.exe. Por defecto %USERPROFILE%\.local\bin.

.PARAMETER DshHome
    Directorio de DSH cuyo AGENTS.md se actualiza. Por defecto $env:DSH_HOME o
    %USERPROFILE%\.dsh.

.PARAMETER Login
    Tras instalar, inicia 'gh auth login --web' en primer plano. El codigo de
    8 caracteres lo genera gh en este equipo y aparece en la terminal; se pega
    en https://github.com/login/device. No es el codigo 2FA. Pensado para
    ejecucion humana en una terminal; un agente debe lanzarlo como tarea en
    segundo plano para poder leer el codigo de un solo uso.

.PARAMETER UpdateInstructionsOnly
    No descarga ni copia nada: solo actualiza AGENTS.md con el estado actual.

.PARAMETER NoPathUpdate
    No anade InstallDir al PATH del usuario si falta.

.PARAMETER Force
    Reinstala aunque la version instalada coincida.

.PARAMETER Check
    Solo diagnostico: no descarga, no escribe y no modifica nada.

.PARAMETER Uninstall
    Elimina gh.exe y el bloque gestionado de AGENTS.md. No cierra la sesion de
    GitHub (para eso: gh auth logout --hostname github.com).

.EXAMPLE
    pwsh -NoProfile -File install-gh.ps1 -Check

.EXAMPLE
    pwsh -NoProfile -File install-gh.ps1
#>
[CmdletBinding()]
param(
    [string]$Version = '2.102.0',
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.local\bin'),
    [string]$DshHome = $(
        if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
    ),
    [switch]$Login,
    [switch]$UpdateInstructionsOnly,
    [switch]$NoPathUpdate,
    [switch]$Force,
    [switch]$Check,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 lee los archivos UTF-8 sin BOM como ANSI. Para que
# '-File' conserve los acentos, nos releemos en UTF-8 y nos reejecutamos una vez.
# Con 'irm | iex' el contenido llega ya decodificado y este bloque no actua.
if ($PSVersionTable.PSVersion.Major -lt 7 -and $PSCommandPath) {
    $fileBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
    $hasBom = ($fileBytes.Length -ge 3 -and $fileBytes[0] -eq 0xEF -and
        $fileBytes[1] -eq 0xBB -and $fileBytes[2] -eq 0xBF)
    if (-not $hasBom -and -not $global:__DshGhReexec) {
        $global:__DshGhReexec = $true
        $utf8Text = [System.Text.Encoding]::UTF8.GetString($fileBytes)
        & ([scriptblock]::Create($utf8Text)) @PSBoundParameters
        exit $LASTEXITCODE
    }
}

# TLS 1.2 explicito: Windows 10/11 con Windows PowerShell 5.1 puede seguir
# negociando TLS 1.0 por defecto y GitHub rechaza la conexion.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# La barra de progreso de Invoke-WebRequest ralentiza y parece colgada en 5.1.
$ProgressPreference = 'SilentlyContinue'

$script:BeginMarker = '<!-- dsh-github-cli:begin'
$script:EndMarker = '<!-- dsh-github-cli:end -->'
$script:GhostPath = Join-Path $InstallDir 'gh.exe'

# Compatible con Windows PowerShell 5.1 y PowerShell 7. El archivo se guarda en
# UTF-8 sin BOM para que 'irm | iex' lo parsee; 5.1 usa el bloque de reejecucion
# de arriba para conservar los acentos al ejecutarlo con -File.

function Write-Step([string]$Message) { Write-Host "[INFO] $Message" }
function Write-Ok([string]$Message) { Write-Host "[OK]   $Message" }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" }
function Write-Next([string]$Message) { Write-Host "[NEXT] $Message" }

function Test-CommandPath([string]$Directory) {
    $parts = $env:PATH -split ';'
    return ($parts | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }).Count -gt 0
}

function Get-GhVersion([string]$GhExe) {
    if (-not (Test-Path -LiteralPath $GhExe)) { return $null }
    try {
        $line = (& $GhExe --version 2>$null | Select-Object -First 1)
    }
    catch { return $null }
    if ($line -match 'gh version (\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Get-GhLogin([string]$GhExe) {
    if (-not (Test-Path -LiteralPath $GhExe)) { return $null }
    # En Windows PowerShell 5.1 el stderr de un comando nativo se convierte en
    # error y, con ErrorActionPreference=Stop, 'gh auth status' sin sesion
    # abortaria el instalador. Se silencia solo durante estas dos llamadas.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & $GhExe auth status *> $null
        if ($LASTEXITCODE -ne 0) { return $null }
        $ghLogin = (& $GhExe api user --jq .login 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($ghLogin)) { return $null }
        return $ghLogin.Trim()
    }
    catch { return $null }
    finally { $ErrorActionPreference = $previous }
}

function Get-ReleaseAssetArch {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'windows_arm64' }
    return 'windows_amd64'
}

function Resolve-LatestVersion {
    $headers = @{ 'User-Agent' = 'dsh-instalar-github-cli' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -Headers $headers
    return ($release.tag_name -replace '^v', '')
}

function Save-GhAsset([string]$AssetVersion, [string]$Arch, [string]$Destination) {
    $asset = "gh_${AssetVersion}_${Arch}.zip"
    $base = "https://github.com/cli/cli/releases/download/v$AssetVersion"
    $zipPath = Join-Path $Destination $asset
    $sumPath = Join-Path $Destination "gh_${AssetVersion}_checksums.txt"

    Write-Step "Descargando $asset ..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri "$base/$asset" -OutFile $zipPath -UseBasicParsing
    Invoke-WebRequest -Uri "$base/gh_${AssetVersion}_checksums.txt" -OutFile $sumPath -UseBasicParsing

    $line = Select-String -LiteralPath $sumPath -Pattern ([regex]::Escape($asset) + '\s*$') |
        Select-Object -First 1
    if (-not $line) { throw "El archivo de checksums no contiene $asset" }
    $expected = ($line.Line -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "SHA256 no coincide para $asset (esperado $expected, obtenido $actual)"
    }
    Write-Ok "SHA256 verificado: $actual"
    return @{ Zip = $zipPath; Asset = $asset }
}

function Install-FromZip([string]$ZipPath, [string]$DestinationGh) {
    $extract = Join-Path ([System.IO.Path]::GetDirectoryName($ZipPath)) 'extract'
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extract -Force
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'gh.exe' | Select-Object -First 1
    if (-not $exe) { throw 'El ZIP descargado no contiene bin\gh.exe' }
    $parent = Split-Path -Parent $DestinationGh
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $exe.FullName -Destination $DestinationGh -Force
    Write-Ok "gh.exe copiado a $DestinationGh"
}

function Ensure-UserPath([string]$Directory) {
    if (Test-CommandPath $Directory) {
        Write-Ok "La carpeta ya esta en el PATH de esta sesion"
        return
    }
    if ($NoPathUpdate) {
        Write-Warn "La carpeta no esta en el PATH (se omite -NoPathUpdate)"
        return
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    $parts = @($userPath -split ';' | Where-Object { $_ -ne '' })
    if ($parts -notcontains $Directory) {
        $newPath = (@($parts) + $Directory) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Ok "Carpeta anadida al PATH del usuario"
    }
    $env:PATH = $env:PATH.TrimEnd(';') + ';' + $Directory
    Write-Ok "PATH actualizado en esta sesion"
}

function New-InstructionsBlock([string]$GhExe) {
    $installedVersion = Get-GhVersion $GhExe
    if (-not $installedVersion) { $installedVersion = 'desconocida' }

    $ghLogin = Get-GhLogin $GhExe
    if ($ghLogin) {
        $authBlock = @'
- Sesión activa en `github.com` como `__LOGIN__` (token en el gestor de
  credenciales del sistema; el login web concede `repo`, `read:org`, `gist` y
  `workflow`). Verifica con `gh auth status`; el login real, con
  `gh api user --jq .login`.
'@
        $authBlock = $authBlock.Replace('__LOGIN__', $ghLogin).TrimEnd()
    }
    else {
        $authBlock = @'
- Sesión **pendiente**: ejecuta
  `gh auth login --hostname github.com --git-protocol https --web` y autoriza en
  el navegador. Nunca pidas el token por el chat.
'@
        $authBlock = $authBlock.TrimEnd()
    }

    $block = @'
<!-- dsh-github-cli:begin (bloque gestionado; no editar a mano) -->
## GitHub — usar GitHub CLI (`gh`)

Toda pregunta sobre GitHub (repositorios, issues, PRs, releases, Actions, gists o
código) debe resolverse con datos reales usando **GitHub CLI**, sin configuración
por sesión.

- `gh` __VERSION__ instalado en modo portable en `__GH_PATH__` (esa carpeta está
  en el PATH del usuario; si no se resuelve, invoca la ruta absoluta).
__AUTH_BLOCK__
- No uses otro método (scraping, API sin autenticar) si `gh` está disponible.

### Comprobación previa (obligatoria)

1. `gh --version` — si falla, `gh` no está instalado: no inventes datos. Informa
   de que falta el binario y ofrece instalar el modo portable.
2. `gh auth status` — si no hay sesión, no pidas el token por el chat. Indica que
   el dueño del equipo debe ejecutar:
   `gh auth login --hostname github.com --git-protocol https --web`

### Comandos de referencia

| Consulta | Comando |
|---|---|
| Todos los repos | `gh repo list <login> --limit 1000 --json name,visibility,description,updatedAt,stargazerCount` |
| Solo públicos | añadir `--visibility public` |
| Detalle de un repo | `gh repo view <owner>/<repo> --json name,description,visibility,defaultBranchRef,url` |
| Issues abiertas | `gh issue list -R <owner>/<repo> --state open` |
| Pull requests | `gh pr list -R <owner>/<repo>` |
| API arbitraria | `gh api <ruta>` (p. ej. `gh api user --jq .login`) |

### Límites

- **Solo lectura por defecto**: no crear issues/PRs, no hacer push, no cambiar
  visibilidad, configuración ni borrar nada, salvo petición explícita.
- **Nunca** imprimir tokens ni escribirlos en archivos, commits o mensajes.
- **Nunca** conceder el scope `delete_repo`: es la barrera que impide borrar
  repositorios. Si alguna vez se necesita, exige confirmación explícita y backup.
- Si faltan repos privados, el token no tiene scope `repo`:
  `gh auth refresh -s repo,read:org`. Ante 403/429, es límite de peticiones:
  espaciar las consultas.
<!-- dsh-github-cli:end -->
'@

    $block = $block.Replace('__VERSION__', $installedVersion)
    $block = $block.Replace('__GH_PATH__', $GhExe)
    $block = $block.Replace('__AUTH_BLOCK__', $authBlock)
    return $block
}

function Update-AgentsFile([string]$Path, [string]$Block) {
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath $Path)) {
        $header = @'
# Contexto global del usuario

> Instrucciones globales: DSH carga este archivo en la primera petición de
> **todas** las sesiones, sin importar la carpeta de trabajo.

'@
        [System.IO.File]::WriteAllText($Path, $header + [Environment]::NewLine + $Block + [Environment]::NewLine, $encoding)
        return 'creado'
    }

    $raw = [System.IO.File]::ReadAllText($Path)
    $begin = $raw.IndexOf($script:BeginMarker)
    $end = $raw.IndexOf($script:EndMarker)

    if ($begin -ge 0 -and $end -gt $begin) {
        $new = $raw.Substring(0, $begin) + $Block + $raw.Substring($end + $script:EndMarker.Length)
    }
    else {
        # Migracion: si ya existe una seccion de GitHub sin marcadores (por ejemplo,
        # escrita a mano), se sustituye por el bloque gestionado en vez de duplicarla.
        $heading = '## GitHub — usar GitHub CLI'
        $headingIndex = $raw.IndexOf($heading)
        if ($headingIndex -ge 0) {
            $nextHeading = $raw.IndexOf("`n## ", $headingIndex + $heading.Length)
            if ($nextHeading -ge 0) {
                $new = $raw.Substring(0, $headingIndex) + $Block + $raw.Substring($nextHeading)
            }
            else {
                $new = $raw.Substring(0, $headingIndex) + $Block + [Environment]::NewLine
            }
        }
        else {
            $new = $raw.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $Block + [Environment]::NewLine
        }
    }

    if ($new -eq $raw) { return 'sin cambios' }
    [System.IO.File]::WriteAllText($Path, $new, $encoding)
    return 'actualizado'
}

# ---------------------------------------------------------------------------
# Flujo principal
# ---------------------------------------------------------------------------

try {
    Write-Step "Destino: $script:GhostPath"
    Write-Step "AGENTS.md: $(Join-Path $DshHome 'AGENTS.md')"

    if ($Uninstall) {
        if (Test-Path -LiteralPath $script:GhostPath) {
            Remove-Item -LiteralPath $script:GhostPath -Force
            Write-Ok "Eliminado $script:GhostPath"
        }
        else {
            Write-Warn "No existe $script:GhostPath"
        }
        $agentsPath = Join-Path $DshHome 'AGENTS.md'
        if (Test-Path -LiteralPath $agentsPath) {
            $raw = [System.IO.File]::ReadAllText($agentsPath)
            $begin = $raw.IndexOf($script:BeginMarker)
            $end = $raw.IndexOf($script:EndMarker)
            if ($begin -ge 0 -and $end -gt $begin) {
                $new = $raw.Remove($begin, $end + $script:EndMarker.Length - $begin).TrimEnd() + [Environment]::NewLine
                [System.IO.File]::WriteAllText($agentsPath, $new, (New-Object System.Text.UTF8Encoding($false)))
                Write-Ok "Bloque de GitHub eliminado de $agentsPath"
            }
        }
        Write-Next 'La sesion de GitHub sigue guardada. Para cerrarla: gh auth logout --hostname github.com'
        $global:LASTEXITCODE = 0
        return
    }

    $installedVersion = Get-GhVersion $script:GhostPath
    $ghLogin = Get-GhLogin $script:GhostPath
    $arch = Get-ReleaseAssetArch

    if ($Check) {
        if ($installedVersion) { Write-Ok "gh $installedVersion instalado en $script:GhostPath" }
        else { Write-Warn "gh no esta instalado en $script:GhostPath" }
        if ($ghLogin) { Write-Ok "Sesion iniciada como $ghLogin" }
        else { Write-Warn 'Sin sesion de GitHub (falta gh auth login)' }
        Write-Ok ("PATH: " + $(if (Test-CommandPath $InstallDir) { 'correcto' } else { 'falta ' + $InstallDir }))
        $agentsPath = Join-Path $DshHome 'AGENTS.md'
        if (Test-Path -LiteralPath $agentsPath) {
            $raw = [System.IO.File]::ReadAllText($agentsPath)
            if ($raw.IndexOf($script:BeginMarker) -ge 0) { Write-Ok "AGENTS.md con bloque gestionado" }
            else { Write-Warn 'AGENTS.md existe sin bloque gestionado (se migrara al ejecutar la instalacion)' }
        }
        else { Write-Warn 'AGENTS.md no existe' }
        $global:LASTEXITCODE = 0
        return
    }

    if (-not $UpdateInstructionsOnly) {
        $needsInstall = $true
        if ($installedVersion -and -not $Force) {
            $wanted = $Version
            if ($wanted -eq 'latest' -or $installedVersion -eq $wanted) { $needsInstall = $false }
        }

        if ($needsInstall) {
            $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('gh-install-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                $downloadVersion = $Version
                try {
                    $asset = Save-GhAsset $downloadVersion $arch $temp
                }
                catch {
                    $status = $null
                    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
                    if ($status -eq 404) {
                        $latest = Resolve-LatestVersion
                        Write-Warn "La version $downloadVersion no existe; se usa la ultima estable ($latest)"
                        $downloadVersion = $latest
                        $asset = Save-GhAsset $downloadVersion $arch $temp
                    }
                    else { throw }
                }
                Install-FromZip $asset.Zip $script:GhostPath
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
            $installedVersion = Get-GhVersion $script:GhostPath
            if (-not $installedVersion) { throw 'gh no responde tras la instalacion' }
            Write-Ok "gh $installedVersion operativo"
        }
        else {
            Write-Ok "gh $installedVersion ya instalado (usa -Force para reinstalar)"
        }
    }
    else {
        if (-not $installedVersion) { throw 'No hay gh instalado; ejecuta el instalador sin -UpdateInstructionsOnly' }
    }

    if (-not $NoPathUpdate) { Ensure-UserPath $InstallDir }

    if ($Login -and -not $ghLogin) {
        Write-Step 'Iniciando login web de GitHub. El codigo de 8 caracteres lo genera gh en este equipo, no GitHub: aparece como "First copy your one-time code" y se pega en https://github.com/login/device. No es el codigo 2FA. Si no lo ves, Ctrl+C y repite: se genera uno nuevo.'
        # stderr del comando nativo no debe abortar el flujo en 5.1.
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $script:GhostPath auth login --hostname github.com --git-protocol https --web
        }
        finally {
            $ErrorActionPreference = $previous
        }
        $ghLogin = Get-GhLogin $script:GhostPath
    }

    $agentsPath = Join-Path $DshHome 'AGENTS.md'
    $block = New-InstructionsBlock $script:GhostPath
    $result = Update-AgentsFile $agentsPath $block
    Write-Ok "AGENTS.md: $result"

    if ($ghLogin) {
        Write-Ok "Sesion de GitHub activa como $ghLogin"
        Write-Next "Prueba: gh repo list $ghLogin --limit 5 --json name,visibility"
    }
    else {
        Write-Warn 'GitHub todavia sin sesion'
        Write-Next 'Ejecuta: gh auth login --hostname github.com --git-protocol https --web'
        Write-Next 'El codigo de 8 caracteres lo genera gh en este equipo y aparece en esa terminal (no es el 2FA). Pegalo en https://github.com/login/device.'
        Write-Next 'Si no ves el codigo, Ctrl+C y repite el comando: se genera uno nuevo (caduca en ~15 min).'
        Write-Next 'Despues vuelve a ejecutar este script (sin -Login) para fijar el login en AGENTS.md'
    }

    # 'gh auth status' sin sesion deja LASTEXITCODE=1 aunque sea un caso
    # esperado; el exito del script debe reflejarse como 0 en el proceso.
    $global:LASTEXITCODE = 0
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($PSCommandPath) { exit 1 }
    $global:LASTEXITCODE = 1
    return
}

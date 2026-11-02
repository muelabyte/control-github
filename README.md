# GitHub CLI en un comando para DSH (Windows, Linux y macOS)

Instalador de **una sola ejecución** que deja GitHub CLI (`gh`) listo para usarse desde [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH) y otros agentes:

- instala `gh` **portable** en Windows, Linux y macOS (sin administrador ni `sudo`),
- verifica el **SHA256** contra la release oficial,
- lo deja en el **PATH** del usuario,
- configura el bloque de GitHub en `~/.dsh/AGENTS.md` (o `$DSH_HOME/AGENTS.md`),
- **guía el login** web y explica de dónde sale el código de 8 dígitos,
- es idempotente: si la versión coincide no descarga ni reemplaza nada; si difiere, no toca el binario y te dice qué hacer.

> Proyecto no oficial. No está afiliado a GitHub ni a DeepSeek.

---

## Inicio rápido

### Windows (PowerShell 5.1 o 7)

```powershell
irm https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.ps1 | iex
```

Con login incluido:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.ps1'))) -Login
```

Desde `cmd.exe` o Win+R:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.ps1 | iex"
```

Diagnóstico, sin instalar nada:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.ps1'))) -Check
```

### Linux y macOS

```bash
curl -fsSL https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.sh | bash
```

Con login incluido:

```bash
curl -fsSL https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.sh | bash -s -- --login
```

Diagnóstico:

```bash
curl -fsSL https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.sh | bash -s -- --check
```

### Copia local (sin ejecutar código remoto)

```powershell
git clone https://github.com/muelabyte/control-github.git
cd control-github
# Windows
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1
# Linux / macOS
bash ./scripts/install-gh.sh
```

### Desde la release

```powershell
# Windows
irm https://github.com/muelabyte/control-github/releases/download/v1.2.0/install-gh.ps1 | iex
```

```bash
# Linux / macOS
curl -fsSL https://github.com/muelabyte/control-github/releases/download/v1.2.0/install-gh.sh | bash
```

---

## Requisitos

| Plataforma | Detalle |
|---|---|
| Windows 10/11 | **Windows PowerShell 5.1** o PowerShell 7 (`pwsh`). Sin administrador |
| Linux | glibc (amd64, arm64, 386, armv6, ppc64le, s390x). `bash` 3.2+, `curl` o `wget`, `tar`. Sin `sudo` |
| macOS 12+ | Intel o Apple Silicon. `curl`, `tar` y `unzip` del sistema. Sin `sudo` |
| Red | Acceso a `github.com`, `api.github.com` y `objects.githubusercontent.com` |

En Linux el script instala en `~/.local/bin` y añade la carpeta al rc de tu shell (`.bashrc`, `.zshrc` o `.profile`). En macOS usa `~/.local/bin` y `.zshrc`/`.bash_profile`.

Si `curl` no está disponible en Linux:

```bash
sudo apt install curl        # Debian/Ubuntu
sudo dnf install curl        # Fedora
sudo apk add curl            # Alpine (ver nota más abajo)
```

> **Alpine/musl:** el binario oficial de `gh` es glibc y no funciona en Alpine. Usa el paquete de la distro: `sudo apk add github-cli`.

---

## El código de 8 dígitos

El código **no viene de GitHub ni de tu cuenta**: lo genera `gh` en tu equipo al iniciar el login.

1. Aparece en la terminal como `First copy your one-time code: XXXX-XXXX` (8 caracteres con guion).
2. Normalmente se copia solo al portapapeles.
3. Se pega en <https://github.com/login/device> y se autoriza.
4. **No es el código 2FA** del autenticador.
5. Si no lo ves: `Ctrl+C`, repite el comando y se genera uno nuevo. Caduca en ~15 minutos.

Este paso es el **único** que no se puede automatizar: GitHub exige que una persona autorice el dispositivo desde el navegador.

---

## Qué hace exactamente

Ambos instaladores (`install-gh.ps1` e `install-gh.sh`) siguen el mismo flujo:

1. Comprueban si `gh` ya está instalado en la carpeta destino.
2. Si falta, descargan la release oficial de `cli/cli` y verifican el SHA256.
3. Extraen el binario y lo copian a la carpeta del usuario.
4. Comprueban el PATH (lo añaden al perfil del usuario si falta).
5. Leen/crean `AGENTS.md` y actualizan un **bloque gestionado** con la ruta, la versión y el login real.
6. Si no hay sesión, explican cómo iniciarla; con `--login` / `-Login`, la lanzan.
7. Verifican y muestran el siguiente comando de prueba.

El bloque gestionado lleva marcadores (`dsh-github-cli:begin` / `end`) y es idempotente: se puede ejecutar varias veces sin duplicar contenido. Si ya existe una sección de GitHub escrita a mano, la **migra** al bloque en lugar de duplicarla.

---

## Si ya está instalado

El instalador **no limpia nada ni hace una instalación desde cero**. No toca credenciales, ni la configuración de `gh`, ni otras copias. Solo puede cambiar el binario de su carpeta destino, el PATH y el bloque de `AGENTS.md`:

| Estado detectado | Sin flags | Con `-Force` |
|---|---|---|
| No hay `gh` | Instala | Reinstala |
| `gh` en destino, **misma versión** | Sin descarga; solo completa PATH/`AGENTS.md` si falta | Reinstala el binario |
| `gh` en destino, **versión distinta** (más nueva o más vieja) | **No toca nada**; avisa y sale con código 2 | Reemplaza, avisando si es downgrade |
| `gh` en destino **corrupto** | Lo repara | Lo repara |
| `gh` en el PATH en **otra ruta**, destino vacío | **No duplica**; avisa y sale con código 2 | Instala en paralelo |
| Tras instalar, `gh` del PATH apunta a otra ruta | Avisa del conflicto de PATH | Igual |

Mensajes y códigos de salida:

- `0`: éxito, instalación o **sin cambios**.
- `2`: acción bloqueada; repite con `-Force` / `--force` si quieres reemplazar o duplicar.
- `1`: error real (red, SHA256, permisos, binario en uso).

Antes de tocar nada puedes simular la decisión:

```powershell
# Windows
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.ps1'))) -Check
```

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/muelabyte/control-github/v1.2.0/scripts/install-gh.sh | bash -s -- --check
```

`-Check` muestra la versión instalada, si hay otra copia en el PATH y la acción prevista (`Sin cambios`, `Instalaría`, `Repararía`, `Requiere -Force`).

---

## Opciones

### Windows (`install-gh.ps1`)

| Opción | Qué hace |
|---|---|
| `-Check` | Solo diagnóstico: no descarga, no escribe, no modifica nada |
| `-Login` | Tras instalar, lanza `gh auth login --web` y muestra el código |
| `-Version <x.y.z>` | Instala una versión concreta; `latest` para la última estable |
| `-Force` | Reinstala y es la única vía para cambiar de versión, incluido un downgrade |
| `-NoPathUpdate` | No añade la carpeta al PATH del usuario |
| `-UpdateInstructionsOnly` | No instala; solo actualiza `AGENTS.md` |
| `-Uninstall` | Elimina `gh.exe` y el bloque gestionado de `AGENTS.md` |

### Linux y macOS (`install-gh.sh`)

| Opción | Qué hace |
|---|---|
| `--check` | Solo diagnóstico: no descarga, no escribe |
| `--login` | Tras instalar, lanza `gh auth login --web` |
| `--version X` | Instala una versión concreta; `latest` para la última estable |
| `--force` | Reinstala y es la única vía para cambiar de versión, incluido un downgrade |
| `--install-dir RUTA` | Carpeta destino (por defecto `~/.local/bin`) |
| `--dsh-home RUTA` | Carpeta de DSH (por defecto `~/.dsh`) |
| `--no-path-update` | No modifica el rc del shell |
| `--update-instructions-only` | No instala; solo actualiza `AGENTS.md` |
| `--uninstall` | Elimina `gh` y el bloque de `AGENTS.md` |

---

## Ejemplos

```powershell
# Windows
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Check
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Login
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Version latest -Force
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -UpdateInstructionsOnly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Uninstall
```

```bash
# Linux / macOS
bash ./scripts/install-gh.sh --check
bash ./scripts/install-gh.sh --login
bash ./scripts/install-gh.sh --version latest --force
bash ./scripts/install-gh.sh --uninstall
```

Verificación manual:

```powershell
gh --version
gh auth status
gh api user --jq .login
gh repo list --limit 5 --json name,visibility
```

---

## Cómo se integra con DSH

DSH carga `$DSH_HOME/AGENTS.md` en la **primera petición de todas las sesiones**, sin importar la carpeta de trabajo. El bloque que escribe el instalador indica:

- usar `gh` para cualquier consulta de GitHub,
- comprobar `gh --version` y `gh auth status` antes de responder,
- comandos de referencia,
- límites: solo lectura por defecto, sin tokens en archivos y sin `delete_repo`.

El resultado: una sesión nueva puede responder «lista mis repositorios públicos» sin configuración adicional.

---

## Seguridad

- **Sin tokens en archivos.** La credencial la guarda `gh` en el gestor de credenciales del sistema (Administrador de credenciales en Windows, Keychain en macOS, libsecret en Linux).
- **Sin `delete_repo`.** El login por navegador concede `repo`, `read:org`, `gist` y `workflow`; no concede `delete_repo`. Esa ausencia es la barrera que impide borrar repositorios por API. **No la añadas** con `gh auth refresh`.
- **Solo lectura por defecto.** El bloque de `AGENTS.md` prohíbe crear, borrar o cambiar configuración sin petición explícita.
- **El one-liner ejecuta código remoto.** Por eso apunta a un **tag inmutable**, no a `main`, y la release publica el SHA256 de cada script. Si prefieres revisar antes: descarga el script, léelo y ejecútalo en local.
- **TLS 1.2 explícito** en Windows PowerShell 5.1, para evitar fallos de negociación en Windows 10.
- **Ramas y force-push.** El scope `repo` sí permite escribir en ramas. Para protegerlas, activa branch protection o rulesets en GitHub.

---

## Solución de problemas

| Síntoma | Solución |
|---|---|
| `gh: no se reconoce` (Windows) | Abre una terminal nueva; el script añade la carpeta al PATH. Si no, usa `C:\Users\<usuario>\.local\bin\gh.exe`. |
| `gh: command not found` (Linux/macOS) | Abre una shell nueva o ejecuta `source ~/.bashrc` / `source ~/.zshrc`. |
| `You are not logged into any GitHub hosts` | Ejecuta `gh auth login --hostname github.com --git-protocol https --web`. |
| No veo el código de 8 dígitos | Está en la terminal; `Ctrl+C`, repite y aparecerá uno nuevo. |
| No aparecen repos privados | `gh auth refresh -s repo,read:org`. |
| Error 403/429 | Límite de peticiones (5.000/h autenticado): espacia las consultas. |
| `Alpine/musl no soportado` | `sudo apk add github-cli` (paquete de la distro). |
| Bloqueado por ExecutionPolicy | Añade `-ExecutionPolicy Bypass` al comando. |
| `AGENTS.md` no se aplica | Verifica `%USERPROFILE%\.dsh\AGENTS.md` o `~/.dsh/AGENTS.md` y abre una sesión nueva. |
| El one-liner no funciona | El repo debe ser público y el tag debe existir. Usa la copia local. |
| Salió con código 2 y no instaló nada | Ya había otra versión u otra copia. Lee el mensaje: usa `-Force` para reemplazar o `-InstallDir RUTA` para otra carpeta. |
| Quiero actualizar a la última | `-Version latest -Force` (o `--version latest --force`). Sin `-Force`, una instalación existente no se toca. |
| Error de TLS/SSL en Windows 10 | Actualiza Windows o usa PowerShell 7: el script ya fuerza TLS 1.2. |

---

## Estructura

```text
.
├── scripts/
│   ├── install-gh.ps1             # Instalador Windows (PowerShell 5.1 / 7)
│   └── install-gh.sh              # Instalador Linux y macOS (bash 3.2+)
├── ANALISIS-ACCESO-GITHUB-AGENTES.md  # Análisis de alternativas y decisión
├── PLAN-ACCESO-GITHUB-DSH.md      # Plan original de implementación
├── SECURITY.md                    # Política de seguridad
├── LICENSE                        # MIT
└── .github/workflows/validate.yml # CI: sintaxis, smoke test y consistencia
```

---

## Por qué este diseño

El análisis completo está en [ANALISIS-ACCESO-GITHUB-AGENTES.md](./ANALISIS-ACCESO-GITHUB-AGENTES.md). En corto:

- **Script único en lugar de skill:** la instalación ocurre una vez; una skill añadiría descubrimiento y carga sin beneficio.
- **`gh` en lugar de MCP o plugin:** no requiere Node, Docker, servidor ni token en archivos, y funciona en cualquier agente que ejecute shell.
- **Binario portable:** sin administrador en Windows, sin `sudo` en Linux/macOS, y sin depender del gestor de paquetes de cada distro.
- **MCP/plugin** quedan como evolución si se necesitan tools nativas o read-only duro.

---

## Licencia

[MIT](./LICENSE) © 2026 muelabyte

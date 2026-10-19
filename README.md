# GitHub CLI en un comando para DSH

Instalador de **una sola ejecución** para Windows que deja GitHub CLI (`gh`) listo para usarse desde [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH) y otros agentes:

- instala `gh` **portable** (sin administrador, sin MSI),
- verifica el **SHA256** contra la release oficial,
- lo deja en el **PATH** del usuario,
- configura el bloque de GitHub en `~/.dsh/AGENTS.md`,
- **guía el login** web y explica de dónde sale el código de 8 dígitos.

> Proyecto no oficial. No está afiliado a GitHub ni a DeepSeek.

---

## Inicio rápido

### One-liner (PowerShell 7)

```powershell
irm https://raw.githubusercontent.com/muelabyte/control-github/v1.0.0/scripts/install-gh.ps1 | iex
```

Con diagnóstico, sin instalar nada:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/muelabyte/control-github/v1.0.0/scripts/install-gh.ps1'))) -Check
```

### Copia local (sin ejecutar código remoto)

```powershell
git clone https://github.com/muelabyte/control-github.git
cd control-github
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1
```

### Desde la release

```powershell
irm https://github.com/muelabyte/control-github/releases/download/v1.0.0/install-gh.ps1 | iex
```

---

## Requisitos

| Requisito | Detalle |
|---|---|
| Windows | 10 u 11 |
| PowerShell | **7 (`pwsh`)**. Con Windows PowerShell 5.1 el script se detiene para no corromper los acentos del `AGENTS.md` |
| Permisos | Usuario normal; **no** hace falta administrador |
| Red | Acceso a `github.com` y `api.github.com` |

Si no tienes PowerShell 7:

```powershell
winget install --id Microsoft.PowerShell -e
```

---

## El código de 8 dígitos

El código **no viene de GitHub ni de tu cuenta**: lo genera `gh` en tu equipo al iniciar el login.

1. Aparece en la terminal como `First copy your one-time code: XXXX-XXXX` (8 caracteres con guion).
2. Normalmente se copia solo al portapapeles.
3. Se pega en <https://github.com/login/device> y se autoriza.
4. **No es el código 2FA** del autenticador.
5. Si no lo ves: `Ctrl+C`, repite el comando y se genera uno nuevo. Caduca en ~15 minutos.

El instalador imprime esta explicación antes de lanzar el flujo y, con `-Login`, muestra el código y la URL.

---

## Qué hace exactamente

1. Comprueba si `gh` ya está instalado en `%USERPROFILE%\.local\bin\gh.exe`.
2. Si falta, descarga la release oficial de `cli/cli` y verifica el SHA256.
3. Extrae `gh.exe` y lo copia a la carpeta del usuario.
4. Comprueba el PATH (lo añade al del usuario si falta).
5. Lee/crea `%USERPROFILE%\.dsh\AGENTS.md` y actualiza un **bloque gestionado** con la ruta, la versión y el login real.
6. Si no hay sesión, explica cómo iniciarla; con `-Login`, la lanza.
7. Verifica y muestra el siguiente comando de prueba.

El bloque gestionado lleva marcadores (`dsh-github-cli:begin` / `end`) y es idempotente: se puede ejecutar varias veces sin duplicar contenido. Si ya existe una sección de GitHub escrita a mano, la **migra** al bloque en lugar de duplicarla.

---

## Opciones

| Opción | Qué hace |
|---|---|
| `-Check` | Solo diagnóstico: no descarga, no escribe, no modifica nada |
| `-Login` | Tras instalar, lanza `gh auth login --web` y muestra el código |
| `-Version <x.y.z>` | Instala una versión concreta; `latest` para la última estable |
| `-Force` | Reinstala aunque la versión coincida |
| `-NoPathUpdate` | No añade la carpeta al PATH del usuario |
| `-UpdateInstructionsOnly` | No instala; solo actualiza `AGENTS.md` |
| `-Uninstall` | Elimina `gh.exe` y el bloque gestionado de `AGENTS.md` |

---

## Ejemplos

```powershell
# Diagnóstico
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Check

# Instalar (o dejar todo listo si ya está)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1

# Instalar y lanzar el login web
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Login

# Forzar la última estable
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Version latest -Force

# Tras autenticar, fijar el login en AGENTS.md
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -UpdateInstructionsOnly

# Desinstalar (no cierra la sesión de GitHub)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1 -Uninstall
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

- **Sin tokens en archivos.** La credencial la guarda `gh` en el Administrador de credenciales de Windows.
- **Sin `delete_repo`.** El login por navegador concede `repo`, `read:org`, `gist` y `workflow`; no concede `delete_repo`. Esa ausencia es la barrera que impide borrar repositorios por API. **No la añadas** con `gh auth refresh`.
- **Solo lectura por defecto.** El bloque de `AGENTS.md` prohíbe crear, borrar o cambiar configuración sin petición explícita.
- **El one-liner ejecuta código remoto.** Por eso apunta a un **tag inmutable**, no a `main`, y la release publica el SHA256. Si prefieres revisar antes: descarga el `.ps1`, léelo y ejecútalo con `-File`.
- **Ramas y force-push.** El scope `repo` sí permite escribir en ramas. Para protegerlas, activa branch protection o rulesets en GitHub.

---

## Solución de problemas

| Síntoma | Solución |
|---|---|
| `gh: no se reconoce` | Abre una terminal nueva; el script añade la carpeta al PATH. Si no, usa `C:\Users\<usuario>\.local\bin\gh.exe`. |
| `You are not logged into any GitHub hosts` | Ejecuta `gh auth login --hostname github.com --git-protocol https --web`. |
| No veo el código de 8 dígitos | Está en la terminal; `Ctrl+C`, repite y aparecerá uno nuevo. |
| No aparecen repos privados | `gh auth refresh -s repo,read:org`. |
| Error 403/429 | Límite de peticiones (5.000/h autenticado): espacia las consultas. |
| `necesita PowerShell 7` | Usa `pwsh`; instálalo con `winget install --id Microsoft.PowerShell -e`. |
| Bloqueado por ExecutionPolicy | Añade `-ExecutionPolicy Bypass` al comando. |
| `AGENTS.md` no se aplica | Verifica `%USERPROFILE%\.dsh\AGENTS.md` y abre una sesión nueva. |
| El one-liner no funciona | El repo debe ser público y el tag debe existir. Usa la copia local. |

---

## Estructura

```text
.
├── scripts/
│   └── install-gh.ps1              # Instalador de una sola ejecución
├── ANALISIS-ACCESO-GITHUB-AGENTES.md  # Análisis de alternativas y decisión
├── PLAN-ACCESO-GITHUB-DSH.md       # Plan original de implementación
├── SECURITY.md                     # Política de seguridad
├── LICENSE                         # MIT
└── .github/workflows/validate.yml  # CI: sintaxis y smoke test
```

---

## Por qué este diseño

El análisis completo está en [ANALISIS-ACCESO-GITHUB-AGENTES.md](./ANALISIS-ACCESO-GITHUB-AGENTES.md). En corto:

- **Script único en lugar de skill:** la instalación ocurre una vez; una skill añadiría descubrimiento y carga sin beneficio.
- **`gh` en lugar de MCP o plugin:** no requiere Node, Docker, servidor ni token en archivos, y funciona en cualquier agente que ejecute shell.
- **MCP/plugin** quedan como evolución si se necesitan tools nativas o read-only duro.

---

## Licencia

[MIT](./LICENSE) © 2026 muelabyte

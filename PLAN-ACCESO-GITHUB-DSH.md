# Plan de implementación — Acceso a GitHub desde cualquier sesión de DSH

> **Para quien implementa:** este documento es autocontenido. Léelo completo,
> ejecuta los pasos en orden y valida los criterios de aceptación del final.
> El paso 2 (login) lo debe ejecutar el dueño del equipo: no puedes autenticarte
> tú. No hagas nada fuera de lo indicado.

- **Máquina:** Windows 11 · usuario `muela`
- **Harness:** DeepSeek Harness `0.2.1-rc.2` (Escritorio, `DSH_PROFILE=desktop`)
- **Shell:** PowerShell 7 (`pwsh`)
- **Owner de GitHub:** `muelabyte` (confirmar el login real tras autenticar)
- **Fecha del plan:** 2026-10-18

---

## 0. Prompt listo para pegar (si el implementador es un agente de IA)

```text
Actúa como implementador del plan adjunto (PLAN-ACCESO-GITHUB-DSH.md).

Contexto: Windows 11, usuario "muela", DeepSeek Harness 0.2.1-rc.2, PowerShell 7.
Objetivo: dejar GitHub CLI ("gh") instalado y autenticado para que cualquier
sesión nueva de DSH pueda listar y consultar todos los repositorios del usuario.

Reglas:
- Sigue el documento al pie de la letra; no re-investigues lo que ya está
  verificado en el documento.
- Tú haces los pasos 1, 3 y 4. El paso 2 (login) lo debe ejecutar el dueño del
  equipo: pídeselo y espera confirmación.
- No pidas permisos de administrador, no uses instaladores MSI.
- No modifiques el repositorio del proyecto, ni paquetes npm, ni
  ~/.dsh/.credentials.yaml.
- Nunca imprimas tokens ni los escribas en archivos o commits.

Al terminar: valida los 6 criterios de aceptación y entrega un informe breve con
lo hecho, la salida de `gh auth status`, el resultado de `gh repo list` y
cualquier límite encontrado.
```

---

## 1. Objetivo

Que en **cualquier sesión nueva de DSH** (en cualquier carpeta) el agente pueda
responder preguntas sobre GitHub —listar repositorios, ver detalles, buscar
código, leer issues/PRs— usando **GitHub CLI (`gh`)** ya instalado y autenticado,
sin configuración por sesión.

### Criterios de aceptación

1. `gh --version` funciona en una shell de DSH desde cualquier carpeta
   (p. ej. `C:\Windows`).
2. `gh auth status` muestra sesión iniciada con scope `repo` (acceso a privados).
3. `gh repo list --limit 1000 --json name,visibility` devuelve los repositorios
   del owner, públicos y privados.
4. Existe `C:\Users\muela\.dsh\AGENTS.md` con la instrucción global que indica
   usar `gh` (DSH la carga en todas las sesiones).
5. En una sesión nueva, la petición «lista mis repositorios públicos» se resuelve
   con `gh` y devuelve datos reales.
6. No hay tokens en el chat, en el repositorio ni en archivos de configuración
   del proyecto.

---

## 2. Decisiones ya tomadas (no re-investigar)

- **Usar `gh` portable**, no un bundle MCP. Motivos: no requiere admin, no hace
  falta tocar el PATH (la carpeta destino ya está en el PATH del proceso de DSH)
  y no exige reiniciar DSH.
- **Ubicación:** `C:\Users\muela\.local\bin\gh.exe`. Esa carpeta ya existe
  (contiene `uv.exe`, etc.) y está en el PATH del usuario **y** del proceso actual
  de DSH.
- **Credenciales:** las gestiona `gh` en el Administrador de credenciales de
  Windows. No se escriben en `AGENTS.md`, ni en el repo, ni en `~/.dsh`.
- **Instrucciones globales:** DSH carga `$DSH_HOME/AGENTS.md`, es decir
  `C:\Users\muela\.dsh\AGENTS.md`. Hoy **no existe**; se crea en el paso 3.
- **Versión objetivo:** `gh` `2.102.0`
  (`gh_2.102.0_windows_amd64.zip`, 15,5 MB). Si la release ya no existe, usar la
  última estable modificando la URL y el nombre del ZIP.
- **No tocar** el repositorio `proyecto-addtranscripcion-deepseek`, ni sus
  paquetes, ni `~/.dsh/.credentials.yaml`, ni la configuración de Git.

### Datos del entorno ya verificados

| Comprobación | Resultado |
|---|---|
| `gh` instalado | ❌ No |
| `C:\Users\muela\.local\bin` | ✅ Existe y está en el PATH |
| `~/.dsh/AGENTS.md` | ❌ No existe |
| `~/.dsh/.credentials.yaml` | ✅ Existe (no modificar) |
| Admin/UAC disponible | ❌ Evitar; usar portable |
| `git` / `curl` / `winget` | ✅ Disponibles |

---

## 3. Pasos de implementación

### Paso 1 — Instalar `gh` portable (sin admin)

```powershell
$url  = "https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_windows_amd64.zip"
$zip  = Join-Path $env:TEMP "gh_2.102.0_windows_amd64.zip"
$dest = Join-Path $env:TEMP "gh_2.102.0"

Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $dest -Force

# El ZIP trae bin/gh.exe
Copy-Item (Join-Path $dest "bin\gh.exe") "C:\Users\muela\.local\bin\gh.exe" -Force

# Verificación (en una llamada nueva de shell)
gh --version
```

Esperado: una línea con `gh version 2.102.0 (...)`.

> Opcional: verificar el SHA256 contra `gh_2.102.0_checksums.txt` de la misma
> release antes de copiar.

### Paso 2 — Autenticación (la ejecuta el dueño del equipo)

**No puedes hacerlo tú.** Pide al dueño que abra una terminal y ejecute:

```powershell
gh auth login --hostname github.com --git-protocol https --web
```

Debe elegir **GitHub.com**, protocolo **HTTPS** y completar el flujo del
navegador. Scope esperado: `repo`, `read:org`, `gist` (el login por navegador los
concede por defecto).

Alternativa sin navegador (si el dueño lo prefiere): crear un token y pasarlo por
stdin desde un archivo que él controle, **nunca por el chat**:

```powershell
gh auth login --hostname github.com --git-protocol https --with-token < C:\ruta\al\token.txt
```

Después, verifica tú:

```powershell
gh auth status
gh api user --jq .login
```

Esperado: `Logged in to github.com account <LOGIN>` y el login real (p. ej.
`muelabyte`). Anota ese `<LOGIN>` para el paso 3.

### Paso 3 — Crear las instrucciones globales de DSH

Crea `C:\Users\muela\.dsh\AGENTS.md` (sustituye `<LOGIN>` por el valor real del
paso 2). Contenido recomendado:

```markdown
# Contexto global del usuario

## GitHub

- `gh` está instalado en `C:\Users\muela\.local\bin\gh.exe` y autenticado como
  `<LOGIN>`.
- Para cualquier pregunta sobre repositorios, issues, PRs, releases, Actions o
  código en GitHub, usa `gh`.
- Comandos de referencia:
  - Listar todos los repos: `gh repo list <LOGIN> --limit 1000 --json name,visibility,description,updatedAt,stargazerCount`
  - Solo públicos: añade `--visibility public`
  - Detalle de un repo: `gh repo view <owner>/<repo> --json name,description,visibility,defaultBranchRef,url`
  - Consultas arbitrarias: `gh api <ruta>`
- Por defecto, solo lectura. No crees issues/PRs, no hagas push, no cambies
  configuración ni visibilidad salvo petición explícita.
- Nunca imprimas tokens ni los copies a archivos, commits ni mensajes.
```

Notas:

- DSH carga este archivo en **todas** las sesiones, de cualquier carpeta.
- No pongas tokens ni datos sensibles en este archivo.
- Si ya existiera en el futuro, **añade** una sección en lugar de sobrescribirlo.

### Paso 4 — Verificación de extremo a extremo

```powershell
# 1) Repos por visibilidad (debe haber privados si la cuenta tiene)
gh repo list <LOGIN> --limit 1000 --json name,visibility |
  ConvertFrom-Json | Group-Object visibility | Select-Object Name,Count

# 2) Un repo concreto
gh repo view muelabyte/plugin-whisper-dictation --json name,visibility,url

# 3) Que funciona fuera del proyecto
Set-Location C:\Windows
gh repo list <LOGIN> --limit 5 --json name
gh --version
```

Después, abre una **sesión nueva de DSH** y pide: «lista mis repositorios
públicos». Debe responder con la lista real, sin que le expliques nada.

---

## 4. Uso esperado en una sesión nueva

Ejemplos de peticiones que deben funcionar:

- «Lista mis repositorios públicos.»
- «¿Qué repos privados no se actualizan desde 2025?»
- «Resume el README del repo X.»
- «Busca issues abiertas en X.»

El agente debe resolverlas con `gh`; si no lo encontrara en PATH, usaría la ruta
absoluta `C:\Users\muela\.local\bin\gh.exe` que figura en `AGENTS.md`.

---

## 5. Casos límite y solución

| Síntoma | Causa / solución |
|---|---|
| `gh: no se reconoce` | Usar ruta absoluta; comprobar que `C:\Users\muela\.local\bin` está en `$env:PATH`. Si se instaló después de abrir DSH, reiniciar DSH o usar la ruta completa. |
| `gh auth status` sin sesión | Repetir el paso 2 (el dueño). |
| Repos privados no aparecen | El token no tiene scope `repo`; `gh auth refresh -s repo,read:org`. |
| Repos de una organización no aparecen | SSO de la organización: autorizar el token/`gh auth refresh -s read:org`. |
| Error 403/429 | Límite de peticiones (5000/h autenticado); espaciar consultas. |
| Token revocado o caducado | Repetir el paso 2. |
| `AGENTS.md` no se aplica | Verificar la ruta exacta `C:\Users\muela\.dsh\AGENTS.md` y abrir una sesión nueva; DSH lo carga al primer request. |

---

## 6. Rollback

```powershell
gh auth logout --hostname github.com
Remove-Item "C:\Users\muela\.local\bin\gh.exe" -Force
Remove-Item "C:\Users\muela\.dsh\AGENTS.md" -Force   # solo si lo creó este plan
```

Nada más del sistema queda modificado.

---

## 7. Restricciones para quien implementa

- **No** pedir permisos de administrador ni ejecutar instaladores MSI.
- **No** modificar el repositorio del proyecto ni sus paquetes npm.
- **No** escribir tokens en el chat, en archivos del repo, en `AGENTS.md` ni en
  commits.
- **No** tocar `C:\Users\muela\.dsh\.credentials.yaml` ni otros archivos de DSH,
  salvo crear `AGENTS.md`.
- **No** instalar el bundle MCP: queda fuera de este plan (ver anexo).

---

## Anexo — Alternativa futura: MCP nativo (no implementar ahora)

DSH soporta servidores MCP mediante un bundle de configuración que inserta
`@deepseek-ai/dsh-mcp-client` (ya incluido en la app). Daría herramientas
nativas `mcp__github__*` en todas las sesiones del perfil.

Esbozo (requiere PAT, empaquetado e instalación por UI + reinicio de DSH):

```yaml
# cordis.patch.yml de un bundle local
- insert:
    - id: mcp-github
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: github
        transport: streamable-http
        url: https://api.githubcopilot.com/mcp/
        headers:
          Authorization: !!js '`Bearer ${process.env.GITHUB_TOKEN}`'
        failOnStartupError: true
```

Pasos: definir `GITHUB_TOKEN` (variable de usuario) → crear carpeta del bundle
con `package.json` (`dsh.bundle.patch`) → `npm pack` → Plugins → Add plugin →
ruta del `.tgz` → reiniciar DSH desde la bandeja → verificar
`mcp__github__*`. Se puede posponer sin afectar al plan principal.

# Acceso a GitHub desde DSH y otros agentes: qué opción elegir

**Documento de decisión** · 2026-10-19 · Proyecto `CONTROL-GITHUB`

---

## 1. Resumen ejecutivo

### 1.1 ¿Qué mecanismo responde mejor a las solicitudes cuando esté funcionando?

Para el conjunto de solicitudes documentado —listar y filtrar repositorios, ver detalle y README, consultar issues/PRs, buscar código, revisar Actions y hacer consultas arbitrarias— hay dos finalistas:

- **A (script único + `gh`)**: máxima flexibilidad. `gh` cubre las operaciones habituales con salida JSON y `gh api` cubre **cualquier** endpoint REST o GraphQL. Es el menor coste de contexto y el menor número de piezas.
- **D (MCP oficial de GitHub)**: máxima fiabilidad de *tool-calling*. Ofrece herramientas tipadas (`search_repositories`, `get_file_contents`, `search_code`, `pull_request_read`, …) y un catálogo amplio por toolsets. A cambio: instalación más pesada, servidor, token en entorno y esquemas que consumen contexto en cada petición.

**Veredicto:** **A gana para las solicitudes concretas de este proyecto** (listar/consultar repos propios, solo lectura, sin admin y con el mínimo mantenimiento). **D gana si el objetivo es responder preguntas abiertas de GitHub con herramientas nativas y read-only duro.** B y C son buenas para un catálogo cerrado de operaciones; E depende del plugin elegido.

### 1.2 ¿Qué mecanismo protege los repositorios de ser eliminados o borrados?

El control decisivo es el **scope del token**: sin `delete_repo`, ningún mecanismo puede borrar un repositorio por API, incluido `gh repo delete --yes` o `gh api -X DELETE /repos/...`. El token actual **no tiene** ese scope (verificado).

Sobre esa base:

| Mecanismo | Protección del repositorio | Protección de ramas/force-push |
|---|---|---|
| **A / F** (`gh` + policy) | **Alta**: el scope ausente bloquea el borrado | Baja: solo política; `repo` permite borrar ramas |
| **B** (plugin que envuelve `gh`) | Alta, si se diseña sin tools de escritura | Alta, si es solo-lectura |
| **C** (plugin API/OAuth) | Media: depende del token y del plugin | Media/baja |
| **D** (MCP) | **Alta**: URL `/readonly` y toolsets sin escritura | **Alta**: no registra tools de escritura |
| **E** (plugin existente) | Mixta: PerryLink aprueba escrituras; Moon-shiyue expone API genérica | Mixta |

**Veredicto:** la barrera más importante y común es **no conceder `delete_repo`**. Para defensa en profundidad, **D** es el más fuerte, seguido de **B** diseñado solo-lectura. **A** protege el repositorio por scope, pero no bloquea técnicamente el borrado de ramas ni el `force-push`: eso queda en la política y en la disciplina del agente.

### 1.3 Recomendación

**A (script de una sola ejecución + `gh` + `AGENTS.md`)**, con dos reglas:

1. **Nunca** conceder el scope `delete_repo`.
2. Si más adelante se necesita cobertura abierta con read-only duro, añadir **D** en modo `/readonly`; si se necesitan tools nativas con aprobaciones, **B** o **E** (PerryLink).

**Sobre la skill:** no es necesaria para una instalación que ocurre una sola vez. Una skill añade un archivo, descubrimiento y carga en el catálogo; no aporta nada que el script no haga. Solo se justificaría si el flujo se repitiera en muchas máquinas o si el agente tuviera que descubrirlo y ejecutarlo por sí mismo en cada sesión.

---

## 2. Contexto y restricciones

El punto de partida es [PLAN-ACCESO-GITHUB-DSH.md](./PLAN-ACCESO-GITHUB-DSH.md), que fija:

- `gh` **portable**, sin administrador y sin MSI.
- Credenciales en el **Administrador de credenciales de Windows**; nunca en archivos, repositorio ni `~/.dsh/.credentials.yaml`.
- Instrucciones globales en `~/.dsh/AGENTS.md`.
- **Solo lectura por defecto**.
- El bundle **MCP queda diferido** (anexo del plan).
- Windows 11, DSH Desktop `0.2.1-rc.2`, PowerShell 7.

Criterios de aceptación originales:

1. `gh --version` funciona desde cualquier carpeta.
2. `gh auth status` muestra sesión con scope `repo`.
3. `gh repo list --limit 1000 --json name,visibility` devuelve públicos y privados.
4. Existe `~/.dsh/AGENTS.md` con la instrucción global.
5. Una sesión nueva resuelve “lista mis repositorios públicos” con datos reales.
6. No hay tokens en el chat, el repositorio ni archivos de configuración.

---

## 3. Origen de cada pieza

| Pieza | De dónde sale |
|---|---|
| **Script instalador** | Del repositorio del proyecto: [`scripts/install-gh.ps1`](./scripts/install-gh.ps1). Se ejecuta desde una copia local, o desde un one-liner fijado a un tag. |
| **Binario `gh.exe`** | De las releases oficiales `github.com/cli/cli/releases`; se verifica el SHA256 contra el archivo de checksums de la misma release. |
| **Código de 8 dígitos** | **Lo genera `gh` en el equipo**, no GitHub ni la cuenta. Aparece en la terminal como `First copy your one-time code: XXXX-XXXX`, se copia al portapapeles y se pega en `https://github.com/login/device`. No es el código 2FA. Si se pierde: `Ctrl+C` y repetir; se genera uno nuevo (caduca en ~15 minutos). |
| **Token** | Lo guarda `gh` en el Administrador de credenciales de Windows. No se escribe en archivos. |
| **`AGENTS.md`** | `$DSH_HOME/AGENTS.md` (aquí `C:\Users\muela\.dsh\AGENTS.md`); DSH lo carga en la primera petición de todas las sesiones. |

### 3.1 Cómo se ejecuta

**Opción recomendada (copia local, sin ejecución remota):**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-gh.ps1
```

**One-liner (requiere repo público y tag):**

```powershell
irm https://raw.githubusercontent.com/<owner>/<repo>/<tag>/scripts/install-gh.ps1 | iex
```

Con flags, por ejemplo diagnóstico:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/<owner>/<repo>/<tag>/scripts/install-gh.ps1'))) -Check
```

> El one-liner descarga y ejecuta código del repositorio. Por eso debe apuntar a un **tag inmutable**, nunca a `main`, y conviene publicar el SHA256 del script en la release. Quien prefiera revisar antes: `irm ... -OutFile install-gh.ps1`, leerlo y ejecutarlo con `-File`.

> **Requisito:** ejecuta el instalador con **PowerShell 7 (`pwsh`)**, no con Windows PowerShell 5.1. El script se guarda en UTF-8 sin BOM (necesario para `irm | iex`); 5.1 lo leería como ANSI y corrompería los acentos del `AGENTS.md` generado. Si se ejecuta con 5.1, el script se detiene con un mensaje claro.

### 3.2 Qué imprime el script

1. `[INFO]` destino y ruta de `AGENTS.md`.
2. `[OK]` checksum verificado y `gh.exe` copiado.
3. `[OK]` `gh <versión>` operativo.
4. `[OK]` `AGENTS.md` creado o actualizado.
5. Guía de login: explica que el código lo genera `gh`, que aparece en la terminal, que no es 2FA y que se pega en `https://github.com/login/device`.
6. `[NEXT]` comando de login y verificación (`gh repo list ...`).

Flags útiles: `-Check` (solo diagnóstico), `-Login` (lanza el flujo web), `-Uninstall`, `-NoPathUpdate`, `-Version latest`, `-Force`.

---

## 4. Las opciones

### A. Script único + `gh` + `AGENTS.md` (propuesta)

Flujo:

```text
usuario ejecuta el script (una vez)
  → descarga gh portable, verifica SHA256, copia a ~/.local/bin
  → actualiza el bloque de AGENTS.md
  → guía el login web (código de 8 dígitos)
agente, en cualquier sesión:
  → lee AGENTS.md, ejecuta gh
  → responde con datos reales
```

### B. Plugin DSH que envuelve `gh`

Paquete `dsh-plugin` con tools nativas (`github_repos`, `github_api`, …) que ejecutan `gh` por dentro. Se instala con `dsh plugin --profile desktop add <paquete>`, requiere Node/pnpm, reinicio y mantenimiento. Puede registrarse solo-lectura para protección dura.

### C. Plugin DSH con API/OAuth nativo

Como los plugins existentes: device flow o PAT, tools propias y, en algunos casos, botón de conexión. El token vive en el host o en `$DSH_HOME`.

### D. MCP oficial + `dsh-mcp-client`

Servidor MCP de GitHub (remoto `https://api.githubcopilot.com/mcp/` o local con Docker/Go). DSH lo puentea con `@deepseek-ai/dsh-mcp-client` y expone `mcp__github__*`. El remoto admite PAT u OAuth, URLs `/readonly` y selección de toolsets (`X-MCP-Toolsets`).

### E. Plugin existente

Instalar uno de los plugins ya publicados en lugar de construir: PerryLink, Moon-shiyue, kaziii.

### F. Manual actual

`gh` + `AGENTS.md` configurados a mano, sin script de instalación.

### Variante A′: skill

Misma capacidad que A, más un `SKILL.md` que el agente descubre y carga. Para una instalación de una sola vez no aporta: duplica el artefacto, añade carga al catálogo y no cambia la seguridad ni la cobertura. Sí tendría sentido si el flujo se repitiera y el agente debiera descubrirlo solo.

---

## 5. Soluciones existentes (evidencia)

Estrellas y fechas: foto de **2026-10-19**.

| Repositorio | ★ | Última act. | Tipo | Autenticación | Alcance | Instalación | Nota |
|---|---:|---|---|---|---|---|---|
| [github/github-mcp-server](https://github.com/github/github-mcp-server) | 33.738 | 2026-10-19 | MCP server | PAT u OAuth | API de GitHub completa | remoto o Docker/Go | Oficial; `/readonly`, toolsets |
| [PivotStackIntelligence/dsh-github](https://github.com/PivotStackIntelligence/dsh-github) | 97 | 2026-09-09 | Plugin UI | Git local | Panel Source Control | `dsh plugin` | **No usa API ni tokens**; no lista repos remotos |
| [PerryLink/dsh-github](https://github.com/PerryLink/dsh-github) | 22 | 2026-10-18 | Plugin | credentials/env/`gh` | PRs, issues, CI; 15 tools | npm o `dsh plugin` | Escrituras con aprobación; DSH 0.2.1 |
| [kaziii/dsh-github-connector](https://github.com/kaziii/dsh-github-connector) | 10 | 2026-08-17 | Plugin multi-paquete | Device flow | PR/issue tools | `dsh plugin` | Token solo en el host |
| [Moon-shiyue/dsh-github-connect](https://github.com/Moon-shiyue/dsh-github-connect) | 9 | 2026-10-06 | Plugin | OAuth device/PAT | `github_api` genérico | plugin o `install.ps1` | Token en `$DSH_HOME/.dsh-github-connect/auth.json` |
| [Fectivnfy112357/github-explore](https://github.com/Fectivnfy112357/github-explore) | 8 | 2026-09-18 | Skill | `gh` | Búsqueda/exploración | `npx skills add` | Valida skill+`gh`; multi-agente |
| [Starfie1d1272/dsh-github-skills](https://github.com/Starfie1d1272/dsh-github-skills) | 5 | 2026-10-12 | Skills | `gh`/git | Workflows PR/CI/publicación | npm/skills | Capa de workflow, no proveedor |

Contexto adicional:

- [`cli/cli`](https://github.com/cli/cli) es el propio `gh`; ya está instalado y autenticado en esta máquina (`2.102.0`, `muelabyte`).
- [`@deepseek-ai/dsh-mcp-client`](https://www.npmjs.com/package/@deepseek-ai/dsh-mcp-client) puentea **solo tools** (no resources/prompts), sin reconexión automática, con coste de esquemas por petición.
- El ecosistema DSH tiene ~13.800 plugins catalogados; ya existen varias propuestas de GitHub, así que construir desde cero solo se justifica por el modelo de credenciales y el alcance concreto.

---

## 6. Evaluación funcional: qué responde mejor

### 6.1 Matriz por escenario (1–5)

| Escenario | A script | B plugin `gh` | C plugin API | D MCP | E existente | F manual |
|---|---:|---:|---:|---:|---:|---:|
| Listar y filtrar repos (visibilidad/fecha) | 5 | 4 | 4 | 5 | 4 | 3 |
| Detalle de repo y README | 4 | 4 | 4 | 5 | 3 | 3 |
| Issues y PRs | 5 | 5 | 5 | 5 | 4 | 4 |
| Búsqueda de código | 5 | 3 | 3 | 5 | 2 | 4 |
| Actions / CI | 4 | 4 | 3 | 5 | 2 | 3 |
| API arbitraria (REST/GraphQL) | 5 | 2 | 3 | 2 | 4 | 4 |
| Preguntas abiertas / robustez | 4 | 4 | 4 | 5 | 3 | 3 |
| **Media** | **4,57** | **3,57** | **3,57** | **4,57** | **3,14** | **3,43** |

### 6.2 Lectura por opción

- **A**: `gh repo list --json`, `gh repo view`, `gh api repos/{owner}/{repo}/readme`, `gh issue list`, `gh search code`, `gh run list`, `gh api graphql`. Cobertura total y salida estructurada; el agente debe elegir bien el comando. Coste de contexto bajo.
- **B**: tools tipadas y deterministas para lo que exponga el plugin; si no incluye una tool de API genérica, las consultas arbitrarias se quedan fuera. El agente puede saltarse el plugin usando `gh` por shell, lo que diluye la ventaja de seguridad.
- **C**: la mejor UX (botón, device flow) y tools integradas; cobertura limitada al catálogo del plugin. Moon-shiyue compensa con `github_api`, a costa de exponer una vía genérica.
- **D**: `search_repositories`, `get_file_contents`, `search_code`, `pull_request_read`, toolsets de Actions/seguridad/proyectos. Muy buena fiabilidad y read-only; no tiene API arbitraria y los esquemas cuestan tokens.
- **E**: depende. PerryLink es fuerte en PRs/issues/CI; Moon-shiyue en consultas genéricas; kaziii en PRs; PivotStack no cubre la API.
- **F**: igual que A pero sin guía ni automatización; la calidad depende de que el agente recuerde los comandos.

### 6.3 Veredicto

- **Solicitudes del plan (listar/consultar repos propios): A.**
- **Preguntas abiertas con tools nativas: D.**
- **Catálogo cerrado con UI y aprobaciones: B/C/E.**
- **Consultas arbitrarias ocasionales: A** (por `gh api`).

---

## 7. Protección de repositorios

### 7.1 Modelo de amenaza

1. El agente malinterpreta una petición y ejecuta un borrado.
2. Prompt injection desde el contenido de un repo (README, issue, comentario) que intenta inducir una acción destructiva.
3. Error humano al copiar/pegar un comando.
4. Plugin o dependencia de terceros con código malicioso o demasiado permisivo.

No cubre accesos externos a GitHub ni acciones hechas desde la web.

### 7.2 El scope es la barrera decisiva

El endpoint de borrado de repositorio exige:

- **PAT clásico:** scope `delete_repo`.
- **Fine-grained PAT:** permiso de **Administration** (write).

El token actual (`gh auth status`) tiene `gist`, `read:org`, `repo`, `workflow`; **no** `delete_repo`. Por tanto:

```text
gh repo delete muelabyte/<repo> --yes   → falla por falta de scope
gh api -X DELETE /repos/muelabyte/<repo> → falla por falta de scope
```

Esto aplica a A, B (si usa el mismo token) y D. El riesgo aparece si alguien ejecuta `gh auth refresh -s delete_repo` o crea un token con Administration. **Regla: no hacerlo nunca.**

### 7.3 Controles por opción

| Control | A | B | C | D | E | F |
|---|---|---|---|---|---|---|
| `delete_repo` ausente | ✅ | ✅ (mismo token) | ⚠️ token propio | ✅ | ⚠️ token propio | ✅ |
| Solo-lectura técnico (sin tools de escritura) | ❌ solo política | ✅ si se diseña | ✅/⚠️ | ✅ `/readonly` | ⚠️ | ❌ |
| Aprobación humana por escritura | ⚠️ según política DSH | ✅ | ✅ PerryLink / ❌ Moon | n/a | ✅/❌ | ⚠️ |
| Vía genérica de escape | ⚠️ `gh api` | ⚠️ shell | ⚠️ `github_api` | ❌ | ⚠️ | ⚠️ |
| Borrado de ramas / force-push | ❌ política | ✅ si read-only | ⚠️ | ✅ | ⚠️ | ❌ |

### 7.4 Salvaguardas recomendadas

1. **No conceder `delete_repo`** ni permisos de Administration en tokens fine-grained.
2. Preferir **solo lectura** en el agente y en el plugin/MCP.
3. Si se usa MCP, apuntar a `.../mcp/readonly` y limitar toolsets.
4. Si se usa plugin, elegir uno que registre solo tools de lectura o que pase toda escritura por aprobación (PerryLink).
5. Activar **branch protection / rulesets** en las ramas importantes: el agente no podrá borrar ni forzar push aunque tenga `repo`.
6. Revisar el `AGENTS.md`/skill: prohibición explícita de borrados y de `delete_repo`.
7. Guardar backups o usar la restauración de repositorios borrados de GitHub (ventana limitada) para el caso extremo.
8. Auditar `gh` y el historial de acciones; revisar plugins antes de instalarlos.

### 7.5 Veredicto

- **D** es el más fuerte en defensa en profundidad (no hay tools de escritura).
- **B** puede igualarlo si se diseña solo-lectura.
- **A** es fuerte contra el borrado de repositorio por scope, pero **no** contra ramas/force-push; ahí manda la política.
- **E** es una lotería: PerryLink bien, Moon-shiyue acepta una API genérica.

---

## 8. Comparación ponderada

Pesos: encaje con el plan 15%, ajuste funcional 20%, cobertura abierta 10%, protección de repositorio 20%, otras acciones destructivas 5%, instalación 8%, dependencias 5%, portabilidad 7%, mantenimiento 5%, UX 3%, coste de contexto 2%.

| Criterio (peso) | A | B | C | D | E | F |
|---|---:|---:|---:|---:|---:|---:|
| Encaje con el plan (15%) | 5 | 3 | 2 | 2 | 2 | 4 |
| Ajuste funcional (20%) | 5 | 4 | 4 | 4 | 3 | 3 |
| Cobertura abierta (10%) | 4 | 3 | 4 | 5 | 3 | 4 |
| Protección de repositorio (20%) | 5 | 5 | 4 | 5 | 3 | 5 |
| Otras acciones destructivas (5%) | 2 | 5 | 4 | 5 | 3 | 2 |
| Instalación (8%) | 5 | 3 | 3 | 2 | 4 | 2 |
| Dependencias (5%) | 5 | 2 | 2 | 3 | 2 | 5 |
| Portabilidad (7%) | 5 | 1 | 1 | 3 | 1 | 4 |
| Mantenimiento (5%) | 4 | 2 | 2 | 3 | 2 | 5 |
| UX (3%) | 3 | 4 | 5 | 3 | 5 | 2 |
| Coste de contexto (2%) | 5 | 4 | 4 | 2 | 4 | 5 |
| **Total ponderado** | **4,64** | **3,51** | **3,24** | **3,65** | **2,77** | **3,80** |

F puntúa alto solo porque no instala ni mantiene nada; no es una solución de automatización. Las puntuaciones son cualitativas y discutibles: el valor está en la comparación relativa.

---

## 9. Pros y contras

### A. Script único + `gh`

**Pros**

- Portable y sin admin; no requiere Node, Docker ni servidor.
- Credenciales en el keyring de Windows, no en archivos.
- Se instala una vez; no hay daemon ni reinicio de DSH.
- Funciona igual en DSH y en otros agentes que ejecuten shell.
- `gh api` cubre cualquier endpoint, incluido GraphQL.
- Bajo coste de contexto y fácil de auditar (un `.ps1`).

**Contras**

- Sin tools nativas: depende de que el agente elija bien los comandos.
- No tiene read-only técnico; el borrado de ramas/force-push queda en política.
- El one-liner ejecuta código remoto (mitigable con tag fijo y hash).
- Windows-only; el instalador es PowerShell.

### B. Plugin DSH que envuelve `gh`

**Pros**

- Tools tipadas y deterministas; mejores aprobaciones y UX.
- Puede registrarse solo-lectura (protección dura).
- Reutiliza `gh`/credenciales sin duplicar autenticación.

**Contras**

- Solo DSH; requiere Node/pnpm/`dsh plugin` y reinicio.
- Mantenimiento propio y compatibilidad con la versión de DSH.
- El agente puede saltarse el plugin y usar shell.
- I+D considerable para un caso de solo lectura.

### C. Plugin DSH con API/OAuth

**Pros**

- Mejor experiencia: botón, device flow, tools integradas.
- Algunos ya existen y están mantenidos.

**Contras**

- Token en el host o en `$DSH_HOME` (rompe el modelo del plan).
- Cobertura limitada al catálogo del plugin.
- Código de terceros y dependencia de su mantenimiento.
- Solo DSH.

### D. MCP oficial

**Pros**

- Oficial, amplio y con esquemas; read-only por URL.
- Estándar entre agentes; toolsets para limitar superficie.
- Sin API arbitraria: menos vías de escape.

**Contras**

- Instalación pesada en DSH (bundle, token, reinicio).
- Coste de tokens por esquemas en cada petición.
- Solo tools (no resources/prompts); sin reconexión automática.
- Requiere servidor remoto o Docker/Go.

### E. Plugin existente

**Pros**

- Listo para usar; UI y auth resueltas.
- PerryLink es maduro y con aprobaciones; Moon-shiyue es flexible.

**Contras**

- Confianza y supply chain de terceros.
- Token en `$DSH_HOME` o propio; no cumple el criterio 6.
- Solapamiento y dependencia de su roadmap.
- Solo DSH.

### F. Manual

**Pros**

- Cero código nuevo; cumple el plan si se hace bien.
- Máximo control y transparencia.

**Contras**

- Repetitivo y propenso a errores; sin guía de login.
- No automatiza la instalación para otros usuarios.

---

## 10. Encaje con los criterios del plan raíz

| Criterio | A | B | C | D | E | F |
|---|---|---|---|---|---|---|
| 1. `gh --version` en cualquier carpeta | ✅ | ⚠️ | ❌ | ❌ | ❌ | ✅ |
| 2. `gh auth status` con `repo` | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| 3. `gh repo list` con públicos y privados | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4. `AGENTS.md` global | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| 5. Sesión nueva resuelve la petición | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 6. Sin tokens en archivos | ✅ | ⚠️ | ❌ | ⚠️ | ❌ | ✅ |

**Lectura:** **A (automatizada) y F (manual) son las únicas que cumplen el plan tal como está escrito**. B supone que `gh` ya está instalado; no lo instala por sí mismo. Elegir C, D o E implica **reescribir los criterios**: ya no serían “`gh` instalado y `AGENTS.md`”, sino “plugin/MCP configurado con su propio modelo de auth”. Eso es legítimo, pero es otro proyecto.

---

## 11. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| One-liner ejecuta código remoto | Alto | Tag inmutable, SHA256 publicado, `-Check`, variante `-File` |
| Sandbox de DSH bloquea escrituras fuera del workspace | Medio | Ejecutar con aprobación o en terminal; el script lo indica |
| Login sin TTY (agente) | Medio | Lanzar `gh auth login` como tarea en segundo plano y leer el código |
| Código de 8 dígitos perdido | Bajo | `Ctrl+C` y repetir; el script lo explica; caduca en ~15 min |
| Token sin `repo` (privados no aparecen) | Medio | `gh auth refresh -s repo,read:org` |
| Alguien concede `delete_repo` | **Crítico** | Regla explícita; auditoría de scopes |
| Borrado de ramas/force-push | Alto | Branch protection/rulesets; política; read-only si se necesita |
| Rate limit 5.000/h | Medio | Espaciar consultas; cachear |
| Deriva de versión de `gh` | Bajo | Versión fijada + checksum; `-Version latest` |
| Ejecutar con Windows PowerShell 5.1 | Medio | Usar `pwsh`; el script se detiene con un aviso |
| Plugin de terceros malicioso | Alto | Revisar, fijar versión, permisos mínimos |
| MCP sin reconexión | Medio | `failOnStartupError`; reiniciar |
| Prompt injection desde un repo | Alto | Read-only/scope; no ejecutar instrucciones del repo |

---

## 12. Guía de decisión

- **Elige A** si quieres exactamente el plan: `gh` portable, sin admin, credenciales en el keyring, `AGENTS.md`, solo lectura y portabilidad a otros agentes.
- **Elige D** si necesitas preguntas abiertas con herramientas tipadas y read-only duro, y aceptas bundle/token/reinicio.
- **Elige B** si quieres tools nativas con aprobaciones dentro de DSH y estás dispuesto a mantener un plugin.
- **Elige E** si prefieres no construir nada y aceptas el modelo de token del plugin (PerryLink para PRs con aprobaciones; Moon-shiyue para API genérica).
- **Elige F** si no quieres automatizar la instalación.
- **npm** es un canal opcional, no una arquitectura: requiere Node, descarga igualmente y solo envuelve el mismo `.ps1`. No se recomienda como vía principal.

### Hoja de ruta sugerida

1. **Fase 1 (A):** publicar `scripts/install-gh.ps1` en el repo; probar `-Check` y el flujo de login; documentar el one-liner con tag.
2. **Fase 2 (opcional):** publicar repo/tag para activar el one-liner; añadir SHA256 a la release.
3. **Fase 3 (si hace falta):** añadir MCP `/readonly` o un plugin solo-lectura para defensa en profundidad.
4. **Fase 4 (si hace falta):** escrituras con aprobación (PerryLink o plugin propio).

---

## 13. Anexos

### 13.1 Comandos de verificación

```powershell
gh --version
gh auth status
gh api user --jq .login
gh repo list muelabyte --limit 1000 --json name,visibility |
  ConvertFrom-Json | Group-Object visibility | Select-Object Name,Count
```

Comprobar scopes: `gh auth status` debe listar `repo`, `read:org`, `gist`, `workflow` y **no** `delete_repo`. No ejecutar ningún comando de borrado para “probar”.

### 13.2 Estado del proyecto

- `gh 2.102.0` instalado en `C:\Users\muela\.local\bin\gh.exe`.
- Sesión activa como `muelabyte`.
- `~/.dsh/AGENTS.md` configurado (sin bloque gestionado todavía; el script lo migra si se ejecuta).
- `scripts/install-gh.ps1` validado en `-Check` con PowerShell 7 y en ejecución piped contra un `DSH_HOME` temporal; con Windows PowerShell 5.1 se detiene con un aviso (evita acentos corruptos).
- La carpeta `skills/` se eliminó: no hay skill.

### 13.3 Fuentes

- [GitHub MCP Server](https://github.com/github/github-mcp-server) y [documentación del servidor remoto](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md).
- [@deepseek-ai/dsh-mcp-client](https://www.npmjs.com/package/@deepseek-ai/dsh-mcp-client).
- [GitHub CLI](https://cli.github.com/manual/).
- [Borrado de repositorio (REST)](https://docs.github.com/en/rest/repos/repos#delete-a-repository).
- [Límites de la API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
- Plugins: [PerryLink](https://github.com/PerryLink/dsh-github), [Moon-shiyue](https://github.com/Moon-shiyue/dsh-github-connect), [kaziii](https://github.com/kaziii/dsh-github-connector), [PivotStack](https://github.com/PivotStackIntelligence/dsh-github).
- Skills: [github-explore](https://github.com/Fectivnfy112357/github-explore), [dsh-github-skills](https://github.com/Starfie1d1272/dsh-github-skills).

> Las estrellas y fechas son una foto de 2026-10-19 y cambian con el tiempo. Las afirmaciones sobre scopes y `/readonly` se verificaron contra la documentación citada y el estado local.

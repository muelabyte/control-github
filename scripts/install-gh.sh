#!/usr/bin/env bash
# Instala GitHub CLI (gh) portable en Linux y macOS, sin sudo.
#
# Uso remoto:
#   curl -fsSL https://raw.githubusercontent.com/muelabyte/control-github/v1.1.0/scripts/install-gh.sh | bash
#   curl -fsSL .../install-gh.sh | bash -s -- --login
#
# Deja gh en ~/.local/bin, lo anade al PATH y escribe el bloque gestionado de
# GitHub en $DSH_HOME/AGENTS.md (por defecto ~/.dsh/AGENTS.md).
#
# Requiere bash 3.2+ (el de macOS), curl o wget, y tar.

set -euo pipefail

VERSION="${GH_VERSION:-2.102.0}"
INSTALL_DIR="${GH_INSTALL_DIR:-$HOME/.local/bin}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
INSTALL_DIR_SET=0
GLOBAL=0
PROJECT=0
PROJECT_DIR=""
NONINTERACTIVE=0
LOGIN=0
CHECK=0
FORCE=0
NO_PATH=0
UPDATE_ONLY=0
UNINSTALL=0

BEGIN_MARK='<!-- dsh-github-cli:begin'
PATH_BEGIN='# dsh-github-cli-path:begin'
PATH_END='# dsh-github-cli-path:end'

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
next() { printf '[NEXT] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Instalador portable de GitHub CLI para Linux y macOS.

Opciones:
  --check, -c                  Solo diagnostico: no descarga ni escribe.
  --global                     Instala para el usuario (global a sus proyectos).
  --project                    Instala solo en el proyecto actual (.dsh/bin).
  --project-dir RUTA           Raiz del proyecto (por defecto raiz git o cwd).
  --non-interactive            No pregunta: usa --global/--project o global.
  --login, -l                  Tras instalar, inicia el login web de GitHub.
  --force, -f                  Reinstala aunque la version coincida.
  --version X                  Version a instalar (por defecto 2.102.0); 'latest'.
  --install-dir RUTA           Carpeta destino (por defecto ~/.local/bin).
  --dsh-home RUTA              Carpeta de DSH (por defecto ~/.dsh).
  --no-path-update             No modifica el rc del shell.
  --update-instructions-only   Solo actualiza AGENTS.md.
  --uninstall                  Elimina gh y el bloque de AGENTS.md.
  --help, -h                   Muestra esta ayuda.

Ejemplos:
  curl -fsSL .../install-gh.sh | bash
  curl -fsSL .../install-gh.sh | bash -s -- --login
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check|-c) CHECK=1 ;;
        --global|-g) GLOBAL=1 ;;
        --project|-p) PROJECT=1 ;;
        --non-interactive|-y) NONINTERACTIVE=1 ;;
        --project-dir)
            shift
            [ $# -gt 0 ] || die '--project-dir necesita un valor'
            PROJECT_DIR="$1"
            ;;
        --project-dir=*) PROJECT_DIR="${1#*=}" ;;
        --login|-l) LOGIN=1 ;;
        --force|-f) FORCE=1 ;;
        --no-path-update) NO_PATH=1 ;;
        --update-instructions-only) UPDATE_ONLY=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --help|-h) usage; exit 0 ;;
        --version)
            shift
            [ $# -gt 0 ] || die '--version necesita un valor'
            VERSION="$1"
            ;;
        --version=*) VERSION="${1#*=}" ;;
        --install-dir)
            shift
            [ $# -gt 0 ] || die '--install-dir necesita un valor'
            INSTALL_DIR="$1"
            INSTALL_DIR_SET=1
            ;;
        --install-dir=*) INSTALL_DIR="${1#*=}"; INSTALL_DIR_SET=1 ;;
        --dsh-home)
            shift
            [ $# -gt 0 ] || die '--dsh-home necesita un valor'
            DSH_HOME="$1"
            ;;
        --dsh-home=*) DSH_HOME="${1#*=}" ;;
        *) die "Opcion desconocida: $1 (usa --help)" ;;
    esac
    shift
done

have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
    url="$1"
    dest="$2"
    if have curl; then
        curl -fsSL --retry 2 -o "$dest" "$url"
    elif have wget; then
        wget -q -O "$dest" "$url"
    else
        die 'Se requiere curl o wget para descargar GitHub CLI'
    fi
}

sha256_of() {
    if have sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    elif have shasum; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die 'Se requiere sha256sum o shasum para verificar la descarga'
    fi
}

gh_version() {
    [ -x "$1" ] || return 1
    "$1" --version 2>/dev/null | head -n 1 |
        sed -n 's/.*gh version \([0-9][0-9.]*\).*/\1/p'
}

gh_login() {
    [ -x "$1" ] || return 1
    "$1" auth status >/dev/null 2>&1 || return 1
    "$1" api user --jq .login 2>/dev/null | head -n 1
}

resolve_path() {
    if have readlink; then
        resolved=$(readlink -f "$1" 2>/dev/null || true)
        if [ -n "$resolved" ]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi
    (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$1")")
}

same_path() {
    [ "$(resolve_path "$1")" = "$(resolve_path "$2")" ]
}

gh_on_path() {
    command -v gh 2>/dev/null | head -n 1 || true
}

semver_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, ".")
        m = split(b, y, ".")
        for (i = 1; i <= 3; i++) {
            xi = (i <= n ? x[i] + 0 : 0)
            yi = (i <= m ? y[i] + 0 : 0)
            if (xi > yi) exit 0
            if (xi < yi) exit 1
        }
        exit 1
    }'
}

resolve_action() {
    if [ -z "$installed_version" ]; then
        if [ "$target_exists" -eq 1 ]; then
            printf 'repair'
        elif [ "$IS_PROJECT" -eq 0 ] && [ "$other_gh_is_other" -eq 1 ] && [ "$INSTALL_DIR_SET" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
            printf 'blocked_other'
        else
            printf 'install'
        fi
    elif [ "$installed_version" = "$VERSION" ]; then
        if [ "$FORCE" -eq 1 ]; then printf 'reinstall'; else printf 'noop'; fi
    elif [ "$FORCE" -eq 1 ]; then
        printf 'replace'
    else
        printf 'blocked_version'
    fi
}

project_root() {
    if [ -n "$PROJECT_DIR" ]; then
        mkdir -p "$PROJECT_DIR"
        (cd "$PROJECT_DIR" && pwd)
    elif have git && git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        pwd
    fi
}

ask_scope() {
    if [ "$GLOBAL" -eq 1 ] && [ "$PROJECT" -eq 1 ]; then
        die 'Usa solo --global o --project'
    fi
    if [ "$GLOBAL" -eq 1 ]; then printf 'global'; return 0; fi
    if [ "$PROJECT" -eq 1 ]; then printf 'project'; return 0; fi
    if [ "$NONINTERACTIVE" -eq 1 ] || { [ ! -t 0 ] && [ ! -r /dev/tty ]; }; then
        printf '[WARN] Sin terminal interactiva: se usa el alcance global (usa --project para el proyecto).\n' >&2
        printf 'global'
        return 0
    fi
    root=$(project_root)
    printf '\n¿Dónde quieres instalar GitHub CLI?\n' >&2
    printf '  [G] Global (este usuario): %s + PATH + %s\n' "$INSTALL_DIR" "$DSH_HOME/AGENTS.md" >&2
    printf '  [P] Solo este proyecto:  %s/.dsh/bin + AGENTS.local.md (sin tocar el PATH)\n' "$root" >&2
    printf '  [C] Cancelar\n' >&2
    printf 'Elige [G/P/C] (G): ' >&2
    answer=""
    if [ -t 0 ]; then
        read -r answer || answer=""
    elif [ -r /dev/tty ]; then
        read -r answer < /dev/tty || answer=""
    fi
    case "$(printf '%s' "$answer" | tr '[:lower:]' '[:upper:]')" in
        P|PROYECTO) printf 'project' ;;
        C|CANCELAR) printf 'cancel' ;;
        *) printf 'global' ;;
    esac
}

write_project_env() {
    root="$1"
    bindir="$2"
    mkdir -p "$root/.dsh"
    envfile="$root/.dsh/env.sh"
    content="# Generado por install-gh.sh (modo proyecto)
export PATH=\"$bindir:\$PATH\""
    ENV_CHANGED=0
    if [ ! -f "$envfile" ] || [ "$(cat "$envfile")" != "$content" ]; then
        printf '%s\n' "$content" > "$envfile"
        ENV_CHANGED=1
    fi
    [ -f "$root/.dsh/.gitignore" ] || printf 'bin/\n' > "$root/.dsh/.gitignore"
    [ "$ENV_CHANGED" -eq 1 ] && ok "Entorno local: $envfile"
}

detect_platform() {
    case "$(uname -s)" in
        Linux*) OS=linux ;;
        Darwin*) OS=darwin ;;
        *) die "Sistema no soportado: $(uname -s). En Windows usa install-gh.ps1" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) ARCH=amd64 ;;
        arm64|aarch64) ARCH=arm64 ;;
        i386|i686) ARCH=386 ;;
        armv6l|armv7l) ARCH=armv6 ;;
        ppc64le) ARCH=ppc64le ;;
        s390x) ARCH=s390x ;;
        *) die "Arquitectura no soportada: $(uname -m)" ;;
    esac

    if [ "$OS" = darwin ]; then
        case "$ARCH" in
            amd64|arm64) ;;
            *) die "macOS solo soporta amd64 y arm64 (detectado: $ARCH)" ;;
        esac
    fi

    if [ "$OS" = linux ] && [ -f /etc/alpine-release ]; then
        die 'Alpine/musl no soportado por el binario oficial (glibc). Usa: sudo apk add github-cli'
    fi
}

resolve_latest() {
    tmpjson="$1"
    fetch 'https://api.github.com/repos/cli/cli/releases/latest' "$tmpjson"
    sed -n 's/.*"tag_name" *: *"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' "$tmpjson" |
        head -n 1
}

choose_rc() {
    shell_name=$(basename "${SHELL:-}")
    case "$shell_name" in
        zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash)
            if [ "$OS" = darwin ]; then
                printf '%s\n' "$HOME/.bash_profile"
            else
                printf '%s\n' "$HOME/.bashrc"
            fi
            ;;
        *) printf '%s\n' "$HOME/.profile" ;;
    esac
}

path_block() {
    printf '%s\n' "$PATH_BEGIN (gestionado por install-gh.sh; no editar a mano)"
    printf 'export PATH="%s:$PATH"\n' "$INSTALL_DIR"
    printf '%s\n' "$PATH_END"
}

update_path_file() {
    rc="$1"
    block=$(mktemp "${TMPDIR:-/tmp}/gh-path.XXXXXX")
    path_block > "$block"
    [ -f "$rc" ] || : > "$rc"
    if grep -qF "$PATH_BEGIN" "$rc"; then
        awk -v blk="$block" '
            BEGIN { while ((getline l < blk) > 0) b = b l "\n" }
            index($0, "# dsh-github-cli-path:begin") == 1 { printf "%s", b; skip = 1; next }
            index($0, "# dsh-github-cli-path:end") == 1 { skip = 0; next }
            !skip { print }
        ' "$rc" > "$rc.dsh.tmp"
    else
        { cat "$rc"; printf '\n'; cat "$block"; } > "$rc.dsh.tmp"
    fi
    rm -f "$block"
    mv "$rc.dsh.tmp" "$rc"
}

agents_header() {
    if [ "${1:-global}" = project ]; then
        printf '# Instrucciones locales del proyecto\n\n'
        printf '> Este archivo solo aplica a este proyecto. DSH lo carga además del AGENTS.md global.\n\n'
        return 0
    fi
    printf '# Contexto global del usuario\n\n'
    printf '> Instrucciones globales: DSH carga este archivo en la primera petición de\n'
    printf '> **todas** las sesiones, sin importar la carpeta de trabajo.\n\n'
}

agents_block() {
    gh_version_value="$1"
    gh_path_value="$2"
    login_value="$3"
    scope_value="${4:-global}"

    path_line=$(mktemp "${TMPDIR:-/tmp}/gh-pathline.XXXXXX")
    if [ "$scope_value" = project ]; then
        cat > "$path_line" <<'EOF'
- `gh` __VERSION__ instalado en modo portable en `__GH_PATH__` (instalación local
  del proyecto; el PATH no se modificó: usa esta ruta o ejecuta `.dsh/env.sh`).
EOF
    else
        cat > "$path_line" <<'EOF'
- `gh` __VERSION__ instalado en modo portable en `__GH_PATH__` (esa carpeta está
  en el PATH del usuario; si no se resuelve, invoca la ruta absoluta).
EOF
    fi

    auth_block=$(mktemp "${TMPDIR:-/tmp}/gh-auth.XXXXXX")
    if [ -n "$login_value" ]; then
        printf -- '- Sesión activa en `github.com` como `%s` (token en el gestor de\n' "$login_value" > "$auth_block"
        printf '  credenciales del sistema; el login web concede `repo`, `read:org`, `gist` y\n' >> "$auth_block"
        printf '  `workflow`). Verifica con `gh auth status`; el login real, con\n' >> "$auth_block"
        printf '  `gh api user --jq .login`.\n' >> "$auth_block"
    else
        cat > "$auth_block" <<'EOF'
- Sesión **pendiente**: ejecuta
  `gh auth login --hostname github.com --git-protocol https --web` y autoriza en
  el navegador. Nunca pidas el token por el chat.
EOF
    fi

    raw_block=$(mktemp "${TMPDIR:-/tmp}/gh-block.XXXXXX")
    cat > "$raw_block" <<'EOF'
<!-- dsh-github-cli:begin (bloque gestionado; no editar a mano) -->
## GitHub — usar GitHub CLI (`gh`)

Toda pregunta sobre GitHub (repositorios, issues, PRs, releases, Actions, gists o
código) debe resolverse con datos reales usando **GitHub CLI**, sin configuración
por sesión.

__PATH_LINE__
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
EOF

    with_auth=$(mktemp "${TMPDIR:-/tmp}/gh-withauth.XXXXXX")
    awk -v authfile="$auth_block" -v pathfile="$path_line" '
        BEGIN {
            while ((getline l < authfile) > 0) a = a l "\n"
            while ((getline p < pathfile) > 0) pl = pl p "\n"
        }
        index($0, "__PATH_LINE__") == 1 { printf "%s", pl; next }
        index($0, "__AUTH_BLOCK__") == 1 { printf "%s", a; next }
        { print }
    ' "$raw_block" > "$with_auth"

    escaped_path=$(printf '%s' "$gh_path_value" | sed 's/[&|\\]/\\&/g')
    sed -e "s|__VERSION__|$gh_version_value|g" \
        -e "s|__GH_PATH__|$escaped_path|g" "$with_auth"

    rm -f "$auth_block" "$raw_block" "$with_auth" "$path_line"
}

update_agents() {
    file="$1"
    block="$2"
    dir=$(dirname "$file")
    [ -d "$dir" ] || mkdir -p "$dir"

    if [ ! -f "$file" ]; then
        { agents_header "$SCOPE"; cat "$block"; } > "$file"
        printf 'creado'
        return 0
    fi

    if grep -qF "$BEGIN_MARK" "$file"; then
        awk -v blk="$block" '
            BEGIN { while ((getline l < blk) > 0) b = b l "\n" }
            index($0, "<!-- dsh-github-cli:begin") == 1 { printf "%s", b; skip = 1; next }
            index($0, "<!-- dsh-github-cli:end -->") == 1 { skip = 0; next }
            !skip { print }
        ' "$file" > "$file.dsh.tmp"
    elif grep -qF '## GitHub — usar GitHub CLI' "$file"; then
        awk -v blk="$block" '
            BEGIN { while ((getline l < blk) > 0) b = b l "\n" }
            index($0, "## GitHub — usar GitHub CLI") == 1 { printf "%s", b; skip = 1; next }
            skip && index($0, "## ") == 1 { skip = 0 }
            !skip { print }
        ' "$file" > "$file.dsh.tmp"
    else
        { cat "$file"; printf '\n'; cat "$block"; } > "$file.dsh.tmp"
    fi

    if cmp -s "$file" "$file.dsh.tmp"; then
        rm -f "$file.dsh.tmp"
        printf 'sin cambios'
    else
        mv "$file.dsh.tmp" "$file"
        printf 'actualizado'
    fi
}

remove_agents_block() {
    file="$1"
    [ -f "$file" ] || return 0
    grep -qF "$BEGIN_MARK" "$file" || return 0
    awk '
        index($0, "<!-- dsh-github-cli:begin") == 1 { skip = 1; next }
        index($0, "<!-- dsh-github-cli:end -->") == 1 { skip = 0; next }
        !skip { print }
    ' "$file" > "$file.dsh.tmp"
    mv "$file.dsh.tmp" "$file"
}

remove_path_block() {
    rc="$1"
    [ -f "$rc" ] || return 0
    grep -qF "$PATH_BEGIN" "$rc" || return 0
    awk '
        index($0, "# dsh-github-cli-path:begin") == 1 { skip = 1; next }
        index($0, "# dsh-github-cli-path:end") == 1 { skip = 0; next }
        !skip { print }
    ' "$rc" > "$rc.dsh.tmp"
    mv "$rc.dsh.tmp" "$rc"
}

install_gh() {
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/gh.XXXXXX") || die 'No se pudo crear un directorio temporal'
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    case "$OS" in
        linux) asset="gh_${VERSION}_linux_${ARCH}.tar.gz" ;;
        darwin) asset="gh_${VERSION}_macOS_${ARCH}.zip" ;;
        *) die "Sistema no soportado: $OS" ;;
    esac
    base="https://github.com/cli/cli/releases/download/v${VERSION}"

    info "Descargando $asset ..."
    fetch "$base/$asset" "$tmpdir/$asset"
    fetch "$base/gh_${VERSION}_checksums.txt" "$tmpdir/checksums.txt"

    expected=$(awk -v a="$asset" '$2 == a { print $1 }' "$tmpdir/checksums.txt" | head -n 1)
    [ -n "$expected" ] || die "El archivo de checksums no contiene $asset"
    actual=$(sha256_of "$tmpdir/$asset")
    [ "$expected" = "$actual" ] || die "SHA256 no coincide para $asset (esperado $expected, obtenido $actual)"
    ok "SHA256 verificado: $actual"

    case "$asset" in
        *.zip)
            have unzip || die 'Se requiere unzip para extraer el binario de macOS'
            unzip -q "$tmpdir/$asset" -d "$tmpdir"
            ;;
        *)
            tar -xzf "$tmpdir/$asset" -C "$tmpdir"
            ;;
    esac
    src=$(find "$tmpdir" -type f -path '*/bin/gh' | head -n 1)
    [ -n "$src" ] || die 'El tar.gz descargado no contiene bin/gh'

    mkdir -p "$INSTALL_DIR"
    install -m 755 "$src" "$GH_BIN"
    ok "gh instalado en $GH_BIN"
}

run_login() {
    info 'Iniciando login web de GitHub. El codigo de 8 caracteres lo genera gh en este equipo, no GitHub: aparece como "First copy your one-time code" y se pega en https://github.com/login/device. No es el codigo 2FA. Si no lo ves, Ctrl+C y repite: se genera uno nuevo.'
    if [ -r /dev/tty ] && [ ! -t 0 ]; then
        "$GH_BIN" auth login --hostname github.com --git-protocol https --web < /dev/tty || \
            warn 'El login no termino correctamente'
    else
        "$GH_BIN" auth login --hostname github.com --git-protocol https --web || \
            warn 'El login no termino correctamente'
    fi
}

detect_platform

SCOPE=$(ask_scope)
case "$SCOPE" in
    cancel)
        ok 'Cancelado, sin cambios.'
        exit 0
        ;;
    project)
        if [ "$INSTALL_DIR_SET" -eq 1 ]; then
            die 'En modo proyecto no uses --install-dir; usa --project-dir'
        fi
        IS_PROJECT=1
        PROJECT_ROOT=$(project_root)
        INSTALL_DIR="$PROJECT_ROOT/.dsh/bin"
        AGENTS_FILE="$PROJECT_ROOT/AGENTS.local.md"
        GH_BIN="$INSTALL_DIR/gh"
        info "Alcance: proyecto ($PROJECT_ROOT)"
        ;;
    *)
        IS_PROJECT=0
        AGENTS_FILE="$DSH_HOME/AGENTS.md"
        GH_BIN="$INSTALL_DIR/gh"
        info 'Alcance: global (usuario)'
        ;;
esac
info "Sistema: $OS/$ARCH"
info "Destino: $GH_BIN"
info "Instrucciones: $AGENTS_FILE"
ENV_CHANGED=0

if [ "$UNINSTALL" -eq 1 ]; then
    if [ -f "$GH_BIN" ]; then
        rm -f "$GH_BIN"
        ok "Eliminado $GH_BIN"
    else
        warn "No existe $GH_BIN"
    fi
    remove_agents_block "$AGENTS_FILE"
    ok "Bloque de GitHub eliminado de $AGENTS_FILE"
    if [ "$IS_PROJECT" -eq 1 ]; then
        rm -f "$PROJECT_ROOT/.dsh/env.sh"
        header_tmp=$(mktemp "${TMPDIR:-/tmp}/gh-header.XXXXXX")
        agents_header project > "$header_tmp"
        if [ -f "$AGENTS_FILE" ] && [ "$(cat "$AGENTS_FILE")" = "$(cat "$header_tmp")" ]; then
            rm -f "$AGENTS_FILE"
            ok "Eliminado $AGENTS_FILE"
        fi
        rm -f "$header_tmp"
    else
        remove_path_block "$(choose_rc)"
    fi
    next 'La sesion de GitHub sigue guardada. Para cerrarla: gh auth logout --hostname github.com'
    exit 0
fi

installed_version=$(gh_version "$GH_BIN" || true)
logged_as=$(gh_login "$GH_BIN" || true)
target_exists=0
[ -f "$GH_BIN" ] && target_exists=1
other_gh=$(gh_on_path || true)
other_version=""
other_gh_is_other=0
if [ -n "$other_gh" ] && ! same_path "$other_gh" "$GH_BIN"; then
    other_version=$(gh_version "$other_gh" || true)
    other_gh_is_other=1
fi
action=none
path_changed=0

if [ "$CHECK" -eq 1 ]; then
    ok "Alcance: $SCOPE"
    if [ -n "$installed_version" ]; then
        ok "gh $installed_version instalado en $GH_BIN"
    elif [ "$target_exists" -eq 1 ]; then
        warn "Existe $GH_BIN pero no responde"
    else
        warn "gh no esta instalado en $GH_BIN"
    fi
    if [ "$other_gh_is_other" -eq 1 ]; then
        if [ "$IS_PROJECT" -eq 1 ]; then
            warn "Otra instalacion en el PATH: $other_gh${other_version:+ (version $other_version)} (la local tiene prioridad)"
        else
            warn "Otra instalacion en el PATH: $other_gh${other_version:+ (version $other_version)}"
        fi
    fi
    if [ -n "$logged_as" ]; then
        ok "Sesion iniciada como $logged_as"
    else
        warn 'Sin sesion de GitHub (falta gh auth login)'
    fi
    if [ "$IS_PROJECT" -eq 1 ]; then
        ok "PATH: sin cambios; entorno local en $PROJECT_ROOT/.dsh/env.sh"
    else
        case ":$PATH:" in
            *":$INSTALL_DIR:"*) ok 'PATH: correcto' ;;
            *) warn "PATH: falta $INSTALL_DIR" ;;
        esac
    fi
    if [ -f "$AGENTS_FILE" ] && grep -qF "$BEGIN_MARK" "$AGENTS_FILE"; then
        ok "$AGENTS_FILE con bloque gestionado"
    elif [ -f "$AGENTS_FILE" ]; then
        warn "$AGENTS_FILE existe sin bloque gestionado (se migrara al ejecutar la instalacion)"
    else
        warn "$AGENTS_FILE no existe"
    fi

    if [ "$VERSION" = latest ]; then
        next 'Accion: resolveria la ultima estable (requiere red) y la compararia con la instalada.'
    else
        case "$(resolve_action)" in
            noop) ok "Accion: sin cambios en el binario (gh $installed_version)" ;;
            install) next "Accion: instalaria gh $VERSION" ;;
            repair) warn "Accion: repararia $GH_BIN" ;;
            blocked_other) warn 'Accion: bloqueado; ya hay otra instalacion (usa --force o --install-dir)' ;;
            blocked_version) warn "Accion: requiere --force para reemplazar gh $installed_version por $VERSION" ;;
            replace) warn "Accion: reemplazaria gh $installed_version por $VERSION (--force)" ;;
            reinstall) next "Accion: reinstalaria gh $installed_version (--force)" ;;
        esac
    fi
    exit 0
fi

if [ "$UPDATE_ONLY" -eq 0 ]; then
    if [ "$VERSION" = latest ]; then
        tmpjson=$(mktemp "${TMPDIR:-/tmp}/gh-latest.XXXXXX")
        resolved=$(resolve_latest "$tmpjson")
        rm -f "$tmpjson"
        [ -n "$resolved" ] || die 'No se pudo resolver la ultima version estable'
        VERSION="$resolved"
        info "Ultima version estable: $VERSION"
    fi

    action=$(resolve_action)

    case "$action" in
        blocked_other)
            warn "Ya hay gh instalado en $other_gh${other_version:+ (version $other_version)}."
            warn "No se instalo una segunda copia en $GH_BIN."
            next 'Para instalar en paralelo: repite el comando con --force'
            next 'Para elegir otra carpeta: --install-dir RUTA'
            next 'Para usar la existente: gh --version'
            exit 2
            ;;
        blocked_version)
            warn "gh $installed_version instalado en $GH_BIN"
            if semver_gt "$installed_version" "$VERSION"; then
                warn "La version solicitada ($VERSION) es anterior: seria un downgrade. No se modifico nada."
            else
                warn "La version solicitada ($VERSION) es distinta de la instalada. No se modifico nada."
            fi
            next "Para reemplazar por $VERSION: repite el comando con --force"
            next 'Para conservar la actual: no hagas nada'
            if [ "$IS_PROJECT" -eq 1 ]; then
                next 'Para otra raiz de proyecto: --project-dir RUTA'
            else
                next 'Para instalar en otra carpeta: --install-dir RUTA'
            fi
            exit 2
            ;;
        repair) warn "Existe $GH_BIN pero no responde; se repara." ;;
        replace)
            if semver_gt "$installed_version" "$VERSION"; then
                warn "Reemplazando gh $installed_version por $VERSION (downgrade solicitado con --force)."
            else
                info "Actualizando gh $installed_version -> $VERSION (--force)."
            fi
            ;;
        reinstall) info "Reinstalando gh $installed_version (--force)." ;;
        noop) ok "gh $installed_version ya instalado; sin cambios en el binario." ;;
    esac

    case "$action" in
        install|repair|replace|reinstall)
            install_gh
            installed_version=$(gh_version "$GH_BIN" || true)
            [ -n "$installed_version" ] || die 'gh no responde tras la instalacion'
            ok "gh $installed_version operativo"
            ;;
    esac
fi

if [ -z "$installed_version" ]; then
    die 'No hay gh instalado; ejecuta el instalador sin --update-instructions-only'
fi

if [ "$NO_PATH" -eq 0 ]; then
    if [ "$IS_PROJECT" -eq 1 ]; then
        write_project_env "$PROJECT_ROOT" "$INSTALL_DIR"
    else
        case ":$PATH:" in
            *":$INSTALL_DIR:"*)
                ok 'La carpeta ya esta en el PATH de esta sesion'
                ;;
            *)
                rc=$(choose_rc)
                update_path_file "$rc"
                PATH="$INSTALL_DIR:$PATH"
                export PATH
                path_changed=1
                ok "PATH actualizado en $rc (abre una shell nueva para que persista)"
                ;;
        esac
    fi
fi

resolved_after=$(gh_on_path || true)
if [ -n "$resolved_after" ] && ! same_path "$resolved_after" "$GH_BIN"; then
    if [ "$IS_PROJECT" -eq 1 ]; then
        warn "El comando 'gh' del PATH apunta a $resolved_after; en este proyecto usa $GH_BIN o .dsh/env.sh."
    else
        warn "El comando 'gh' del PATH apunta a $resolved_after, no a $GH_BIN. Ajusta el PATH o invoca la ruta absoluta."
    fi
fi

if [ "$LOGIN" -eq 1 ] && [ -z "$logged_as" ]; then
    run_login
    logged_as=$(gh_login "$GH_BIN" || true)
fi

block_file=$(mktemp "${TMPDIR:-/tmp}/gh-block.XXXXXX")
agents_block "$installed_version" "$GH_BIN" "$logged_as" "$SCOPE" > "$block_file"
result=$(update_agents "$AGENTS_FILE" "$block_file")
rm -f "$block_file"
ok "Instrucciones: $result"

if [ -n "$logged_as" ]; then
    ok "Sesion de GitHub activa como $logged_as"
    next "Prueba: gh repo list $logged_as --limit 5 --json name,visibility"
else
    warn 'GitHub todavia sin sesion'
    next 'Ejecuta: gh auth login --hostname github.com --git-protocol https --web'
    next 'El codigo de 8 caracteres lo genera gh en este equipo y aparece en esa terminal (no es el 2FA). Pegalo en https://github.com/login/device.'
fi

parts=""
case "$action" in
    install|repair|replace|reinstall) parts="binario gh $installed_version" ;;
esac
if [ "$path_changed" -eq 1 ]; then
    parts="${parts:+$parts; }PATH"
fi
if [ "$ENV_CHANGED" -eq 1 ]; then
    parts="${parts:+$parts; }entorno local (.dsh/env.sh)"
fi
if [ "$result" != "sin cambios" ]; then
    parts="${parts:+$parts; }instrucciones ($result)"
fi
if [ -z "$parts" ]; then
    ok 'Resumen: sin cambios.'
else
    ok "Resumen: $parts"
fi

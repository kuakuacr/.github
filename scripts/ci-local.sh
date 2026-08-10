#!/usr/bin/env bash
#
# Espejo local de ci.yml (el CI reutilizable de kuakuacr/.github): corre los
# mismos linters, con la misma configuración, gratis y antes de pushear.
# Fase 3 del plan de ahorro de minutos de Actions (PLAN-actions-minutos.md).
#
# Uso: parado en la raíz de cualquier repo de Kua'kua —
#
#   curl -sSfL https://raw.githubusercontent.com/kuakuacr/.github/main/scripts/ci-local.sh | bash
#
# Sin copia local en cada repo a propósito: la misma razón que ya vale para
# .gitleaks.toml en ci.yml — una copia por repo se desactualiza en cuanto
# cambia la fuente. Esta SÍ hay que bajarla de acá cada vez; no vale la pena
# cachearla.
#
# Lee los flags (yaml/shell/docker/node/html/n8n) del propio
# .github/workflows/ci.yml del repo donde se corre — no hace falta pasarlos
# a mano ni mantenerlos sincronizados en dos lugares.
#
# Funciona en Linux, macOS y Windows (Git Bash) — detecta la plataforma y
# baja el binario que corresponda. Las herramientas se cachean en
# ~/.cache/kuakua-ci-local/bin (redefinible con $CI_LOCAL_CACHE) para no
# volver a bajarlas en cada corrida.
#
# A diferencia de CI, un chequeo que no se pudo instalar es una advertencia,
# no un fallo: esto es una ayuda antes de pushear, no el gate final — CI
# sigue siendo quien decide de verdad.

set -uo pipefail

# Mismas versiones que ci.yml. Si cambian ahí, cambiar acá también — no se
# leen dinámicamente para no depender de la red solo para saber qué versión
# usar.
GITLEAKS_VERSION="8.30.1"
HADOLINT_VERSION="2.14.0"
SHELLCHECK_VERSION="0.11.0"

CACHE_DIR="${CI_LOCAL_CACHE:-$HOME/.cache/kuakua-ci-local}"
BIN_DIR="$CACHE_DIR/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

FALLOS=0
ADVERTENCIAS=0
CI_YML=".github/workflows/ci.yml"

if [ ! -d .git ]; then
  echo "error: correr esto parado en la raíz de un repo git" >&2
  exit 1
fi

# ── Plataforma ───────────────────────────────────────────────────────────

case "$(uname -s)" in
  Linux*) OS=linux ;;
  Darwin*) OS=darwin ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=unknown ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH=x64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) ARCH=x64 ;;
esac

# ── Python utilizable (mismo problema que scripts/update-secret.sh: python3
# suele estar en el PATH como un stub de Microsoft Store que no imprime nada)

find_python() {
  local interprete
  for interprete in python3 python py; do
    command -v "$interprete" >/dev/null 2>&1 || continue
    if [ -n "$("$interprete" -c 'print(1)' 2>/dev/null)" ]; then
      echo "$interprete"
      return 0
    fi
  done
  return 1
}

# ── Flags: leídos del ci.yml del repo actual ────────────────────────────

flag() {
  local nombre="$1" default="$2"
  [ -f "$CI_YML" ] || { echo "$default"; return; }
  local linea
  linea=$(grep -E "^[[:space:]]*${nombre}:[[:space:]]*(true|false)" "$CI_YML" | head -1)
  [ -z "$linea" ] && { echo "$default"; return; }
  echo "$linea" | grep -q true && echo true || echo false
}

YAML=$(flag yaml true)
SHELL_ON=$(flag shell true)
DOCKER_ON=$(flag docker false)
NODE_ON=$(flag node false)
HTML_ON=$(flag html false)
N8N_ON=$(flag n8n false)

echo "── $(basename "$(pwd)") — según $CI_YML ─────────────────────"
echo "   yaml=$YAML  shell=$SHELL_ON  docker=$DOCKER_ON  node=$NODE_ON  html=$HTML_ON  n8n=$N8N_ON"
echo

paso() { echo "▶ $1"; }
ok()   { echo "  ✓ $1"; }
mal()  { echo "  ✗ $1"; FALLOS=$((FALLOS + 1)); }
avisa(){ echo "  ⚠ $1"; ADVERTENCIAS=$((ADVERTENCIAS + 1)); }

# ── gitleaks (siempre corre, como en ci.yml) ────────────────────────────

paso "gitleaks"
if ! command -v gitleaks >/dev/null 2>&1; then
  case "$OS" in
    linux)   ASSET="gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz" ;;
    darwin)  ASSET="gitleaks_${GITLEAKS_VERSION}_darwin_${ARCH}.tar.gz" ;;
    windows) ASSET="gitleaks_${GITLEAKS_VERSION}_windows_${ARCH}.zip" ;;
    *) ASSET="" ;;
  esac
  if [ -n "$ASSET" ]; then
    URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${ASSET}"
    TMP=$(mktemp -d)
    if curl -sSfL -o "$TMP/pkg" "$URL"; then
      if [ "$OS" = windows ]; then
        unzip -oq "$TMP/pkg" -d "$TMP"
        cp "$TMP/gitleaks.exe" "$BIN_DIR/gitleaks.exe"
      else
        tar -xzf "$TMP/pkg" -C "$TMP" gitleaks
        install -m 0755 "$TMP/gitleaks" "$BIN_DIR/gitleaks"
      fi
    fi
    rm -rf "$TMP"
  fi
fi
if command -v gitleaks >/dev/null 2>&1; then
  CONFIG=""
  if curl -sSfL -o "$CACHE_DIR/gitleaks-canon.toml" \
       "https://raw.githubusercontent.com/kuakuacr/.github/main/.gitleaks.toml?v=$(date +%s)" 2>/dev/null; then
    CONFIG="$CACHE_DIR/gitleaks-canon.toml"
  elif [ -f .gitleaks.toml ]; then
    CONFIG=".gitleaks.toml"
    avisa "no se pudo bajar la config canónica de gitleaks; usando la copia local"
  fi
  ARGS_DIR=(dir . --redact --exit-code 1)
  ARGS_GIT=(git . --redact --exit-code 1)
  [ -n "$CONFIG" ] && { ARGS_DIR+=(--config "$CONFIG"); ARGS_GIT+=(--config "$CONFIG"); }
  if gitleaks "${ARGS_DIR[@]}" >/tmp/gitleaks-dir.log 2>&1 && gitleaks "${ARGS_GIT[@]}" >/tmp/gitleaks-git.log 2>&1; then
    ok "sin secretos"
  else
    mal "gitleaks encontró algo — ver /tmp/gitleaks-dir.log y /tmp/gitleaks-git.log"
  fi
else
  avisa "no se pudo obtener gitleaks para esta plataforma ($OS/$ARCH) — sin chequear"
fi

# ── yamllint ─────────────────────────────────────────────────────────────

if [ "$YAML" = true ]; then
  paso "yamllint"
  if ! command -v yamllint >/dev/null 2>&1; then
    PY=$(find_python) || PY=""
    if [ -n "$PY" ]; then
      "$PY" -m pip install --quiet --user --upgrade yamllint 2>/dev/null || true
      # pip --user instala los ejecutables en un directorio que sysconfig
      # sabe calcular pero que no está en PATH por defecto. En Windows NO es
      # simplemente "<user-base>/Scripts": lleva un subdirectorio con la
      # versión en medio ("Roaming/Python/Python312/Scripts") que hay que
      # preguntarle a Python, no adivinar.
      USER_SCRIPTS=$("$PY" -c "
import sysconfig, os
scheme = 'nt_user' if os.name == 'nt' else 'posix_user'
print(sysconfig.get_path('scripts', scheme))
" 2>/dev/null || echo "")
      [ -n "$USER_SCRIPTS" ] && export PATH="$USER_SCRIPTS:$PATH"
    fi
  fi
  if command -v yamllint >/dev/null 2>&1; then
    if [ -f .yamllint.yml ]; then
      YL_OUT=$(yamllint -d .yamllint.yml . 2>&1)
    else
      YL_OUT=$(yamllint -d "{extends: relaxed, rules: {line-length: disable}}" . 2>&1)
    fi
    if [ -z "$YL_OUT" ]; then
      ok "sin problemas"
    else
      echo "$YL_OUT" | sed 's/^/    /'
      echo "$YL_OUT" | grep -q ": error" && mal "yamllint encontró errores" || avisa "yamllint tiene advertencias (no bloquean)"
    fi
  else
    avisa "no se pudo instalar yamllint (¿python3/pip disponibles?) — sin chequear"
  fi
fi

# ── shellcheck ───────────────────────────────────────────────────────────

if [ "$SHELL_ON" = true ]; then
  paso "shellcheck"
  mapfile -t SH_FILES < <(find . -type f -name '*.sh' -not -path './.git/*')
  if [ ${#SH_FILES[@]} -eq 0 ]; then
    ok "sin scripts .sh"
  else
    if ! command -v shellcheck >/dev/null 2>&1; then
      case "$OS" in
        linux)   ASSET="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" ;;
        darwin)  ASSET="shellcheck-v${SHELLCHECK_VERSION}.darwin.x86_64.tar.xz" ;;
        windows) ASSET="shellcheck-v${SHELLCHECK_VERSION}.zip" ;;
        *) ASSET="" ;;
      esac
      if [ -n "$ASSET" ]; then
        URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${ASSET}"
        TMP=$(mktemp -d)
        if curl -sSfL -o "$TMP/pkg" "$URL"; then
          if [ "$OS" = windows ]; then
            unzip -oq "$TMP/pkg" -d "$TMP"
            cp "$TMP/shellcheck.exe" "$BIN_DIR/shellcheck.exe"
          else
            tar -xJf "$TMP/pkg" -C "$TMP" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
            install -m 0755 "$TMP/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$BIN_DIR/shellcheck"
          fi
        fi
        rm -rf "$TMP"
      fi
    fi
    if command -v shellcheck >/dev/null 2>&1; then
      if shellcheck -S warning "${SH_FILES[@]}"; then
        ok "${#SH_FILES[@]} script(s) OK"
      else
        mal "shellcheck encontró problemas"
      fi
    else
      avisa "no se pudo obtener shellcheck para esta plataforma ($OS/$ARCH) — sin chequear"
    fi
  fi
fi

# ── hadolint ─────────────────────────────────────────────────────────────

if [ "$DOCKER_ON" = true ]; then
  paso "hadolint"
  mapfile -t DOCKERFILES < <(find . -type f -name 'Dockerfile*' -not -path './.git/*')
  if [ ${#DOCKERFILES[@]} -eq 0 ]; then
    ok "sin Dockerfiles"
  else
    if ! command -v hadolint >/dev/null 2>&1; then
      case "$OS" in
        linux)   ASSET="hadolint-linux-x86_64" ;;
        darwin)  ASSET="hadolint-macos-x86_64" ;;
        windows) ASSET="hadolint-windows-x86_64.exe" ;;
        *) ASSET="" ;;
      esac
      if [ -n "$ASSET" ]; then
        URL="https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/${ASSET}"
        OUT="$BIN_DIR/hadolint"; [ "$OS" = windows ] && OUT="$BIN_DIR/hadolint.exe"
        curl -sSfL -o "$OUT" "$URL" && chmod +x "$OUT" 2>/dev/null || true
      fi
    fi
    if command -v hadolint >/dev/null 2>&1; then
      if hadolint --failure-threshold error "${DOCKERFILES[@]}"; then
        ok "${#DOCKERFILES[@]} Dockerfile(s) OK"
      else
        mal "hadolint encontró errores"
      fi
    else
      avisa "no se pudo obtener hadolint para esta plataforma ($OS/$ARCH) — sin chequear"
    fi
  fi
fi

# ── node --check ─────────────────────────────────────────────────────────

if [ "$NODE_ON" = true ]; then
  paso "node --check"
  mapfile -t JS_FILES < <(find . -type f -name '*.js' -not -path './.git/*' -not -path './node_modules/*')
  if [ ${#JS_FILES[@]} -eq 0 ]; then
    ok "sin archivos .js"
  elif command -v node >/dev/null 2>&1; then
    BIEN=0
    for f in "${JS_FILES[@]}"; do
      node --check "$f" || { mal "sintaxis inválida: $f"; BIEN=1; }
    done
    [ "$BIEN" -eq 0 ] && ok "${#JS_FILES[@]} archivo(s) JS con sintaxis válida"
  else
    avisa "node no está disponible — sin chequear"
  fi
fi

# ── htmlhint ─────────────────────────────────────────────────────────────

if [ "$HTML_ON" = true ]; then
  paso "htmlhint"
  mapfile -t HTML_FILES < <(find . -type f -name '*.html' -not -path './.git/*')
  if [ ${#HTML_FILES[@]} -eq 0 ]; then
    ok "sin archivos .html"
  elif command -v npx >/dev/null 2>&1; then
    if npx --yes htmlhint "${HTML_FILES[@]}"; then
      ok "${#HTML_FILES[@]} archivo(s) HTML OK"
    else
      mal "htmlhint encontró problemas"
    fi
  else
    avisa "npx no está disponible — sin chequear"
  fi
fi

# ── workflows de n8n ─────────────────────────────────────────────────────

if [ "$N8N_ON" = true ]; then
  paso "validar workflows n8n"
  if command -v jq >/dev/null 2>&1; then
    shopt -s nullglob
    N8N_FILES=(workflows/*.json)
    if [ ${#N8N_FILES[@]} -eq 0 ]; then
      mal "no hay workflows/*.json"
    else
      N8N_FALLOS=0
      for f in "${N8N_FILES[@]}"; do
        if ! jq empty "$f" 2>/dev/null; then
          echo "    $f: JSON inválido"; N8N_FALLOS=1; continue
        fi
        if ! jq -e '(.id? // empty) and (.name? // empty) and (.nodes | type == "array" and length > 0)' "$f" >/dev/null; then
          echo "    $f: falta id/name/nodes"; N8N_FALLOS=1; continue
        fi
        if jq -e '[.nodes[] | select(.type=="n8n-nodes-base.code") | .parameters.jsCode // ""]
                  | join("\n") | test("\\$helpers|(^|[^.\\w])fetch\\s*\\(")' "$f" >/dev/null; then
          BASE=$(basename "$f")
          if [ -f workflows/D10-DEUDA.txt ] && grep -qxF "$BASE" workflows/D10-DEUDA.txt; then
            echo "    $f: deuda D10 conocida"
          else
            echo "    $f: Code node usa \$helpers o fetch — prohibido (docs/RULES.md D10)"; N8N_FALLOS=1
          fi
        fi
      done
      [ "$N8N_FALLOS" -eq 0 ] && ok "${#N8N_FILES[@]} workflow(s) válidos" || mal "workflows con problemas"
    fi
  else
    avisa "jq no está disponible — sin chequear"
  fi
fi

# ── resumen ──────────────────────────────────────────────────────────────

echo
if [ "$FALLOS" -eq 0 ]; then
  echo "✓ Todo en verde ($ADVERTENCIAS advertencia(s))."
  [ "$ADVERTENCIAS" -gt 0 ] && echo "  Las advertencias son de herramientas no disponibles en esta máquina — CI sigue siendo el chequeo real para esas."
else
  echo "✗ $FALLOS chequeo(s) en rojo. Arreglar antes de pushear."
fi
exit "$FALLOS"

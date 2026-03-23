#!/usr/bin/env bash
# passx installer
#
#   Remote (curl):
#     bash <(curl -fsSL https://raw.githubusercontent.com/tonycrt7/passx/main/install.sh)
#     curl -fsSL .../install.sh | bash
#     curl -fsSL .../install.sh | PREFIX=$HOME/.local bash
#
#   Local (cloned repo / extracted tarball):
#     bash install.sh
#     PREFIX=$HOME/.local bash install.sh
#     sudo bash install.sh                  # for system-wide install
#
#   Uninstall:
#     bash install.sh --uninstall
#     sudo bash install.sh --uninstall
#
set -euo pipefail

REPO="tonycrt7/passx"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
VERSION="1.7.0"

PREFIX="${PREFIX:-/usr/local}"
BINDIR="${PREFIX}/bin"
MANDIR="${PREFIX}/share/man/man1"
BASH_COMP_DIR="${PREFIX}/share/bash-completion/completions"
ZSH_COMP_DIR="${PREFIX}/share/zsh/site-functions"
FISH_COMP_DIR="${PREFIX}/share/fish/vendor_completions.d"
DOC_DIR="${PREFIX}/share/doc/passx"

# ── Colour ────────────────────────────────────────────────────────
if [ -t 1 ] || [ "${FORCE_COLOR:-}" = "1" ]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    CYAN='\033[0;36m' BOLD='\033[1m' RESET='\033[0m' DIM='\033[2m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET='' DIM=''
fi
ok()   { printf "${GREEN}  ✔${RESET}  %s\n" "$*"; }
info() { printf "${CYAN}  ℹ${RESET}  %s\n" "$*"; }
warn() { printf "${YELLOW}  ⚠${RESET}  %s\n" "$*" >&2; }
err()  { printf "${RED}  ✖${RESET}  %s\n" "$*" >&2; exit 1; }
step() { printf "${BOLD}  →${RESET}  %s\n" "$*"; }
dim()  { printf "     ${DIM}%s${RESET}\n" "$*"; }

# ── Privilege helpers ─────────────────────────────────────────────
_do_install() {
    if [ -w "$(dirname "$2")" ]; then install "$@"; else sudo install "$@"; fi
}
_do_mkdir() {
    if mkdir -p "$1" 2>/dev/null; then :; else sudo mkdir -p "$1"; fi
}
_do_gzip() {
    if [ -w "$1" ]; then gzip -f "$1"; else sudo gzip -f "$1"; fi
}
_do_rm() {
    if [ -w "$1" ]; then rm -f "$1"; else sudo rm -f "$1"; fi
}

# ── Detect current shell ──────────────────────────────────────────
# We check $SHELL, not $0, because this script runs as bash regardless.
CURRENT_SHELL="$(basename "${SHELL:-bash}")"

# ── Detect pipe mode vs local mode ───────────────────────────────
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] \
   && [ "${BASH_SOURCE[0]}" != "bash" ] \
   && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/passx" ]; then
    MODE="local"
    dim "Mode: local  ($SCRIPT_DIR)"
else
    MODE="remote"
    command -v curl >/dev/null 2>&1 \
        || err "curl is required for remote install.  Install curl and try again."
    dim "Mode: remote  (github.com/${REPO})"
fi

# ── Uninstall ─────────────────────────────────────────────────────
uninstall() {
    printf "\n${BOLD}Uninstalling passx${RESET}\n\n"
    local removed=0
    for f in \
        "$BINDIR/passx"             \
        "$BINDIR/passx-menu"        \
        "$MANDIR/passx.1"           \
        "$MANDIR/passx.1.gz"        \
        "$BASH_COMP_DIR/passx"      \
        "$ZSH_COMP_DIR/_passx"      \
        "$FISH_COMP_DIR/passx.fish" \
        "$DOC_DIR/README.md"
    do
        if [ -f "$f" ]; then
            _do_rm "$f"; ok "Removed: $f"; removed=$((removed+1))
        fi
    done
    [ $removed -eq 0 ] \
        && info "Nothing found — already clean" \
        || ok "passx uninstalled"
    printf "\n  ${YELLOW}Your password store (~/.password-store) is untouched.${RESET}\n\n"
    exit 0
}
[ "${1:-}" = "--uninstall" ] && uninstall

# ── Banner ────────────────────────────────────────────────────────
printf "\n"
printf "  ${BOLD}${CYAN}passx v%s${RESET}  installer\n" "$VERSION"
printf "  Shell:         ${BOLD}%s${RESET}\n" "$CURRENT_SHELL"
printf "  Installing to: ${BOLD}%s${RESET}\n\n" "$PREFIX"

# ── Package manager detection ─────────────────────────────────────
detect_pm() {
    command -v pacman  >/dev/null 2>&1 && { echo pacman; return; }
    command -v apt-get >/dev/null 2>&1 && { echo apt;    return; }
    command -v dnf     >/dev/null 2>&1 && { echo dnf;    return; }
    command -v zypper  >/dev/null 2>&1 && { echo zypper; return; }
    command -v brew    >/dev/null 2>&1 && { echo brew;   return; }
    echo unknown
}
PM="$(detect_pm)"

# ── Ensure pass is installed ──────────────────────────────────────
if ! command -v pass >/dev/null 2>&1; then
    warn "'pass' is not installed — it is required"
    printf "  Install it now? [Y/n] "
    read -r yn </dev/tty 2>/dev/null || yn="y"
    if [ "${yn,,}" != "n" ]; then
        case "$PM" in
            pacman) sudo pacman -S --noconfirm pass ;;
            apt)    sudo apt-get install -y pass ;;
            dnf)    sudo dnf install -y pass ;;
            zypper) sudo zypper install -y pass ;;
            brew)   brew install pass ;;
            *)
                printf "\n  Install pass manually: https://www.passwordstore.org\n\n"
                exit 1 ;;
        esac
    else
        printf "\n  Install pass first: https://www.passwordstore.org\n\n"
        exit 1
    fi
fi

# ── Scratch directory ─────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/completions"

# ── Fetch helper ─────────────────────────────────────────────────
_fetch() {
    local src="$1" dst="$2"
    if [ "$MODE" = "local" ]; then
        [ -f "$SCRIPT_DIR/$src" ] || { warn "Not found: $SCRIPT_DIR/$src"; return 1; }
        cp "$SCRIPT_DIR/$src" "$dst"
    else
        curl -fsSL --retry 3 --retry-delay 2 "${BASE_URL}/${src}" -o "$dst" \
            || { warn "Download failed: $src"; return 1; }
    fi
}

# ── Download all files ────────────────────────────────────────────
step "Fetching files..."
_fetch "passx"                      "$TMP_DIR/passx"
_fetch "passx-menu"                 "$TMP_DIR/passx-menu"
_fetch "passx.1"                    "$TMP_DIR/passx.1"
_fetch "README.md"                  "$TMP_DIR/README.md"
_fetch "completions/passx.bash"     "$TMP_DIR/completions/passx.bash"
_fetch "completions/_passx"         "$TMP_DIR/completions/_passx"
_fetch "completions/passx.fish"     "$TMP_DIR/completions/passx.fish"

grep -q "PASSX_VERSION" "$TMP_DIR/passx" \
    || err "Downloaded file looks corrupt. Check your connection and try again."

# ── Install binaries ──────────────────────────────────────────────
step "Installing binaries..."
_do_mkdir "$BINDIR"
_do_install -Dm755 "$TMP_DIR/passx"       "$BINDIR/passx"
ok "passx      → $BINDIR/passx"
_do_install -Dm755 "$TMP_DIR/passx-menu"  "$BINDIR/passx-menu"
ok "passx-menu → $BINDIR/passx-menu"

# ── Man page ──────────────────────────────────────────────────────
if [ -f "$TMP_DIR/passx.1" ]; then
    step "Installing man page..."
    _do_mkdir "$MANDIR"
    _do_install -Dm644 "$TMP_DIR/passx.1" "$MANDIR/passx.1"
    if command -v gzip >/dev/null 2>&1; then
        _do_gzip "$MANDIR/passx.1"
        ok "man page  → $MANDIR/passx.1.gz"
    else
        ok "man page  → $MANDIR/passx.1"
    fi
fi

# ── Shell completions ─────────────────────────────────────────────
step "Installing completions..."

# bash
if [ -f "$TMP_DIR/completions/passx.bash" ]; then
    _do_mkdir "$BASH_COMP_DIR"
    _do_install -Dm644 "$TMP_DIR/completions/passx.bash" "$BASH_COMP_DIR/passx"
    ok "bash → $BASH_COMP_DIR/passx"
fi

# zsh — system dir + optional user-local fpath
if [ -f "$TMP_DIR/completions/_passx" ]; then
    _do_mkdir "$ZSH_COMP_DIR"
    _do_install -Dm644 "$TMP_DIR/completions/_passx" "$ZSH_COMP_DIR/_passx"
    ok "zsh  → $ZSH_COMP_DIR/_passx"
    if [[ "$PREFIX" == "$HOME"* ]]; then
        local_zsh="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
        mkdir -p "$local_zsh"
        install -Dm644 "$TMP_DIR/completions/_passx" "$local_zsh/_passx"
        ok "zsh  → $local_zsh/_passx  (user fpath)"
    fi
fi

# fish
if [ -f "$TMP_DIR/completions/passx.fish" ]; then
    _do_mkdir "$FISH_COMP_DIR"
    _do_install -Dm644 "$TMP_DIR/completions/passx.fish" "$FISH_COMP_DIR/passx.fish"
    ok "fish → $FISH_COMP_DIR/passx.fish"
fi

# ── README ────────────────────────────────────────────────────────
if [ -f "$TMP_DIR/README.md" ]; then
    _do_mkdir "$DOC_DIR"
    _do_install -Dm644 "$TMP_DIR/README.md" "$DOC_DIR/README.md"
fi

# ── PATH: add to shell rc if missing ─────────────────────────────
_add_to_rc() {
    local rcfile="$1" line="$2"
    # Don't add if already present (check for the export line)
    grep -qF "$BINDIR" "$rcfile" 2>/dev/null && return 0
    printf "\n# passx — added by installer\nexport PATH=\"%s:\$PATH\"\n" "$BINDIR" >> "$rcfile"
    ok "PATH updated in $rcfile"
}

if ! command -v passx >/dev/null 2>&1 \
   && [[ ":${PATH}:" != *":${BINDIR}:"* ]]; then
    warn "passx is not in your PATH"
    printf "  Add %s to PATH automatically? [Y/n] " "$BINDIR" >&2
    read -r yn </dev/tty 2>/dev/null || yn="y"
    if [ "${yn,,}" != "n" ]; then
        case "$CURRENT_SHELL" in
            zsh)  _add_to_rc "${ZDOTDIR:-$HOME}/.zshrc"   "export PATH=\"$BINDIR:\$PATH\"" ;;
            bash) _add_to_rc "$HOME/.bashrc"               "export PATH=\"$BINDIR:\$PATH\"" ;;
            fish) # fish uses a different syntax
                command -v fish >/dev/null 2>&1 \
                    && fish -c "fish_add_path $BINDIR" 2>/dev/null \
                    && ok "PATH updated (fish)" \
                    || warn "Run in fish:  fish_add_path $BINDIR" ;;
            *)    info "Add to your profile:  export PATH=\"$BINDIR:\$PATH\"" ;;
        esac
    fi
fi

# ── Completions: wire into rc file if needed ─────────────────────
# For zsh, we also add a compinit loader if not already present.
# For bash, the system loader picks up $BASH_COMP_DIR automatically.
# For zsh with a user-local PREFIX, we may need to add the fpath entry.
_wire_zsh_completions() {
    local rcfile="${ZDOTDIR:-$HOME}/.zshrc"

    # Check if compinit is already called somewhere
    local has_compinit=false
    grep -q "compinit" "$rcfile" 2>/dev/null && has_compinit=true

    # Check if our fpath dir is already in fpath
    local needs_fpath=false
    local comp_src="$ZSH_COMP_DIR"
    [[ "$PREFIX" == "$HOME"* ]] && \
        comp_src="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"

    grep -qF "$comp_src" "$rcfile" 2>/dev/null || needs_fpath=true

    if $needs_fpath || ! $has_compinit; then
        printf "  Wire zsh completions into %s? [Y/n] " "$rcfile" >&2
        read -r yn </dev/tty 2>/dev/null || yn="y"
        if [ "${yn,,}" != "n" ]; then
            {
                printf "\n# passx completions — added by installer\n"
                $needs_fpath && \
                    printf "fpath=('%s' \$fpath)\n" "$comp_src"
                ! $has_compinit && \
                    printf "autoload -Uz compinit && compinit\n"
            } >> "$rcfile"
            ok "Wired zsh completions into $rcfile"
        fi
    else
        dim "zsh completions already configured in $rcfile"
    fi
}

case "$CURRENT_SHELL" in
    zsh) _wire_zsh_completions ;;
    fish) dim "fish completions load automatically from vendor_completions.d" ;;
    bash) dim "bash completions load automatically from $BASH_COMP_DIR" ;;
esac

# ── Done ─────────────────────────────────────────────────────────
printf "\n"
ok "passx v${VERSION} installed!"
printf "\n  ${BOLD}Activate now (without restarting shell):${RESET}\n\n"

case "$CURRENT_SHELL" in
    zsh)
        printf "    ${CYAN}source ~/.zshrc${RESET}\n\n"
        ;;
    bash)
        printf "    ${CYAN}source ~/.bashrc${RESET}\n\n"
        printf "    ${DIM}# or for completions only:${RESET}\n"
        printf "    ${CYAN}source %s/passx${RESET}\n\n" "$BASH_COMP_DIR"
        ;;
    fish)
        printf "    ${CYAN}# Already active — open a new tab or run:${RESET}\n"
        printf "    ${CYAN}exec fish${RESET}\n\n"
        ;;
    *)
        printf "    Restart your shell\n\n"
        ;;
esac

printf "  ${BOLD}Then:${RESET}\n\n"
printf "    ${CYAN}passx setup${RESET}     # first-time wizard\n"
printf "    ${CYAN}passx doctor${RESET}    # verify everything\n"
printf "    ${CYAN}passx show${RESET}      # open the picker\n\n"

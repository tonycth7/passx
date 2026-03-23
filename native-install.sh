#!/usr/bin/env bash
# passx install.sh — standalone bootstrap installer
# Works on Arch, Debian/Ubuntu, Fedora, macOS (Homebrew)
# Usage:
#   ./install.sh              # install to /usr/local/bin (needs sudo)
#   PREFIX=$HOME/.local ./install.sh   # install to ~/.local/bin (no sudo)
#   ./install.sh --uninstall  # remove installed files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.7.0"
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${PREFIX}/bin"
MANDIR="${PREFIX}/share/man/man1"
BASH_COMP_DIR="${PREFIX}/share/bash-completion/completions"
ZSH_COMP_DIR="${PREFIX}/share/zsh/site-functions"
FISH_COMP_DIR="${PREFIX}/share/fish/vendor_completions.d"
DOC_DIR="${PREFIX}/share/doc/passx"

# ── Colour output ─────────────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    CYAN='\033[0;36m' BOLD='\033[1m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi
ok()   { printf "${GREEN}  ✔${RESET}  %s\n" "$*"; }
info() { printf "${CYAN}  ℹ${RESET}  %s\n" "$*"; }
warn() { printf "${YELLOW}  ⚠${RESET}  %s\n" "$*" >&2; }
err()  { printf "${RED}  ✖${RESET}  %s\n" "$*" >&2; exit 1; }
step() { printf "${BOLD}  →${RESET}  %s\n" "$*"; }

# ── Privilege helper ──────────────────────────────────────────────
_install() {
    if [ -w "$(dirname "$2")" ]; then
        install "$@"
    else
        sudo install "$@"
    fi
}
_mkdir() {
    if [ -w "$(dirname "$1")" ]; then
        mkdir -p "$1"
    else
        sudo mkdir -p "$1"
    fi
}

# ── Uninstall ─────────────────────────────────────────────────────
uninstall() {
    printf "\n${BOLD}Uninstalling passx v${VERSION}${RESET}\n\n"
    local removed=0
    for f in \
        "$BINDIR/passx"          \
        "$BINDIR/passx-menu"     \
        "$MANDIR/passx.1"        \
        "$BASH_COMP_DIR/passx"   \
        "$ZSH_COMP_DIR/_passx"   \
        "$FISH_COMP_DIR/passx.fish" \
        "$DOC_DIR/README.md"
    do
        if [ -f "$f" ]; then
            if [ -w "$f" ]; then rm -f "$f"; else sudo rm -f "$f"; fi
            ok "Removed: $f"
            removed=$((removed+1))
        fi
    done
    [ $removed -eq 0 ] && info "Nothing to remove" || ok "passx removed"
    printf "\n  ${YELLOW}Your password store (~/.password-store) is untouched.${RESET}\n\n"
    exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# ── Banner ────────────────────────────────────────────────────────
printf "\n"
printf "  ${BOLD}${CYAN}passx v${VERSION}${RESET} — installer\n"
printf "  Installing to: ${BOLD}${PREFIX}${RESET}\n\n"

# ── Detect distro / package manager ──────────────────────────────
detect_pm() {
    command -v pacman  >/dev/null 2>&1 && echo pacman  && return
    command -v apt-get >/dev/null 2>&1 && echo apt     && return
    command -v dnf     >/dev/null 2>&1 && echo dnf     && return
    command -v zypper  >/dev/null 2>&1 && echo zypper  && return
    command -v brew    >/dev/null 2>&1 && echo brew    && return
    echo unknown
}
PM="$(detect_pm)"

# ── Check & optionally install pass ──────────────────────────────
if ! command -v pass >/dev/null 2>&1; then
    warn "'pass' is not installed (required)"
    printf "  Install it now? [Y/n] "
    read -r yn || yn=y
    if [ "${yn,,}" != "n" ]; then
        case "$PM" in
            pacman) sudo pacman -S --noconfirm pass ;;
            apt)    sudo apt-get install -y pass ;;
            dnf)    sudo dnf install -y pass ;;
            zypper) sudo zypper install -y pass ;;
            brew)   brew install pass ;;
            *)      err "Cannot auto-install pass. Install it manually: https://www.passwordstore.org" ;;
        esac
    else
        err "pass is required. Install it first: https://www.passwordstore.org"
    fi
fi

# ── Install main scripts ──────────────────────────────────────────
step "Installing binaries..."
_mkdir "$BINDIR"
_install -Dm755 "$SCRIPT_DIR/passx"      "$BINDIR/passx"
ok "passx → $BINDIR/passx"
_install -Dm755 "$SCRIPT_DIR/passx-menu" "$BINDIR/passx-menu"
ok "passx-menu → $BINDIR/passx-menu"

# ── Man page ──────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/passx.1" ]; then
    step "Installing man page..."
    _mkdir "$MANDIR"
    _install -Dm644 "$SCRIPT_DIR/passx.1" "$MANDIR/passx.1"
    # Compress if gzip available and not already compressed
    if command -v gzip >/dev/null 2>&1 && [ ! -f "$MANDIR/passx.1.gz" ]; then
        if [ -w "$MANDIR/passx.1" ]; then gzip -f "$MANDIR/passx.1"
        else sudo gzip -f "$MANDIR/passx.1"; fi
    fi
    ok "man page → $MANDIR/passx.1.gz"
fi

# ── Shell completions ─────────────────────────────────────────────
step "Installing completions..."

# bash
if [ -f "$SCRIPT_DIR/completions/passx.bash" ]; then
    _mkdir "$BASH_COMP_DIR"
    _install -Dm644 "$SCRIPT_DIR/completions/passx.bash" "$BASH_COMP_DIR/passx"
    ok "bash → $BASH_COMP_DIR/passx"
fi

# zsh
if [ -f "$SCRIPT_DIR/completions/_passx" ]; then
    _mkdir "$ZSH_COMP_DIR"
    _install -Dm644 "$SCRIPT_DIR/completions/_passx" "$ZSH_COMP_DIR/_passx"
    ok "zsh  → $ZSH_COMP_DIR/_passx"
fi

# fish
if [ -f "$SCRIPT_DIR/completions/passx.fish" ]; then
    _mkdir "$FISH_COMP_DIR"
    _install -Dm644 "$SCRIPT_DIR/completions/passx.fish" "$FISH_COMP_DIR/passx.fish"
    ok "fish → $FISH_COMP_DIR/passx.fish"
fi

# ── User-local zsh fpath (if installing to ~/.local) ──────────────
if [[ "$PREFIX" == "$HOME"* ]]; then
    local_zsh_func="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
    if [ -f "$SCRIPT_DIR/completions/_passx" ]; then
        mkdir -p "$local_zsh_func"
        install -Dm644 "$SCRIPT_DIR/completions/_passx" "$local_zsh_func/_passx"
        ok "zsh (user) → $local_zsh_func/_passx"
    fi
fi

# ── README ────────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/README.md" ]; then
    _mkdir "$DOC_DIR"
    _install -Dm644 "$SCRIPT_DIR/README.md" "$DOC_DIR/README.md"
fi

# ── PATH warning ──────────────────────────────────────────────────
if ! command -v passx >/dev/null 2>&1; then
    warn "passx is not in your PATH"
    info "Add to your shell profile:   export PATH=\"$BINDIR:\$PATH\""
fi

# ── Done ──────────────────────────────────────────────────────────
printf "\n"
ok "passx v${VERSION} installed!"
printf "\n  ${BOLD}Next steps:${RESET}\n\n"
printf "  1.  Restart your shell (for completions)\n"
printf "  2.  Run the setup wizard:\n\n"
printf "        ${CYAN}passx setup${RESET}\n\n"
printf "  Or if you already use pass:\n\n"
printf "        ${CYAN}passx doctor${RESET}   # verify everything works\n"
printf "        ${CYAN}passx show${RESET}     # open the interactive picker\n"
printf "        ${CYAN}passx --help${RESET}   # full command reference\n\n"

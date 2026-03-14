#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  passx installer  —  setup passx + pass + GPG                 ║
# ╚════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────
C_RED=$'\033[38;5;203m';    C_GREEN=$'\033[38;5;151m'
C_YELLOW=$'\033[38;5;222m'; C_BLUE=$'\033[38;5;110m'
C_CYAN=$'\033[38;5;117m';   C_MAGENTA=$'\033[38;5;183m'
C_BOLD=$'\033[1m';          C_DIM=$'\033[2m'
C_ITALIC=$'\033[3m';        C_RESET=$'\033[0m'

ok()    { printf "\n${C_GREEN}${C_BOLD}  ✔  %s${C_RESET}\n" "$*"; }
err()   { printf "\n${C_RED}${C_BOLD}  ✖  %s${C_RESET}\n" "$*" >&2; exit 1; }
warn()  { printf "\n${C_YELLOW}  ⚠  %s${C_RESET}\n" "$*"; }
info()  { printf "  ${C_CYAN}ℹ  %s${C_RESET}\n" "$*"; }
step()  { printf "\n${C_BLUE}  →  %s${C_RESET}\n" "$*"; }
dim()   { printf "  ${C_DIM}%s${C_RESET}\n" "$*"; }
ask()   { printf "\n${C_MAGENTA}${C_BOLD}  ❯  %s${C_RESET} " "$*"; }
label() {
  printf "\n  ${C_BOLD}${C_CYAN}%s${C_RESET}\n  ${C_DIM}"
  printf '─%.0s' $(seq 1 $(( ${#1} + 2 )))
  printf "${C_RESET}\n"
}

banner() {
  local t="$1" w=58 p
  p=$(( (w - ${#t}) / 2 ))
  printf "\n${C_BOLD}${C_CYAN}"
  printf "  ╔"; printf '═%.0s' $(seq 1 $w); printf "╗\n"
  printf "  ║%*s%s%*s║\n" $p "" "$t" $((w - p - ${#t})) ""
  printf "  ╚"; printf '═%.0s' $(seq 1 $w); printf "╝${C_RESET}\n\n"
}

confirm() {
  ask "${1} [y/N]"
  local r; read -r r </dev/tty 2>/dev/null || r="n"
  [[ "${r,,}" == "y" || "${r,,}" == "yes" ]]
}

PICKED=""   # global — set by pick_one(), read by caller

pick_one() {
  local q="$1"; shift
  local opts=("$@")
  printf "\n  ${C_BOLD}${C_MAGENTA}❯  %s${C_RESET}\n\n" "$q"
  local i=1
  for o in "${opts[@]}"; do
    printf "    ${C_CYAN}[%d]${C_RESET}  %s\n" "$i" "$o"
    (( i++ ))
  done
  printf "\n"
  PICKED=""
  while true; do
    ask "Choice (1-${#opts[@]})"
    local r; read -r r </dev/tty 2>/dev/null || r=""
    if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= ${#opts[@]} )); then
      PICKED="${opts[$((r-1))]}"; return 0
    fi
    warn "Enter a number between 1 and ${#opts[@]}"
  done
}

has() { command -v "$1" >/dev/null 2>&1; }

# ── Package manager detection ─────────────────────────────────────
_detect_pm() {
  has apt-get && { PM="apt"; return; }
  has pacman  && { PM="pacman"; return; }
  has dnf     && { PM="dnf"; return; }
  has zypper  && { PM="zypper"; return; }
  has brew    && { PM="brew"; return; }
  PM="unknown"
}
_detect_pm

_pm_install() {
  case "$PM" in
    apt)    sudo apt-get install -y "$1" >/dev/null 2>&1 ;;
    pacman) sudo pacman -S --noconfirm "$1" >/dev/null 2>&1 ;;
    dnf)    sudo dnf install -y "$1" >/dev/null 2>&1 ;;
    zypper) sudo zypper install -y "$1" >/dev/null 2>&1 ;;
    brew)   brew install "$1" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

_pkg() {
  local t="$1"
  case "$PM" in
    apt)
      case "$t" in
        oathtool)    echo "oathtool" ;;
        zbarimg)     echo "zbar-tools" ;;
        notify-send) echo "libnotify-bin" ;;
        wl-clipboard)echo "wl-clipboard" ;;
        gpg)         echo "gnupg" ;;
        *)           echo "$t" ;;
      esac ;;
    pacman)
      case "$t" in
        oathtool)    echo "oath-toolkit" ;;
        zbarimg)     echo "zbar" ;;
        notify-send) echo "libnotify" ;;
        gpg)         echo "gnupg" ;;
        *)           echo "$t" ;;
      esac ;;
    brew)
      case "$t" in
        gpg)         echo "gnupg" ;;
        oathtool)    echo "oath-toolkit" ;;
        zbarimg)     echo "zbar" ;;
        wl-clipboard)echo "" ;;
        notify-send) echo "" ;;
        *)           echo "$t" ;;
      esac ;;
    *) echo "$t" ;;
  esac
}

_install_pkg() {
  local tool="$1" label="${2:-$1}"
  local pkg; pkg="$(_pkg "$tool")"
  [ -z "${pkg:-}" ] && { dim "skipping $label (not available on $PM)"; return 0; }
  step "Installing $label..."
  _pm_install "$pkg" && ok "$label installed" || warn "Failed to install $label"
}

# ════════════════════════════════════════════════════════════════
#   START
# ════════════════════════════════════════════════════════════════
clear
banner "passx installer  v1.0.0"
printf "  ${C_ITALIC}${C_DIM}power-user wrapper around pass${C_RESET}\n\n"

info "Detected package manager: ${C_BOLD}$PM${C_RESET}"
[ "$PM" = "unknown" ] && warn "Unknown package manager — may need to install deps manually"

# ════════════════════════════════════════════════════════════════
#   STEP 1 — REQUIRED DEPS  (auto-install, no prompting)
# ════════════════════════════════════════════════════════════════
label "Step 1 — Required dependencies"

MISSING=()
has gpg  || MISSING+=("gpg")
has pass || MISSING+=("pass")
has git  || MISSING+=("git")
has curl || MISSING+=("curl")

if [ ${#MISSING[@]} -eq 0 ]; then
  ok "All required tools present"
else
  warn "Missing: ${MISSING[*]}"
  if [ "$PM" = "unknown" ]; then
    err "Cannot auto-install on unknown package manager. Install manually: ${MISSING[*]}"
  fi
  step "Installing missing required tools..."
  for t in "${MISSING[@]}"; do
    _install_pkg "$t"
  done
  # re-check
  for t in gpg pass git; do
    has "$t" || err "$t still missing after install — fix manually and re-run"
  done
fi

# ════════════════════════════════════════════════════════════════
#   STEP 2 — OPTIONAL DEPS  (one confirm, then batch)
# ════════════════════════════════════════════════════════════════
label "Step 2 — Optional dependencies"

declare -A OPT=(
  [fzf]="fuzzy picker and search"
  [xdotool]="autofill + login automation"
  [oathtool]="TOTP / OTP codes"
  [qrencode]="QR code generation"
  [zbarimg]="QR code scanning"
  [wl-clipboard]="Wayland clipboard"
  [xclip]="X11 clipboard"
  [notify-send]="desktop notifications"
  [sshpass]="SSH credential injection"
  [jq]="JSON export"
  [bat]="syntax-highlighted previews"
)

MISSING_OPT=()
for t in "${!OPT[@]}"; do has "$t" || MISSING_OPT+=("$t"); done

if [ ${#MISSING_OPT[@]} -eq 0 ]; then
  ok "All optional tools present"
else
  printf "  ${C_YELLOW}Not installed:${C_RESET}\n\n"
  for t in "${MISSING_OPT[@]}"; do
    printf "    ${C_DIM}%-18s${C_RESET}  %s\n" "$t" "${OPT[$t]}"
  done
  printf "\n"
  if confirm "Install optional tools? (recommended)"; then
    for t in "${MISSING_OPT[@]}"; do _install_pkg "$t"; done
  else
    info "Skipped — install any time later"
  fi
fi

# ════════════════════════════════════════════════════════════════
#   STEP 3 — INSTALL PASSX  (just do it)
# ════════════════════════════════════════════════════════════════
label "Step 3 — Install passx"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSX_BIN=""
for c in "$SCRIPT_DIR/passx" "$SCRIPT_DIR/passx.sh" \
          "$SCRIPT_DIR/passx-1_0.sh" "$SCRIPT_DIR/passx-1.0.sh"; do
  [ -f "$c" ] && { PASSX_BIN="$c"; break; }
done
[ -n "$PASSX_BIN" ] || err "Cannot find passx script in $SCRIPT_DIR"

INSTALL_DIR="/usr/local/bin"
if sudo install -m 755 "$PASSX_BIN" "$INSTALL_DIR/passx" 2>/dev/null; then
  ok "passx  →  $INSTALL_DIR/passx"
else
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$PASSX_BIN" "$HOME/.local/bin/passx"
  INSTALL_DIR="$HOME/.local/bin"
  ok "passx  →  $INSTALL_DIR/passx"
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] \
    && warn "~/.local/bin is not in PATH — add: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# passx-menu
for c in "$SCRIPT_DIR/passx-menu" "$SCRIPT_DIR/passx-menu.sh"; do
  if [ -f "$c" ]; then
    sudo install -m 755 "$c" "$INSTALL_DIR/passx-menu" 2>/dev/null \
      || install -m 755 "$c" "$HOME/.local/bin/passx-menu" 2>/dev/null || true
    ok "passx-menu  →  $INSTALL_DIR/passx-menu"
    break
  fi
done

# ════════════════════════════════════════════════════════════════
#   STEP 4 — GPG KEY
# ════════════════════════════════════════════════════════════════
label "Step 4 — GPG key"

printf "  ${C_DIM}pass encrypts every entry with your GPG key.${C_RESET}\n\n"

# Parse existing secret keys into arrays
declare -a KEY_FPRS=()
declare -a KEY_UIDS=()

while IFS= read -r line; do
  [ -z "$line" ] && continue
  KEY_FPRS+=("$(printf "%s" "$line" | cut -d: -f1)")
  KEY_UIDS+=("$(printf "%s" "$line" | cut -d: -f2-)")
done < <(
  gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '
    /^sec/ { fpr=""; uid="" }
    /^fpr/ { if (!fpr) fpr=$10 }
    /^uid/ { if (!uid) uid=$10 }
    /^ssb/ { if (fpr && uid) { print fpr ":" uid; fpr=""; uid="" } }
  ' 2>/dev/null || true
)

GPG_KEY_ID=""

if [ ${#KEY_FPRS[@]} -gt 0 ]; then
  printf "  ${C_GREEN}${C_BOLD}Existing GPG keys:${C_RESET}\n\n"
  for i in "${!KEY_FPRS[@]}"; do
    printf "    ${C_CYAN}[%d]${C_RESET}  %s\n        ${C_DIM}%s${C_RESET}\n" \
      $((i+1)) "${KEY_UIDS[$i]}" "${KEY_FPRS[$i]:(-16)}"
  done
  printf "\n"

  pick_one "What to do?" \
    "Use an existing key" \
    "Create a new GPG key" \
    "Skip (I'll run pass init manually)"

  case "$PICKED" in
    "Use an existing key")
      if [ ${#KEY_FPRS[@]} -eq 1 ]; then
        GPG_KEY_ID="${KEY_FPRS[0]}"
        info "Using: ${KEY_UIDS[0]}"
      else
        printf "\n  ${C_BOLD}${C_MAGENTA}❯  Pick a key:${C_RESET}\n\n"
        for i in "${!KEY_FPRS[@]}"; do
          printf "    ${C_CYAN}[%d]${C_RESET}  %s  ${C_DIM}(%s)${C_RESET}\n" \
            $((i+1)) "${KEY_UIDS[$i]}" "${KEY_FPRS[$i]:(-16)}"
        done
        printf "\n"
        while true; do
          ask "Number (1-${#KEY_FPRS[@]})"
          local r; read -r r </dev/tty 2>/dev/null || r=""
          if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= ${#KEY_FPRS[@]} )); then
            GPG_KEY_ID="${KEY_FPRS[$((r-1))]}"
            info "Using: ${KEY_UIDS[$((r-1))]}"
            break
          fi
          warn "Enter 1-${#KEY_FPRS[@]}"
        done
      fi ;;
    "Create a new GPG key") GPG_KEY_ID="__CREATE__" ;;
    *)                       GPG_KEY_ID="__SKIP__" ;;
  esac
else
  printf "  ${C_YELLOW}No GPG secret keys found.${C_RESET}\n\n"
  pick_one "What to do?" \
    "Create a new GPG key" \
    "I'll import one and re-run" \
    "Skip"

  case "$PICKED" in
    "Create a new GPG key") GPG_KEY_ID="__CREATE__" ;;
    "I'll import one and re-run")
      info "Import a key then re-run:"
      dim "  gpg --import key.asc"
      dim "  gpg --recv-keys <KEYID>"
      exit 0 ;;
    *) GPG_KEY_ID="__SKIP__" ;;
  esac
fi

# ── Create new key  ────────────────────────────────────────────
if [ "$GPG_KEY_ID" = "__CREATE__" ]; then
  printf "\n  ${C_BOLD}New RSA 4096 key${C_RESET}\n\n"

  ask "Your name"
  read -r GPG_NAME </dev/tty 2>/dev/null || GPG_NAME=""
  [ -z "$GPG_NAME" ] && err "Name cannot be empty"

  ask "Your email"
  read -r GPG_EMAIL </dev/tty 2>/dev/null || GPG_EMAIL=""
  [[ "$GPG_EMAIL" == *@* ]] || err "Invalid email"

  printf "\n"
  info "GPG will now ask for a passphrase via your pinentry program."
  info "This passphrase protects every password in your store — make it strong."
  printf "\n"
  read -rp "  Press Enter when ready..." </dev/tty 2>/dev/null || true
  printf "\n"

  # Use --quick-gen-key: fully interactive passphrase via pinentry agent
  # Does NOT suppress the passphrase dialog like --batch %no-protection did
  step "Generating key... (passphrase dialog will appear)"
  if gpg --batch --gen-key 2>/dev/null <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GPG_NAME
Name-Email: $GPG_EMAIL
Expire-Date: 2y
%commit
EOF
  then
    : # batch succeeded (agent handled passphrase)
  else
    # Batch without passphrase protection failed or agent unavailable
    # Fall back to fully interactive full key generation
    warn "Batch mode failed — launching interactive key generator"
    printf "\n"
    info "Follow the prompts — choose RSA, 4096 bits, 2y expiry"
    printf "\n"
    gpg --full-gen-key </dev/tty || err "GPG key creation failed"
  fi

  GPG_KEY_ID=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
    | awk -F: '/^fpr/ {print $10; exit}')
  [ -n "${GPG_KEY_ID:-}" ] || err "Key created but fingerprint not found"

  ok "Key created: ${GPG_KEY_ID:(-16)}"
  gpg --fingerprint "$GPG_KEY_ID" 2>/dev/null | grep -A1 "pub" | sed 's/^/  /'

  printf "\n"
  info "Back up your key:"
  dim "  gpg --export-secret-keys --armor $GPG_KEY_ID > passx-backup.asc"
fi

# ════════════════════════════════════════════════════════════════
#   STEP 5 — PASS INIT  (auto if new store, ask if exists)
# ════════════════════════════════════════════════════════════════
if [ "${GPG_KEY_ID:-}" != "__SKIP__" ] && [ -n "${GPG_KEY_ID:-}" ]; then
  label "Step 5 — Password store"

  STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

  if [ -f "$STORE_DIR/.gpg-id" ]; then
    local_id="$(cat "$STORE_DIR/.gpg-id" 2>/dev/null | head -1)"
    info "Store already initialized (key: ${local_id:-unknown})"
    if [ "${local_id:-}" != "$GPG_KEY_ID" ]; then
      if confirm "Re-initialize with new key ${GPG_KEY_ID:(-16)}?"; then
        pass init "$GPG_KEY_ID" && ok "Store re-initialized" || warn "pass init failed"
      fi
    else
      dim "Same key — no change needed"
    fi
  else
    step "Initializing password store..."
    pass init "$GPG_KEY_ID" && ok "Store initialized at $STORE_DIR" || err "pass init failed"

    if ! [ -d "$STORE_DIR/.git" ]; then
      if confirm "Set up git tracking for your store?"; then
        pass git init && ok "git initialized"
        dim "Add a remote later: pass git remote add origin <url>"
      fi
    fi
  fi
else
  label "Step 5 — Skipped"
  dim "When ready: pass init <gpg-key-id>"
fi

# ════════════════════════════════════════════════════════════════
#   STEP 6 — CONFIG  (auto-generate if missing)
# ════════════════════════════════════════════════════════════════
label "Step 6 — Configuration"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx"
CONF_FILE="$CONF_DIR/passx.conf"

if [ -f "$CONF_FILE" ]; then
  dim "Config already exists at $CONF_FILE"
else
  step "Generating starter config..."
  if has passx; then
    passx gen-conf 2>/dev/null && ok "Config generated at $CONF_FILE"
  else
    mkdir -p "$CONF_DIR"
    cat > "$CONF_FILE" <<'CONF'
# passx configuration — edit to taste
PASSX_AUTOSYNC="false"
PASSX_CLIP_TIMEOUT="20"
PASSX_MAX_AGE="180"
PASSX_NOTIFY="true"
PASSX_THEME="catppuccin"
PASSX_GEN_LENGTH="32"
PASSX_GEN_CHARS="A-Za-z0-9@#%+=_"
PASSX_JSON="0"
PASSX_COLOR="auto"
PASSX_DEBUG="0"
CONF
    ok "Config written to $CONF_FILE"
  fi
fi

# ════════════════════════════════════════════════════════════════
#   STEP 7 — COMPLETIONS  (write to file, not source <())
# ════════════════════════════════════════════════════════════════
label "Step 7 — Shell completions"

CURRENT_SHELL="$(basename "${SHELL:-bash}")"
info "Shell: $CURRENT_SHELL"

_setup_completions() {
  local shell="$1"
  case "$shell" in

    zsh)
      # Write to a file in fpath — correct way for zsh
      local zfunc_dir="${HOME}/.local/share/zsh/site-functions"
      mkdir -p "$zfunc_dir"
      passx completions zsh > "$zfunc_dir/_passx" 2>/dev/null \
        || { warn "Could not write zsh completions"; return; }
      ok "zsh completion file: $zfunc_dir/_passx"

      # Add fpath entry to .zshrc if needed
      local rc="$HOME/.zshrc"
      if ! grep -q "passx.*site-functions" "$rc" 2>/dev/null; then
        cat >> "$rc" <<'ZRC'

# passx completions
fpath=($HOME/.local/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit
ZRC
        ok "fpath updated in $rc"
      else
        dim "fpath already set in $rc"
      fi

      # Remove any old broken source <() line
      if grep -q "source <(passx completions zsh)" "$rc" 2>/dev/null; then
        sed -i '/source <(passx completions zsh)/d' "$rc" 2>/dev/null \
          && dim "Removed old broken source <() line from $rc"
      fi ;;

    bash)
      # Write to bash-completion drop-in dir
      local bcomp_dir="${HOME}/.local/share/bash-completion/completions"
      mkdir -p "$bcomp_dir"
      passx completions bash > "$bcomp_dir/passx" 2>/dev/null \
        || { warn "Could not write bash completions"; return; }
      ok "bash completion file: $bcomp_dir/passx"

      # Ensure bash-completion loads it (most modern setups do automatically)
      local rc="$HOME/.bashrc"
      if ! grep -q "bash-completion" "$rc" 2>/dev/null; then
        cat >> "$rc" <<'BRC'

# load bash-completion drop-ins (includes passx)
[ -f /usr/share/bash-completion/bash_completion ] \
  && source /usr/share/bash-completion/bash_completion
BRC
        dim "bash-completion loader added to $rc"
      fi

      # Remove any old broken source <() line
      if grep -q "source <(passx completions bash)" "$rc" 2>/dev/null; then
        sed -i '/source <(passx completions bash)/d' "$rc" 2>/dev/null \
          && dim "Removed old broken source <() line from $rc"
      fi ;;

    fish)
      local fdir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
      mkdir -p "$fdir"
      passx completions fish > "$fdir/passx.fish" 2>/dev/null \
        && ok "fish completions: $fdir/passx.fish" \
        || warn "Could not write fish completions" ;;

    *)
      warn "Unknown shell '$shell' — set up completions manually:"
      dim "  zsh:  passx completions zsh > ~/.local/share/zsh/site-functions/_passx"
      dim "  bash: passx completions bash > ~/.local/share/bash-completion/completions/passx"
      dim "  fish: passx completions fish > ~/.config/fish/completions/passx.fish" ;;
  esac
}

if has passx; then
  _setup_completions "$CURRENT_SHELL"
else
  warn "passx not in PATH yet — skipping completions (re-run after sourcing your shell)"
fi

# ════════════════════════════════════════════════════════════════
#   DONE
# ════════════════════════════════════════════════════════════════
banner "passx is ready"

printf "  ${C_BOLD}Quick start:${C_RESET}\n\n"
printf "    ${C_CYAN}passx doctor${C_RESET}                      ${C_DIM}# check setup${C_RESET}\n"
printf "    ${C_CYAN}passx add github user@mail.com${C_RESET}    ${C_DIM}# first entry${C_RESET}\n"
printf "    ${C_CYAN}passx ui${C_RESET}                          ${C_DIM}# interactive picker${C_RESET}\n"
printf "    ${C_CYAN}passx --help${C_RESET}                      ${C_DIM}# all commands${C_RESET}\n"
printf "\n"
info "Restart your shell (or open a new tab) to activate completions."
printf "\n"

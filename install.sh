#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  passx installer  —  setup passx + pass + GPG                 ║
# ║                                                                ║
# ║  One-liner install:                                            ║
# ║  curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh | bash
# ╚════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Never let git fall back to password auth ──────────────────
export GIT_TERMINAL_PROMPT=0

# Globals set by _select_ssh_key() / _load_ssh_key()
SELECTED_SSH_KEY=""

# ── Repo — change these if you fork ──────────────────────────────
PASSX_REPO_BASE="https://raw.githubusercontent.com/tonycth7/passx/main"
PASSX_SCRIPT_URL="${PASSX_REPO_BASE}/passx-1.0.sh"
PASSX_MENU_URL="${PASSX_REPO_BASE}/passx-menu.sh"

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

# Robust TTY read — retries until non-empty (up to 5 times).
_read_tty() {
  local _var="$1" _prompt="$2" _val="" _try=0 _max=5
  while [ -z "$_val" ] && [ $_try -lt $_max ]; do
    ask "$_prompt"
    IFS= read -r _val </dev/tty 2>/dev/null || _val=""
    _val="${_val#"${_val%%[![:space:]]*}"}"
    _val="${_val%"${_val##*[![:space:]]}"}"
    [ -z "$_val" ] && (( _try++ )) && [ $_try -lt $_max ] && warn "Cannot be empty, please try again"
  done
  printf -v "$_var" '%s' "$_val"
}

# Scan ~/.ssh for all private keys (paired .pub or PRIVATE KEY header).
# Auto-creates .pub if missing. Sets SELECTED_SSH_KEY.
_select_ssh_key() {
  local -a found_keys=()
  local f
  for f in "$HOME/.ssh"/*; do
    [ -f "$f" ] || continue
    [[ "$f" == *.pub ]] && continue
    [[ "$f" == */known_hosts* || "$f" == */authorized_keys* || "$f" == */config ]] && continue
    if head -1 "$f" 2>/dev/null | grep -q "PRIVATE KEY"; then
      found_keys+=("$f")
    elif [ -f "${f}.pub" ]; then
      found_keys+=("$f")
    fi
  done

  if [ ${#found_keys[@]} -eq 0 ]; then
    SELECTED_SSH_KEY=""
    return 1
  fi

  if [ ${#found_keys[@]} -eq 1 ]; then
    SELECTED_SSH_KEY="${found_keys[0]}"
  else
    printf "\n  ${C_BOLD}${C_CYAN}Multiple SSH keys found:${C_RESET}\n\n"
    local i=1
    for f in "${found_keys[@]}"; do
      local comment=""
      [ -f "${f}.pub" ] && comment="  ${C_DIM}$(awk '{print $3}' "${f}.pub" 2>/dev/null)${C_RESET}"
      printf "    ${C_CYAN}[%d]${C_RESET}  %-30s%b\n" "$i" "$(basename "$f")" "$comment"
      (( i++ ))
    done
    printf "\n"
    local choice=""
    while true; do
      ask "Which key to use? (1-${#found_keys[@]})"
      read -r choice </dev/tty 2>/dev/null || choice=""
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#found_keys[@]} )); then
        SELECTED_SSH_KEY="${found_keys[$((choice-1))]}"
        break
      fi
      warn "Enter a number between 1 and ${#found_keys[@]}"
    done
  fi

  info "Using SSH key: ${C_BOLD}$(basename "$SELECTED_SSH_KEY")${C_RESET}  (${SELECTED_SSH_KEY})"

  # ── Auto-create .pub if missing ──────────────────────────────
  if [ ! -f "${SELECTED_SSH_KEY}.pub" ]; then
    step "No .pub file — extracting public key from $(basename "$SELECTED_SSH_KEY")..."
    printf "  ${C_DIM}(enter passphrase if the key is protected)${C_RESET}\n"
    if ssh-keygen -y -f "$SELECTED_SSH_KEY" > "${SELECTED_SSH_KEY}.pub" </dev/tty 2>/dev/null; then
      ok "Created ${SELECTED_SSH_KEY}.pub"
    else
      rm -f "${SELECTED_SSH_KEY}.pub"
      warn "Could not extract public key (wrong passphrase?)"
    fi
  fi

  return 0
}

# Load the selected key into ssh-agent (prompts passphrase once, cached after).
# Once loaded, plain `ssh` / `git` picks it up automatically — no wrapper needed.
_load_ssh_key() {
  [ -z "$SELECTED_SSH_KEY" ] && return 1

  # Start agent if not running
  if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l >/dev/null 2>&1; then
    step "Starting ssh-agent..."
    eval "$(ssh-agent -s 2>/dev/null)" >/dev/null
  fi

  # Already loaded?
  local key_fp
  key_fp="$(ssh-keygen -lf "$SELECTED_SSH_KEY" 2>/dev/null | awk '{print $2}')" || true
  if [ -n "$key_fp" ] && ssh-add -l 2>/dev/null | grep -qF "$key_fp"; then
    ok "Key already in agent — no passphrase needed"
    return 0
  fi

  step "Loading $(basename "$SELECTED_SSH_KEY") into ssh-agent..."
  printf "  ${C_DIM}Enter passphrase once — it will be cached for the rest of this install.${C_RESET}\n"
  printf "  ${C_DIM}Just press Enter if the key has no passphrase.${C_RESET}\n\n"

  local attempts=0
  while [ $attempts -lt 3 ]; do
    # ssh-add reads passphrase from the TTY directly
    if SSH_ASKPASS="" ssh-add "$SELECTED_SSH_KEY" </dev/tty 2>&1; then
      ok "Key loaded — git will now authenticate silently"
      # Point GIT_SSH_COMMAND at plain ssh using the agent — no -i, no IdentitiesOnly
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
      return 0
    fi
    (( attempts++ ))
    [ $attempts -lt 3 ] && warn "Wrong passphrase — try again (attempt $((attempts+1))/3)"
  done

  warn "Could not load key after 3 attempts — clone will likely fail"
  return 1
}
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
#   STEP 3 — DOWNLOAD + INSTALL PASSX
# ════════════════════════════════════════════════════════════════
label "Step 3 — Install passx"

# Determine install dir — try /usr/local/bin first, fall back silently
INSTALL_DIR="/usr/local/bin"
if ! sudo -n true 2>/dev/null && ! sudo true 2>/dev/null; then
  INSTALL_DIR="$HOME/.local/bin"
fi
mkdir -p "$HOME/.local/bin"  # always exists as fallback

_do_install() {
  # _do_install "src" "dest-name"  — tries system dir first, falls back to ~/.local/bin
  local src="$1" name="$2"
  if sudo install -m 755 "$src" "/usr/local/bin/$name" 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
    ok "$name  →  /usr/local/bin/$name"
  else
    install -m 755 "$src" "$HOME/.local/bin/$name"
    INSTALL_DIR="$HOME/.local/bin"
    ok "$name  →  $HOME/.local/bin/$name"
  fi
}

_fetch_install() {
  # _fetch_install "url" "dest-name"
  local url="$1" name="$2"
  local tmp; tmp="$(mktemp)"
  step "Downloading ${name}..."

  local got_file=false

  # Try download
  if curl -fsSL --retry 2 --retry-delay 1 "$url" -o "$tmp" 2>/dev/null \
      && head -1 "$tmp" | grep -q '^#!'; then
    got_file=true
  else
    rm -f "$tmp"; tmp="$(mktemp)"
    # Fallback: look for file next to the install script
    local sdir
    sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
    local c
    for c in "$sdir/${name}" "$sdir/${name}.sh" \
              "$sdir/passx-1.0.sh" "$sdir/passx-1_0.sh" \
              "$sdir/passx-menu.sh"; do
      if [ -f "$c" ] && { [ "$name" = "passx" ] || [[ "$c" == *menu* ]]; }; then
        cp "$c" "$tmp" && got_file=true && warn "Using local file: $c"
        break
      fi
    done
    # simpler fallback without the menu check
    if ! $got_file; then
      for c in "$sdir/${name}" "$sdir/${name}.sh" \
                "$sdir/passx-1.0.sh" "$sdir/passx-1_0.sh"; do
        [ -f "$c" ] && { cp "$c" "$tmp" && got_file=true && warn "Using local: $c"; break; }
      done
    fi
  fi

  if $got_file && [ -s "$tmp" ]; then
    _do_install "$tmp" "$name"
  else
    warn "Could not obtain $name — skipping"
  fi
  rm -f "$tmp"
}

_fetch_install "$PASSX_SCRIPT_URL" "passx"
_fetch_install "$PASSX_MENU_URL"   "passx-menu"

# PATH warning if landed in ~/.local/bin
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  warn "~/.local/bin is not in PATH — add to your shell rc:
    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Resolve actual installed paths — don't rely on INSTALL_DIR since each
# binary picks its own location independently
if   [ -x "/usr/local/bin/passx" ];  then PASSX_BIN="/usr/local/bin/passx"
elif [ -x "$HOME/.local/bin/passx" ]; then PASSX_BIN="$HOME/.local/bin/passx"
else PASSX_BIN=""; fi

if   [ -x "/usr/local/bin/passx-menu" ];  then PASSX_MENU_BIN="/usr/local/bin/passx-menu"
elif [ -x "$HOME/.local/bin/passx-menu" ]; then PASSX_MENU_BIN="$HOME/.local/bin/passx-menu"
else PASSX_MENU_BIN=""; fi

[ -n "$PASSX_BIN" ] && ok "passx found at $PASSX_BIN"   || warn "passx not found after install — something went wrong"

_passx() { "$PASSX_BIN" "$@"; }

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
  printf "\n  ${C_BOLD}New GPG key${C_RESET}\n\n"

  GPG_NAME="" GPG_EMAIL=""
  _read_tty GPG_NAME "Your name"
  [ -z "$GPG_NAME" ] && err "Name cannot be empty"

  _read_tty GPG_EMAIL "Your email"
  [[ "$GPG_EMAIL" == *@* ]] || err "Invalid email"

  # Read passphrase directly in the terminal with echo off
  GPG_PASS="" GPG_PASS2=""
  local_stty="$(stty -g </dev/tty 2>/dev/null || true)"
  printf "\n${C_MAGENTA}${C_BOLD}  ❯  Passphrase for your key  (leave blank for none)${C_RESET} "
  stty -echo </dev/tty 2>/dev/null || true
  read -r GPG_PASS </dev/tty 2>/dev/null || true
  [ -n "$local_stty" ] && stty "$local_stty" </dev/tty 2>/dev/null || true
  printf "\n"

  if [ -n "$GPG_PASS" ]; then
    printf "${C_MAGENTA}${C_BOLD}  ❯  Confirm passphrase${C_RESET} "
    stty -echo </dev/tty 2>/dev/null || true
    read -r GPG_PASS2 </dev/tty 2>/dev/null || true
    [ -n "$local_stty" ] && stty "$local_stty" </dev/tty 2>/dev/null || true
    printf "\n"
    [ "$GPG_PASS" = "$GPG_PASS2" ] || err "Passphrases do not match"
  else
    warn "No passphrase — key will be unprotected"
  fi
  unset GPG_PASS2

  # ── Configure gpg-agent for loopback BEFORE starting the agent ──
  # This is required in WSL / SSH / headless — any env without a
  # graphical pinentry. Must be done before gpg-agent starts.
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"

  # Write loopback setting
  touch "$HOME/.gnupg/gpg-agent.conf"
  if ! grep -q "allow-loopback-pinentry" "$HOME/.gnupg/gpg-agent.conf"; then
    printf "allow-loopback-pinentry\n" >> "$HOME/.gnupg/gpg-agent.conf"
  fi

  # Also write gpg.conf to always use loopback
  touch "$HOME/.gnupg/gpg.conf"
  if ! grep -q "pinentry-mode" "$HOME/.gnupg/gpg.conf"; then
    printf "pinentry-mode loopback\n" >> "$HOME/.gnupg/gpg.conf"
  fi

  # Kill any running agent so it restarts with new config
  gpgconf --kill gpg-agent 2>/dev/null || true
  sleep 0.5

  # Set GPG_TTY so curses-based pinentry works as a last resort
  export GPG_TTY
  GPG_TTY="$(tty 2>/dev/null)" || GPG_TTY=""

  # ── Build batch file in a temp file ─────────────────────────────
  _gpg_batch="$(mktemp)"
  chmod 600 "$_gpg_batch"

  if [ -n "$GPG_PASS" ]; then
    cat > "$_gpg_batch" <<BATCH
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: 2y
Passphrase: ${GPG_PASS}
%commit
BATCH
  else
    cat > "$_gpg_batch" <<BATCH
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: 2y
%no-protection
%commit
BATCH
  fi

  step "Generating Ed25519 key..."
  gpg --batch --pinentry-mode loopback --gen-key "$_gpg_batch" 2>&1 \
    | grep -v "^gpg: key\|^gpg: revocation\|^pub\|^uid" | sed 's/^/  /' || true
  _gpg_exit="${PIPESTATUS[0]}"

  rm -f "$_gpg_batch"
  unset GPG_PASS

  [ "$_gpg_exit" -eq 0 ] || err "GPG key generation failed (exit ${_gpg_exit})"

  GPG_KEY_ID="$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
    | awk -F: '/^fpr/ {print $10; exit}')"
  [ -n "${GPG_KEY_ID:-}" ] || err "Key created but fingerprint not found"

  ok "Key created: ${GPG_KEY_ID:(-16)}"
  gpg --fingerprint "$GPG_KEY_ID" 2>/dev/null | sed 's/^/  /'

  printf "\n"
  info "Back up your key:"
  dim "  gpg --export-secret-keys --armor $GPG_KEY_ID > passx-backup.asc"
  dim "  store that file somewhere safe and offline"
fi

# ════════════════════════════════════════════════════════════════
#   STEP 5 — PASSWORD STORE  (clone existing or init new)
# ════════════════════════════════════════════════════════════════
STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
STORE_CLONED=false

label "Step 5 — Password store"

# ── Helper: pick git SSH URL ──────────────────────────────────
_pick_ssh_url() {
  # Sets GIT_REMOTE_URL global
  GIT_REMOTE_URL=""

  pick_one "Git host"     "GitHub              git@github.com"     "GitLab              git@gitlab.com"     "Codeberg            git@codeberg.org"     "Gitea / Forgejo     git@your-server"     "Other self-hosted   (enter full SSH URL)"

  local host_label="$PICKED"
  local host_domain=""

  case "$host_label" in
    GitHub*)      host_domain="github.com" ;;
    GitLab*)      host_domain="gitlab.com" ;;
    Codeberg*)    host_domain="codeberg.org" ;;
    "Gitea"*|"Other"*)
      _read_tty host_domain "SSH hostname  (e.g. git.example.com)"
      [ -z "$host_domain" ] && { warn "No hostname given"; return 1; } ;;
  esac

  case "$host_label" in
    "Other self-hosted"*)
      _read_tty GIT_REMOTE_URL "Full SSH URL  (e.g. git@git.example.com:user/passwords.git)"
      [ -z "$GIT_REMOTE_URL" ] && { warn "No URL given"; return 1; }
      ;;
    *)
      local git_user="" git_repo=""
      _read_tty git_user "Username / org  (your GitHub/GitLab username)"
      [ -z "$git_user" ] && { warn "Username cannot be empty"; return 1; }

      _read_tty git_repo "Repository name  (e.g. passwords)"
      [ -z "$git_repo" ] && { warn "Repo name cannot be empty"; return 1; }

      # Strip .git suffix if provided, then re-add it cleanly
      git_repo="${git_repo%.git}"
      GIT_REMOTE_URL="git@${host_domain}:${git_user}/${git_repo}.git"
      ;;
  esac

  printf "
"
  info "SSH URL:  ${C_BOLD}$GIT_REMOTE_URL${C_RESET}"
  return 0
}

# ── Helper: test SSH connection ───────────────────────────────
_test_ssh() {
  local url="$1"
  local host
  if [[ "$url" == ssh://* ]]; then
    host="$(printf "%s" "$url" | sed 's|ssh://[^@]*@||; s|/.*||')"
  else
    host="$(printf "%s" "$url" | sed 's/.*@//; s/:.*//')"
  fi
  [ -z "$host" ] && return 0

  # Select key if not done yet
  if [ -z "$SELECTED_SSH_KEY" ]; then
    if ! _select_ssh_key; then
      printf "\n"
      warn "No SSH key found in ~/.ssh/"
      if confirm "Generate a new ed25519 SSH key now?"; then
        local _ssh_email=""
        _read_tty _ssh_email "Email for SSH key"
        ssh-keygen -t ed25519 -C "$_ssh_email" -f "$HOME/.ssh/id_ed25519" </dev/tty \
          && ok "SSH key created: ~/.ssh/id_ed25519" \
          && _select_ssh_key \
          || warn "ssh-keygen failed"
      fi
      [ -z "$SELECTED_SSH_KEY" ] && { confirm "Continue anyway (clone will fail)?" || return 1; return 0; }
    fi
  fi

  # Load into agent — passphrase entered once here, cached for all subsequent ops
  _load_ssh_key || {
    warn "Key not loaded into agent — clone may fail"
    confirm "Continue anyway?" || return 1
    return 0
  }

  step "Testing SSH connection to ${host}..."
  # Test using the agent — same way git clone will authenticate
  local ssh_out ssh_rc=0
  ssh_out="$(ssh -T \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    "git@${host}" 2>&1)" || ssh_rc=$?

  if printf "%s" "$ssh_out" | grep -qiE 'success|welcome|authenticated|hi '; then
    ok "SSH auth OK  (${host})"
    return 0
  elif printf "%s" "$ssh_out" | grep -qiE 'publickey|Permission denied'; then
    warn "SSH key not accepted by ${host}"
    printf "\n"
    info "Add this public key to ${host}:"
    [ -f "${SELECTED_SSH_KEY}.pub" ] && cat "${SELECTED_SSH_KEY}.pub" | sed 's/^/    /'
    printf "\n"
    case "$host" in
      *github*)   dim "  → https://github.com/settings/ssh/new" ;;
      *gitlab*)   dim "  → https://gitlab.com/-/profile/keys" ;;
      *codeberg*) dim "  → https://codeberg.org/user/settings/keys" ;;
      *)          dim "  → your git host SSH key settings page" ;;
    esac
    printf "\n"
    confirm "Continue anyway (clone will fail if key isn't added)?" || return 1
    return 0
  elif printf "%s" "$ssh_out" | grep -qiE 'refused|timeout|unreachable|no route|could not resolve'; then
    warn "Cannot reach ${host} — check your network"
    confirm "Continue anyway?" || return 1
    return 0
  else
    ok "SSH reachable (${host})"
    return 0
  fi
}

# ── Helper: add remote + first push ──────────────────────────
_setup_remote() {
  local store="$1" url="$2" label="${3:-origin}"

  # Add or update remote
  if git -C "$store" remote get-url "$label" >/dev/null 2>&1; then
    git -C "$store" remote set-url "$label" "$url" 2>/dev/null
    info "Updated remote '$label' → $url"
  else
    git -C "$store" remote add "$label" "$url" 2>/dev/null
    ok "Remote '$label' added → $url"
  fi

  # First push
  if confirm "Push store to remote now?"; then
    step "Pushing to $url ..."
    local branch
    branch="$(git -C "$store" rev-parse --abbrev-ref HEAD 2>/dev/null || printf "main")"
    git -C "$store" push -u "$label" "$branch" 2>&1       && ok "Pushed to ${label}/${branch}"       || warn "Push failed — you can push manually later: pass git push"
  else
    dim "Push later with: pass git push"
  fi
}

# ══════════════════════════════════════════════════════════════
# MAIN STORE SETUP FLOW
# ══════════════════════════════════════════════════════════════

if [ -f "$STORE_DIR/.gpg-id" ]; then
  # ── Store already exists locally ──────────────────────────
  local_id="$(cat "$STORE_DIR/.gpg-id" 2>/dev/null | head -1)"
  info "Store already exists at $STORE_DIR  (key: ${local_id:-unknown})"

  if [ -n "${GPG_KEY_ID:-}" ] && [ "${GPG_KEY_ID:-}" != "__SKIP__" ]       && [ "${local_id:-}" != "$GPG_KEY_ID" ]; then
    if confirm "Re-initialize with new GPG key ${GPG_KEY_ID:(-16)}?"; then
      pass init "$GPG_KEY_ID" && ok "Store re-initialized" || warn "pass init failed"
    fi
  fi

  # Check if git remote already configured
  if [ -d "$STORE_DIR/.git" ]; then
    EXISTING_REMOTE="$(git -C "$STORE_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -n "$EXISTING_REMOTE" ]; then
      info "Git remote already set: $EXISTING_REMOTE"
      if confirm "Pull latest from remote?"; then
        pass git pull 2>&1 && ok "Pulled" || warn "Pull failed"
      fi
    else
      printf "
"
      info "Store has git but no remote configured."
      if confirm "Add a remote git repo now?"; then
        GIT_REMOTE_URL=""
        _pick_ssh_url && _test_ssh "$GIT_REMOTE_URL"           && _setup_remote "$STORE_DIR" "$GIT_REMOTE_URL" || true
      else
        dim "Add later: pass git remote add origin <SSH-URL>"
        dim "           pass git push -u origin main"
      fi
    fi
  else
    printf "
"
    info "Store exists but has no git tracking."
    pick_one "Git setup"       "Init git + add remote repo  (recommended)"       "Init git locally only  (add remote later)"       "Skip git entirely"
    case "$PICKED" in
      "Init git + add remote"*)
        pass git init && ok "git initialized"
        GIT_REMOTE_URL=""
        _pick_ssh_url && _test_ssh "$GIT_REMOTE_URL"           && _setup_remote "$STORE_DIR" "$GIT_REMOTE_URL" || true ;;
      "Init git locally"*)
        pass git init && ok "git initialized"
        dim "Add remote later: pass git remote add origin <SSH-URL>" ;;
      *) dim "Skipping git" ;;
    esac
  fi

else
  # ── No store yet ──────────────────────────────────────────
  printf "
"
  pick_one "Do you have an existing password store in a git repo?"     "Yes — clone it via SSH  (restore from existing repo)"     "No  — start fresh  (new local store, optionally add remote)"     "Skip for now  (set everything up manually)"

  case "$PICKED" in

    "Yes"*)
      # ── Clone existing store ─────────────────────────────
      label "Cloning existing store"
      printf "  ${C_DIM}Your store will be cloned into: ${C_BOLD}$STORE_DIR${C_RESET}\n\n"

      while true; do
        GIT_REMOTE_URL=""
        if ! _pick_ssh_url; then
          warn "URL setup cancelled — skipping clone"
          break
        fi

        # Selects key + loads into agent (prompts passphrase once, cached after)
        _test_ssh "$GIT_REMOTE_URL" || break

        # Clear dir if needed
        if [ -d "$STORE_DIR" ] && [ -n "$(ls -A "$STORE_DIR" 2>/dev/null)" ]; then
          warn "$STORE_DIR already exists and is not empty"
          confirm "Remove it and clone fresh?" \
            && { rm -rf "$STORE_DIR"; step "Removed $STORE_DIR"; } \
            || { warn "Skipping clone — directory not empty"; break; }
        fi

        step "Cloning $GIT_REMOTE_URL ..."
        if git clone "$GIT_REMOTE_URL" "$STORE_DIR" 2>&1; then
          ok "Cloned to $STORE_DIR"
          STORE_CLONED=true

          if [ -f "$STORE_DIR/.gpg-id" ]; then
            local_id="$(cat "$STORE_DIR/.gpg-id" 2>/dev/null | head -1)"
            info "Store GPG ID: $local_id"
            if [ -n "${GPG_KEY_ID:-}" ] && [ "${GPG_KEY_ID:-}" != "__SKIP__" ] \
                && [ "$local_id" != "$GPG_KEY_ID" ]; then
              warn "Store was encrypted with a different key: $local_id"
              warn "Make sure you have that key imported, or entries won't decrypt"
            fi
          else
            warn "Cloned repo has no .gpg-id — may not be a valid pass store"
            dim "Run: pass init <your-gpg-key-id>  inside $STORE_DIR"
          fi
          break

        else
          printf "\n"
          warn "Clone failed"
          dim "  URL tried: $GIT_REMOTE_URL"
          dim "  Key tried: $(basename "$SELECTED_SSH_KEY")"
          printf "\n"
          pick_one "What to do?" \
            "Try a different SSH key" \
            "Change the repository URL" \
            "Give up — I'll clone manually"
          case "$PICKED" in
            "Try a different"*)
              SELECTED_SSH_KEY=""
              ;;
            "Give up"*)
              dim "Manual clone:"
              dim "  git clone $GIT_REMOTE_URL $STORE_DIR"
              break
              ;;
          esac
          # "Change URL" — loop continues, _pick_ssh_url runs again
        fi
      done ;;

    "No"*)
      # ── Fresh local store ────────────────────────────────
      if [ -n "${GPG_KEY_ID:-}" ] && [ "${GPG_KEY_ID:-}" != "__SKIP__" ]; then
        step "Initializing new password store..."
        pass init "$GPG_KEY_ID" && ok "Store initialized at $STORE_DIR"           || err "pass init failed — check your GPG key"
      else
        warn "No GPG key selected — skipping pass init"
        dim "Run later: pass init <your-gpg-key-id>"
      fi

      printf "
"
      pick_one "Git remote setup"         "Add a remote repo now  (recommended — backup + sync)"         "Skip — I'll add a remote later"

      case "$PICKED" in
        "Add a remote"*)
          pass git init 2>/dev/null && ok "git initialized" || true
          GIT_REMOTE_URL=""
          _pick_ssh_url && _test_ssh "$GIT_REMOTE_URL"             && _setup_remote "$STORE_DIR" "$GIT_REMOTE_URL" || true

          printf "
"
          info "Future sync:"
          dim "  pass git pull    →  pull from remote"
          dim "  pass git push    →  push to remote"
          dim "  passx sync       →  pull + push at once" ;;

        *)
          if ! [ -d "$STORE_DIR/.git" ]; then
            if confirm "At least init local git tracking?"; then
              pass git init && ok "git initialized locally"
            fi
          fi
          dim "Add remote later:"
          dim "  pass git remote add origin git@github.com:you/passwords.git"
          dim "  pass git push -u origin main" ;;
      esac ;;

    *)
      # Skip
      info "Skipping store setup"
      dim "When ready:"
      dim "  pass init <gpg-key-id>"
      dim "  pass git init"
      dim "  pass git remote add origin <SSH-URL>" ;;

  esac
fi

# ── Ensure git is always initialized in the store ──────────────
# pass git init is idempotent — safe to call even on a cloned repo.
# Without .git, passx sync/log/diff all fail with "_need_git" error.
if [ -d "${STORE_DIR:-$HOME/.password-store}" ]     && [ -f "${STORE_DIR:-$HOME/.password-store}/.gpg-id" ]     && [ ! -d "${STORE_DIR:-$HOME/.password-store}/.git" ]; then
  step "Initializing git in store (required for passx sync)..."
  pass git init 2>/dev/null && ok "git initialized" || warn "pass git init failed"
fi

# SSH key reminder — only when we set up a remote but didn't clone
if [ "${GIT_REMOTE_URL:-}" != "" ] && ! $STORE_CLONED; then
  if [ -n "$SELECTED_SSH_KEY" ] && [ -f "${SELECTED_SSH_KEY}.pub" ]; then
    printf "\n"
    info "SSH public key — paste this into your git host if not already added:"
    cat "${SELECTED_SSH_KEY}.pub" | sed 's/^/  /'
  elif [ -z "$SELECTED_SSH_KEY" ]; then
    printf "\n"
    warn "No SSH key found — generate one and add it to your git host:"
    dim "  ssh-keygen -t ed25519 -C your@email.com"
  fi
fi

# ════════════════════════════════════════════════════════════════
#   STEP 6 — GIT IDENTITY  (required for commits / passx sync)
# ════════════════════════════════════════════════════════════════
label "Step 6 — Git identity"

printf "  ${C_DIM}pass records every change as a git commit.\n"
printf "  Without a name + email git silently skips commits,\n"
printf "  so passx sync appears to work but nothing is saved.${C_RESET}\n\n"

_GIT_NAME="$(git config --global user.name  2>/dev/null || true)"
_GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -n "$_GIT_NAME" ] && [ -n "$_GIT_EMAIL" ]; then
  ok "Git identity already set"
  dim "  name  : $_GIT_NAME"
  dim "  email : $_GIT_EMAIL"
else
  if [ -z "$_GIT_NAME" ] && [ -z "$_GIT_EMAIL" ]; then
    warn "Git identity not set (no user.name or user.email)"
  elif [ -z "$_GIT_NAME" ]; then
    warn "Git user.name is not set  (user.email is: $_GIT_EMAIL)"
  else
    warn "Git user.email is not set  (user.name is: $_GIT_NAME)"
  fi
  printf "\n"

  _default_name="${GPG_NAME:-}"
  _default_email="${GPG_EMAIL:-}"

  if [ -z "$_GIT_NAME" ]; then
    if [ -n "$_default_name" ]; then
      ask "Your name  [${_default_name}]"
      IFS= read -r _GIT_NAME </dev/tty 2>/dev/null || _GIT_NAME=""
      _GIT_NAME="${_GIT_NAME:-$_default_name}"
    else
      _read_tty _GIT_NAME "Your name"
    fi
  fi

  if [ -z "$_GIT_EMAIL" ]; then
    if [ -n "$_default_email" ]; then
      ask "Your email  [${_default_email}]"
      IFS= read -r _GIT_EMAIL </dev/tty 2>/dev/null || _GIT_EMAIL=""
      _GIT_EMAIL="${_GIT_EMAIL:-$_default_email}"
    else
      _read_tty _GIT_EMAIL "Your email"
    fi
  fi

  if [ -n "$_GIT_NAME" ] && [ -n "$_GIT_EMAIL" ]; then
    git config --global user.name  "$_GIT_NAME"
    git config --global user.email "$_GIT_EMAIL"
    ok "Git identity saved"
    dim "  name  : $_GIT_NAME"
    dim "  email : $_GIT_EMAIL"
  else
    warn "Skipped — git commits will be anonymous until you run:"
    dim "  git config --global user.name  \"Your Name\""
    dim "  git config --global user.email \"you@example.com\""
  fi
fi

# ════════════════════════════════════════════════════════════════
#   STEP 7 — CONFIG  (auto-generate if missing)
# ════════════════════════════════════════════════════════════════
label "Step 7 — Configuration"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx"
CONF_FILE="$CONF_DIR/passx.conf"

if [ -f "$CONF_FILE" ]; then
  dim "Config already exists at $CONF_FILE"
else
  step "Generating starter config..."
  if [ -x "$PASSX_BIN" ]; then
    _passx gen-conf 2>/dev/null && ok "Config generated at $CONF_FILE"
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
#   STEP 8 — COMPLETIONS  (write to file, not source <())
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
      "$PASSX_BIN" completions zsh > "$zfunc_dir/_passx" 2>/dev/null \
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
      "$PASSX_BIN" completions bash > "$bcomp_dir/passx" 2>/dev/null \
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
      "$PASSX_BIN" completions fish > "$fdir/passx.fish" 2>/dev/null \
        && ok "fish completions: $fdir/passx.fish" \
        || warn "Could not write fish completions" ;;

    *)
      warn "Unknown shell '$shell' — set up completions manually:"
      dim "  zsh:  passx completions zsh > ~/.local/share/zsh/site-functions/_passx"
      dim "  bash: passx completions bash > ~/.local/share/bash-completion/completions/passx"
      dim "  fish: passx completions fish > ~/.config/fish/completions/passx.fish" ;;
  esac
}

if [ -x "$PASSX_BIN" ]; then
  _setup_completions "$CURRENT_SHELL"
else
  warn "passx binary not found at $PASSX_BIN — skipping completions"
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

#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  passx installer  —  setup passx + pass + GPG                 ║
# ║                                                                ║
# ║  One-liner install:                                            ║
# ║  curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh | bash
# ╚════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Repo — change these if you fork ──────────────────────────────
PASSX_REPO_BASE="https://raw.githubusercontent.com/tonycth7/passx/main"
PASSX_SCRIPT_URL="${PASSX_REPO_BASE}/passx-1_0.sh"
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

# Determine install dir
INSTALL_DIR="/usr/local/bin"
if ! sudo true 2>/dev/null; then
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
  warn "No sudo — installing to $INSTALL_DIR"
fi

_fetch_install() {
  # _fetch_install "url" "dest-name"
  local url="$1" name="$2" tmp
  tmp="$(mktemp)"
  step "Downloading ${name}..."
  if curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
    # quick sanity — must start with shebang
    head -1 "$tmp" | grep -q '^#!' \
      || { rm -f "$tmp"; warn "Download looks wrong for $name — skipping"; return 1; }
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
      sudo install -m 755 "$tmp" "$INSTALL_DIR/$name"
    else
      install -m 755 "$tmp" "$INSTALL_DIR/$name"
    fi
    rm -f "$tmp"
    ok "$name  →  $INSTALL_DIR/$name"
  else
    rm -f "$tmp"
    # fallback: look for the file locally (running from a cloned repo)
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
    local found=""
    for c in "$SCRIPT_DIR/${name}" "$SCRIPT_DIR/${name}.sh" \
              "$SCRIPT_DIR/passx-1_0.sh" "$SCRIPT_DIR/passx-1.0.sh"; do
      [ -f "$c" ] && { found="$c"; break; }
    done
    if [ -n "$found" ]; then
      warn "Download failed — using local file: $found"
      if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        sudo install -m 755 "$found" "$INSTALL_DIR/$name"
      else
        install -m 755 "$found" "$INSTALL_DIR/$name"
      fi
      ok "$name  →  $INSTALL_DIR/$name  (local)"
    else
      warn "Could not download or find $name — install manually"
      return 1
    fi
  fi
}

_fetch_install "$PASSX_SCRIPT_URL" "passx" || true
_fetch_install "$PASSX_MENU_URL"   "passx-menu" || true

# PATH warning
if [ "$INSTALL_DIR" = "$HOME/.local/bin" ]; then
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]     && warn "~/.local/bin is not in PATH — add to your shell rc:
    export PATH="\$HOME/.local/bin:\$PATH""
fi

# Full paths to installed binaries — used throughout the rest of the script
# so PATH doesn't need to be correct yet (e.g. during curl | bash)
PASSX_BIN="$INSTALL_DIR/passx"
PASSX_MENU_BIN="$INSTALL_DIR/passx-menu"
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

  ask "Your name"
  read -r GPG_NAME </dev/tty 2>/dev/null || GPG_NAME=""
  [ -z "$GPG_NAME" ] && err "Name cannot be empty"

  ask "Your email"
  read -r GPG_EMAIL </dev/tty 2>/dev/null || GPG_EMAIL=""
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
      ask "SSH hostname  (e.g. git.example.com)"
      read -r host_domain </dev/tty 2>/dev/null || host_domain=""
      [ -z "$host_domain" ] && { warn "No hostname given"; return 1; } ;;
  esac

  case "$host_label" in
    "Other self-hosted"*)
      # Full URL mode
      ask "Full SSH URL  (e.g. git@git.example.com:user/passwords.git)"
      read -r GIT_REMOTE_URL </dev/tty 2>/dev/null || GIT_REMOTE_URL=""
      [ -z "$GIT_REMOTE_URL" ] && { warn "No URL given"; return 1; }
      ;;
    *)
      ask "Username / org  (your git account name)"
      local git_user; read -r git_user </dev/tty 2>/dev/null || git_user=""
      [ -z "$git_user" ] && { warn "Username cannot be empty"; return 1; }

      ask "Repository name  (e.g. passwords)"
      local git_repo; read -r git_repo </dev/tty 2>/dev/null || git_repo=""
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
  # extract host from git@host:path or ssh://git@host/path
  local host
  if [[ "$url" == ssh://* ]]; then
    host="$(printf "%s" "$url" | sed 's|ssh://[^@]*@||; s|/.*||')"
  else
    host="$(printf "%s" "$url" | sed 's/.*@//; s/:.*//')"
  fi
  [ -z "$host" ] && return 0  # can't parse — skip test

  step "Testing SSH connection to ${host}..."
  if ssh -T -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new          -o BatchMode=yes "git@${host}" 2>&1 | grep -qiE 'success|welcome|authenticated|hi '; then
    ok "SSH connection works"
    return 0
  else
    # exit code 1 from github/gitlab is normal (no shell access) but still authenticated
    # only fail on connection refused / timeout / host unreachable
    local ssh_out
    ssh_out="$(ssh -T -o ConnectTimeout=6 -o BatchMode=yes "git@${host}" 2>&1 || true)"
    if printf "%s" "$ssh_out" | grep -qiE 'refused|timeout|unreachable|no route|could not resolve'; then
      warn "SSH connection failed — cannot reach ${host}"
      warn "Check: is your SSH key added to ${host}? Is the host reachable?"
      printf "
"
      confirm "Continue anyway?" || return 1
    else
      ok "SSH reachable (${host})"
    fi
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
      printf "  ${C_DIM}Your store will be cloned into: ${C_BOLD}$STORE_DIR${C_RESET}

"

      GIT_REMOTE_URL=""
      if ! _pick_ssh_url; then
        warn "URL setup cancelled — skipping clone"
      else
        if _test_ssh "$GIT_REMOTE_URL"; then
          # Make sure target dir is clear
          if [ -d "$STORE_DIR" ] && [ -n "$(ls -A "$STORE_DIR" 2>/dev/null)" ]; then
            warn "$STORE_DIR already exists and is not empty"
            confirm "Remove it and clone fresh?"               && { rm -rf "$STORE_DIR"; step "Removed $STORE_DIR"; }               || { warn "Skipping clone — directory not empty"; }
          fi

          if [ ! -d "$STORE_DIR" ] || [ -z "$(ls -A "$STORE_DIR" 2>/dev/null)" ]; then
            step "Cloning $GIT_REMOTE_URL ..."
            if git clone "$GIT_REMOTE_URL" "$STORE_DIR" 2>&1; then
              ok "Cloned to $STORE_DIR"
              STORE_CLONED=true

              # Verify it looks like a pass store
              if [ -f "$STORE_DIR/.gpg-id" ]; then
                local_id="$(cat "$STORE_DIR/.gpg-id" 2>/dev/null | head -1)"
                info "Store GPG ID: $local_id"
                if [ -n "${GPG_KEY_ID:-}" ] && [ "${GPG_KEY_ID:-}" != "__SKIP__" ]                     && [ "$local_id" != "$GPG_KEY_ID" ]; then
                  warn "Store was encrypted with a different key: $local_id"
                  warn "Make sure you have that key imported, or entries won't decrypt"
                fi
              else
                warn "Cloned repo has no .gpg-id — may not be a valid pass store"
                dim "Run: pass init <your-gpg-key-id>  inside $STORE_DIR"
              fi
            else
              warn "Clone failed"
              dim "Common causes:"
              dim "  • SSH key not added to the git host"
              dim "  • Wrong username or repo name"
              dim "  • Host not reachable"
              dim ""
              dim "Manual clone: git clone $GIT_REMOTE_URL $STORE_DIR"
            fi
          fi
        fi
      fi ;;

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

# SSH key hint — only relevant when a new remote was configured
# If the user just cloned successfully they obviously have an SSH key already
if [ "${GIT_REMOTE_URL:-}" != "" ] && ! $STORE_CLONED; then
  # We just set up a new remote — show/generate SSH key for the host
  if [ -f "$HOME/.ssh/id_ed25519.pub" ] || [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    printf "\n"
    info "Your SSH public key — paste this into your git host if not done yet:"
    for _pub in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
      [ -f "$_pub" ] && { cat "$_pub" | sed 's/^/  /'; break; }
    done
  elif ! [ -f "$HOME/.ssh/id_ed25519" ] && ! [ -f "$HOME/.ssh/id_rsa" ]; then
    printf "\n"
    warn "No SSH key found — you need one to push/pull from a private git repo"
    if confirm "Generate an SSH key now?"; then
      ask "Email for SSH key"
      _ssh_email=""; read -r _ssh_email </dev/tty 2>/dev/null || _ssh_email="passx@local"
      ssh-keygen -t ed25519 -C "$_ssh_email" -f "$HOME/.ssh/id_ed25519" </dev/tty         && ok "SSH key created: ~/.ssh/id_ed25519"         && { printf "\n"; info "Add this to your git host:";              cat "$HOME/.ssh/id_ed25519.pub" | sed 's/^/  /'; }         || warn "ssh-keygen failed"
    fi
  fi
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

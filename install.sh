#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║  passx installer — interactive setup for passx + pass + GPG  ║
# ╚═══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────
C_RED=$'\033[38;5;203m';    C_GREEN=$'\033[38;5;151m'
C_YELLOW=$'\033[38;5;222m'; C_BLUE=$'\033[38;5;110m'
C_CYAN=$'\033[38;5;117m';   C_MAGENTA=$'\033[38;5;183m'
C_BOLD=$'\033[1m';          C_DIM=$'\033[2m'
C_ITALIC=$'\033[3m';        C_RESET=$'\033[0m'

# ── Print helpers ─────────────────────────────────────────────────
ok()    { printf "\n${C_GREEN}${C_BOLD}  ✔  %s${C_RESET}\n" "$*"; }
err()   { printf "\n${C_RED}${C_BOLD}  ✖  %s${C_RESET}\n" "$*" >&2; exit 1; }
warn()  { printf "\n${C_YELLOW}  ⚠  %s${C_RESET}\n" "$*"; }
info()  { printf "${C_CYAN}  ℹ  %s${C_RESET}\n" "$*"; }
step()  { printf "\n${C_BLUE}  →  %s${C_RESET}\n" "$*"; }
dim()   { printf "  ${C_DIM}%s${C_RESET}\n" "$*"; }
ask()   { printf "\n${C_MAGENTA}${C_BOLD}  ❯  %s${C_RESET} " "$*"; }
label() { printf "\n  ${C_BOLD}${C_CYAN}%s${C_RESET}\n  ${C_DIM}"; \
          printf '─%.0s' $(seq 1 $(( ${#1} + 2 ))); printf "${C_RESET}\n"; }

banner() {
  local t="$1" w=58
  local p=$(( (w - ${#t}) / 2 ))
  printf "\n${C_BOLD}${C_CYAN}"
  printf "  ╔"; printf '═%.0s' $(seq 1 $w); printf "╗\n"
  printf "  ║%*s%s%*s║\n" $p "" "$t" $((w - p - ${#t})) ""
  printf "  ╚"; printf '═%.0s' $(seq 1 $w); printf "╝${C_RESET}\n\n"
}

confirm() {
  # confirm "question" → returns 0 for yes, 1 for no
  ask "${1} [y/N]"
  local r; read -r r </dev/tty 2>/dev/null || r=""
  [[ "${r,,}" == "y" || "${r,,}" == "yes" ]]
}

pick_one() {
  # pick_one "question" opt1 opt2 opt3 ...
  local q="$1"; shift
  local opts=("$@")
  printf "\n  ${C_BOLD}${C_MAGENTA}❯  %s${C_RESET}\n\n" "$q"
  local i=1
  for o in "${opts[@]}"; do
    printf "    ${C_CYAN}[%d]${C_RESET}  %s\n" "$i" "$o"
    (( i++ ))
  done
  printf "\n"
  while true; do
    ask "Enter number (1-${#opts[@]})"
    local r; read -r r </dev/tty 2>/dev/null || r=""
    if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= ${#opts[@]} )); then
      PICKED="${opts[$((r-1))]}"
      return 0
    fi
    warn "Please enter a number between 1 and ${#opts[@]}"
  done
}

# ── Detect package manager ────────────────────────────────────────
_detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then   PM="apt"; return; fi
  if command -v pacman  >/dev/null 2>&1; then   PM="pacman"; return; fi
  if command -v dnf     >/dev/null 2>&1; then   PM="dnf"; return; fi
  if command -v zypper  >/dev/null 2>&1; then   PM="zypper"; return; fi
  if command -v brew    >/dev/null 2>&1; then   PM="brew"; return; fi
  PM="unknown"
}

_pm_install() {
  local pkg="$1"
  case "$PM" in
    apt)    sudo apt-get install -y "$pkg" >/dev/null 2>&1 ;;
    pacman) sudo pacman -S --noconfirm "$pkg" >/dev/null 2>&1 ;;
    dnf)    sudo dnf install -y "$pkg" >/dev/null 2>&1 ;;
    zypper) sudo zypper install -y "$pkg" >/dev/null 2>&1 ;;
    brew)   brew install "$pkg" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

# Map generic names to distro-specific package names
_pkg_name() {
  local tool="$1"
  case "$PM" in
    apt)
      case "$tool" in
        wl-clipboard)   echo "wl-clipboard" ;;
        xclip)          echo "xclip" ;;
        oathtool)       echo "oathtool" ;;
        qrencode)       echo "qrencode" ;;
        zbarimg)        echo "zbar-tools" ;;
        notify-send)    echo "libnotify-bin" ;;
        xdotool)        echo "xdotool" ;;
        sshpass)        echo "sshpass" ;;
        jq)             echo "jq" ;;
        fzf)            echo "fzf" ;;
        bat)            echo "bat" ;;
        curl)           echo "curl" ;;
        pass)           echo "pass" ;;
        gpg)            echo "gnupg" ;;
        git)            echo "git" ;;
        *)              echo "$tool" ;;
      esac ;;
    pacman)
      case "$tool" in
        wl-clipboard)   echo "wl-clipboard" ;;
        oathtool)       echo "oath-toolkit" ;;
        zbarimg)        echo "zbar" ;;
        notify-send)    echo "libnotify" ;;
        gpg)            echo "gnupg" ;;
        *)              echo "$tool" ;;
      esac ;;
    brew)
      case "$tool" in
        pass)           echo "pass" ;;
        gpg)            echo "gnupg" ;;
        oathtool)       echo "oath-toolkit" ;;
        zbarimg)        echo "zbar" ;;
        notify-send)    echo "terminal-notifier" ;;
        wl-clipboard)   echo "" ;;  # not available on macOS
        *)              echo "$tool" ;;
      esac ;;
    *)  echo "$tool" ;;
  esac
}

_install_pkg() {
  local tool="$1" label="${2:-$1}"
  local pkg; pkg="$(_pkg_name "$tool")"
  [ -z "$pkg" ] && { dim "  skipping $label (not available on $PM)"; return 0; }
  step "Installing $label..."
  if _pm_install "$pkg"; then
    ok "$label installed"
  else
    warn "Failed to install $label — you may need to install it manually"
  fi
}

# ── Check if command exists ───────────────────────────────────────
has() { command -v "$1" >/dev/null 2>&1; }

# ═════════════════════════════════════════════════════════════════
#   START
# ═════════════════════════════════════════════════════════════════
clear
banner "passx installer  v1.0.0"

printf "  ${C_ITALIC}${C_DIM}a power-user wrapper around pass${C_RESET}\n\n"
dim "This script will:"
dim "  • install required and optional dependencies"
dim "  • install passx to /usr/local/bin"
dim "  • help you set up a GPG key"
dim "  • initialize your password store"
printf "\n"

if ! confirm "Ready to begin?"; then
  printf "\n  ${C_DIM}Aborted. Run again when you're ready.${C_RESET}\n\n"
  exit 0
fi

# ── Detect distro / package manager ──────────────────────────────
_detect_pm
printf "\n"
info "Detected package manager: ${C_BOLD}$PM${C_RESET}"
[ "$PM" = "unknown" ] && warn "Unknown package manager — you may need to install dependencies manually"

# ═════════════════════════════════════════════════════════════════
#   STEP 1 — REQUIRED DEPENDENCIES
# ═════════════════════════════════════════════════════════════════
label "Step 1 — Required dependencies"

MISSING_REQUIRED=()
has gpg  || MISSING_REQUIRED+=("gpg")
has pass || MISSING_REQUIRED+=("pass")
has git  || MISSING_REQUIRED+=("git")
has curl || MISSING_REQUIRED+=("curl")

if [ ${#MISSING_REQUIRED[@]} -eq 0 ]; then
  ok "All required dependencies already installed"
else
  warn "Missing required tools: ${MISSING_REQUIRED[*]}"
  if confirm "Install missing required dependencies now?"; then
    for tool in "${MISSING_REQUIRED[@]}"; do
      _install_pkg "$tool"
    done
  else
    err "Cannot continue without required dependencies (gpg, pass, git, curl)"
  fi
fi

# Final check
for req in gpg pass git; do
  has "$req" || err "$req is not installed and is required. Install it manually and re-run."
done

# ═════════════════════════════════════════════════════════════════
#   STEP 2 — OPTIONAL DEPENDENCIES
# ═════════════════════════════════════════════════════════════════
label "Step 2 — Optional dependencies"

printf "  ${C_DIM}passx degrades gracefully without these, but they unlock more features.${C_RESET}\n\n"

declare -A OPTIONALS=(
  [fzf]="fuzzy finder (picker, search, ui)"
  [xdotool]="autofill + login automation"
  [oathtool]="TOTP/OTP codes"
  [qrencode]="QR code generation"
  [zbarimg]="QR code scanning"
  [wl-clipboard]="Wayland clipboard (wl-copy)"
  [xclip]="X11 clipboard"
  [notify-send]="desktop notifications"
  [sshpass]="SSH credential injection"
  [jq]="JSON export"
  [bat]="syntax-highlighted fzf previews"
)

MISSING_OPT=()
for tool in "${!OPTIONALS[@]}"; do
  has "$tool" || MISSING_OPT+=("$tool")
done

if [ ${#MISSING_OPT[@]} -eq 0 ]; then
  ok "All optional tools already installed"
else
  printf "  ${C_YELLOW}Missing optional tools:${C_RESET}\n\n"
  for tool in "${MISSING_OPT[@]}"; do
    printf "    ${C_DIM}%-18s${C_RESET}  %s\n" "$tool" "${OPTIONALS[$tool]}"
  done
  printf "\n"
  if confirm "Install all missing optional dependencies?"; then
    for tool in "${MISSING_OPT[@]}"; do
      _install_pkg "$tool" "$tool — ${OPTIONALS[$tool]}"
    done
  else
    info "Skipping optional tools — you can install them later"
  fi
fi

# ═════════════════════════════════════════════════════════════════
#   STEP 3 — INSTALL PASSX
# ═════════════════════════════════════════════════════════════════
label "Step 3 — Install passx"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSX_BIN="$SCRIPT_DIR/passx-1_0.sh"

# Try to find the script with multiple names
for candidate in \
    "$SCRIPT_DIR/passx" \
    "$SCRIPT_DIR/passx.sh" \
    "$SCRIPT_DIR/passx-1.0" \
    "$SCRIPT_DIR/passx-1_0.sh" \
    "$SCRIPT_DIR/passx-1.0.sh"; do
  [ -f "$candidate" ] && { PASSX_BIN="$candidate"; break; }
done

[ -f "$PASSX_BIN" ] || err "Cannot find the passx script in $SCRIPT_DIR"

INSTALL_DIR="/usr/local/bin"
info "Installing passx → $INSTALL_DIR/passx"

if sudo install -m 755 "$PASSX_BIN" "$INSTALL_DIR/passx"; then
  ok "passx installed to $INSTALL_DIR/passx"
else
  warn "sudo install failed — trying to install to ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$PASSX_BIN" "$HOME/.local/bin/passx"
  INSTALL_DIR="$HOME/.local/bin"
  ok "passx installed to $INSTALL_DIR/passx"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "~/.local/bin is not in your PATH"
    dim "Add this to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
fi

# Install passx-menu if present
for candidate in \
    "$SCRIPT_DIR/passx-menu" \
    "$SCRIPT_DIR/passx-menu.sh" \
    "$SCRIPT_DIR/passx-menu-0_0_1.sh"; do
  if [ -f "$candidate" ]; then
    step "Installing passx-menu..."
    sudo install -m 755 "$candidate" "$INSTALL_DIR/passx-menu" 2>/dev/null \
      || install -m 755 "$candidate" "$HOME/.local/bin/passx-menu" 2>/dev/null || true
    ok "passx-menu installed"
    break
  fi
done

# ═════════════════════════════════════════════════════════════════
#   STEP 4 — GPG KEY SETUP
# ═════════════════════════════════════════════════════════════════
label "Step 4 — GPG key setup"

printf "  ${C_DIM}pass uses your GPG key to encrypt every entry.${C_RESET}\n"
printf "  ${C_DIM}Let's check what you have and set one up if needed.${C_RESET}\n\n"

# List existing secret keys
EXISTING_KEYS=$(gpg --list-secret-keys --with-colons 2>/dev/null \
  | awk -F: '
      /^sec/ { uid=""; fpr="" }
      /^fpr/ { if (!fpr) fpr=$10 }
      /^uid/ { if (!uid) uid=$10 }
      /^ssb|^sec/ && fpr { if (uid) print fpr "  →  " uid; uid=""; fpr="" }
    ' || true)

# Also try simpler fallback
if [ -z "$EXISTING_KEYS" ]; then
  EXISTING_KEYS=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | grep -E "^(sec|uid)" | paste - - \
    | sed 's/sec.*\/\([A-F0-9]*\).*/\1/' || true)
fi

GPG_KEY_ID=""

if [ -n "$EXISTING_KEYS" ]; then
  printf "  ${C_GREEN}${C_BOLD}Found existing GPG secret keys:${C_RESET}\n\n"
  
  # Build array of keys for selection
  declare -a KEY_FPRS=()
  declare -a KEY_LABELS=()
  
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local_fpr=$(printf "%s" "$line" | awk '{print $1}')
    local_uid=$(printf "%s" "$line" | sed 's/^[^ ]* *→ *//')
    KEY_FPRS+=("$local_fpr")
    KEY_LABELS+=("$local_uid  ${C_DIM}(${local_fpr:(-16)})${C_RESET}")
    printf "    ${C_CYAN}•${C_RESET}  %s\n" "${local_uid}  ${C_DIM}(${local_fpr:(-16)})${C_RESET}"
  done <<< "$EXISTING_KEYS"
  printf "\n"

  pick_one "What would you like to do?" \
    "Use an existing key" \
    "Create a new GPG key" \
    "Skip GPG setup (I'll run pass init manually)"

  case "$PICKED" in
    "Use an existing key")
      if [ ${#KEY_FPRS[@]} -eq 1 ]; then
        GPG_KEY_ID="${KEY_FPRS[0]}"
        info "Using key: ${KEY_LABELS[0]:-$GPG_KEY_ID}"
      else
        printf "\n  ${C_BOLD}${C_MAGENTA}❯  Select a key:${C_RESET}\n\n"
        local i=1
        for lbl in "${KEY_LABELS[@]}"; do
          printf "    ${C_CYAN}[%d]${C_RESET}  %b\n" "$i" "$lbl"
          (( i++ ))
        done
        printf "\n"
        while true; do
          ask "Enter number (1-${#KEY_FPRS[@]})"
          local r; read -r r </dev/tty 2>/dev/null || r=""
          if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= ${#KEY_FPRS[@]} )); then
            GPG_KEY_ID="${KEY_FPRS[$((r-1))]}"
            info "Using key: ${KEY_LABELS[$((r-1))]:-$GPG_KEY_ID}"
            break
          fi
          warn "Enter a number between 1 and ${#KEY_FPRS[@]}"
        done
      fi
      ;;
    "Create a new GPG key") GPG_KEY_ID="__CREATE__" ;;
    "Skip GPG setup"*)      GPG_KEY_ID="__SKIP__"   ;;
  esac
else
  printf "  ${C_YELLOW}No existing GPG secret keys found.${C_RESET}\n\n"
  pick_one "What would you like to do?" \
    "Create a new GPG key for passx" \
    "I already have a key — import it first, then re-run this installer" \
    "Skip (I'll set up GPG manually)"

  case "$PICKED" in
    "Create a new GPG key"*) GPG_KEY_ID="__CREATE__" ;;
    "I already have"*)
      printf "\n"
      info "To import your key:"
      dim "  gpg --import your-private-key.asc"
      dim "  or"
      dim "  gpg --recv-keys <KEYID>    (if it's on a keyserver)"
      printf "\n  ${C_DIM}Re-run this installer after importing.${C_RESET}\n\n"
      exit 0 ;;
    *) GPG_KEY_ID="__SKIP__" ;;
  esac
fi

# ── Create new key ────────────────────────────────────────────────
if [ "$GPG_KEY_ID" = "__CREATE__" ]; then
  label "Creating new GPG key"
  printf "  ${C_DIM}We'll generate a strong RSA 4096 key.${C_RESET}\n\n"

  ask "Your real name (for the key)"
  read -r GPG_NAME </dev/tty 2>/dev/null || GPG_NAME=""
  [ -z "$GPG_NAME" ] && err "Name cannot be empty"

  ask "Your email address"
  read -r GPG_EMAIL </dev/tty 2>/dev/null || GPG_EMAIL=""
  [[ "$GPG_EMAIL" == *@* ]] || err "Invalid email address"

  printf "\n  ${C_DIM}You'll be asked to set a passphrase for your key.${C_RESET}\n"
  printf "  ${C_DIM}Use a strong one — this protects every password you store.${C_RESET}\n\n"

  # Generate key non-interactively using batch input
  step "Generating RSA 4096 key..."
  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GPG_NAME
Name-Email: $GPG_EMAIL
Expire-Date: 2y
%commit
EOF

  # Find the key we just created
  GPG_KEY_ID=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
    | awk -F: '/^fpr/ {print $10; exit}')

  [ -n "$GPG_KEY_ID" ] || err "Key creation seemed to succeed but could not find the fingerprint"
  ok "GPG key created: ${GPG_KEY_ID:(-16)}"

  printf "\n  ${C_BOLD}Your key fingerprint:${C_RESET}\n"
  gpg --fingerprint "$GPG_KEY_ID" 2>/dev/null | sed 's/^/  /'

  printf "\n  ${C_DIM}Consider backing up your key:${C_RESET}\n"
  dim "  gpg --export-secret-keys --armor $GPG_KEY_ID > passx-key-backup.asc"
  dim "  store that file somewhere offline and safe"
fi

# ═════════════════════════════════════════════════════════════════
#   STEP 5 — PASS INIT
# ═════════════════════════════════════════════════════════════════
if [ "$GPG_KEY_ID" != "__SKIP__" ] && [ -n "$GPG_KEY_ID" ]; then
  label "Step 5 — Initialize password store"

  STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  printf "  ${C_DIM}Store path: ${C_RESET}${C_BOLD}%s${C_RESET}\n\n" "$STORE_DIR"

  if [ -d "$STORE_DIR" ] && [ -f "$STORE_DIR/.gpg-id" ]; then
    CURRENT_ID=$(cat "$STORE_DIR/.gpg-id" 2>/dev/null || echo "")
    info "Password store already initialized"
    dim "Current GPG ID: $CURRENT_ID"
    printf "\n"
    if confirm "Re-initialize with key ${GPG_KEY_ID:(-16)}? (existing entries will be re-encrypted)"; then
      step "Running: pass init $GPG_KEY_ID"
      pass init "$GPG_KEY_ID" && ok "Store re-initialized" || warn "pass init failed"
    else
      info "Keeping existing store configuration"
    fi
  else
    if confirm "Initialize password store at $STORE_DIR?"; then
      step "Running: pass init $GPG_KEY_ID"
      pass init "$GPG_KEY_ID" && ok "Password store initialized" || err "pass init failed"

      if confirm "Set up git for your password store?"; then
        pass git init && ok "git initialized in store"
        info "You can add a remote later:"
        dim "  pass git remote add origin git@github.com:you/passwords.git"
        dim "  pass git push -u origin main"
      fi
    else
      info "Skipping pass init — run it manually: pass init <GPG-KEY-ID>"
    fi
  fi
else
  label "Step 5 — Skipped"
  info "Skipping pass init"
  dim "When ready, run: pass init <your-gpg-key-id>"
fi

# ═════════════════════════════════════════════════════════════════
#   STEP 6 — GENERATE CONFIG
# ═════════════════════════════════════════════════════════════════
label "Step 6 — Configuration"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx"
CONF_FILE="$CONF_DIR/passx.conf"

if [ -f "$CONF_FILE" ]; then
  info "Config file already exists at $CONF_FILE"
else
  if confirm "Generate a starter config file at $CONF_FILE?"; then
    passx gen-conf 2>/dev/null && ok "Config generated" || {
      mkdir -p "$CONF_DIR"
      cat > "$CONF_FILE" <<'CONF'
# passx configuration
# See: passx gen-conf for full documentation

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
    }
    dim "Edit $CONF_FILE to customize your setup"
  fi
fi

# ═════════════════════════════════════════════════════════════════
#   STEP 7 — SHELL COMPLETIONS
# ═════════════════════════════════════════════════════════════════
label "Step 7 — Shell completions"

CURRENT_SHELL=$(basename "${SHELL:-bash}")
info "Detected shell: $CURRENT_SHELL"

_setup_completions() {
  local shell="$1"
  case "$shell" in
    bash)
      local rc="$HOME/.bashrc"
      if ! grep -q "passx completions bash" "$rc" 2>/dev/null; then
        printf '\n# passx completions\nsource <(passx completions bash)\n' >> "$rc"
        ok "bash completions added to $rc"
      else
        dim "bash completions already in $rc"
      fi ;;
    zsh)
      local rc="$HOME/.zshrc"
      if ! grep -q "passx completions zsh" "$rc" 2>/dev/null; then
        printf '\n# passx completions\nsource <(passx completions zsh)\n' >> "$rc"
        ok "zsh completions added to $rc"
      else
        dim "zsh completions already in $rc"
      fi ;;
    fish)
      local fishdir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
      mkdir -p "$fishdir"
      passx completions fish > "$fishdir/passx.fish" 2>/dev/null \
        && ok "fish completions written to $fishdir/passx.fish" \
        || warn "Could not write fish completions" ;;
    *)
      warn "Unknown shell: $shell — set up completions manually"
      dim "  bash:  source <(passx completions bash)"
      dim "  zsh:   source <(passx completions zsh)"
      dim "  fish:  passx completions fish | source" ;;
  esac
}

if confirm "Set up tab completions for $CURRENT_SHELL?"; then
  _setup_completions "$CURRENT_SHELL"
fi

# ═════════════════════════════════════════════════════════════════
#   DONE
# ═════════════════════════════════════════════════════════════════
banner "passx is ready"

printf "  ${C_BOLD}Quick start:${C_RESET}\n\n"
printf "    ${C_CYAN}passx doctor${C_RESET}                      ${C_DIM}# verify your setup${C_RESET}\n"
printf "    ${C_CYAN}passx add github user@mail.com${C_RESET}    ${C_DIM}# add your first entry${C_RESET}\n"
printf "    ${C_CYAN}passx ui${C_RESET}                          ${C_DIM}# open interactive picker${C_RESET}\n"
printf "    ${C_CYAN}passx --help${C_RESET}                      ${C_DIM}# full command reference${C_RESET}\n"
printf "\n"
dim "If you set up completions, restart your shell or source your rc file."
printf "\n"

#!/usr/bin/env bash
# passx — power-user wrapper around 'pass'
# Version: 0.2.0
# Features: OTP, fzf UI, WSL/Wayland/X11 clipboard, autofill (xdotool),
#           auto-sync (git), SSH key management (full file storage in pass),
#           GPG key management (full export storage in pass),
#           private-key access protection, secure clipboard clearing,
#           debug logging, packaging-ready.
set -euo pipefail

# ================================================================
# CONFIGURATION
# ================================================================
PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
PASSX_AUTOSYNC="${PASSX_AUTOSYNC:-false}"
PASSX_CLIP_TIMEOUT="${PASSX_CLIP_TIMEOUT:-20}"
PASSX_DEBUG="${PASSX_DEBUG:-0}"
PASSX_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/passx"
PASSX_LOG="$PASSX_CACHE_DIR/log"

# ================================================================
# HELPERS
# ================================================================
err() {
  printf "❌ %s\n" "$1" >&2
  printf "Run: passx -h for help\n" >&2
  exit "${2:-1}"
}

debug() {
  if [ "$PASSX_DEBUG" = "1" ]; then
    mkdir -p "$PASSX_CACHE_DIR"
    printf "[%s] DEBUG: %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$PASSX_LOG" >&2
  fi
}

info() { printf "ℹ  %s\n" "$*"; }
warn() { printf "⚠  %s\n" "$*" >&2; }

# ================================================================
# PRIVATE KEY GUARD
# ================================================================
# Returns 0 if the pass path looks like a private key entry
_is_pvt_path() {
  local path="$1"
  [[ "$path" == *-pvt ]] || [[ "$path" == */pvt ]]
}

# Prompt the user to confirm access to a private key.
# Exits the script if the user says no.
_confirm_pvt_access() {
  local path="$1"
  echo "" >&2
  echo "  ╔══════════════════════════════════════╗" >&2
  echo "  ║  ⚠  PRIVATE KEY ACCESS WARNING       ║" >&2
  echo "  ╚══════════════════════════════════════╝" >&2
  printf "  Entry  : %s\n" "$path" >&2
  echo "  This entry contains a private key." >&2
  echo "  Your GPG passphrase will be required." >&2
  echo "" >&2
  printf "  Are you sure you want to proceed? [y/N]: " >&2
  read -r yn </dev/tty || yn=""
  [[ "${yn,,}" == "y" ]] || { echo "Aborted." >&2; exit 0; }
}

# ================================================================
# CLIPBOARD
# ================================================================
clipboard_available() {
  command -v wl-copy >/dev/null 2>&1 && return 0
  command -v clip.exe >/dev/null 2>&1 && return 0
  command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ] && return 0
  return 1
}

# copy_clipboard: reads from stdin
# usage: printf "%s" "$data" | copy_clipboard [--silent]
copy_clipboard() {
  local silent=false
  [ "${1:-}" = "--silent" ] && silent=true

  # Wayland
  if command -v wl-copy >/dev/null 2>&1; then
    if $silent; then wl-copy
    else wl-copy && echo "✔ Copied (Wayland)" || { warn "Wayland copy failed"; return 1; }
    fi
    _schedule_clipboard_clear
    return 0
  fi

  # WSL / Windows
  if command -v clip.exe >/dev/null 2>&1; then
    if $silent; then clip.exe
    else clip.exe && echo "✔ Copied (Windows clipboard)" || { warn "clip.exe failed"; return 1; }
    fi
    return 0
  fi

  # X11
  if command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    if $silent; then xclip -selection clipboard
    else xclip -selection clipboard && echo "✔ Copied (X11)" || { warn "xclip failed"; return 1; }
    fi
    _schedule_clipboard_clear
    return 0
  fi

  if ! $silent; then cat; echo; warn "No clipboard available (TTY mode)"; fi
  return 1
}

_schedule_clipboard_clear() {
  local timeout="$PASSX_CLIP_TIMEOUT"
  debug "Scheduling clipboard clear in ${timeout}s"
  (
    sleep "$timeout"
    if command -v wl-copy >/dev/null 2>&1; then
      printf "" | wl-copy 2>/dev/null || true
    elif command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
      printf "" | xclip -selection clipboard 2>/dev/null || true
    fi
    debug "Clipboard cleared after ${timeout}s"
  ) &
  disown 2>/dev/null || true
}

# ================================================================
# ENTRY LISTING  (fast: uses pass ls --flat, fallback to find)
# ================================================================
list_entries() {
  debug "Listing entries"
  if pass ls --flat >/dev/null 2>&1; then
    pass ls --flat 2>/dev/null | sort
  else
    find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
      | sed "s|^$PASSWORD_STORE_DIR/||; s|\.gpg$||" | sort
  fi
}

# ================================================================
# fzf PICKER
# ================================================================
pick_entry() {
  command -v fzf >/dev/null 2>&1 || err "fzf not installed (required for interactive picker)"
  list_entries | fzf
}

# ================================================================
# PASSWORD GENERATOR
# ================================================================
gen_password() {
  local length="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom | head -c "$length"
}

# ================================================================
# FIELD EXTRACTION
# ================================================================
extract_field() {
  local path="$1" field="$2"
  case "$field" in
    password) pass show "$path" 2>/dev/null | sed -n '1p' ;;
    email|username|notes)
      pass show "$path" 2>/dev/null | awk -F': ' "/^$field:/ {print \$2; exit}" ;;
    full) pass show "$path" 2>/dev/null ;;
    *) err "Unknown field: $field" ;;
  esac
}

# ================================================================
# AUTO SYNC (git)
# ================================================================
cmd_sync() {
  debug "Running sync"
  [ ! -d "$PASSWORD_STORE_DIR/.git" ] && \
    err "Password store is not a git repository. Initialise with: pass git init"
  echo "↓ Pulling changes..."
  pass git pull 2>&1 || warn "git pull failed (continuing anyway)"
  echo "↑ Pushing changes..."
  pass git push 2>&1 && echo "✔ Sync complete" || { warn "git push failed — check remote config"; return 1; }
}

_autosync() {
  if [ "$PASSX_AUTOSYNC" = "true" ] && [ -d "$PASSWORD_STORE_DIR/.git" ]; then
    debug "Autosync triggered"
    pass git push >/dev/null 2>&1 && debug "Autosync OK" || debug "Autosync push failed (non-fatal)"
  fi
}

# ================================================================
# ADD ENTRY
# ================================================================
cmd_add() {
  [ "$#" -lt 1 ] && err "Usage: passx add <path> [email] [username] [notes] [length]"
  local path="$1"; shift
  local email="" user="" notes="" length="32"
  for arg in "$@"; do
    if [[ "$arg" == *"@"* ]]; then email="$arg"
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then length="$arg"
    elif [ -z "$user" ]; then user="$arg"
    else notes="$arg"
    fi
  done
  local password
  password="$(gen_password "$length")"
  {
    echo "$password"
    [ -n "$email" ]  && echo "email: $email"
    [ -n "$user" ]   && echo "username: $user"
    [ -n "$notes" ]  && echo "notes: $notes"
  } | pass insert -m "$path" || err "pass insert failed for $path"
  echo "✔ Added: $path"
  debug "Added entry: $path"
  _autosync
}

# ================================================================
# SHOW / COPY
# ================================================================
cmd_show_copy() {
  local mode="$1"; shift
  local path="${1:-}" field="password"

  OPTIND=1
  while getopts ":puefn" opt; do
    case "$opt" in
      p) field="password" ;;
      u) field="username" ;;
      e) field="email" ;;
      n) field="notes" ;;
      f) field="full" ;;
      *) err "Invalid flag for show/copy" ;;
    esac
  done
  shift $((OPTIND - 1))

  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "No entry selected"

  # Private key guard — always ask before exposing a private key entry
  if _is_pvt_path "$path"; then
    _confirm_pvt_access "$path"
  fi

  if [ "$mode" = "copy" ]; then
    # For key entries (-pub / -pvt), copy the entire entry (it IS the key)
    if _is_pvt_path "$path" || [[ "$path" == *-pub ]]; then
      pass show "$path" 2>/dev/null | copy_clipboard || err "Copy failed"
    else
      extract_field "$path" "$field" | tr -d '\n' | copy_clipboard || err "Copy failed (no clipboard?)"
    fi
  else
    if _is_pvt_path "$path" || [[ "$path" == *-pub ]]; then
      pass show "$path" 2>/dev/null || err "Show failed for $path"
    else
      extract_field "$path" "$field" || err "Show failed for $path"
    fi
  fi
}

# ================================================================
# OTP
# ================================================================
cmd_otp() {
  local copy_flag=true
  OPTIND=1
  while getopts ":n" opt; do
    case "$opt" in
      n) copy_flag=false ;;
      *) err "Invalid flag for otp" ;;
    esac
  done
  shift $((OPTIND - 1))

  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "No entry selected"

  local otp_out=""
  if command -v pass >/dev/null 2>&1 && pass otp "$path" >/dev/null 2>&1; then
    otp_out="$(pass otp "$path" 2>/dev/null)"
  elif command -v oathtool >/dev/null 2>&1; then
    local entry secret
    entry="$(pass show "$path" 2>/dev/null || true)"
    secret=$(printf "%s\n" "$entry" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p' | head -n1)
    [ -z "$secret" ] && secret=$(printf "%s\n" "$entry" | awk -F': ' '/^otp:/ {print $2; exit}')
    [ -n "$secret" ] && otp_out="$(oathtool --totp -b "$secret")"
  fi

  [ -z "$otp_out" ] && err "OTP not configured or 'pass otp'/'oathtool' unavailable for $path"
  printf "%s\n" "$otp_out"
  if $copy_flag && clipboard_available; then
    printf "%s" "$otp_out" | copy_clipboard --silent || true
  elif $copy_flag; then
    warn "Clipboard not available"
  fi
}

cmd_otp_show() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "No entry selected"

  while true; do
    clear
    local otp_out entry secret
    if command -v pass >/dev/null 2>&1 && pass otp "$path" >/dev/null 2>&1; then
      otp_out="$(pass otp "$path" 2>/dev/null)"
    else
      entry="$(pass show "$path" 2>/dev/null || true)"
      secret=$(printf "%s\n" "$entry" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p' | head -n1)
      [ -z "$secret" ] && secret=$(printf "%s\n" "$entry" | awk -F': ' '/^otp:/ {print $2; exit}')
      otp_out="$(oathtool --totp -b "$secret" 2>/dev/null || echo "N/A")"
    fi
    local remaining=$((30 - $(date +%s) % 30))
    echo "OTP for: $path"
    echo
    printf "  %s\n\n" "$otp_out"
    echo "Expires in: ${remaining}s (press Ctrl-C to exit)"
    clipboard_available && [ "$otp_out" != "N/A" ] \
      && printf "%s" "$otp_out" | copy_clipboard --silent || true
    sleep 1
  done
}

cmd_otp_import() {
  command -v zbarimg >/dev/null 2>&1 || err "zbarimg required for otp-import"
  local path="${1:-}" img="${2:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx otp-import <path> <qr-image>"
  [ -z "$img" ]  && err "Usage: passx otp-import <path> <qr-image>"
  [ ! -f "$img" ] && err "QR image not found: $img"

  local secret_url secret tmp
  secret_url=$(zbarimg --quiet --raw "$img" 2>/dev/null || true)
  [ -z "$secret_url" ] && err "Could not read QR or not an otpauth QR"
  secret=$(printf "%s" "$secret_url" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p')
  tmp="$(mktemp)"
  if pass show "$path" >/dev/null 2>&1; then
    pass show "$path" > "$tmp"
    awk '!/^otp:/' "$tmp" > "${tmp}.new"
    [ -n "$secret" ] \
      && printf "otp: %s\n" "$secret" >> "${tmp}.new" \
      || printf "%s\n" "$secret_url" >> "${tmp}.new"
    mv "${tmp}.new" "$tmp"
  else
    [ -n "$secret" ] \
      && printf "otp: %s\n" "$secret" > "$tmp" \
      || printf "%s\n" "$secret_url" > "$tmp"
  fi
  pass insert -m -f "$path" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
  rm -f "$tmp"
  echo "✔ OTP added to $path"
}

cmd_otp_export() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx otp-export <path> [--qr <file>]"

  local entry otpauth secret label
  entry="$(pass show "$path" 2>/dev/null || true)"
  otpauth=$(printf "%s\n" "$entry" | grep -m1 '^otpauth://' || true)
  if [ -z "$otpauth" ]; then
    secret=$(printf "%s\n" "$entry" | awk -F': ' '/^otp:/ {print $2; exit}')
    if [ -n "$secret" ]; then
      label="$(printf "%s" "$path" | sed 's/ /%20/g')"
      otpauth="otpauth://totp/${label}?secret=${secret}&issuer=${label}"
    fi
  fi
  [ -z "$otpauth" ] && err "No OTP data found in $path"

  if [ "${2:-}" = "--qr" ]; then
    local qrfile="${3:-}"
    [ -z "$qrfile" ] && err "Usage: passx otp-export <path> --qr <file.png>"
    command -v qrencode >/dev/null 2>&1 \
      || { echo "$otpauth"; err "qrencode required to write PNG (printed URL above)"; }
    qrencode -o "$qrfile" -s 10 "$otpauth" || err "qrencode failed"
    echo "✔ QR written to $qrfile"
  else
    echo "$otpauth"
  fi
}

cmd_otp_qr() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx otp-qr <path>"

  local entry otpauth secret label
  entry="$(pass show "$path" 2>/dev/null || true)"
  otpauth=$(printf "%s\n" "$entry" | grep -m1 '^otpauth://' || true)
  if [ -z "$otpauth" ]; then
    secret=$(printf "%s\n" "$entry" | awk -F': ' '/^otp:/ {print $2; exit}')
    [ -z "$secret" ] && err "No OTP data found in $path"
    label="$(printf "%s" "$path" | sed 's/ /%20/g')"
    otpauth="otpauth://totp/${label}?secret=${secret}&issuer=${label}"
  fi
  command -v qrencode >/dev/null 2>&1 || err "qrencode required to show QR in terminal"
  qrencode -t ansiutf8 "$otpauth" || err "qrencode failed"
}

# ================================================================
# SEARCH
# ================================================================
cmd_search() {
  local query="$*"
  local entries
  entries="$(list_entries)"
  if command -v fzf >/dev/null 2>&1; then
    [ -n "$query" ] && echo "$entries" | fzf -f "$query" || echo "$entries" | fzf
  else
    [ -n "$query" ] && echo "$entries" | grep -i -- "$query" || true || echo "$entries"
  fi
}

# ================================================================
# LOGIN
# ================================================================
cmd_login() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "No entry selected"
  local user passw
  user=$(extract_field "$path" username)
  passw=$(extract_field "$path" password)
  [ -z "$user" ] && [ -z "$passw" ] && err "No username or password found for $path"
  printf "%s\n%s" "$user" "$passw" | copy_clipboard || err "Copy failed (no clipboard?)"
  echo "✔ Copied username and password for $path"
}

# ================================================================
# STRENGTH & ROTATE
# ================================================================
cmd_strength() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx strength <path>"
  local pw len u l n s score
  pw=$(extract_field "$path" password)
  [ -z "$pw" ] && err "No password found for $path"
  len=${#pw}
  u=$(printf "%s" "$pw" | grep -q '[A-Z]' && echo 1 || echo 0)
  l=$(printf "%s" "$pw" | grep -q '[a-z]' && echo 1 || echo 0)
  n=$(printf "%s" "$pw" | grep -q '[0-9]' && echo 1 || echo 0)
  s=$(printf "%s" "$pw" | grep -q '[^A-Za-z0-9]' && echo 1 || echo 0)
  score=$((u + l + n + s))
  echo "Password length : $len"
  echo "Complexity      : upper=$u lower=$l digits=$n symbols=$s"
  echo "Strength score  : $score / 4"
  if [ "$len" -lt 12 ] || [ "$score" -lt 3 ]; then
    warn "Suggest rotating — short or low-complexity password."
  else
    echo "✔ Looks reasonably strong."
  fi
}

cmd_rotate() {
  local path="${1:-}" length="${2:-32}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx rotate <path> [length]"
  pass show "$path" >/dev/null 2>&1 || err "Path does not exist: $path"
  local newpass rest
  newpass=$(gen_password "$length")
  rest="$(pass show "$path" | tail -n +2)"
  { echo "$newpass"; printf "%s\n" "$rest"; } | pass insert -m -f "$path" || err "pass insert failed"
  printf "%s" "$newpass" | copy_clipboard || true
  echo "✔ Rotated password for $path (new password copied if clipboard available)"
  _autosync
}

# ================================================================
# RM & EDIT
# ================================================================
cmd_rm() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx rm <path>"
  printf "Are you sure you want to remove '%s'? [y/N]: " "$path" >&2
  read -r yn </dev/tty || true
  [ "${yn,,}" != "y" ] && { echo "Aborted."; return 0; }
  pass rm -r "$path" || err "pass rm failed for $path"
  _autosync
}

cmd_edit() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx edit <path>"
  local editor="${EDITOR:-${VISUAL:-}}"
  if [ -z "$editor" ]; then
    for e in vim vi nano; do command -v "$e" >/dev/null 2>&1 && { editor="$e"; break; }; done
  fi
  [ -z "${editor:-}" ] && err "No editor found; set \$EDITOR or install vim/vi/nano"
  env EDITOR="$editor" pass edit "$path" || err "pass edit failed for $path"
  _autosync
}

# ================================================================
# URL
# ================================================================
cmd_url() {
  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx url <path>"

  local entry url first_line
  entry="$(pass show "$path" 2>/dev/null || true)"
  url=$(printf "%s\n" "$entry" | awk -F': ' '/^url:/ {print $2; exit}')
  if [ -z "$url" ]; then
    first_line=$(printf "%s\n" "$entry" | sed -n '1p')
    printf "%s" "$first_line" | grep -qE '^https?://' && url="$first_line"
  fi

  if [ -z "$url" ]; then
    printf "No URL found in %s. Enter URL to save (empty to cancel): " "$path" >&2
    read -r newurl </dev/tty || newurl=""
    [ -z "$newurl" ] && { echo "Aborted."; return 0; }
    local tmp
    tmp="$(mktemp)"
    if pass show "$path" >/dev/null 2>&1; then
      pass show "$path" > "$tmp"
      awk '!/^url:/' "$tmp" > "${tmp}.new"
      printf "url: %s\n" "$newurl" >> "${tmp}.new"
      mv "${tmp}.new" "$tmp"
    else
      printf "url: %s\n" "$newurl" > "$tmp"
    fi
    pass insert -m -f "$path" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
    rm -f "$tmp"
    url="$newurl"
    echo "✔ Saved URL to $path"
  fi

  clipboard_available && { printf "%s" "$url" | copy_clipboard --silent || true; echo "✔ URL copied to clipboard"; } || echo "$url"
  command -v xdg-open >/dev/null 2>&1 && { xdg-open "$url" >/dev/null 2>&1 || true; echo "✔ Opened $url"; }
}

# ================================================================
# SSH KEY MANAGEMENT
# ================================================================
# Pass store layout for a key named "ssh/github":
#
#   ssh/github          ← metadata (key type, path, created date)
#   ssh/github-pub      ← full public key content  (plain text, GPG-encrypted by pass)
#   ssh/github-pvt      ← full private key content (GPG-encrypted by pass, access-guarded)
#
# The actual key files also live at ~/.ssh/<basename> and ~/.ssh/<basename>.pub
# as normal SSH keys would. passx stores copies inside pass for portability/backup.
# ================================================================

# Internal: store SSH key files into pass
# Usage: _ssh_store_keys <store-base> <private-key-path>
_ssh_store_keys() {
  local base="$1"          # e.g.  ssh/github
  local pvt_path="$2"      # e.g.  ~/.ssh/github_ed25519
  local pub_path="${pvt_path}.pub"

  [ ! -f "$pvt_path" ] && err "Private key not found: $pvt_path"
  [ ! -f "$pub_path" ] && err "Public key not found: $pub_path"

  echo "  Storing public key  → pass: ${base}-pub"
  pass insert -m -f "${base}-pub" < "$pub_path" \
    || err "Failed to store public key in pass"

  echo "  Storing private key → pass: ${base}-pvt"
  pass insert -m -f "${base}-pvt" < "$pvt_path" \
    || err "Failed to store private key in pass"
}

# Internal: store SSH metadata entry
_ssh_store_meta() {
  local base="$1" pvt_path="$2" created="$3" comment="${4:-}"
  {
    echo "ssh-key"
    echo "key: $pvt_path"
    echo "public: ${pvt_path}.pub"
    [ -n "$comment" ] && echo "comment: $comment"
    echo "created: $created"
    echo ""
    echo "--- Public key ---"
    cat "${pvt_path}.pub"
  } | pass insert -m -f "$base" || err "Failed to store SSH metadata in pass"
}

cmd_ssh_add() {
  local store_base="${1:-}"
  local ssh_dir="$HOME/.ssh"

  if [ -z "$store_base" ]; then
    printf "Pass store path for this SSH key (e.g. ssh/github): " >&2
    read -r store_base </dev/tty || true
    [ -z "$store_base" ] && err "No store path provided"
  fi

  debug "ssh-add: store_base=$store_base"

  # Ensure ssh-agent is running
  if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    warn "ssh-agent not running — starting one for this session..."
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || warn "Could not start ssh-agent (non-fatal)"
  fi

  # Action selection
  local action
  if command -v fzf >/dev/null 2>&1; then
    action=$(printf "Use existing SSH key\nCreate new SSH key\nCancel" \
      | fzf --prompt="SSH key action > " --height=20%) || action=""
  else
    echo "SSH Key Actions:"
    echo "  1) Use existing SSH key"
    echo "  2) Create new SSH key"
    echo "  3) Cancel"
    printf "Choice [1-3]: " >&2
    read -r c </dev/tty || c="3"
    case "$c" in
      1) action="Use existing SSH key" ;;
      2) action="Create new SSH key" ;;
      *) action="Cancel" ;;
    esac
  fi

  case "$action" in
    # -----------------------------------------------------------
    "Use existing SSH key")
      local key_list
      key_list=$(find "$ssh_dir" -maxdepth 1 -name '*.pub' 2>/dev/null \
        | sed 's|\.pub$||' | sort)
      [ -z "$key_list" ] && err "No SSH public keys found in $ssh_dir"

      local chosen_pvt
      if command -v fzf >/dev/null 2>&1; then
        chosen_pvt=$(echo "$key_list" | fzf --prompt="Select SSH key > ") || chosen_pvt=""
      else
        echo "Available keys:"
        local i=1
        while IFS= read -r k; do echo "  $i) $k"; ((i++)); done <<< "$key_list"
        printf "Select number: " >&2
        read -r n </dev/tty || n=""
        chosen_pvt=$(echo "$key_list" | sed -n "${n}p")
      fi
      [ -z "$chosen_pvt" ] && { echo "Aborted."; return 0; }

      echo ""
      echo "Selected key : $chosen_pvt"
      echo "Will be stored in pass as:"
      echo "  ${store_base}       (metadata + inline public key)"
      echo "  ${store_base}-pub   (public key file)"
      echo "  ${store_base}-pvt   (private key file — GPG-encrypted)"
      echo ""

      local created
      created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

      # Store key files in pass
      _ssh_store_keys "$store_base" "$chosen_pvt"

      # Store metadata
      local comment
      comment=$(ssh-keygen -l -f "${chosen_pvt}.pub" 2>/dev/null | awk '{$1=$2=""; print $0}' | sed 's/^ *//' || echo "")
      _ssh_store_meta "$store_base" "$chosen_pvt" "$created" "$comment"

      # Add to agent
      echo "  Adding to ssh-agent..."
      ssh-add "$chosen_pvt" || warn "ssh-add failed (check passphrase)"

      echo ""
      echo "✔ SSH key stored in pass and added to agent:"
      echo "  ${store_base}       — metadata"
      echo "  ${store_base}-pub   — public key"
      echo "  ${store_base}-pvt   — private key"
      ;;

    # -----------------------------------------------------------
    "Create new SSH key")
      printf "Key filename (stored in ~/.ssh/<name>): " >&2
      read -r key_name </dev/tty || key_name=""
      [ -z "$key_name" ] && err "No key name provided"

      printf "Comment / email (optional): " >&2
      read -r key_comment </dev/tty || key_comment=""

      local pvt_path="$ssh_dir/$key_name"
      [ -f "$pvt_path" ] && err "Key already exists: $pvt_path  (remove it first)"

      mkdir -p "$ssh_dir"
      chmod 700 "$ssh_dir"

      echo "Generating ed25519 key → $pvt_path"
      if [ -n "$key_comment" ]; then
        ssh-keygen -t ed25519 -a 100 -f "$pvt_path" -C "$key_comment" || err "ssh-keygen failed"
      else
        ssh-keygen -t ed25519 -a 100 -f "$pvt_path" || err "ssh-keygen failed"
      fi
      # Ensure correct permissions
      chmod 600 "$pvt_path"
      chmod 644 "${pvt_path}.pub"

      echo ""
      echo "Generated key files:"
      echo "  Private : $pvt_path"
      echo "  Public  : ${pvt_path}.pub"
      echo ""
      echo "Storing in pass as:"
      echo "  ${store_base}       (metadata + inline public key)"
      echo "  ${store_base}-pub   (public key)"
      echo "  ${store_base}-pvt   (private key — GPG-encrypted)"
      echo ""

      local created
      created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

      _ssh_store_keys "$store_base" "$pvt_path"
      _ssh_store_meta "$store_base" "$pvt_path" "$created" "$key_comment"

      echo "  Adding to ssh-agent..."
      ssh-add "$pvt_path" || warn "ssh-add failed (check passphrase)"

      echo ""
      echo "✔ SSH key created, stored in pass, and added to agent:"
      echo "  ${store_base}       — metadata"
      echo "  ${store_base}-pub   — public key"
      echo "  ${store_base}-pvt   — private key"
      echo ""
      echo "Public key (paste this to authorised_keys / GitHub / etc.):"
      cat "${pvt_path}.pub"
      ;;

    *)
      echo "Cancelled."
      ;;
  esac
  _autosync
}

# ================================================================
# GPG KEY MANAGEMENT
# ================================================================
# Pass store layout for a key named "gpg/work":
#
#   gpg/work          ← metadata (keyid, uid, email, created)
#   gpg/work-pub      ← armored public key  (plain text, GPG-encrypted by pass)
#   gpg/work-pvt      ← armored private key (GPG-encrypted by pass, access-guarded)
#
# The key also remains in the GPG keyring as normal.
# ================================================================

# Internal: export and store a GPG key pair in pass
# Usage: _gpg_store_keys <store-base> <keyid>
_gpg_store_keys() {
  local base="$1" keyid="$2"

  echo "  Exporting public key  → pass: ${base}-pub"
  gpg --export --armor "$keyid" 2>/dev/null \
    | pass insert -m -f "${base}-pub" \
    || err "Failed to store GPG public key in pass"

  echo "  Exporting private key → pass: ${base}-pvt"
  warn "GPG will ask for your key passphrase to export the private key."
  gpg --export-secret-keys --armor "$keyid" 2>/dev/null \
    | pass insert -m -f "${base}-pvt" \
    || err "Failed to store GPG private key in pass"
}

# Internal: store GPG metadata
_gpg_store_meta() {
  local base="$1" keyid="$2" uid="$3" email="${4:-}" created="$5"
  {
    echo "gpg-key"
    echo "keyid: $keyid"
    echo "uid: $uid"
    [ -n "$email" ] && echo "email: $email"
    echo "created: $created"
    echo ""
    echo "--- Public key fingerprint ---"
    gpg --fingerprint "$keyid" 2>/dev/null || true
  } | pass insert -m -f "$base" || err "Failed to store GPG metadata in pass"
}

cmd_gpg_add() {
  local store_base="${1:-}"
  command -v gpg >/dev/null 2>&1 || err "gpg is required for gpg-add"

  if [ -z "$store_base" ]; then
    printf "Pass store path for this GPG key (e.g. gpg/work): " >&2
    read -r store_base </dev/tty || true
    [ -z "$store_base" ] && err "No store path provided"
  fi

  debug "gpg-add: store_base=$store_base"

  # List secret keys for display
  local key_list
  key_list=$(gpg --list-secret-keys --with-colons 2>/dev/null \
    | awk -F: '
        /^sec/ { id=$5 }
        /^uid/ { print id " | " $10 }
      ' | sort -u)

  local action
  if command -v fzf >/dev/null 2>&1; then
    action=$(printf "Use existing GPG key\nCreate new GPG key\nCancel" \
      | fzf --prompt="GPG key action > " --height=20%) || action=""
  else
    echo "GPG Key Actions:"
    echo "  1) Use existing GPG key"
    echo "  2) Create new GPG key"
    echo "  3) Cancel"
    printf "Choice [1-3]: " >&2
    read -r c </dev/tty || c="3"
    case "$c" in
      1) action="Use existing GPG key" ;;
      2) action="Create new GPG key" ;;
      *) action="Cancel" ;;
    esac
  fi

  case "$action" in
    # -----------------------------------------------------------
    "Use existing GPG key")
      [ -z "$key_list" ] && err "No GPG secret keys found in keyring. Create one first."

      local chosen_line chosen_id chosen_uid
      if command -v fzf >/dev/null 2>&1; then
        chosen_line=$(echo "$key_list" | fzf --prompt="Select GPG key > ") || chosen_line=""
      else
        echo "Available secret keys:"
        local i=1
        while IFS= read -r k; do echo "  $i) $k"; ((i++)); done <<< "$key_list"
        printf "Select number: " >&2
        read -r n </dev/tty || n=""
        chosen_line=$(echo "$key_list" | sed -n "${n}p")
      fi
      [ -z "$chosen_line" ] && { echo "Aborted."; return 0; }

      chosen_id=$(echo "$chosen_line" | awk -F' | ' '{print $1}' | xargs)
      chosen_uid=$(echo "$chosen_line" | awk -F' | ' '{print $2}' | xargs)
      local email
      email=$(printf "%s" "$chosen_uid" | grep -oE '[^< >]+@[^< >]+' | head -1 || echo "")

      echo ""
      echo "Selected key : $chosen_uid  ($chosen_id)"
      echo "Will be stored in pass as:"
      echo "  ${store_base}       (metadata + fingerprint)"
      echo "  ${store_base}-pub   (armored public key)"
      echo "  ${store_base}-pvt   (armored private key — GPG-encrypted)"
      echo ""

      local created
      created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

      _gpg_store_keys "$store_base" "$chosen_id"
      _gpg_store_meta "$store_base" "$chosen_id" "$chosen_uid" "$email" "$created"

      echo ""
      echo "✔ GPG key exported and stored in pass:"
      echo "  ${store_base}       — metadata"
      echo "  ${store_base}-pub   — public key"
      echo "  ${store_base}-pvt   — private key"
      ;;

    # -----------------------------------------------------------
    "Create new GPG key")
      echo "Launching gpg interactive key generation..."
      echo "(Recommended: ECC ed25519/cv25519 for sign+encrypt)"
      echo ""
      gpg --full-generate-key || err "gpg key generation failed"

      # Grab the newest key id and uid
      local new_id new_uid email created
      new_id=$(gpg --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^sec/ {id=$5} END {print id}')
      new_uid=$(gpg --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^uid/ {uid=$10} END {print uid}')
      email=$(printf "%s" "$new_uid" | grep -oE '[^< >]+@[^< >]+' | head -1 || echo "")
      created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

      echo ""
      echo "New key: $new_uid  ($new_id)"
      echo "Storing in pass as:"
      echo "  ${store_base}       (metadata + fingerprint)"
      echo "  ${store_base}-pub   (armored public key)"
      echo "  ${store_base}-pvt   (armored private key — GPG-encrypted)"
      echo ""

      _gpg_store_keys "$store_base" "$new_id"
      _gpg_store_meta "$store_base" "$new_id" "$new_uid" "$email" "$created"

      echo ""
      echo "✔ GPG key created and stored in pass:"
      echo "  ${store_base}       — metadata"
      echo "  ${store_base}-pub   — public key"
      echo "  ${store_base}-pvt   — private key"
      echo ""
      echo "Public key (armored — safe to share):"
      gpg --export --armor "$new_id" 2>/dev/null || true
      ;;

    *)
      echo "Cancelled."
      ;;
  esac
  _autosync
}

# ================================================================
# DOCTOR
# ================================================================
cmd_doctor() {
  local required=(pass gpg)
  local recommended=(fzf xdotool xclip wl-copy xdg-open ssh-agent oathtool)
  local otp_tools=(qrencode zbarimg)

  echo "=== passx doctor ==="
  echo
  echo "Required dependencies:"
  for d in "${required[@]}"; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ✔ %-14s %s\n" "$d" "$(command -v "$d")" \
      || printf "  ✖ %-14s MISSING\n" "$d"
  done

  echo
  echo "Recommended tools:"
  for d in "${recommended[@]}"; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ✔ %-14s %s\n" "$d" "$(command -v "$d")" \
      || printf "  ✖ %-14s missing (optional)\n" "$d"
  done

  echo
  echo "OTP / QR tools:"
  for d in "${otp_tools[@]}"; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ✔ %-14s %s\n" "$d" "$(command -v "$d")" \
      || printf "  ✖ %-14s missing (optional)\n" "$d"
  done

  echo
  echo "Environment:"
  printf "  PASSWORD_STORE_DIR  %s\n" "$PASSWORD_STORE_DIR"
  printf "  PASSX_AUTOSYNC      %s\n" "$PASSX_AUTOSYNC"
  printf "  PASSX_CLIP_TIMEOUT  %ss\n" "$PASSX_CLIP_TIMEOUT"
  printf "  PASSX_DEBUG         %s\n" "$PASSX_DEBUG"

  echo
  echo "Store:"
  if [ -d "$PASSWORD_STORE_DIR" ]; then
    local count
    count=$(find "$PASSWORD_STORE_DIR" -name '*.gpg' 2>/dev/null | wc -l)
    printf "  ✔ Store exists (%s encrypted entries)\n" "$count"
    [ -d "$PASSWORD_STORE_DIR/.git" ] \
      && echo "  ✔ Git sync enabled" \
      || echo "  ✖ Git sync not configured (pass git init)"
  else
    printf "  ✖ Store not found at %s\n" "$PASSWORD_STORE_DIR"
  fi

  echo
  echo "Clipboard:"
  clipboard_available && echo "  ✔ Clipboard available" || echo "  ✖ No clipboard backend found"
}

# ================================================================
# RECENT, STATS, BACKUP
# ================================================================
cmd_recent() {
  local n="${1:-10}"
  find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n "$n" | sed "s|^.* $PASSWORD_STORE_DIR/||; s|\.gpg$||"
}

cmd_stats() {
  local entries otps ssh_keys gpg_keys folders
  entries=$(find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null | wc -l)
  otps=$(grep -RIl --exclude-dir='.git' -e '^otpauth://' -e '^otp:' \
    "$PASSWORD_STORE_DIR" 2>/dev/null | wc -l || true)
  ssh_keys=$(find "$PASSWORD_STORE_DIR" -type f -name '*-pub.gpg' 2>/dev/null | wc -l)
  gpg_keys=$(grep -Rl --exclude-dir='.git' '^keyid:' "$PASSWORD_STORE_DIR" 2>/dev/null | wc -l || true)
  folders=$(find "$PASSWORD_STORE_DIR" -type d 2>/dev/null | wc -l)
  echo "Total entries        : $entries"
  echo "OTP-enabled          : $otps"
  echo "SSH/GPG pub keys     : $ssh_keys"
  echo "GPG metadata entries : $gpg_keys"
  echo "Folders (incl. root) : $folders"
}

cmd_backup() {
  local out="${1:-}"
  [ -z "$out" ] && err "Usage: passx backup <file.gpg>"
  command -v gpg >/dev/null 2>&1 || err "gpg required for backup"
  local tmp
  tmp="$(mktemp -d)"
  tar -C "$(dirname "$PASSWORD_STORE_DIR")" -czf "$tmp/store.tar.gz" \
    "$(basename "$PASSWORD_STORE_DIR")" || { rm -rf "$tmp"; err "tar failed"; }
  gpg -c -o "$out" "$tmp/store.tar.gz" || { rm -rf "$tmp"; err "gpg encryption failed"; }
  rm -rf "$tmp"
  echo "✔ Encrypted backup written to $out"
}

# ================================================================
# UI (fzf control panel)
# ================================================================
cmd_ui() {
  command -v fzf >/dev/null 2>&1 || err "fzf required for ui"
  local entry
  entry="$(list_entries | fzf --prompt="passx: pick entry > ")" || return 0
  [ -z "$entry" ] && return 0

  # Build contextual action list
  local actions
  if _is_pvt_path "$entry"; then
    actions=$'show private key\ncopy private key\nedit\nremove'
  elif [[ "$entry" == *-pub ]]; then
    actions=$'show public key\ncopy public key\nedit\nremove'
  else
    actions=$'copy password\ncopy username\nshow entry\notp\notp-show\notp-qr\nedit\nremove\nopen url\nrotate password\nlogin (copy user+pass)\nfill (autotype)\nsync'
  fi

  local action
  action="$(printf "%s\n" "$actions" | fzf --prompt="action > " --height=25%)" || return 0
  [ -z "$action" ] && return 0

  case "$action" in
    "copy password")           extract_field "$entry" password | tr -d '\n' | copy_clipboard --silent ;;
    "copy username")           extract_field "$entry" username | tr -d '\n' | copy_clipboard --silent ;;
    "show entry")              pass show "$entry" ;;
    "show public key")         pass show "$entry" ;;
    "show private key")        _confirm_pvt_access "$entry"; pass show "$entry" ;;
    "copy public key")         pass show "$entry" | copy_clipboard ;;
    "copy private key")        _confirm_pvt_access "$entry"; pass show "$entry" | copy_clipboard ;;
    "otp")                     cmd_otp "$entry" ;;
    "otp-show")                cmd_otp_show "$entry" ;;
    "otp-qr")                  cmd_otp_qr "$entry" ;;
    "edit")                    cmd_edit "$entry" ;;
    "remove")                  cmd_rm "$entry" ;;
    "open url")                cmd_url "$entry" ;;
    "rotate password")
      printf "Password length (default 32): " >&2
      read -r length </dev/tty || length="32"
      cmd_rotate "$entry" "${length:-32}"
      ;;
    "login (copy user+pass)")  cmd_login "$entry" ;;
    "fill (autotype)")         cmd_fill "$entry" ;;
    "sync")                    cmd_sync ;;
    *)                         echo "Unknown action" ;;
  esac
}

# ================================================================
# FILL (xdotool autotype)
# ================================================================
cmd_fill() {
  local enter_after=false
  [ "${1:-}" = "-e" ] && { enter_after=true; shift; }

  local path="${1:-}"
  [ -z "$path" ] && path="$(pick_entry || true)"
  [ -z "$path" ] && err "Usage: passx fill <path> [-e]"
  command -v xdotool >/dev/null 2>&1 || err "xdotool required for fill; install xdotool"

  local user passw
  user=$(extract_field "$path" username || true)
  passw=$(extract_field "$path" password || true)
  [ -z "${user:-}" ] && [ -z "${passw:-}" ] && err "No username/password found for $path"

  [ -n "${user:-}" ] && { xdotool type --delay 25 --clearmodifiers "$user"; sleep 0.08; }
  xdotool key --clearmodifiers Tab; sleep 0.08
  [ -n "${passw:-}" ] && { xdotool type --delay 20 --clearmodifiers "$passw"; sleep 0.08; }
  $enter_after && xdotool key --clearmodifiers Return
}

# ================================================================
# HELP
# ================================================================
cmd_help() {
  cat <<'EOF'
NAME
    passx — power-user wrapper around 'pass'

SYNOPSIS
    passx [COMMAND] [ARGS...]

DESCRIPTION
    passx extends 'pass' with interactive search (fzf), OTP helpers, git sync,
    SSH/GPG key management with full file storage inside pass, private-key
    access protection, auto-fill (xdotool), and more.
    Most commands accept an optional path; when omitted an interactive picker appears.

KEY STORAGE MODEL
    When you run ssh-add or gpg-add, passx creates three pass entries:

      ssh/github          ← metadata + inline public key
      ssh/github-pub      ← full public key  (safe to show/copy freely)
      ssh/github-pvt      ← full private key (GPG-encrypted; access requires confirmation)

    The real key files also remain at their normal locations:
      ~/.ssh/<name>  and  ~/.ssh/<name>.pub   (for SSH)
      GPG keyring                              (for GPG)

COMMANDS
  Password management:
    add <path> [email] [user] [notes] [len]   Generate & store a new password
    show <path> [-p|-u|-e|-n|-f]              Print a field (-p pass -u user -e email)
    copy <path> [-p|-u|-e|-n]                 Copy a field to clipboard
    pick                                       Interactive entry picker (fzf)
    rotate <path> [length]                     Rotate password (copies new one)
    strength <path>                            Report password strength
    rm <path>                                  Remove entry (with confirmation)
    edit <path>                                Edit entry in $EDITOR

  SSH / GPG keys (show & copy also work for -pub and -pvt entries):
    ssh-add [store-path]                       Add/create SSH key → stores in pass
    gpg-add [store-path]                       Add/create GPG key → stores in pass

    passx show  ssh/github-pub                 Show SSH public key
    passx show  ssh/github-pvt                 Show SSH private key (asks confirmation)
    passx copy  ssh/github-pub                 Copy SSH public key to clipboard
    passx copy  ssh/github-pvt                 Copy SSH private key (asks confirmation)
    passx show  gpg/work-pub                   Show GPG armored public key
    passx show  gpg/work-pvt                   Show GPG armored private key (guarded)
    passx copy  gpg/work-pub                   Copy GPG public key to clipboard
    passx copy  gpg/work-pvt                   Copy GPG private key (guarded)

  Search / UI:
    search [query]                             fzf search (filter with query)
    ui                                         Full fzf control panel

  OTP:
    otp <path> [-n]                            Print & copy OTP (-n = no copy)
    otp-show <path>                            Live OTP with countdown
    otp-import <path> <qr.png>                Import OTP from QR image
    otp-export <path> [--qr <file.png>]       Export OTP URI or QR
    otp-qr <path>                              Display OTP QR in terminal

  Automation:
    fill <path> [-e]                           Autotype user<TAB>pass (xdotool)
    login <path>                               Copy username+password to clipboard
    url <path>                                 Copy & open URL

  Utilities:
    sync                                       git pull + push password store
    doctor                                     Check dependencies & configuration
    recent [N]                                 Show N most recently modified entries
    stats                                      Show store statistics
    backup <file.gpg>                          Encrypted backup of entire store

PRIVATE KEY PROTECTION
    Any entry whose name ends in -pvt (e.g. ssh/github-pvt, gpg/work-pvt)
    triggers a confirmation prompt before passx will show or copy its contents.
    The data itself is always protected by GPG (as all pass entries are).

ENVIRONMENT
    PASSWORD_STORE_DIR    default: $HOME/.password-store
    PASSX_AUTOSYNC        true | false (default: false) — auto push after changes
    PASSX_CLIP_TIMEOUT    seconds before clipboard is cleared (default: 20)
    PASSX_DEBUG           1 = enable debug logging to ~/.cache/passx/log
    EDITOR / VISUAL       editor used by 'passx edit'

EXAMPLES
    passx add work/github user@example.com myusername
    passx copy work/github -u             # copy username
    passx ssh-add ssh/github              # interactive SSH key setup
    passx show ssh/github-pub             # print public key
    passx copy ssh/github-pvt             # copy private key (asks confirmation)
    passx gpg-add gpg/work               # interactive GPG key setup
    passx show gpg/work-pub              # print armored public key
    passx copy gpg/work-pvt              # copy armored private key (guarded)
    passx otp work/github                # print & copy OTP
    passx fill work/github -e            # autotype + Enter
    passx sync                           # git pull + push
    passx ui                             # full control panel
    PASSX_AUTOSYNC=true passx rotate work/github
EOF
}

# ================================================================
# DEFAULT: pass ls if no args
# ================================================================
if [ "${1:-}" = "" ]; then
  command -v pass >/dev/null 2>&1 && { pass ls; exit $?; } || { cmd_help; exit 0; }
fi

# ================================================================
# DISPATCHER
# ================================================================
case "${1:-}" in
  -h|--help|help)  cmd_help ;;
  add)             shift; cmd_add "$@" ;;
  show)            shift; cmd_show_copy show "$@" ;;
  copy)            shift; cmd_show_copy copy "$@" ;;
  pick)            pick_entry ;;
  ui)              cmd_ui ;;
  otp)             shift; cmd_otp "$@" ;;
  otp-show)        shift; cmd_otp_show "$@" ;;
  otp-import)      shift; cmd_otp_import "$@" ;;
  otp-export)      shift; cmd_otp_export "$@" ;;
  otp-qr)          shift; cmd_otp_qr "$@" ;;
  search)          shift; cmd_search "$@" ;;
  login)           shift; cmd_login "$@" ;;
  rotate)          shift; cmd_rotate "$@" ;;
  strength)        shift; cmd_strength "$@" ;;
  rm)              shift; cmd_rm "$@" ;;
  edit)            shift; cmd_edit "$@" ;;
  doctor)          cmd_doctor ;;
  url)             shift; cmd_url "$@" ;;
  recent)          shift; cmd_recent "$@" ;;
  stats)           cmd_stats ;;
  backup)          shift; cmd_backup "$@" ;;
  fill)            shift; cmd_fill "$@" ;;
  sync)            cmd_sync ;;
  ssh-add)         shift; cmd_ssh_add "$@" ;;
  gpg-add)         shift; cmd_gpg_add "$@" ;;
  *)
    printf "❌ Unknown command: %s\n" "$1" >&2
    printf "Run: passx -h for help\n" >&2
    exit 1
    ;;
esac

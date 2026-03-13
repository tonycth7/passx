#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  passx  —  power-user wrapper around 'pass'                    ║
# ║  Version: 1.0.0                                                ║
# ╚════════════════════════════════════════════════════════════════╝
set -euo pipefail
PASSX_VERSION="1.0.0"

# ════════════════════════════════════════════════════════════════
# § THEME / COLORS
# ════════════════════════════════════════════════════════════════
_init_colors() {
  if [ ! -t 1 ] && [ "${PASSX_COLOR:-auto}" != "always" ]; then
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
    C_MAGENTA=''; C_BOLD=''; C_DIM=''; C_RESET=''; C_WHITE=''; C_ITALIC=''
    return
  fi
  case "${PASSX_THEME:-catppuccin}" in
    catppuccin)
      C_RED=$'\033[38;5;203m';    C_GREEN=$'\033[38;5;151m'
      C_YELLOW=$'\033[38;5;222m'; C_BLUE=$'\033[38;5;110m'
      C_CYAN=$'\033[38;5;117m';   C_MAGENTA=$'\033[38;5;183m';;
    nord)
      C_RED=$'\033[38;5;131m';    C_GREEN=$'\033[38;5;108m'
      C_YELLOW=$'\033[38;5;179m'; C_BLUE=$'\033[38;5;67m'
      C_CYAN=$'\033[38;5;110m';   C_MAGENTA=$'\033[38;5;139m' ;;
    gruvbox)
      C_RED=$'\033[38;5;167m';    C_GREEN=$'\033[38;5;142m'
      C_YELLOW=$'\033[38;5;214m'; C_BLUE=$'\033[38;5;109m'
      C_CYAN=$'\033[38;5;108m';   C_MAGENTA=$'\033[38;5;175m' ;;
    dracula)
      C_RED=$'\033[38;5;203m';    C_GREEN=$'\033[38;5;84m'
      C_YELLOW=$'\033[38;5;228m'; C_BLUE=$'\033[38;5;61m'
      C_CYAN=$'\033[38;5;117m';   C_MAGENTA=$'\033[38;5;212m' ;;
    solarized)
      C_RED=$'\033[38;5;160m';    C_GREEN=$'\033[38;5;64m'
      C_YELLOW=$'\033[38;5;136m'; C_BLUE=$'\033[38;5;33m'
      C_CYAN=$'\033[38;5;37m';    C_MAGENTA=$'\033[38;5;125m' ;;
    *)  
  esac
  C_WHITE=$'\033[0;37m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_ITALIC=$'\033[3m';   C_RESET=$'\033[0m'
}
_init_colors

# ════════════════════════════════════════════════════════════════
# § CONFIGURATION
# ════════════════════════════════════════════════════════════════
PASSX_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/passx"
PASSX_HOOKS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx/hooks"
PASSX_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx"
PASSX_LOG="$PASSX_CACHE_DIR/log"

# Load config if present (prefer passx/passx.conf over root passx.conf)
if [ -f "$PASSX_CONF_DIR/passx.conf" ]; then
  source "$PASSX_CONF_DIR/passx.conf"
elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/passx.conf" ]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/passx.conf"
fi

# Apply defaults for anything not set (allows config or env to override)
: "${PASSWORD_STORE_DIR:=$HOME/.password-store}"
: "${PASSX_AUTOSYNC:=false}"
: "${PASSX_CLIP_TIMEOUT:=20}"
: "${PASSX_MAX_AGE:=180}"
: "${PASSX_NOTIFY:=true}"
: "${PASSX_DEBUG:=0}"
: "${PASSX_THEME:=catppuccin}"
: "${PASSX_COLOR:=auto}"
: "${PASSX_GEN_LENGTH:=32}"
: "${PASSX_GEN_CHARS:=A-Za-z0-9@#%+=_}"
: "${PASSX_JSON:=0}"

_init_colors  # re-run in case PASSX_THEME was changed by config

# ════════════════════════════════════════════════════════════════
# § PRINT HELPERS
# ════════════════════════════════════════════════════════════════
_cmd=""  # set per command for contextual errors

err()  {
  printf "\n${C_RED}${C_BOLD}  ✖  %s${C_RESET}\n" "$1" >&2
  [ -n "${_cmd:-}" ] && printf "  ${C_DIM}Try: passx %s --help${C_RESET}\n\n" "$_cmd" >&2
  exit "${2:-1}"
}
warn() { printf "${C_YELLOW}  ⚠  %s${C_RESET}\n" "$*" >&2; }
ok()   { printf "${C_GREEN}  ✔  %s${C_RESET}\n" "$*"; }
info() { printf "${C_CYAN}  ℹ  %s${C_RESET}\n" "$*"; }
step() { printf "${C_BLUE}  →  %s${C_RESET}\n" "$*"; }
fail() { printf "${C_RED}  ✖  %s${C_RESET}\n" "$*" >&2; }
dim()  { printf "${C_DIM}     %s${C_RESET}\n" "$*"; }

debug() {
  [ "$PASSX_DEBUG" = "1" ] || return 0
  mkdir -p "$PASSX_CACHE_DIR"
  printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" >> "$PASSX_LOG"
}

_notify() {
  [ "$PASSX_NOTIFY" = "true" ] || return 0
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a passx -t 3000 -i dialog-password "${1:-passx}" "${2:-}" 2>/dev/null || true
}

_banner() {
  local t="$1" w=54 p
  p=$(( (w - ${#t}) / 2 ))
  printf "\n${C_BOLD}${C_CYAN}"
  printf "  ╔"; printf '═%.0s' $(seq 1 $w); printf "╗\n"
  printf "  ║%*s%s%*s║\n" $p "" "$t" $((w - p - ${#t})) ""
  printf "  ╚"; printf '═%.0s' $(seq 1 $w); printf "╝\n"
  printf "${C_RESET}\n"
}

_section() {
  local t="$1"
  printf "\n  ${C_BOLD}${C_CYAN}%s${C_RESET}\n" "$t"
  printf "  ${C_DIM}"; printf '─%.0s' $(seq 1 $((${#t}+2))); printf "${C_RESET}\n"
}

_json_kv() {
  local out="{" first=1
  while [ "$#" -ge 2 ]; do
    local k="$1" v="$2"; shift 2
    [ $first -eq 0 ] && out+=","
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    out+="\"$k\":\"$v\""
    first=0
  done
  printf "%s}\n" "$out"
}

# ════════════════════════════════════════════════════════════════
# § PRIVATE KEY GUARD
# ════════════════════════════════════════════════════════════════
_is_pvt() { [[ "${1:-}" == *-pvt ]]; }

_guard_pvt() {
  local path="$1"
  printf "\n${C_YELLOW}${C_BOLD}"
  printf "  ╔═══════════════════════════════════════════════╗\n"
  printf "  ║  🔐  PRIVATE KEY  —  confirm access           ║\n"
  printf "  ╚═══════════════════════════════════════════════╝\n"
  printf "${C_RESET}  ${C_BOLD}Entry${C_RESET}: %s\n" "$path"
  printf "  ${C_DIM}GPG decryption required.${C_RESET}\n\n"
  printf "  Continue? [y/N] " >&2
  local yn; read -r yn </dev/tty 2>/dev/null || yn=""
  [[ "${yn,,}" == "y" ]] || { printf "\n  ${C_DIM}Aborted.${C_RESET}\n" >&2; exit 0; }
}

# ════════════════════════════════════════════════════════════════
# § CLIPBOARD
# ════════════════════════════════════════════════════════════════
clipboard_available() {
  command -v wl-copy  >/dev/null 2>&1 && return 0
  command -v clip.exe >/dev/null 2>&1 && return 0
  { command -v xclip  >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; } && return 0
  return 1
}

copy_clipboard() {
  local silent=false
  [ "${1:-}" = "--silent" ] && silent=true

  if command -v wl-copy >/dev/null 2>&1; then
    $silent && wl-copy || { wl-copy && ok "Copied (Wayland)" || { warn "wl-copy failed"; return 1; }; }
    _clip_clear_later; return 0
  fi
  if command -v clip.exe >/dev/null 2>&1; then
    $silent && clip.exe || { clip.exe && ok "Copied (Windows)" || { warn "clip.exe failed"; return 1; }; }
    return 0
  fi
  if command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    $silent && xclip -selection clipboard \
             || { xclip -selection clipboard && ok "Copied (X11)" || { warn "xclip failed"; return 1; }; }
    _clip_clear_later; return 0
  fi
  $silent || { cat; warn "No clipboard backend (printed above)"; }
  return 1
}

_clip_clear_later() {
  local t="$PASSX_CLIP_TIMEOUT"
  debug "clip-clear in ${t}s"
  ( sleep "$t"
    { command -v wl-copy >/dev/null 2>&1 && printf "" | wl-copy 2>/dev/null; } || \
    { command -v xclip   >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ] \
        && printf "" | xclip -selection clipboard 2>/dev/null; } || true
    _notify "passx" "Clipboard cleared after ${t}s"
    debug "clip cleared"
  ) &
  disown 2>/dev/null || true
  dim "Clipboard auto-clears in ${t}s"
}

cmd_lock() {
  _cmd="lock"
  step "Clearing clipboard..."
  { command -v wl-copy >/dev/null 2>&1 && printf "" | wl-copy  2>/dev/null; } || \
  { command -v xclip   >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ] \
      && printf "" | xclip -selection clipboard 2>/dev/null; } || true
  ok "Clipboard cleared"
  _notify passx "Clipboard cleared"
}

# ════════════════════════════════════════════════════════════════
# § ENTRY LISTING
# ════════════════════════════════════════════════════════════════
list_entries() {
  if pass ls --flat >/dev/null 2>&1; then
    pass ls --flat 2>/dev/null | sort
  else
    find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
      | sed "s|^$PASSWORD_STORE_DIR/||; s|\.gpg$||" | sort
  fi
}

# ════════════════════════════════════════════════════════════════
# § FZF HELPERS
# ════════════════════════════════════════════════════════════════
_fzf_flags() {
  printf "%s" "--pointer=▶ --marker=✓ --layout=reverse --border=rounded --info=inline"
}

_fzf_colors() {
  case "${PASSX_THEME:-catppuccin}" in
    catppuccin)printf "%s" "--color=border:#94e2d5,prompt:#cba6f7,pointer:#f5e0dc,marker:#a6e3a1,header:#89b4fa" ;;
    nord)      printf "%s" "--color=border:#5e81ac,prompt:#81a1c1,pointer:#b48ead,marker:#a3be8c,header:#88c0d0" ;;
    gruvbox)   printf "%s" "--color=border:#689d6a,prompt:#458588,pointer:#d3869b,marker:#b8bb26,header:#83a598" ;;
    dracula)   printf "%s" "--color=border:#6272a4,prompt:#8be9fd,pointer:#ff79c6,marker:#50fa7b,header:#bd93f9" ;;
    solarized) printf "%s" "--color=border:#268bd2,prompt:#2aa198,pointer:#d33682,marker:#859900,header:#6c71c4" ;;
    *)         printf "%s" "--color=border:#6c71c4,prompt:#268bd2,pointer:#d33682,marker:#2aa198,header:#859900" ;;
  esac
}

_fzf_pick() {
  local prompt="${1:-pick}" header="${2:-}" height="${3:-50%}"
  fzf --prompt="  ${prompt} ❯ " \
      --header="  ${header}" \
      --height="$height" \
      $(_fzf_flags) $(_fzf_colors) 2>/dev/null
}

_preview_script() {
  bat <<'PREV'
bash -c '
p="$1"
e=$(pass show "$p" 2>/dev/null) || { printf "\n  \033[31m(decrypt failed)\033[0m\n"; exit; }
printf "\n  \033[1mEntry\033[0m: %s\n" "$p"
printf "  \033[2m──────────────────────────────────────────\033[0m\n\n"
_f() { local v; v=$(printf "%s\n" "$e" | grep -m1 "^$1:" | sed "s/^$1: *//"); [ -n "$v" ] && printf "  \033[36m%-10s\033[0m %s\n" "$1" "$v"; }
_f username; _f email; _f url; _f notes; _f host; _f token
printf "%s\n" "$e"|grep -q "^otp:\|^otpauth" && printf "  \033[35m%-10s\033[0m %s\n" "otp" "● configured"
printf "%s\n" "$e"|grep -q "^-----BEGIN" && printf "  \033[33m%-10s\033[0m %s\n" "type" "🔑 key data"
printf "  \033[2m%-10s\033[0m %s\n" "password" "●●●●●●●●"
printf "\n"
' _ {}
PREV
}

# ════════════════════════════════════════════════════════════════
# § PASSWORD GENERATOR
# ════════════════════════════════════════════════════════════════
gen_password() {
  local length="${1:-$PASSX_GEN_LENGTH}"
  local chars="${PASSX_GEN_CHARS:-A-Za-z0-9@#%+=_}"
  local pw
  pw=$(set +o pipefail; LC_ALL=C tr -dc "$chars" </dev/urandom 2>/dev/null | head -c "$length"; true)
  printf "%s" "$pw"
}

_gen_words() {
  local count="${1:-4}"
  local wl=""
  for f in /usr/share/dict/words /usr/share/dict/american-english \
            /usr/share/dict/british-english /usr/dict/words; do
    [ -f "$f" ] && { wl="$f"; break; }
  done
  if [ -n "$wl" ]; then
    grep -E '^[a-z]{4,8}$' "$wl" 2>/dev/null | shuf -n "$count" | tr '\n' '-' | sed 's/-$//'
  else
    local -a W=( apple breeze cactus dune echo fossil glitch hollow ivory jigsaw kite lunar mist nebula oasis pulse quartz rhythm solar tulip urban vortex willow xylem yacht zenith amber beacon chasm drift embers flint gully harbor island jungle knoll lagoon meadow nomad ocean peak quiver ridge summit tundra valley wharf abyss bluff canyon delta estuary fjord geyser haven inlet jetty kelp ledge marsh narrows outcrop plateau quagmire reef shoal tarn upland veldt wynd acorn birch cedar dahlia elm fern gorse hazel iris juniper lark maple nettle oak pine quince rowan spruce thistle ulex vine walnut yarrow zinnia atlas brooch canvas dial enamel flask gavel hinge ink jar key loom mask needle oar pane quill rope sieve torch urn vial wick yoke anvil bolt clamp drill edge file grit hammer iron joint knob lathe mesh nail oil plug rivet saw tube valve wedge arc beam core disk etch fuse glow hull icon jolt knot link mold node orb plot ray slot tier unit void wave zone brisk calm damp even faint grim hard idle just kind lush mild near open pure quick rare soft tidy vast wild acid bolt cave desk exit frog game host item jump luck maze noon opal page roof star tank unit view wolf yard zinc )   
    local r=""
    for ((i=0;i<count;i++)); do [ -n "$r" ] && r+="-"; r+="${W[RANDOM%${#W[@]}]}"; done
    printf "%s" "$r"
  fi
}

_gen_pin()         { local l="${1:-6}"; set +o pipefail; LC_ALL=C tr -dc '0-9' </dev/urandom 2>/dev/null | head -c "$l"; true; }
_gen_pronounceable() {
  local len="${1:-16}" r="" cv="bcdfghjklmnprstv" vw="aeiou"
  for ((i=0;i<len;i++)); do
    ((i%2==0)) && r+="${cv:RANDOM%${#cv}:1}" || r+="${vw:RANDOM%${#vw}:1}"
  done
  printf "%s" "$r"
}

cmd_gen() {
  _cmd="gen"
  local mode="random" length="$PASSX_GEN_LENGTH" words=4 store_path="" copy_it=true
  while [ "$#" -gt 0 ]; do
    case "${1:-}" in
      --words|-w)      mode="words"; [[ "${2:-}" =~ ^[0-9]+$ ]] && { words="$2"; shift; } ;;
      --pin)           mode="pin";   [[ "${2:-}" =~ ^[0-9]+$ ]] && { length="$2"; shift; } ;;
      --pronounceable) mode="pronounce" ;;
      --no-copy)       copy_it=false ;;
      --store|-s)      store_path="${2:-}"; [ -z "$store_path" ] && err "--store requires a path"; shift ;;
      --length|-l|--len) length="${2:-}"; shift ;;
      --help|-h)       _help gen; return 0 ;;
      [0-9]*)          length="$1" ;;
      -*)              err "Unknown flag: $1" ;;
      *)               [ -z "$store_path" ] && store_path="$1" || err "Unexpected arg: $1" ;;
    esac
    shift
  done
  local pw
  case "$mode" in
    words)     pw="$(_gen_words "$words")" ;;
    pin)       pw="$(_gen_pin   "$length")" ;;
    pronounce) pw="$(_gen_pronounceable "$length")" ;;
    *)         pw="$(gen_password "$length")" ;;
  esac
  printf "%s\n" "$pw"
  if $copy_it && clipboard_available; then
    printf "%s" "$pw" | copy_clipboard --silent
    dim "Generated password copied to clipboard"
  fi
  if [ -n "$store_path" ]; then
    printf "%s\n" "$pw" | pass insert -m "$store_path" \
      && ok "Stored at $store_path" || warn "Storage failed"
    _autosync
  fi
}

cmd_gen_conf() {
  _cmd="gen-conf"
  local conf_file="$PASSX_CONF_DIR/passx.conf"
  
  if [ -f "$conf_file" ]; then
    warn "Config file already exists: $conf_file"
    return 0
  fi
  
  mkdir -p "$PASSX_CONF_DIR"
  cat << EOF > "$conf_file"
# passx configuration file
# Loaded automatically from $conf_file

# Store path (default uses pass behavior)
# PASSWORD_STORE_DIR="\$HOME/.password-store"

# Automatically run git push/pull on changes
PASSX_AUTOSYNC="false"

# Auto-clear clipboard after X seconds
PASSX_CLIP_TIMEOUT="20"

# Age limit in days for 'audit' warnings
PASSX_MAX_AGE="180"

# Desktop notifications for events
PASSX_NOTIFY="true"

# UI Theme: catppuccin|nord|gruvbox|dracula|solarized
PASSX_THEME="catppuccin"

# Password Generation Defaults
PASSX_GEN_LENGTH="32"
PASSX_GEN_CHARS="A-Za-z0-9@#%+=_"

# Other Settings
PASSX_JSON="0"        # Print scriptable JSON where possible
PASSX_COLOR="auto"    # auto|always|never
PASSX_DEBUG="0"       # Write execution trace to $PASSX_CACHE_DIR/log
EOF

  ok "Generated sample configuration at $conf_file"
  dim "Edit this file to set your default preferences."
}

# ════════════════════════════════════════════════════════════════
# § FIELD EXTRACTION
# ════════════════════════════════════════════════════════════════
extract_field() {
  local path="$1" field="$2"
  case "$field" in
    password) pass show "$path" 2>/dev/null | sed -n '1p' ;;
    full)     pass show "$path" 2>/dev/null ;;
    *)
      pass show "$path" 2>/dev/null \
        | grep -m1 "^${field}:" \
        | sed "s/^${field}: *//" ;;
  esac
}

# ════════════════════════════════════════════════════════════════
# § HOOKS
# ════════════════════════════════════════════════════════════════
_hook() {
  local event="$1"; shift
  for ext in sh bash; do
    local f="$PASSX_HOOKS_DIR/${event}.${ext}"
    [ -f "$f" ] && [ -x "$f" ] && "$f" "$@" 2>/dev/null || true
  done
}

# ════════════════════════════════════════════════════════════════
# § GIT / SYNC
# ════════════════════════════════════════════════════════════════
_need_git() {
  [ -d "$PASSWORD_STORE_DIR/.git" ] || err "Store is not a git repo.  Run: pass git init"
}

_autosync() {
  [ "$PASSX_AUTOSYNC" = "true" ] && [ -d "$PASSWORD_STORE_DIR/.git" ] || return 0
  pass git push >/dev/null 2>&1 && debug "autosync OK" || debug "autosync failed"
}

cmd_sync() {
  _cmd="sync"; _need_git
  _banner "Sync"
  step "Pulling..."; pass git pull 2>&1 || warn "Pull failed"
  step "Pushing..."; pass git push 2>&1 && ok "Synced" || { warn "Push failed"; return 1; }
  _notify passx "Store synced"
  _hook post-sync
}

cmd_log() {
  _cmd="log"; _need_git
  local n="${1:-20}"
  _banner "History — last $n commits"
  pass git log --oneline --decorate --color=always -"$n" 2>/dev/null | sed 's/^/  /'
  echo
}

cmd_diff() {
  _cmd="diff"
  _need_git
  local path="${1:-}" commit="${2:-HEAD~1}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "diff entry" "Select entry to diff")" || true
  [ -z "$path" ] && err "No entry selected"
  local cur old
  cur="$(pass show "$path" 2>/dev/null)" \
    || err "Cannot decrypt current version of $path"
  old="$(cd "$PASSWORD_STORE_DIR" \
    && git show "${commit}:${path}.gpg" 2>/dev/null \
    | gpg --quiet --batch --yes --decrypt 2>/dev/null)" \
    || { warn "Cannot decrypt $path at $commit (may not exist there)"; return 1; }
  _banner "Diff: $path  ($commit → now)"
  diff <(printf "%s\n" "$old") <(printf "%s\n" "$cur") \
    | sed "s/^+/${C_GREEN}+${C_RESET}/; s/^-/${C_RED}-${C_RESET}/" || true
  echo
}

cmd_watch() {
  _cmd="watch"; _need_git
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "watch" "Select entry")" || true
  [ -z "$path" ] && err "No entry selected"
  _banner "Watching: $path"
  info "Polls every 5s — Ctrl-C to stop"
  local last=""
  while true; do
    local cur
    cur="$(cd "$PASSWORD_STORE_DIR" \
      && git log -1 --format="%H" -- "${path}.gpg" 2>/dev/null || echo "")"
    if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
      [ -n "$last" ] && {
        local ts; ts="$(cd "$PASSWORD_STORE_DIR" && git log -1 --format="%ai" -- "${path}.gpg")"
        ok "Changed: $ts"
        _notify passx "Entry changed: $path"
      }
      last="$cur"
    fi
    sleep 5
  done
}

cmd_git() { pass git "$@"; }

# ════════════════════════════════════════════════════════════════
# § ADD
# ════════════════════════════════════════════════════════════════
cmd_add() {
  _cmd="add"
  [ "$#" -lt 1 ] && err "Usage: passx add <path> [email] [username] [notes] [length]"
  local path="$1"; shift
  local email="" user="" notes="" length="$PASSX_GEN_LENGTH"
  for arg in "$@"; do
    case "$arg" in
      *@*)              email="$arg" ;;
      [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) length="$arg" ;;
      *)  [ -z "$user" ] && user="$arg" || notes="$arg" ;;
    esac
  done
  local pw
  pw="$(gen_password "$length")" || err "Password generation failed"
  [ -z "$pw" ] && err "Password generation produced empty result"
  {
    printf "%s\n" "$pw"
    [ -n "$email" ]  && printf "email: %s\n"    "$email"
    [ -n "$user"  ]  && printf "username: %s\n" "$user"
    [ -n "$notes" ]  && printf "notes: %s\n"    "$notes"
  } | pass insert -m "$path" || err "pass insert failed — entry may already exist, use: passx edit $path"
  ok "Added: $path"
  clipboard_available && { printf "%s" "$pw" | copy_clipboard --silent; dim "Password copied to clipboard"; } || true
  debug "add: $path"
  _hook post-add "$path"
  _autosync
}

# ════════════════════════════════════════════════════════════════
# § TEMPLATE
# ════════════════════════════════════════════════════════════════
cmd_template() {
  _cmd="template"
  local show_pw=true
  [ "${1:-}" = "-n" ] && { show_pw=false; shift; }
  command -v fzf >/dev/null 2>&1 || err "fzf required"
  local ttype
  ttype="$(printf "web-login\nserver\ndatabase\napi-key\nemail-account\ncredit-card\nsoftware-license\nwifi\nnote" \
    | _fzf_pick "template" "Choose entry type" 40%)" || return 0
  [ -z "$ttype" ] && return 0
  printf "\n  Store path (e.g. work/github): " >&2; read -r tpath </dev/tty || true
  [ -z "${tpath:-}" ] && { dim "Aborted"; return 0; }
  local tmp; tmp="$(mktemp)"
  local _r _u _e _p _h _db _port _exp _cvv _name _ctype _svc _url _ssid _sec _prod _lic _gen_pw
  case "$ttype" in
    web-login)
      printf "  URL:      " >&2; read -r _url  </dev/tty || _url=""
      printf "  Username: " >&2; read -r _u    </dev/tty || _u=""
      printf "  Email:    " >&2; read -r _e    </dev/tty || _e=""
      { printf "%s\n" "$(gen_password)"
        [ -n "${_u:-}"   ] && printf "username: %s\n" "$_u"
        [ -n "${_e:-}"   ] && printf "email: %s\n"    "$_e"
        [ -n "${_url:-}" ] && printf "url: %s\n"      "$_url"; } > "$tmp" ;;
    server)
      printf "  Host:     " >&2; read -r _h  </dev/tty || _h=""
      printf "  Username: " >&2; read -r _u  </dev/tty || _u=""
      printf "  Port[22]: " >&2; read -r _port </dev/tty || _port="22"
      { printf "%s\n" "$(gen_password)"
        printf "username: %s\n" "${_u:-root}"
        printf "host: %s\n"     "${_h:-}"
        printf "port: %s\n"     "${_port:-22}"; } > "$tmp" ;;
    database)
      printf "  Host:     " >&2; read -r _h    </dev/tty || _h=""
      printf "  Database: " >&2; read -r _db   </dev/tty || _db=""
      printf "  Username: " >&2; read -r _u    </dev/tty || _u=""
      printf "  Port:     " >&2; read -r _port </dev/tty || _port=""
      { printf "%s\n" "$(gen_password)"
        printf "username: %s\n" "${_u:-}"
        printf "host: %s\n"     "${_h:-}"
        printf "database: %s\n" "${_db:-}"
        [ -n "${_port:-}" ] && printf "port: %s\n" "$_port"; } > "$tmp" ;;
    api-key)
      printf "  Service:  " >&2; read -r _svc </dev/tty || _svc=""
      printf "  URL:      " >&2; read -r _url </dev/tty || _url=""
      { printf "%s\n" "$(gen_password 48)"
        printf "service: %s\n" "${_svc:-}"
        [ -n "${_url:-}" ] && printf "url: %s\n" "$_url"
        printf "token: \n"; } > "$tmp" ;;
    email-account)
      printf "  Address:  " >&2; read -r _e    </dev/tty || _e=""
      printf "  IMAP:     " >&2; read -r _h    </dev/tty || _h=""
      printf "  SMTP:     " >&2; read -r _svc  </dev/tty || _svc=""
      { printf "%s\n" "$(gen_password)"
        printf "email: %s\n"    "${_e:-}"
        printf "imap: %s\n"     "${_h:-}"
        printf "smtp: %s\n"     "${_svc:-}"; } > "$tmp" ;;
    credit-card)
      printf "  Cardholder: " >&2; read -r _name  </dev/tty || _name=""
      printf "  Number:     " >&2; read -r _db     </dev/tty || _db=""
      printf "  Expiry MM/YY: " >&2; read -r _exp  </dev/tty || _exp=""
      printf "  CVV:        " >&2; read -r _cvv    </dev/tty || _cvv=""
      printf "  Type(visa/mc): " >&2; read -r _ctype </dev/tty || _ctype=""
      { printf "%s\n" "${_cvv:-}"
        printf "name: %s\n"   "${_name:-}"
        printf "number: %s\n" "${_db:-}"
        printf "expiry: %s\n" "${_exp:-}"
        printf "type: %s\n"   "${_ctype:-}"; } > "$tmp" ;;
    software-license)
      printf "  Product:  " >&2; read -r _prod </dev/tty || _prod=""
      printf "  Email:    " >&2; read -r _e    </dev/tty || _e=""
      printf "  License key: " >&2; read -r _lic </dev/tty || _lic=""
      { printf "%s\n" "${_lic:-}"
        printf "product: %s\n" "${_prod:-}"
        printf "email: %s\n"   "${_e:-}"
        printf "key: %s\n"     "${_lic:-}"; } > "$tmp" ;;
    wifi)
      printf "  SSID:     " >&2; read -r _ssid </dev/tty || _ssid=""
      printf "  Security[WPA2]: " >&2; read -r _sec </dev/tty || _sec="WPA2"
      { printf "%s\n" "$(gen_password 20)"
        printf "ssid: %s\n"     "${_ssid:-}"
        printf "security: %s\n" "${_sec:-WPA2}"; } > "$tmp" ;;
    note)
      printf "  Enter note (Ctrl-D when done):\n" >&2
      cat > "$tmp" ;;
  esac
  pass insert -m "$tpath" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
  
  local _saved_pw; _saved_pw="$(head -n1 "$tmp")"
  rm -f "$tmp"
  echo ""
  ok "Created $ttype: $tpath"
  if [ -n "${_saved_pw:-}" ]; then
    if $show_pw; then
      printf "  ${C_BOLD}Password:${C_RESET}  ${C_GREEN}%s${C_RESET}\n" "$_saved_pw"
    fi
    clipboard_available && { printf "%s" "$_saved_pw" | copy_clipboard --silent
      dim "Password copied to clipboard (clears in ${PASSX_CLIP_TIMEOUT}s)"; } || true
  fi
  echo ""
  _hook post-add "$tpath"
  _autosync
}

# ════════════════════════════════════════════════════════════════
# § SHOW
# ════════════════════════════════════════════════════════════════
cmd_show() {
  _cmd="show"
  local path="" field="" do_full=false do_json=false

  OPTIND=1
  while getopts ":puenfthj-:" opt; do
    case "$opt" in
      p) field="password" ;; u) field="username" ;; e) field="email" ;;
      n) field="notes"    ;; f) do_full=true      ;; t) field="token" ;;
      j) do_json=true     ;; h) _help show; return 0 ;;
      -)
        case "$OPTARG" in
          help)     _help show; return 0 ;;
          full)     do_full=true ;;
          json)     do_json=true ;;
          password) field="password" ;;
          username) field="username" ;;
          email)    field="email" ;;
          notes)    field="notes" ;;
          token)    field="token" ;;
          *) err "Unknown flag: --$OPTARG" ;;
        esac ;;
      *) err "Unknown flag: -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))
  path="${1:-}"

  if [[ "$path" == *:* ]]; then
    local cf="${path##*:}"; path="${path%:*}"
    case "$cf" in
      p|password)  field="password" ;;
      u|username) field="username" ;;
      e|email)     field="email"    ;;
      n|notes)    field="notes"    ;;
      f|full)      do_full=true     ;;
      t|token)    field="token"    ;;
      url)         field="url"      ;;
      pub)        do_full=true; path="${path}-pub" ;;
      pvt)         do_full=true; path="${path}-pvt" ;;
      *)           field="$cf"      ;;
    esac
  fi

  if [ -n "$field" ] || $do_full; then
    if [ -z "$path" ]; then
      command -v fzf >/dev/null 2>&1 || err "fzf required when no path given"
      path="$(list_entries | _fzf_pick "show" "Select entry")" 2>/dev/null || true
      [ -z "${path:-}" ] && return 0
    fi
    _is_pvt "$path" && _guard_pvt "$path"
    local val
    if $do_full; then
      val="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"
    else
      val="$(extract_field "$path" "$field")" || err "Field '$field' not found in $path"
      [ -z "${val:-}" ] && err "Field '$field' is empty in $path"
    fi
    $do_json && { _json_kv entry "$path" field "${field:-full}" value "$val"; return 0; }
    printf "%s\n" "$val"
    return 0
  fi

  command -v fzf >/dev/null 2>&1 || err "fzf required for interactive mode (install fzf)"
  if [ -z "$path" ]; then
    path="$(list_entries | fzf \
      --prompt="  passx ❯ " \
      --header="$(printf "  passx %s  │  Ctrl-C to quit   " "$PASSX_VERSION")" \
      --preview="$(_preview_script)" \
      --preview-window="right:42%:wrap" \
      --height=80% \
      $(_fzf_flags) $(_fzf_colors))" 2>/dev/null || return 0
    [ -z "${path:-}" ] && return 0
  fi

  _show_action_menu "$path"
}

_show_action_menu() {
  local entry="$1"

  while true; do
    local actions
    if _is_pvt "$entry"; then
      actions=$'show private key\ncopy private key\ndelete entry'
    elif [[ "$entry" == *-pub ]]; then
      actions=$'show public key\ncopy public key\ndelete entry'
    else
      actions=$(cat <<'ACTS'
── Credentials ─────────────
copy password
copy username
copy email
copy token
show full entry
── OTP ──────────────────────
otp → copy
otp → show live
otp → type (xdotool)
otp → QR code
── Automation ───────────────
fill (autotype user+pass)
login (copy user+pass)
open URL
── Edit ─────────────────────
rotate password
set field
rename entry
clone entry
edit in editor
── Security ─────────────────
check strength
check entropy
check HIBP
── Other ────────────────────
sync store
run command with creds
delete entry
ACTS
)
    fi

    local action
    action="$(printf "%s\n" "$actions" | grep -v '^──' | grep -v '^$' | \
      fzf --prompt="  $entry ❯ " \
          --header="$(printf "  ${C_DIM}Select action  (Esc = back to list)${C_RESET}")" \
          --height=65% \
          $(_fzf_flags) $(_fzf_colors))" 2>/dev/null || return 0
    [ -z "${action:-}" ] && return 0

    case "$action" in
      "copy password")      extract_field "$entry" password | tr -d '\n' | copy_clipboard --silent; _notify passx "Password copied" ;;
      "copy username")      extract_field "$entry" username | tr -d '\n' | copy_clipboard --silent ;;
      "copy email")         extract_field "$entry" email    | tr -d '\n' | copy_clipboard --silent ;;
      "copy token")         extract_field "$entry" token    | tr -d '\n' | copy_clipboard --silent ;;
      "show full entry")    pass show "$entry" | ${PAGER:-cat}; _pause ;;
      "show public key")    pass show "$entry" | ${PAGER:-cat}; _pause ;;
      "show private key")   _guard_pvt "$entry"; pass show "$entry" | ${PAGER:-cat}; _pause ;;
      "copy public key")    pass show "$entry" | copy_clipboard ;;
      "copy private key")   _guard_pvt "$entry"; pass show "$entry" | copy_clipboard ;;
      "otp → copy")         cmd_otp "$entry" ;;
      "otp → show live")    cmd_otp_show "$entry"; return 0 ;;
      "otp → type (xdotool)") cmd_otp_fill "$entry" ;;
      "otp → QR code")      cmd_otp_qr "$entry"; _pause ;;
      "fill (autotype user+pass)") cmd_fill "$entry" ;;
      "login (copy user+pass)") cmd_login "$entry" ;;
      "open URL")           cmd_url "$entry" ;;
      "rotate password")
        printf "\n  New length [%s]: " "$PASSX_GEN_LENGTH" >&2
        read -r _l </dev/tty || _l=""
        cmd_rotate "$entry" "${_l:-$PASSX_GEN_LENGTH}"; _pause ;;
      "set field")
        printf "\n  Field name: " >&2; read -r _f </dev/tty || _f=""
        [ -n "${_f:-}" ] && cmd_set_field "$entry" "$_f"; _pause ;;
      "rename entry")   cmd_rename "$entry"; return 0 ;;
      "clone entry")    cmd_clone  "$entry"; _pause ;;
      "edit in editor") cmd_edit   "$entry" ;;
      "check strength") cmd_strength "$entry"; _pause ;;
      "check entropy")  cmd_entropy  "$entry"; _pause ;;
      "check HIBP")     cmd_hibp     "$entry"; _pause ;;
      "sync store")     cmd_sync; _pause ;;
      "run command with creds")
        printf "\n  Command: " >&2; read -r _c </dev/tty || _c=""
        [ -n "${_c:-}" ] && cmd_run "$entry" bash -c "$_c"; _pause ;;
      "delete entry")   cmd_rm "$entry"; return 0 ;;
    esac
  done
}

_pause() {
  printf "\n  ${C_DIM}↵ Enter to continue...${C_RESET}" >&2
  read -r </dev/tty 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════
# § COPY
# ════════════════════════════════════════════════════════════════
cmd_copy() {
  _cmd="copy"
  local path="" field="password" do_json=false

  OPTIND=1
  while getopts ":puenfthj-:" opt; do
    case "$opt" in
      p) field="password" ;; u) field="username" ;; e) field="email" ;;
      n) field="notes"    ;; f) field="full"      ;; t) field="token" ;;
      j) do_json=true     ;; h) _help copy; return 0 ;;
      -) case "$OPTARG" in
           help) _help copy; return 0 ;;
           full) field="full" ;;
           *) err "Unknown flag: --$OPTARG" ;;
         esac ;;
      *) err "Unknown flag: -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))
  path="${1:-}"

  if [[ "$path" == *:* ]]; then
    local cf="${path##*:}"; path="${path%:*}"
    case "$cf" in
      p|password) field="password" ;;
      u|username) field="username" ;;
      e|email)    field="email"    ;;
      n|notes)    field="notes"    ;;
      f|full)     field="full"     ;;
      t|token)    field="token"    ;;
      url)        field="url"      ;;
      pub)        field="full"; path="${path}-pub" ;;
      pvt)        field="full"; path="${path}-pvt" ;;
      *)          field="$cf" ;;
    esac
  fi

  [ -z "$path" ] && {
    command -v fzf >/dev/null 2>&1 || err "fzf required when no path given"
    path="$(list_entries | _fzf_pick "copy" "Select entry to copy from")" || true
  }
  [ -z "${path:-}" ] && err "No entry selected"
  _is_pvt "$path" && _guard_pvt "$path"

  local val
  if [ "$field" = "full" ] || _is_pvt "$path" || [[ "$path" == *-pub ]]; then
    val="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"
  else
    val="$(extract_field "$path" "$field")" || err "Field '$field' not found"
    [ -z "${val:-}" ] && err "Field '$field' is empty in $path"
  fi
  printf "%s" "$val" | tr -d '\n' | copy_clipboard || err "Copy failed"
  _notify passx "$field copied from ${path##*/}"
}

# ════════════════════════════════════════════════════════════════
# § SET-FIELD / RENAME / CLONE
# ════════════════════════════════════════════════════════════════
cmd_set_field() {
  [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && { _help set-field; return 0; }
  _cmd="set-field"

  local path="" field="" value=""

  if [[ "${1:-}" == *:* && -z "${2:-}" ]]; then
    field="${1%%:*}"
    value="${1#*:}"
    path="$(list_entries | _fzf_pick "set-field" "Select entry to update")"
    [ -z "$path" ] && { dim "Aborted"; return 0; }
  else
    path="${1:-}"
    field="${2:-}"
    value="${3:-}"
  fi

  [ -z "$path"  ] && err "Usage: passx set-field <path> <field> [value]"
  [ -z "$field" ] && err "Usage: passx set-field <path> <field> [value]"
  
  if [ -z "$value" ]; then
    printf "  Value for '%s': " "$field" >&2; read -r value </dev/tty
  fi
  
  [ -z "${value:-}" ] && err "No value provided"

  local entry; entry="$(pass show "$path" 2>/dev/null)" || err "Entry not found: $path"
  local tmp; tmp="$(mktemp)"

  if [ "$field" = "password" ]; then
    { printf "%s\n" "$value"; printf "%s\n" "$(printf "%s\n" "$entry" | tail -n +2)"; } \
      | pass insert -m -f "$path" || { rm -f "$tmp"; err "pass insert failed"; }
  else
    printf "%s\n" "$entry" | grep -v "^${field}:" > "$tmp"
    printf "%s: %s\n" "$field" "$value" >> "$tmp"
    pass insert -m -f "$path" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
  fi
  
  rm -f "$tmp"
  ok "Updated '$field' in $path"
  _autosync
}

cmd_rename() {
  _cmd="rename"
  local old="${1:-}" new="${2:-}"
  [ -z "$old" ] && old="$(list_entries | _fzf_pick "rename" "Select entry")" || true
  [ -z "${old:-}" ] && err "No entry selected"
  [ -z "$new"  ] && { printf "  New path: " >&2; read -r new </dev/tty; }
  [ -z "${new:-}" ] && err "No destination"
  pass mv "$old" "$new" || err "Rename failed"
  ok "Renamed: $old → $new"
  _autosync
}

cmd_clone() {
  _cmd="clone"
  local src="${1:-}" dest="${2:-}"
  [ -z "$src"  ] && src="$(list_entries | _fzf_pick "clone" "Select entry to clone")" || true
  [ -z "${src:-}"  ] && err "No entry selected"
  [ -z "$dest" ] && { printf "  Clone destination: " >&2; read -r dest </dev/tty; }
  [ -z "${dest:-}" ] && err "No destination"
  pass show "$src" 2>/dev/null | pass insert -m "$dest" || err "Clone failed"
  ok "Cloned: $src → $dest"
  _autosync
}

# ════════════════════════════════════════════════════════════════
# § SECRETS — NOTE, CARD, ENV, DOTENV, RUN
# ════════════════════════════════════════════════════════════════
cmd_note() {
  _cmd="note"
  local path="" action="show" arg1="${1:-}" arg2="${2:-}"
  case "$arg1" in
    show|edit|copy|add|new|list) action="$arg1"; path="$arg2" ;;
    *)                           path="$arg1"; [ -n "$arg2" ] && action="$arg2" ;;
  esac
  case "$action" in
    add|new)
      [ -z "$path" ] && { printf "  Store path for note (e.g. notes/diary): " >&2; read -r path </dev/tty || true; }
      [ -z "${path:-}" ] && err "No path provided"
      local _title; printf "  Note title/summary (one line): " >&2; read -r _title </dev/tty || _title=""
      local tmp; tmp="$(mktemp)"
      printf "  Enter note body (Ctrl-D when done):\n" >&2
      local _body; _body="$(cat)"
      { printf "note: %s\n" "${_title:-untitled}"
        [ -n "${_body:-}" ] && printf "%s\n" "$_body"; } > "$tmp"
      [ ! -s "$tmp" ] && { rm -f "$tmp"; err "Empty note"; }
      pass insert -m "$path" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
      rm -f "$tmp"; ok "Note saved: $path"; _autosync ;;
    list)
      command -v fzf >/dev/null 2>&1 || err "fzf required"
      local _notes=()
      while IFS= read -r e; do
        [ -z "$e" ] && continue
        pass show "$e" 2>/dev/null | grep -q "^note:" && _notes+=("$e") || true
      done < <(list_entries)
      [ ${#_notes[@]} -eq 0 ] && { info "No notes found (create with: passx note add)"; return 0; }
      local _sel; _sel="$(printf "%s\n" "${_notes[@]}" | _fzf_pick "note" "Your notes  (${#_notes[@]} found)")" || return 0
      [ -n "${_sel:-}" ] && pass show "$_sel" 2>/dev/null ;;
    edit)
      [ -z "$path" ] && path="$(list_entries | _fzf_pick "note" "Select entry to edit")" || true
      [ -z "${path:-}" ] && err "No entry selected"
      env EDITOR="${EDITOR:-${VISUAL:-vim}}" pass edit "$path"; _autosync ;;
    copy)
      [ -z "$path" ] && path="$(list_entries | _fzf_pick "note" "Select entry")" || true
      [ -z "${path:-}" ] && err "No entry selected"
      local _nc; _nc="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"
      printf "%s" "$_nc" | copy_clipboard && ok "Note copied" ;;
    *)
      [ -z "$path" ] && path="$(list_entries | _fzf_pick "note" "Select entry")" || true
      [ -z "${path:-}" ] && err "No entry selected"
      pass show "$path" 2>/dev/null ;;
  esac
}

cmd_card() {
  _cmd="card"
  local path="" action="show" arg1="${1:-}" arg2="${2:-}"
  case "$arg1" in
    list|add|new|show|copy-number|copy-cvv) action="$arg1"; path="$arg2" ;;
    *) path="$arg1"; [ -n "$arg2" ] && action="$arg2" ;;
  esac

  if [ "$action" = "add" ] || [ "$action" = "new" ]; then
    printf "  Store path (e.g. cards/visa): " >&2; read -r _cpath </dev/tty || _cpath=""
    [ -z "${_cpath:-}" ] && { dim "Aborted"; return 0; }
    printf "  Cardholder: " >&2; read -r _name </dev/tty || _name=""
    printf "  Number:     " >&2; read -r _num  </dev/tty || _num=""
    printf "  Expiry MM/YY: " >&2; read -r _exp </dev/tty || _exp=""
    printf "  CVV:        " >&2; read -r _cvv  </dev/tty || _cvv=""
    printf "  Type (visa/mc/amex): " >&2; read -r _ctype </dev/tty || _ctype=""
    local tmp; tmp="$(mktemp)"
    { printf "%s\n" "${_cvv:-}"
      printf "name: %s\n"   "${_name:-}"
      printf "number: %s\n" "${_num:-}"
      printf "expiry: %s\n" "${_exp:-}"
      printf "type: %s\n"   "${_ctype:-}"; } > "$tmp"
    pass insert -m "$_cpath" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
    rm -f "$tmp"; ok "Card saved: $_cpath"; _autosync; return 0
  fi

  # If no path is provided, find all actual cards and prompt via fzf
  if [ -z "$path" ]; then
    command -v fzf >/dev/null 2>&1 || err "fzf required"
    local _cards=()
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      pass show "$e" 2>/dev/null | grep -q "^number:" && _cards+=("$e") || true
    done < <(list_entries)
    
    [ ${#_cards[@]} -eq 0 ] && { info "No cards found (create with: passx card add or passx T)"; return 0; }
    
    local _sel; _sel="$(printf "%s\n" "${_cards[@]}" | _fzf_pick "card" "Your cards  (${#_cards[@]} found)")" || return 0
    [ -n "${_sel:-}" ] && path="$_sel" || return 0
  fi

  # If the user simply typed 'passx card list' and picked an entry, default the action to show
  [ "$action" = "list" ] && action="show"

  [ -z "${path:-}" ] && err "Usage: passx card [show|copy-number|copy-cvv] <path>"
  
  local e; e="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"
  local num name exp type
  num="$(printf "%s\n" "$e"  | grep -m1 "^number:" | sed "s/^number: *//" || true)"
  name="$(printf "%s\n" "$e" | grep -m1 "^name:" | sed "s/^name: *//" || true)"
  exp="$(printf "%s\n" "$e"  | grep -m1 "^expiry:" | sed "s/^expiry: *//" || true)"
  type="$(printf "%s\n" "$e" | grep -m1 "^type:" | sed "s/^type: *//" || true)"
  
  case "$action" in
    show)
      echo ""
      printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Type"    "${type:-unknown}"
      printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Holder"  "${name:-}"
      [ -n "${num:-}" ] && printf "  ${C_BOLD}%-12s${C_RESET} **** **** **** %s\n" "Number" "${num: -4}" || true
      printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Expiry"  "${exp:-}"
      printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "CVV"     "***"
      echo "" ;;
    copy-number)
      _guard_pvt "$path"
      printf "%s\n" "$e" | grep -m1 '^number:' | sed 's/^number: *//' | tr -d '\n' | copy_clipboard ;;
    copy-cvv)
      _guard_pvt "$path"
      printf "%s\n" "$e" | sed -n '1p' | tr -d '\n' | copy_clipboard ;;
  esac
}

cmd_env() {
  _cmd="env"
  [[ "${1:-}" == "--help" ]] && { _help "env"; return 0; }

  local path="" action="export" arg1="${1:-}" arg2="${2:-}"
  case "$arg1" in
    list|add|new|export|dotenv|show) action="$arg1"; path="$arg2" ;;
    *) path="$arg1"; [ -n "$arg2" ] && action="$arg2" ;;
  esac

  if [ "$action" = "list" ]; then
    command -v fzf >/dev/null 2>&1 || err "fzf required"
    local _envs=()
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      pass show "$e" 2>/dev/null | grep -qE "^(token|api.key|secret|key|access):" && _envs+=("$e") || true
    done < <(list_entries)
    [ ${#_envs[@]} -eq 0 ] && { info "No env/token entries found"; return 0; }
    local _sel; _sel="$(printf "%s\n" "${_envs[@]}" | _fzf_pick "env" "Env entries  (${#_envs[@]} found)")" || return 0
    [ -n "${_sel:-}" ] && { action="export"; path="$_sel"; } || return 0
  fi

  if [ "$action" = "add" ] || [ "$action" = "new" ]; then
    printf "  Store path (e.g. env/aws-prod): " >&2; read -r _epath </dev/tty || _epath=""
    [ -z "${_epath:-}" ] && { dim "Aborted"; return 0; }
    printf "  Service name: " >&2; read -r _svc </dev/tty || _svc=""
    printf "  Token/API key: " >&2; read -r _tok </dev/tty || _tok=""
    printf "  URL (optional): " >&2; read -r _url </dev/tty || _url=""
    local tmp; tmp="$(mktemp)"
    { printf "%s\n" "${_tok:-}"
      [ -n "${_svc:-}" ] && printf "service: %s\n" "$_svc"
      [ -n "${_url:-}" ] && printf "url: %s\n" "$_url"
      printf "token: %s\n" "${_tok:-}"; } > "$tmp"
    pass insert -m "$_epath" < "$tmp" || { rm -f "$tmp"; err "pass insert failed"; }
    rm -f "$tmp"; ok "Env entry saved: $_epath"; _autosync; return 0
  fi

  [ -z "$path" ] && path="$(list_entries | _fzf_pick "env" "Select entry")" || true
  [ -z "${path:-}" ] && err "Usage: passx env [export|dotenv|show] <path>"
  
  local e; e="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"

  if [ "$action" = "show" ]; then
    printf "%s\n" "$e"
    return 0
  fi

  local pfx; pfx="$(printf "%s" "${path##*/}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_"
  local pw; pw="$(printf "%s\n" "$e" | sed -n '1p')"
  
  case "$action" in
    dotenv)
      printf "PASSWORD=%s\n" "$pw"
      while IFS=': ' read -r k v; do
        [ -z "$k" ] && continue
        local ek; ek="$(printf "%s" "$k" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
        printf "%s=%s\n" "$ek" "$v"
      done < <(printf "%s\n" "$e" | tail -n +2 | grep ':') ;;
    *)
      printf "export %sPASSWORD='%s'\n" "$pfx" "$pw"
      while IFS=': ' read -r k v; do
        [ -z "$k" ] && continue
        local ek; ek="$(printf "%s" "$k" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
        printf "export %s%s='%s'\n" "$pfx" "$ek" "$v"
      done < <(printf "%s\n" "$e" | tail -n +2 | grep ':') ;;
  esac
}

cmd_dotenv() { _cmd="dotenv"; cmd_env dotenv "${1:-}"; }

cmd_run() {
  _cmd="run"
  if [[ "${1:-}" == "--help" ]]; then _help "run"; return 0; fi

  local path="${1:-}"; shift 2>/dev/null || true
  [ -z "$path" ] && err "Usage: passx run <path> <command> [args...]"
  [ "$#" -eq 0 ] && err "Usage: passx run <path> <command> [args...]"

  local e; e="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt: $path"
  local pw user email host port db token
  pw="$(printf "%s\n" "$e"      | sed -n '1p')"
  user="$(printf "%s\n" "$e"    | grep -m1 "^username:" | sed "s/^username: *//")"
  email="$(printf "%s\n" "$e"   | grep -m1 "^email:" | sed "s/^email: *//")"
  host="$(printf "%s\n" "$e"    | grep -m1 "^host:" | sed "s/^host: *//")"
  port="$(printf "%s\n" "$e"    | grep -m1 "^port:" | sed "s/^port: *//")"
  db="$(printf "%s\n" "$e"      | grep -m1 "^database:" | sed "s/^database: *//")"
  token="$(printf "%s\n" "$e"   | grep -m1 "^token:" | sed "s/^token: *//")"
  
  export PASSX_PASSWORD="$pw"
  export PASSX_USERNAME="${user:-${email:-}}"
  [ -n "$user"  ] && export PASSX_USER="$user"
  [ -n "$email" ] && export PASSX_EMAIL="$email"
  [ -n "$host"  ] && export PASSX_HOST="$host"
  [ -n "$port"  ] && export PASSX_PORT="$port"
  [ -n "$db"    ] && export PASSX_DATABASE="$db"
  [ -n "$token" ] && export PASSX_TOKEN="$token"

  local cmd_base; cmd_base="${1##*/}"
  case "$cmd_base" in
    ssh)
      if command -v sshpass >/dev/null 2>&1; then
        export SSHPASS="$pw"
        set -- sshpass -e "$@"
      else
        pass -c "$path" >/dev/null 2>&1
      fi ;;
    psql*) [ -n "$pw"   ] && export PGPASSWORD="$pw"
           [ -n "$user" ] && export PGUSER="$user"
           [ -n "$host" ] && export PGHOST="$host"
           [ -n "$port" ] && export PGPORT="$port"
           [ -n "$db"   ] && export PGDATABASE="$db" ;;
    mysql*|mariadb*) [ -n "$pw" ] && export MYSQL_PWD="$pw" ;;
    aws)   [ -n "$token" ] && {
             export AWS_ACCESS_KEY_ID="${token%%:*}"
             [[ "$token" == *:* ]] && export AWS_SECRET_ACCESS_KEY="${token##*:}"; } ;;
  esac

  dim "Running: $*"
  exec "$@"
}

# ════════════════════════════════════════════════════════════════
# § OTP
# ════════════════════════════════════════════════════════════════
_get_otp() {
  local path="$1" out=""
  if command -v pass >/dev/null 2>&1 && pass otp "$path" >/dev/null 2>&1; then
    out="$(pass otp "$path" 2>/dev/null)"
  elif command -v oathtool >/dev/null 2>&1; then
    local e secret
    e="$(pass show "$path" 2>/dev/null || true)"
    secret="$(printf "%s\n" "$e" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p' | head -n1)"
    [ -z "$secret" ] && secret="$(printf "%s\n" "$e" | grep -m1 "^otp:" | sed "s/^otp: *//")"
    [ -n "$secret" ] && out="$(oathtool --totp -b "$secret" 2>/dev/null || true)"
  fi
  printf "%s" "$out"
}

cmd_otp() {
  _cmd="otp"
  local no_copy=false
  OPTIND=1
  while getopts ":nh-:" opt; do
    case "$opt" in
      n) no_copy=true ;; h) _help otp; return 0 ;;
      -) [ "$OPTARG" = "help" ] && { _help otp; return 0; } || err "Unknown flag: --$OPTARG" ;;
      *) err "Usage: passx otp [-n] <path>" ;;
    esac
  done
  shift $((OPTIND - 1))
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "otp" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  local out; out="$(_get_otp "$path")"
  [ -z "$out" ] && err "OTP not configured for $path"
  printf "%s\n" "$out"
  if ! $no_copy && clipboard_available; then
    printf "%s" "$out" | copy_clipboard --silent
    _notify passx "OTP copied — clears in ${PASSX_CLIP_TIMEOUT}s"
  elif ! $no_copy; then warn "No clipboard available"; fi
}

cmd_otp_show() {
  _cmd="otp-show"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "otp-show" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  while true; do
    clear
    local out remaining bar=""
    out="$(_get_otp "$path")"; [ -z "$out" ] && out="N/A"
    remaining=$((30 - $(date +%s) % 30))
    local filled=$((30 - remaining)); local i
    for ((i=0;i<30;i++)); do ((i<filled)) && bar+="█" || bar+="░"; done
    printf "\n  ${C_BOLD}${C_CYAN}OTP${C_RESET}  —  %s\n\n" "$path"
    printf "  ${C_BOLD}${C_GREEN}  %s  ${C_RESET}\n\n" "$out"
    if   [ "$remaining" -le 5  ]; then printf "  ${C_RED}[%s]${C_RESET}  %2ss\n"    "$bar" "$remaining"
    elif [ "$remaining" -le 10 ]; then printf "  ${C_YELLOW}[%s]${C_RESET}  %2ss\n" "$bar" "$remaining"
    else                               printf "  ${C_GREEN}[%s]${C_RESET}  %2ss\n"  "$bar" "$remaining"
    fi
    printf "\n  ${C_DIM}Ctrl-C to exit${C_RESET}\n"
    clipboard_available && [ "$out" != "N/A" ] \
      && printf "%s" "$out" | copy_clipboard --silent 2>/dev/null || true
    sleep 1
  done
}

cmd_otp_fill() {
  _cmd="otp-fill"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "otp-fill" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  command -v xdotool >/dev/null 2>&1 || err "xdotool required"
  local out; out="$(_get_otp "$path")"
  [ -z "$out" ] && err "OTP not configured for $path"
  info "Focus the OTP field — typing in 2s..."
  sleep 2
  xdotool type --delay 30 --clearmodifiers "$out"
  ok "OTP typed"
}

cmd_otp_list() {
  _cmd="otp-list"
  _banner "OTP-enabled entries"
  local found=false
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    pass show "$e" 2>/dev/null | grep -q "^otp:\|^otpauth://" \
      && { printf "  ${C_MAGENTA}◉${C_RESET}  %s\n" "$e"; found=true; } || true
  done < <(list_entries)
  $found || info "No OTP entries found"
  echo
}

cmd_otp_import() {
  _cmd="otp-import"
  local path="${1:-}"
  
  if [ -z "$path" ]; then
    path="$(list_entries | _fzf_pick "otp-import" "Select entry to add OTP")"
  fi
  [ -z "$path" ] && return 1

  local method
  method=$(printf "Scan QR (zbarimg)\nManual Entry\nSearch System for QR (.png)" | \
           fzf --height 40% --reverse --header "Choose OTP Import Method")

  local otp_url=""

  case "$method" in
    "Scan QR (zbarimg)")
      command -v zbarimg >/dev/null 2>&1 || err "zbarimg required for QR scanning"
      read -rp "Path to QR Image: " img
      img="${img/#\~/$HOME}"
      [ ! -f "$img" ] && err "File not found: $img"
      otp_url=$(zbarimg --quiet --raw "$img" | tr -d '\n' || true)
      ;;
    "Search System for QR (.png)")
      command -v zbarimg >/dev/null 2>&1 || err "zbarimg required"
      local found_img
      found_img=$(find "$HOME" -maxdepth 3 -name "*.png" -o -name "*.jpg" 2>/dev/null | fzf --header "Select QR Code Image")
      [ -z "$found_img" ] && return
      otp_url=$(zbarimg --quiet --raw "$found_img" | tr -d '\n' || true)
      ;;
    "Manual Entry")
      read -rp "Issuer (e.g. GitHub): " issuer
      read -rp "Account (e.g. user@mail.com): " account
      read -rp "Secret Key: " secret
      secret=$(echo "$secret" | tr -d ' ')
      otp_url="otpauth://totp/${issuer}:${account}?secret=${secret}&issuer=${issuer}"
      ;;
    *) return ;;
  esac

  [ -z "$otp_url" ] && err "Failed to generate or read OTP URL"

  local tmp; tmp=$(mktemp)
  if pass show "$path" >/dev/null 2>&1; then
    pass show "$path" | grep -v "^otpauth://" | grep -v "^otp:" > "$tmp"
    printf "otpauth://%s\n" "${otp_url#otpauth://}" >> "$tmp"
  else
    printf "otpauth://%s\n" "${otp_url#otpauth://}" > "$tmp"
  fi

  pass insert -m -f "$path" < "$tmp"
  rm -f "$tmp"
  ok "OTP imported to $path"
}

cmd_otp_export() {
  _cmd="otp-export"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "otp-export" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  local e otpauth secret label
  e="$(pass show "$path" 2>/dev/null || true)"
  otpauth="$(printf "%s\n" "$e" | grep -m1 '^otpauth://' || true)"
  [ -z "$otpauth" ] && {
    secret="$(printf "%s\n" "$e" | grep -m1 "^otp:" | sed "s/^otp: *//")"
    [ -n "$secret" ] && {
      label="$(printf "%s" "$path" | sed 's/ /%20/g')"
      otpauth="otpauth://totp/${label}?secret=${secret}&issuer=${label}"; }
  }
  [ -z "$otpauth" ] && err "No OTP data in $path"
  if [ "${2:-}" = "--qr" ]; then
    local f="${3:-}"; [ -z "$f" ] && err "--qr requires a filename"
    command -v qrencode >/dev/null 2>&1 || { printf "%s\n" "$otpauth"; err "qrencode required"; }
    qrencode -o "$f" -s 10 "$otpauth" && ok "QR written to $f"
  else printf "%s\n" "$otpauth"; fi
}

cmd_otp_qr() {
  _cmd="otp-qr"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "otp-qr" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  command -v qrencode >/dev/null 2>&1 || err "qrencode required"
  local e otpauth secret label
  e="$(pass show "$path" 2>/dev/null || true)"
  otpauth="$(printf "%s\n" "$e" | grep -m1 '^otpauth://' || true)"
  [ -z "$otpauth" ] && {
    secret="$(printf "%s\n" "$e" | grep -m1 "^otp:" | sed "s/^otp: *//")"
    [ -z "$secret" ] && err "No OTP data in $path"
    label="$(printf "%s" "$path" | sed 's/ /%20/g')"
    otpauth="otpauth://totp/${label}?secret=${secret}&issuer=${label}"
  }
  qrencode -t ansiutf8 "$otpauth"
}

# ════════════════════════════════════════════════════════════════
# § QR
# ════════════════════════════════════════════════════════════════
cmd_qr() {
  _cmd="qr"
  local path="${1:-}" field="${2:-password}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "qr" "Select entry")" || true
  [ -z "${path:-}" ] && err "Usage: passx qr <path> [field]"
  command -v qrencode >/dev/null 2>&1 || err "qrencode required"
  local val; val="$(extract_field "$path" "$field")" || err "Field not found"
  printf "%s" "$val" | qrencode -t ansiutf8 || err "qrencode failed"
}

# ════════════════════════════════════════════════════════════════
# § SEARCH / LOGIN / FILL / URL
# ════════════════════════════════════════════════════════════════
cmd_search() {
  _cmd="search"
  local q="$*"
  local entries; entries="$(list_entries)"
  if command -v fzf >/dev/null 2>&1; then
    [ -n "$q" ] && printf "%s\n" "$entries" | fzf -f "$q" \
                || printf "%s\n" "$entries" | _fzf_pick "search" "Search your store"
  else
    [ -n "$q" ] && printf "%s\n" "$entries" | grep -i -- "$q" || true \
                || printf "%s\n" "$entries"
  fi
}

cmd_login() {
  _cmd="login"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "login" "Select entry")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  local user passw
  user="$(extract_field "$path" username)"
  passw="$(extract_field "$path" password)"
  [ -z "${user:-}" ] && [ -z "${passw:-}" ] && err "No credentials in $path"
  printf "%s\n%s" "$user" "$passw" | copy_clipboard || err "Copy failed"
  ok "Copied user + password for ${path##*/}"
}

cmd_fill() {
  _cmd="fill"
  local enter_after=false
  [ "${1:-}" = "-e" ] && { enter_after=true; shift; }
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "fill" "Select entry to autofill")" || true
  [ -z "${path:-}" ] && err "Usage: passx fill [-e] <path>"
  command -v xdotool >/dev/null 2>&1 || err "xdotool required"
  local user passw
  user="$(extract_field "$path" username || true)"
  passw="$(extract_field "$path" password || true)"
  [ -z "${user:-}" ] && [ -z "${passw:-}" ] && err "No credentials in $path"
  [ -n "${user:-}" ]  && { xdotool type --delay 25 --clearmodifiers "$user"; sleep 0.08; }
  xdotool key --clearmodifiers Tab; sleep 0.08
  [ -n "${passw:-}" ] && { xdotool type --delay 20 --clearmodifiers "$passw"; sleep 0.08; }
  $enter_after && xdotool key --clearmodifiers Return
  ok "Autofilled ${path##*/}"
}

cmd_url() {
  _cmd="url"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "url" "Select entry")" || true
  [ -z "${path:-}" ] && err "Usage: passx url <path>"
  local e url
  e="$(pass show "$path" 2>/dev/null || true)"
  url="$(printf "%s\n" "$e" | grep -m1 "^url:" | sed "s/^url: *//" || true)"
  [ -z "$url" ] && {
    local fl; fl="$(printf "%s\n" "$e" | sed -n '1p')"
    printf "%s" "$fl" | grep -qE '^https?://' && url="$fl"
  }
  if [ -z "$url" ]; then
    printf "  No URL found.  Enter URL to save (empty to cancel): " >&2
    read -r url </dev/tty || url=""
    [ -z "${url:-}" ] && { dim "Aborted"; return 0; }
    cmd_set_field "$path" "url" "$url"
  fi
  clipboard_available && { printf "%s" "$url" | copy_clipboard --silent; ok "URL copied"; } \
                       || printf "%s\n" "$url"
  command -v xdg-open >/dev/null 2>&1 && { xdg-open "$url" >/dev/null 2>&1 & ok "Opened: $url"; }
}

# ════════════════════════════════════════════════════════════════
# § STRENGTH / ENTROPY / ROTATE / RM / EDIT
# ════════════════════════════════════════════════════════════════
cmd_strength() {
  _cmd="strength"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "strength" "Select entry")" || true
  [ -z "${path:-}" ] && err "Usage: passx strength <path>"
  local pw; pw="$(extract_field "$path" password)"
  [ -z "${pw:-}" ] && err "No password in $path"
  local len u l n s score
  len=${#pw}
  u=$(printf "%s" "$pw" | grep -c '[A-Z]'        2>/dev/null || true); u=$((u>0?1:0))
  l=$(printf "%s" "$pw" | grep -c '[a-z]'        2>/dev/null || true); l=$((l>0?1:0))
  n=$(printf "%s" "$pw" | grep -c '[0-9]'        2>/dev/null || true); n=$((n>0?1:0))
  s=$(printf "%s" "$pw" | grep -c '[^A-Za-z0-9]' 2>/dev/null || true); s=$((s>0?1:0))
  score=$((u+l+n+s))
  echo ""
  printf "  ${C_BOLD}Strength report${C_RESET}  —  %s\n\n" "$path"
  printf "  %-14s ${C_BOLD}%d${C_RESET}\n" "Length" "$len"
  printf "  %-14s %s\n" "Uppercase"  "$([ $u -eq 1 ] && printf "${C_GREEN}✔${C_RESET}" || printf "${C_DIM}✖${C_RESET}")"
  printf "  %-14s %s\n" "Lowercase"  "$([ $l -eq 1 ] && printf "${C_GREEN}✔${C_RESET}" || printf "${C_DIM}✖${C_RESET}")"
  printf "  %-14s %s\n" "Digits"     "$([ $n -eq 1 ] && printf "${C_GREEN}✔${C_RESET}" || printf "${C_DIM}✖${C_RESET}")"
  printf "  %-14s %s\n" "Symbols"    "$([ $s -eq 1 ] && printf "${C_GREEN}✔${C_RESET}" || printf "${C_DIM}✖${C_RESET}")"
  echo ""
  if   [ "$len" -ge 20 ] && [ "$score" -eq 4 ]; then printf "  ${C_GREEN}${C_BOLD}★★★★  Excellent${C_RESET}\n"
  elif [ "$len" -ge 16 ] && [ "$score" -ge 3 ]; then printf "  ${C_CYAN}${C_BOLD}★★★☆  Strong${C_RESET}\n"
  elif [ "$len" -ge 12 ] && [ "$score" -ge 3 ]; then printf "  ${C_YELLOW}${C_BOLD}★★☆☆  Good — consider rotating${C_RESET}\n"
  elif [ "$len" -ge 8  ] && [ "$score" -ge 2 ]; then printf "  ${C_YELLOW}${C_BOLD}★☆☆☆  Fair — rotate soon${C_RESET}\n"
  else                                               printf "  ${C_RED}${C_BOLD}☆☆☆☆  Weak — rotate immediately${C_RESET}\n"
  fi
  echo ""
}

cmd_entropy() {
  _cmd="entropy"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "entropy" "Select entry")" || true
  [ -z "${path:-}" ] && err "Usage: passx entropy <path>"
  local pw; pw="$(extract_field "$path" password)"
  [ -z "${pw:-}" ] && err "No password in $path"
  command -v python3 >/dev/null 2>&1 || err "python3 required for entropy calculation"
  local out
  out="$(printf "%s" "$pw" | python3 -c "
import sys,math
from collections import Counter
s=sys.stdin.read()
n=len(s)
if n==0: print('0 0 0'); exit()
H=-sum((v/n)*math.log2(v/n) for v in Counter(s).values())
pool=0
import re
if re.search(r'[a-z]',s): pool+=26
if re.search(r'[A-Z]',s): pool+=26
if re.search(r'[0-9]',s): pool+=10
if re.search(r'[^A-Za-z0-9]',s): pool+=32
p=round(H*n,1); m=round(math.log2(pool)*n,1) if pool else 0
print(p,m,n)
" 2>/dev/null)" || err "Entropy calc failed"
  local shannon pool_bits chars
  shannon="${out%% *}"; out="${out#* }"
  pool_bits="${out%% *}"; chars="${out##* }"
  echo ""
  printf "  ${C_BOLD}Entropy report${C_RESET}  —  %s\n\n" "$path"
  printf "  %-24s ${C_BOLD}%s chars${C_RESET}\n"                           "Length"          "$chars"
  printf "  %-24s ${C_BOLD}%s bits${C_RESET}  ${C_DIM}(Shannon)${C_RESET}\n" "Entropy"       "$shannon"
  printf "  %-24s ${C_BOLD}%s bits${C_RESET}  ${C_DIM}(pool max)${C_RESET}\n" "Theoretical"  "$pool_bits"
  echo ""
  local sh_int; sh_int="$(printf "%.0f" "$shannon")"
  if   [ "$sh_int" -ge 80 ]; then printf "  ${C_GREEN}${C_BOLD}Exceptional${C_RESET}  — brute-force resistant\n"
  elif [ "$sh_int" -ge 60 ]; then printf "  ${C_GREEN}${C_BOLD}Strong${C_RESET}       — good for most uses\n"
  elif [ "$sh_int" -ge 40 ]; then printf "  ${C_YELLOW}${C_BOLD}Moderate${C_RESET}     — consider rotating\n"
  else                             printf "  ${C_RED}${C_BOLD}Weak${C_RESET}         — rotate immediately\n"
  fi
  echo ""
}

cmd_rotate() {
  _cmd="rotate"
  local path="${1:-}" length="${2:-$PASSX_GEN_LENGTH}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "rotate" "Select entry to rotate")" || true
  [ -z "${path:-}" ] && err "Usage: passx rotate <path> [length]"
  pass show "$path" >/dev/null 2>&1 || err "Entry not found: $path"
  local newpw rest
  newpw="$(gen_password "$length")"
  rest="$(pass show "$path" | tail -n +2)"
  { printf "%s\n" "$newpw"; printf "%s\n" "$rest"; } | pass insert -m -f "$path" \
    || err "Rotate failed"
  printf "%s" "$newpw" | copy_clipboard --silent || true
  ok "Rotated password for $path"
  dim "New password copied to clipboard"
  _notify passx "Password rotated: ${path##*/}"
  _hook post-rotate "$path"
  _autosync
}

cmd_rm() {
  _cmd="rm"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "rm" "Select entry to delete")" || true
  [ -z "${path:-}" ] && err "Usage: passx rm <path>"
  printf "\n  ${C_YELLOW}${C_BOLD}Remove '%s'?${C_RESET} [y/N] " "$path" >&2
  local yn; read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
  pass rm -r "$path" || err "pass rm failed"
  ok "Removed: $path"
  _hook post-rm "$path"
  _autosync
}

cmd_edit() {
  _cmd="edit"
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "edit" "Select entry to edit")" || true
  [ -z "${path:-}" ] && err "Usage: passx edit <path>"
  local editor="${EDITOR:-${VISUAL:-}}"
  [ -z "$editor" ] && for e in vim vi nano; do
    command -v "$e" >/dev/null 2>&1 && { editor="$e"; break; }
  done
  [ -z "${editor:-}" ] && err "No editor found — set \$EDITOR"
  env EDITOR="$editor" pass edit "$path" || err "Edit failed"
  _hook post-edit "$path"
  _autosync
}

# ════════════════════════════════════════════════════════════════
# § AUDIT
# ════════════════════════════════════════════════════════════════
cmd_audit() {
  _cmd="audit"
  local fix_mode=false
  [ "${1:-}" = "--fix" ] && fix_mode=true
  _banner "Password Audit"
  local entries; entries="$(list_entries | grep -v '\-pub$\|-pvt$' || true)"
  declare -A _seen
  local total=0 weak=0 dupes=0 aged=0
  step "Scanning (requires GPG decryption)..."
  echo ""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local pw; pw="$(pass show "$entry" 2>/dev/null | sed -n '1p')" || continue
    [ -z "$pw" ] && continue
    total=$((total+1))
    local len u l n s score issues=""
    len=${#pw}
    u=$(printf "%s" "$pw" | grep -c '[A-Z]' 2>/dev/null || true); u=$((u>0?1:0))
    l=$(printf "%s" "$pw" | grep -c '[a-z]' 2>/dev/null || true); l=$((l>0?1:0))
    n=$(printf "%s" "$pw" | grep -c '[0-9]' 2>/dev/null || true); n=$((n>0?1:0))
    s=$(printf "%s" "$pw" | grep -c '[^A-Za-z0-9]' 2>/dev/null || true); s=$((s>0?1:0))
    score=$((u+l+n+s))
    [ "$len" -lt 12 ] || [ "$score" -lt 3 ] && {
      weak=$((weak+1))
      issues+="${C_RED}[WEAK len=${len} score=${score}/4]${C_RESET} "
    }
    local h="${len}_${pw:0:3}_${pw: -3}"
    [ -n "${_seen[$h]:-}" ] && {
      dupes=$((dupes+1))
      issues+="${C_YELLOW}[DUPE of ${_seen[$h]}]${C_RESET} "
    } || _seen[$h]="$entry"
    [ -d "$PASSWORD_STORE_DIR/.git" ] && {
      local lc days
      lc="$(cd "$PASSWORD_STORE_DIR" \
        && git log -1 --format="%ct" -- "${entry}.gpg" 2>/dev/null || echo 0)"
      [ "$lc" -gt 0 ] && {
        days=$(( ($(date +%s) - lc) / 86400 ))
        [ "$days" -gt "$PASSX_MAX_AGE" ] && {
          aged=$((aged+1))
          issues+="${C_CYAN}[AGED ${days}d]${C_RESET} "
        }
      }
    }
    [ -n "$issues" ] && {
      printf "  %-40s " "$entry"
      printf "%b\n" "$issues"
      $fix_mode && [[ "$issues" == *WEAK* ]] && {
        printf "     ${C_DIM}→ rotating...${C_RESET}\n"
        cmd_rotate "$entry" >/dev/null && printf "     ${C_GREEN}✔ rotated${C_RESET}\n" || true
      }
    }
  done <<< "$entries"
  echo ""
  _section "Summary"
  printf "  %-26s ${C_BOLD}%d${C_RESET}\n" "Entries scanned" "$total"
  [ $weak  -gt 0 ] && printf "  %-26s ${C_RED}${C_BOLD}%d${C_RESET}\n"    "Weak"  "$weak" \
                    || printf "  %-26s ${C_GREEN}0 — all good${C_RESET}\n" "Weak"
  [ $dupes -gt 0 ] && printf "  %-26s ${C_YELLOW}${C_BOLD}%d${C_RESET}\n" "Duplicates" "$dupes" \
                    || printf "  %-26s ${C_GREEN}0 — all good${C_RESET}\n" "Duplicates"
  [ $aged  -gt 0 ] && printf "  %-26s ${C_CYAN}${C_BOLD}%d${C_RESET}  ${C_DIM}(>%dd)${C_RESET}\n" \
                        "Aged" "$aged" "$PASSX_MAX_AGE" \
                    || printf "  %-26s ${C_GREEN}0 — all good${C_RESET}\n" "Aged"
  echo ""
  [ $((weak+dupes+aged)) -eq 0 ] && ok "All passwords look healthy!"
  $fix_mode && [ $weak -gt 0 ] && info "Weak passwords have been rotated"
  return 0
}

# ════════════════════════════════════════════════════════════════
# § HIBP
# ════════════════════════════════════════════════════════════════
_hibp_one() {
  local path="$1"
  local pw; pw="$(extract_field "$path" password)"
  [ -z "${pw:-}" ] && { warn "No password in $path"; return; }
  local hash prefix suffix resp count
  hash="$(printf "%s" "$pw" | sha1sum | awk '{print toupper($1)}')"
  prefix="${hash:0:5}"; suffix="${hash:5}"
  resp="$(curl -sf --max-time 5 "https://api.pwnedpasswords.com/range/${prefix}" 2>/dev/null)" || {
    warn "HIBP API request failed for $path"; return; }
  count="$(printf "%s\n" "$resp" | grep -i "^${suffix}:" | cut -d: -f2 || echo 0)"
  count="${count//[[:space:]]/}"
  if [ -n "${count:-}" ] && [ "${count:-0}" -gt 0 ]; then
    printf "  ${C_RED}${C_BOLD}✖ BREACHED${C_RESET}  %-36s  ${C_DIM}found %s times${C_RESET}\n" "$path" "$count"
    return 1
  else
    printf "  ${C_GREEN}✔ SAFE${C_RESET}      %-36s\n" "$path"
    return 0
  fi
}

cmd_hibp() {
  _cmd="hibp"
  command -v curl    >/dev/null 2>&1 || err "curl required"
  command -v sha1sum >/dev/null 2>&1 || err "sha1sum required"
  if [ "${1:-}" = "--all" ]; then
    _banner "HaveIBeenPwned — All Entries"
    info "k-anonymity: only first 5 hash chars sent to HIBP"
    echo ""
    local breached=0
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      [[ "$e" == *-pub ]] || [[ "$e" == *-pvt ]] && continue
      _hibp_one "$e" || breached=$((breached+1))
      sleep 1   # rate limiting
    done < <(list_entries)
    echo ""
    [ $breached -gt 0 ] \
      && { printf "  ${C_RED}${C_BOLD}%d breached — rotate immediately!${C_RESET}\n\n" "$breached"
           _notify passx "${breached} breached passwords found"; } \
      || ok "No breached passwords"
    return 0
  fi
  local path="${1:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "hibp" "Select entry to check")" || true
  [ -z "${path:-}" ] && err "No entry selected"
  _banner "HaveIBeenPwned"
  info "k-anonymity: only first 5 hash chars sent"
  echo ""
  _hibp_one "$path" \
    || { printf "\n  ${C_RED}Rotate now:${C_RESET} passx rotate %s\n\n" "$path"
         _notify passx "⚠ Breached: ${path##*/}"; }
}

# ════════════════════════════════════════════════════════════════
# § AGE REPORT
# ════════════════════════════════════════════════════════════════
cmd_age() {
  _cmd="age"
  _need_git
  local warn_days="${1:-$PASSX_MAX_AGE}"
  _banner "Password Age  (warn after ${warn_days}d)"
  local count=0
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    [[ "$e" == *-pub ]] || [[ "$e" == *-pvt ]] && continue
    local lc days ds
    lc="$(cd "$PASSWORD_STORE_DIR" \
      && git log -1 --format="%ct" -- "${e}.gpg" 2>/dev/null || echo 0)"
    [ "$lc" -eq 0 ] && continue
    days=$(( ($(date +%s) - lc) / 86400 ))
    ds="$(date -d "@${lc}" '+%Y-%m-%d' 2>/dev/null \
       || date -r "$lc"   '+%Y-%m-%d' 2>/dev/null || echo '?')"
    count=$((count+1))
    [ "$days" -gt "$warn_days" ] \
      && printf "  ${C_RED}%4dd${C_RESET}  %-38s  ${C_DIM}%s${C_RESET}\n" "$days" "$e" "$ds" \
      || printf "  ${C_GREEN}%4dd${C_RESET}  %-38s  ${C_DIM}%s${C_RESET}\n" "$days" "$e" "$ds"
  done < <(list_entries | sort)
  [ $count -eq 0 ] && info "No git history found"
  echo ""
}

# ════════════════════════════════════════════════════════════════
# § SSH KEYS
# ════════════════════════════════════════════════════════════════
_ssh_store() {
  local base="$1" pvt="$2"
  [ -f "$pvt"       ] || err "Private key not found: $pvt"
  [ -f "${pvt}.pub" ] || err "Public key not found: ${pvt}.pub"
  step "Storing public  → ${base}-pub"
  pass insert -m -f "${base}-pub"  < "${pvt}.pub"   || err "Failed to store public key"
  step "Storing private → ${base}-pvt"
  pass insert -m -f "${base}-pvt"  < "$pvt"          || err "Failed to store private key"
}

cmd_ssh_add() {
  _cmd="ssh-add"
  local base="${1:-}"
  [ -z "$base" ] && { printf "  Store path (e.g. ssh/github): " >&2; read -r base </dev/tty || true; }
  [ -z "${base:-}" ] && err "No path provided"
  local sshdir="$HOME/.ssh"; mkdir -p "$sshdir"; chmod 700 "$sshdir"
  [ -z "${SSH_AUTH_SOCK:-}" ] && eval "$(ssh-agent -s)" >/dev/null 2>&1 || true

  local action
  command -v fzf >/dev/null 2>&1 \
    && action="$(printf "Use existing key\nCreate new key\nCancel" \
         | _fzf_pick "action" "SSH key management" 30%)" \
    || { printf "  1) Use existing  2) Create new  3) Cancel\n  Choice: " >&2
         read -r _c </dev/tty || _c=3
         case "$_c" in 1) action="Use existing key";; 2) action="Create new key";; *) action="Cancel";; esac; }

  case "$action" in
    "Use existing key")
      local kl; kl="$(find "$sshdir" -maxdepth 1 -name '*.pub' 2>/dev/null \
        | sed 's|\.pub$||' | sort)"
      [ -z "$kl" ] && err "No SSH keys in $sshdir"
      local pvt
      command -v fzf >/dev/null 2>&1 \
        && pvt="$(printf "%s\n" "$kl" | _fzf_pick "key" "Select SSH key" 30%)" \
        || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$kl"
             printf "  Select: " >&2; read -r _n </dev/tty; pvt="$(printf "%s\n" "$kl" | sed -n "${_n}p")"; }
      [ -z "${pvt:-}" ] && { dim "Aborted"; return 0; }
      _banner "Storing SSH key"
      _ssh_store "$base" "$pvt"
      ssh-add "$pvt" 2>/dev/null && ok "Added to ssh-agent" || warn "ssh-add failed"
      ok "Stored: ${base}-pub  ${base}-pvt"
      dim "Restore on any machine: passx ssh-set $base" ;;
    "Create new key")
      printf "  Key name (stored as ~/.ssh/<name>): " >&2; read -r _kn </dev/tty || _kn=""
      [ -z "${_kn:-}" ] && err "No name provided"
      printf "  Comment/email (optional): " >&2; read -r _kc </dev/tty || _kc=""
      local pvt="$sshdir/$_kn"
      [ -f "$pvt" ] && err "Key already exists: $pvt"
      _banner "Generating SSH key (ed25519)"
      [ -n "${_kc:-}" ] && ssh-keygen -t ed25519 -a 100 -f "$pvt" -C "$_kc" \
                        || ssh-keygen -t ed25519 -a 100 -f "$pvt"
      chmod 600 "$pvt"; chmod 644 "${pvt}.pub"
      _ssh_store "$base" "$pvt"
      ssh-add "$pvt" 2>/dev/null && ok "Added to agent" || warn "ssh-add failed"
      ok "Created and stored: ${base}-pub  ${base}-pvt"
      echo ""; printf "  ${C_BOLD}Public key:${C_RESET}\n"; cat "${pvt}.pub" ;;
    *) dim "Cancelled"; return 0 ;;
  esac
  _hook post-ssh-add "$base"
  _autosync
}

cmd_ssh_set() {
  _cmd="ssh-set"
  _banner "Restore SSH key"
  local pubs; pubs="$(list_entries | grep '^ssh/.*-pub$' || true)"
  [ -z "$pubs" ] && err "No SSH keys in store.  Add with: passx ssh-add"

  local chosen
  command -v fzf >/dev/null 2>&1 \
    && chosen="$(printf "%s\n" "$pubs" | _fzf_pick "ssh-set" "Select key to restore" 40%)" \
    || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$pubs"
         printf "  Select: " >&2; read -r _n </dev/tty; chosen="$(printf "%s\n" "$pubs" | sed -n "${_n}p")"; }
  [ -z "${chosen:-}" ] && { dim "Aborted"; return 0; }

  local base="${chosen%-pub}" keyname="${chosen%-pub}"; keyname="${keyname##*/}"
  local sshdir="$HOME/.ssh" pvt="$HOME/.ssh/$keyname" pub="$HOME/.ssh/${keyname}.pub"
  local stored_pub; stored_pub="$(pass show "${base}-pub" 2>/dev/null)" || err "Cannot read ${base}-pub"

  local fp; fp="$(printf "%s\n" "$stored_pub" | ssh-keygen -l -f /dev/stdin 2>/dev/null || true)"
  [ -n "${fp:-}" ] && { echo ""; printf "  ${C_BOLD}Fingerprint:${C_RESET} %s\n" "$fp"; }

  if [ -f "$pub" ]; then
    local disk_pub; disk_pub="$(cat "$pub" 2>/dev/null || true)"
    if [ "$stored_pub" = "$disk_pub" ]; then
      ok "Public key already installed at $pub"
      [ -f "$pvt" ] && {
        printf "  Add to ssh-agent? [y/N] " >&2; read -r yn </dev/tty || yn=""
        [ "${yn,,}" = "y" ] && { ssh-add "$pvt" && ok "Added to agent"; }
      }
      return 0
    else
      warn "Different key already at $pub"
      printf "  Overwrite? [y/N] " >&2; read -r yn </dev/tty || yn=""
      [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
    fi
  fi

  printf "  Write to %s ? [y/N] " "$pub" >&2; read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }

  mkdir -p "$sshdir"; chmod 700 "$sshdir"
  printf "%s\n" "$stored_pub" > "$pub"; chmod 644 "$pub"
  ok "Public key → $pub"

  _guard_pvt "${base}-pvt"
  local pvt_key; pvt_key="$(pass show "${base}-pvt" 2>/dev/null)" || err "Cannot read ${base}-pvt"
  printf "%s\n" "$pvt_key" > "$pvt"; chmod 600 "$pvt"
  ok "Private key → $pvt"

  [ -z "${SSH_AUTH_SOCK:-}" ] && eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  ssh-add "$pvt" 2>/dev/null && ok "Added to ssh-agent" || warn "ssh-add failed"

  local sconf="$sshdir/config"
  if ! grep -q "IdentityFile.*${pvt}" "$sconf" 2>/dev/null; then
    printf "\n  Add entry to ~/.ssh/config? [y/N] " >&2; read -r yn </dev/tty || yn=""
    if [ "${yn,,}" = "y" ]; then
      printf "  Host label (e.g. github.com): " >&2; read -r _hl </dev/tty || _hl=""
      [ -n "${_hl:-}" ] && {
        { printf "\n# Added by passx\nHost %s\n    IdentityFile %s\n" "$_hl" "$pvt"; } >> "$sconf"
        chmod 600 "$sconf"; ok "Added Host block for $_hl to ~/.ssh/config"
      }
    fi
  fi
  ok "SSH key '$keyname' restored"
  _notify passx "SSH key restored: $keyname"
}

cmd_ssh_rm() {
  _cmd="ssh-rm"
  local base="${1:-}"
  [ -z "$base" ] && {
    local pubs; pubs="$(list_entries | grep '^ssh/.*-pub$' | sed 's/-pub$//' || true)"
    [ -z "$pubs" ] && err "No SSH keys in store"
    command -v fzf >/dev/null 2>&1 \
      && base="$(printf "%s\n" "$pubs" | _fzf_pick "ssh-rm" "Select key to remove" 30%)" \
      || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$pubs"
           printf "  Select: " >&2; read -r _n </dev/tty; base="$(printf "%s\n" "$pubs" | sed -n "${_n}p")"; }
  }
  [ -z "${base:-}" ] && err "No key selected"
  printf "\n  ${C_YELLOW}Remove %s-pub + %s-pvt?${C_RESET} [y/N] " "$base" "$base" >&2
  read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
  pass rm -f "${base}-pub" 2>/dev/null && ok "Removed ${base}-pub" || warn "Not found: ${base}-pub"
  pass rm -f "${base}-pvt" 2>/dev/null && ok "Removed ${base}-pvt" || warn "Not found: ${base}-pvt"
  _autosync
}

cmd_ssh_list() {
  _cmd="ssh-list"
  _banner "SSH keys in store"
  local found=false
  while IFS= read -r e; do
    [[ "$e" == *-pub ]] || continue
    local b="${e%-pub}"
    local pvt_ok; pass show "${b}-pvt" >/dev/null 2>&1 \
      && pvt_ok="${C_GREEN}pvt ✔${C_RESET}" || pvt_ok="${C_RED}pvt ✖${C_RESET}"
    printf "  ${C_CYAN}%-40s${C_RESET}  pub ✔  %b\n" "$b" "$pvt_ok"
    found=true
  done < <(list_entries | grep '^ssh/')
  $found || info "No SSH keys — add with: passx ssh-add"
  echo ""
}

cmd_ssh_copy_id() {
  _cmd="ssh-copy-id"
  local base="${1:-}" remote="${2:-}"
  [ -z "$base" ] && {
    local pubs; pubs="$(list_entries | grep '^ssh/.*-pub$' | sed 's/-pub$//' || true)"
    command -v fzf >/dev/null 2>&1 \
      && base="$(printf "%s\n" "$pubs" | _fzf_pick "ssh-copy-id" "Select key" 30%)" \
      || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$pubs"
           printf "  Select: " >&2; read -r _n </dev/tty; base="$(printf "%s\n" "$pubs" | sed -n "${_n}p")"; }
  }
  [ -z "${base:-}" ] && err "No key selected"
  [ -z "$remote"   ] && { printf "  Remote (user@host): " >&2; read -r remote </dev/tty; }
  [ -z "${remote:-}" ] && err "No remote provided"
  local pub; pub="$(pass show "${base}-pub" 2>/dev/null)" || err "Cannot read ${base}-pub"
  printf "%s\n" "$pub" | ssh "$remote" \
    "mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys" \
    && ok "Public key installed on $remote" || err "Failed to copy to $remote"
}

cmd_ssh_agent_status() {
  _cmd="ssh-agent-status"
  _banner "SSH Agent Status"
  if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    warn "ssh-agent not running (SSH_AUTH_SOCK not set)"
    return 0
  fi
  local keys; keys="$(ssh-add -l 2>/dev/null || true)"
  if [ -z "$keys" ] || [ "$keys" = "The agent has no identities." ]; then
    info "Agent running — no keys loaded"
  else
    printf "%s\n" "$keys" | while IFS= read -r line; do
      printf "  ${C_GREEN}◉${C_RESET}  %s\n" "$line"
    done
  fi
  echo ""
}

# ════════════════════════════════════════════════════════════════
# § GPG KEYS
# ════════════════════════════════════════════════════════════════
_gpg_store() {
  local base="$1" keyid="$2"
  step "Exporting public  → ${base}-pub"
  gpg --export --armor "$keyid" 2>/dev/null \
    | pass insert -m -f "${base}-pub" || err "Failed to store GPG public key"
  step "Exporting private → ${base}-pvt"
  gpg --export-secret-keys --armor "$keyid" 2>/dev/null \
    | pass insert -m -f "${base}-pvt" || err "Failed to store GPG private key"
}

cmd_gpg_add() {
  _cmd="gpg-add"
  command -v gpg >/dev/null 2>&1 || err "gpg required"
  local base="${1:-}"
  [ -z "$base" ] && { printf "  Store path (e.g. gpg/work): " >&2; read -r base </dev/tty || true; }
  [ -z "${base:-}" ] && err "No path provided"
  local action
  command -v fzf >/dev/null 2>&1 \
    && action="$(printf "Use existing key\nCreate new key\nCancel" \
         | _fzf_pick "action" "GPG key management" 30%)" \
    || { printf "  1) Use existing  2) Create new  3) Cancel\n  Choice: " >&2
         read -r _c </dev/tty || _c=3
         case "$_c" in 1) action="Use existing key";; 2) action="Create new key";; *) action="Cancel";; esac; }
  case "$action" in
    "Use existing key")
      local klines; klines="$(gpg --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^sec/{id=$5}/^uid/{print id " │ " $10}' | sort -u)"
      [ -z "$klines" ] && err "No GPG secret keys in keyring"
      local chosen_line chosen_id
      command -v fzf >/dev/null 2>&1 \
        && chosen_line="$(printf "%s\n" "$klines" | _fzf_pick "key" "Select GPG key" 30%)" \
        || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$klines"
             printf "  Select: " >&2; read -r _n </dev/tty; chosen_line="$(printf "%s\n" "$klines" | sed -n "${_n}p")"; }
      [ -z "${chosen_line:-}" ] && { dim "Aborted"; return 0; }
      chosen_id="$(printf "%s" "$chosen_line" | awk -F' │ ' '{print $1}' | xargs)"
      _banner "Storing GPG key"
      _gpg_store "$base" "$chosen_id"
      ok "Stored: ${base}-pub  ${base}-pvt" ;;
    "Create new key")
      _banner "Create GPG key"; info "Recommended: ECC ed25519+cv25519"
      gpg --full-generate-key || err "Key generation failed"
      local new_id
      new_id="$(gpg --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^sec/{id=$5}END{print id}')"
      _gpg_store "$base" "$new_id"
      ok "Created and stored: ${base}-pub  ${base}-pvt" ;;
    *) dim "Cancelled"; return 0 ;;
  esac
  _hook post-gpg-add "$base"; _autosync
}

cmd_gpg_set() {
  _cmd="gpg-set"
  command -v gpg >/dev/null 2>&1 || err "gpg required"
  _banner "Restore GPG key"
  local pubs; pubs="$(list_entries | grep '^gpg/.*-pub$' || true)"
  [ -z "$pubs" ] && err "No GPG keys in store.  Add with: passx gpg-add"
  local chosen
  command -v fzf >/dev/null 2>&1 \
    && chosen="$(printf "%s\n" "$pubs" | _fzf_pick "gpg-set" "Select key to restore" 40%)" \
    || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$pubs"
         printf "  Select: " >&2; read -r _n </dev/tty; chosen="$(printf "%s\n" "$pubs" | sed -n "${_n}p")"; }
  [ -z "${chosen:-}" ] && { dim "Aborted"; return 0; }
  local base="${chosen%-pub}"
  local pub_key; pub_key="$(pass show "${base}-pub" 2>/dev/null)" || err "Cannot read ${base}-pub"
  local fp
  fp="$(printf "%s\n" "$pub_key" \
    | gpg --with-fingerprint --import-options import-show --dry-run 2>/dev/null \
    | awk '/fingerprint/{gsub(/ /,"");sub(/Keyfingerprint=/,"");print;exit}' || true)"

  if [ -n "$fp" ] && gpg --list-keys "$fp" >/dev/null 2>&1; then
    ok "Public key already in keyring ($fp)"
  else
    step "Importing public key..."
    printf "%s\n" "$pub_key" | gpg --import 2>/dev/null && ok "Public key imported" || warn "Import failed"
  fi

  printf "\n  Import private key? [y/N] " >&2; read -r yn </dev/tty || yn=""
  if [ "${yn,,}" = "y" ]; then
    [ -n "$fp" ] && gpg --list-secret-keys "$fp" >/dev/null 2>&1 \
      && { ok "Private key already in keyring"; } || {
      _guard_pvt "${base}-pvt"
      pass show "${base}-pvt" 2>/dev/null | gpg --import 2>/dev/null \
        && ok "Private key imported" || err "Import failed"
    }
    [ -n "$fp" ] && {
      printf "  Set ultimate trust? [y/N] " >&2; read -r yn </dev/tty || yn=""
      [ "${yn,,}" = "y" ] && {
        printf "5\ny\n" | gpg --command-fd 0 --expert --batch \
          --edit-key "$fp" trust 2>/dev/null && ok "Trust set" || warn "Trust update failed"
      }
      local gpg_conf="$HOME/.gnupg/gpg.conf"
      ! grep -q "^default-key" "$gpg_conf" 2>/dev/null && {
        printf "  Set as default key in gpg.conf? [y/N] " >&2; read -r yn </dev/tty || yn=""
        [ "${yn,,}" = "y" ] && {
          mkdir -p "$HOME/.gnupg"; chmod 700 "$HOME/.gnupg"
          printf "default-key %s\n" "$fp" >> "$gpg_conf"
          ok "Set default-key in gpg.conf"
        }
      }
    }
  fi
  ok "GPG key '${base}' restored"
  _notify passx "GPG key restored: $base"
}

cmd_gpg_rm() {
  _cmd="gpg-rm"
  local base="${1:-}"
  [ -z "$base" ] && {
    local pubs; pubs="$(list_entries | grep '^gpg/.*-pub$' | sed 's/-pub$//' || true)"
    [ -z "$pubs" ] && err "No GPG keys in store"
    command -v fzf >/dev/null 2>&1 \
      && base="$(printf "%s\n" "$pubs" | _fzf_pick "gpg-rm" "Select key to remove" 30%)" \
      || { local i=1; while IFS= read -r k; do printf "  %d) %s\n" $i "$k"; ((i++)); done <<< "$pubs"
           printf "  Select: " >&2; read -r _n </dev/tty; base="$(printf "%s\n" "$pubs" | sed -n "${_n}p")"; }
  }
  [ -z "${base:-}" ] && err "No key selected"
  printf "\n  ${C_YELLOW}Remove %s-pub + %s-pvt?${C_RESET} [y/N] " "$base" "$base" >&2
  read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
  pass rm -f "${base}-pub" 2>/dev/null && ok "Removed ${base}-pub" || warn "Not found"
  pass rm -f "${base}-pvt" 2>/dev/null && ok "Removed ${base}-pvt" || warn "Not found"
  _autosync
}

cmd_gpg_list() {
  _cmd="gpg-list"
  _banner "GPG keys in store"
  local found=false
  while IFS= read -r e; do
    [[ "$e" == *-pub ]] || continue
    local b="${e%-pub}"
    local pvt_ok; pass show "${b}-pvt" >/dev/null 2>&1 \
      && pvt_ok="${C_GREEN}pvt ✔${C_RESET}" || pvt_ok="${C_RED}pvt ✖${C_RESET}"
    printf "  ${C_MAGENTA}%-40s${C_RESET}  pub ✔  %b\n" "$b" "$pvt_ok"
    found=true
  done < <(list_entries | grep '^gpg/')
  $found || info "No GPG keys — add with: passx gpg-add"
  echo ""
}

# ════════════════════════════════════════════════════════════════
# § SHARE / RECIPIENTS / REENCRYPT
# ════════════════════════════════════════════════════════════════
cmd_share() {
  _cmd="share"
  command -v gpg >/dev/null 2>&1 || err "gpg required"
  local path="${1:-}" recipient="${2:-}"
  [ -z "$path" ] && path="$(list_entries | _fzf_pick "share" "Select entry to share")" || true
  [ -z "${path:-}" ] && err "Usage: passx share <path> <gpg-email-or-keyid>"
  [ -z "$recipient" ] && { printf "  Recipient (email or key ID): " >&2; read -r recipient </dev/tty; }
  [ -z "${recipient:-}" ] && err "No recipient"
  local content; content="$(pass show "$path" 2>/dev/null)" || err "Cannot decrypt $path"
  step "Encrypting for $recipient..."
  printf "%s\n" "$content" | gpg --encrypt --armor -r "$recipient" 2>/dev/null \
    || err "Encryption failed — is $recipient in your GPG keyring?"
  ok "Encrypted block ready — share the PGP block above"
}

cmd_recipients() {
  _cmd="recipients"
  _banner "Store recipients"
  local f="$PASSWORD_STORE_DIR/.gpg-id"
  [ ! -f "$f" ] && err "No .gpg-id file found"
  while IFS= read -r rid; do
    [ -z "$rid" ] || [[ "$rid" == '#'* ]] && continue
    local uid; uid="$(gpg --list-keys --with-colons "$rid" 2>/dev/null \
      | awk -F: '/^uid/{print $10;exit}' || echo "(unknown)")"
    printf "  ${C_CYAN}%-22s${C_RESET}  %s\n" "$rid" "$uid"
  done < "$f"
  echo ""
}

cmd_reencrypt() {
  _cmd="reencrypt"
  _banner "Re-encrypt store"
  cat "$PASSWORD_STORE_DIR/.gpg-id" 2>/dev/null | grep -v '^#\|^$' \
    | while IFS= read -r r; do printf "  ${C_DIM}%s${C_RESET}\n" "$r"; done
  echo ""
  printf "  New recipient key IDs (space-separated, Enter to cancel):\n  > " >&2
  read -r _rids </dev/tty || _rids=""
  [ -z "${_rids:-}" ] && { dim "Cancelled"; return 0; }
  local args=(); for rid in $_rids; do args+=("-p" "$rid"); done
  step "Re-initialising store..."
  pass init "${args[@]}" || err "Re-encryption failed"
  ok "Store re-encrypted for: $_rids"
}

# ════════════════════════════════════════════════════════════════
# § IMPORT
# ════════════════════════════════════════════════════════════════
_import_one() {
  local path="$1" pw="$2" user="$3" email="$4" url="$5" notes="$6"
  path="$(printf "%s" "$path" | tr ' ' '_' | tr -cd 'A-Za-z0-9/_-')"
  [ -z "$path" ] && return 1
  pass show "$path" >/dev/null 2>&1 && { warn "Skipping (exists): $path"; return 1; }
  {
    printf "%s\n" "${pw:-$(gen_password)}"
    [ -n "${user:-}"  ] && printf "username: %s\n" "$user"
    [ -n "${email:-}" ] && printf "email: %s\n"    "$email"
    [ -n "${url:-}"   ] && printf "url: %s\n"      "$url"
    [ -n "${notes:-}" ] && printf "notes: %s\n"    "$notes"
  } | pass insert -m "$path" >/dev/null 2>&1 && return 0 || return 1
}

cmd_import_csv() {
  _cmd="import-csv"
  local file="${1:-}"; [ -z "$file" ] && err "Usage: passx import-csv <file.csv>"
  [ ! -f "$file" ] && err "Not found: $file"
  _banner "Import CSV"
  local ok_c=0 skip=0 hdr=1
  while IFS=',' read -r name pw user email url notes _r; do
    [ $hdr -eq 1 ] && { hdr=0; continue; }
    name="$(printf "%s" "$name" | tr -d '"')"; pw="$(printf "%s" "$pw" | tr -d '"')"
    user="$(printf "%s" "$user" | tr -d '"')"; email="$(printf "%s" "$email" | tr -d '"')"
    url="$(printf "%s" "$url" | tr -d '"')"; notes="$(printf "%s" "$notes" | tr -d '"')"
    [ -z "$name" ] && { skip=$((skip+1)); continue; }
    _import_one "$name" "$pw" "$user" "$email" "$url" "$notes" \
      && { ok "  $name"; ok_c=$((ok_c+1)); } || skip=$((skip+1))
  done < "$file"
  echo ""; ok "${ok_c} imported, ${skip} skipped"; _autosync
}

cmd_import_bitwarden() {
  _cmd="import-bitwarden"
  local file="${1:-}"; [ -z "$file" ] && err "Usage: passx import-bitwarden <export.json>"
  [ ! -f "$file" ] && err "Not found: $file"
  command -v jq >/dev/null 2>&1 || err "jq required"
  _banner "Import Bitwarden JSON"
  local ok_c=0 skip=0
  while IFS=$'\t' read -r name user pw url notes; do
    [ -z "$name" ] && { skip=$((skip+1)); continue; }
    _import_one "$name" "$pw" "$user" "" "$url" "$notes" \
      && { ok "  $name"; ok_c=$((ok_c+1)); } || skip=$((skip+1))
  done < <(jq -r '.items[]|select(.type==1)|
    [.name,(.login.username//""),(.login.password//""),((.login.uris//[])[0].uri//""),(.notes//"")]|@tsv' \
    "$file" 2>/dev/null)
  echo ""; ok "${ok_c} imported, ${skip} skipped"; _autosync
}

cmd_import_firefox() {
  _cmd="import-firefox"
  local file="${1:-}"; [ -z "$file" ] && err "Usage: passx import-firefox <logins.csv>"
  [ ! -f "$file" ] && err "Not found: $file"
  _banner "Import Firefox CSV"
  local ok_c=0 skip=0 hdr=1
  while IFS=',' read -r url user pw _r; do
    [ $hdr -eq 1 ] && { hdr=0; continue; }
    url="$(printf "%s" "$url" | tr -d '"')"; user="$(printf "%s" "$user" | tr -d '"')"
    pw="$(printf "%s" "$pw" | tr -d '"')"
    [ -z "$url" ] && { skip=$((skip+1)); continue; }
    local name; name="$(printf "%s" "$url" | sed 's|https\?://||; s|/.*||')"
    _import_one "firefox/$name" "$pw" "$user" "" "$url" "" \
      && { ok "  firefox/$name"; ok_c=$((ok_c+1)); } || skip=$((skip+1))
  done < "$file"
  echo ""; ok "${ok_c} imported, ${skip} skipped"; _autosync
}

cmd_import_chrome() {
  _cmd="import-chrome"
  local file="${1:-}"; [ -z "$file" ] && err "Usage: passx import-chrome <passwords.csv>"
  [ ! -f "$file" ] && err "Not found: $file"
  _banner "Import Chrome CSV"
  local ok_c=0 skip=0 hdr=1
  while IFS=',' read -r name url user pw _r; do
    [ $hdr -eq 1 ] && { hdr=0; continue; }
    name="$(printf "%s" "$name" | tr -d '"')"; url="$(printf "%s" "$url" | tr -d '"')"
    user="$(printf "%s" "$user" | tr -d '"')"; pw="$(printf "%s" "$pw" | tr -d '"')"
    [ -z "$name" ] && name="$(printf "%s" "$url" | sed 's|https\?://||; s|/.*||')"
    _import_one "chrome/$name" "$pw" "$user" "" "$url" "" \
      && { ok "  chrome/$name"; ok_c=$((ok_c+1)); } || skip=$((skip+1))
  done < "$file"
  echo ""; ok "${ok_c} imported, ${skip} skipped"; _autosync
}

cmd_import_keepass() {
  _cmd="import-keepass"
  local file="${1:-}"; [ -z "$file" ] && err "Usage: passx import-keepass <export.xml>"
  [ ! -f "$file" ] && err "Not found: $file"
  command -v python3 >/dev/null 2>&1 || err "python3 required"
  _banner "Import KeePass XML"
  local ok_c=0 skip=0
  while IFS=$'\t' read -r title user pw url notes; do
    [ -z "$title" ] && { skip=$((skip+1)); continue; }
    _import_one "keepass/$title" "$pw" "$user" "" "$url" "$notes" \
      && { ok "  keepass/$title"; ok_c=$((ok_c+1)); } || skip=$((skip+1))
  done < <(python3 - "$file" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
def walk(node):
    for e in node.findall('Entry'):
        d={s.find('Key').text:(s.find('Value').text or '') for s in e.findall('String')}
        print('\t'.join([d.get('Title',''),d.get('UserName',''),d.get('Password',''),d.get('URL',''),d.get('Notes','')]))
    for g in node.findall('Group'): walk(g)
for r in ET.parse(sys.argv[1]).findall('.//Group'): walk(r)
PYEOF
)
  echo ""; ok "${ok_c} imported, ${skip} skipped"; _autosync
}

# ════════════════════════════════════════════════════════════════
# § EXPORT
# ════════════════════════════════════════════════════════════════
cmd_export_bitwarden() {
  _cmd="export-bitwarden"
  local out="${1:-}"; [ -z "$out" ] && err "Usage: passx export-bitwarden <output.json>"
  command -v jq >/dev/null 2>&1 || err "jq required"
  _banner "Export to Bitwarden JSON"
  warn "Exports decrypted passwords — keep the output file secure"
  printf "  Continue? [y/N] " >&2; read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
  local items="[]"
  while IFS= read -r entry; do
    [[ "$entry" == *-pub ]] || [[ "$entry" == *-pvt ]] && continue
    local e pw user email url notes
    e="$(pass show "$entry" 2>/dev/null)" || continue
    pw="$(printf "%s\n" "$e" | sed -n '1p')"
    user="$(printf "%s\n" "$e" | grep -m1 "^username:" | sed "s/^username: *//")"
    email="$(printf "%s\n" "$e" | grep -m1 "^email:" | sed "s/^email: *//")"
    url="$(printf "%s\n" "$e" | grep -m1 "^url:" | sed "s/^url: *//")"
    notes="$(printf "%s\n" "$e" | grep -m1 "^notes:" | sed "s/^notes: *//")"
    local item; item="$(jq -n \
      --arg n "$entry" --arg u "${user:-${email:-}}" \
      --arg p "$pw" --arg l "${url:-}" --arg no "${notes:-}" \
      '{type:1,name:$n,notes:$no,login:{username:$u,password:$p,uris:[{uri:$l}]}}')"
    items="$(jq -n --argjson a "$items" --argjson b "$item" '$a+[$b]')"
    ok "  $entry"
  done < <(list_entries)
  jq -n --argjson items "$items" '{encrypted:false,items:$items}' > "$out"
  ok "Bitwarden export → $out"
}

cmd_export_encrypted() {
  _cmd="export-encrypted"
  local out="${1:-}"; [ -z "$out" ] && err "Usage: passx export-encrypted <file.gpg>"
  command -v gpg >/dev/null 2>&1 || err "gpg required"
  _banner "Encrypted Store Export"
  local tmp; tmp="$(mktemp -d)"
  step "Archiving..."
  tar -C "$(dirname "$PASSWORD_STORE_DIR")" -czf "$tmp/store.tar.gz" \
    "$(basename "$PASSWORD_STORE_DIR")" || { rm -rf "$tmp"; err "tar failed"; }
  step "Encrypting with symmetric passphrase..."
  gpg -c -o "$out" "$tmp/store.tar.gz" || { rm -rf "$tmp"; err "gpg failed"; }
  rm -rf "$tmp"; ok "Encrypted export → $out"
}

# ════════════════════════════════════════════════════════════════
# § MAINTENANCE — GC / LINT / VERIFY
# ════════════════════════════════════════════════════════════════
cmd_gc() {
  _cmd="gc"
  local auto_rm=false
  [ "${1:-}" = "--rm" ] || [ "${1:-}" = "rm" ] && auto_rm=true
  _banner "Garbage Collect${auto_rm:+ (auto-remove mode)}"
  local issues=0 removed=0
  local -a orphans=()

  while IFS= read -r e; do
    [ -z "$e" ] && continue
    local is_orphan=false orphan_reason=""
    [[ "$e" == *-pub ]] && {
      local b="${e%-pub}"
      pass show "${b}-pvt" >/dev/null 2>&1         || { orphan_reason="pub without pvt"; is_orphan=true; } }
    [[ "$e" == *-pvt ]] && {
      local b="${e%-pvt}"
      pass show "${b}-pub" >/dev/null 2>&1         || { orphan_reason="pvt without pub"; is_orphan=true; } }
    { [[ "$e" == ssh/* ]] || [[ "$e" == gpg/* ]]; } &&     [[ "$e" != *-pub ]] && [[ "$e" != *-pvt ]] &&       { orphan_reason="unexpected in ssh/gpg namespace"; is_orphan=true; }

    if $is_orphan; then
      warn "Orphan [$orphan_reason]: $e"
      issues=$((issues+1))
      orphans+=("$e")
    fi
  done < <(list_entries)

  echo ""
  if [ $issues -eq 0 ]; then
    ok "Store clean — no issues"
    return 0
  fi

  warn "$issues orphan(s) found"

  if $auto_rm; then
    echo ""
    step "Auto-removing orphans..."
    for o in "${orphans[@]}"; do
      pass rm -f "$o" 2>/dev/null && { ok "  Removed: $o"; removed=$((removed+1)); }         || fail "  Could not remove: $o"
    done
    ok "Removed $removed / $issues orphan(s)"
    _autosync
  else
    echo ""
    dim "  Run 'passx gc --rm' to automatically delete all orphans"
    dim "  Or 'passx gc rm'    (same thing)"
  fi
}

cmd_lint() {
  _cmd="lint"
  _banner "Store Lint"
  local issues=0
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    [[ "$e" == *-pub ]] || [[ "$e" == *-pvt ]] && continue
    local entry; entry="$(pass show "$e" 2>/dev/null)" || {
      warn "Cannot decrypt: $e"; issues=$((issues+1)); continue; }
    local pw; pw="$(printf "%s\n" "$entry" | sed -n '1p')"
    [ -z "${pw:-}" ] && { warn "No password on line 1: $e"; issues=$((issues+1)); }
    local user email
    user="$(printf "%s\n" "$entry"  | grep -m1 "^username:" | sed "s/^username: *//")"
    email="$(printf "%s\n" "$entry" | grep -m1 "^email:" | sed "s/^email: *//")"
    [ -z "${user:-}" ] && [ -z "${email:-}" ] && \
      dim "No username/email: $e  (consider adding)"
  done < <(list_entries)
  echo ""; [ $issues -eq 0 ] && ok "No lint errors" || warn "$issues error(s)"
}

cmd_verify() {
  _cmd="verify"
  _banner "Verify Store"
  warn "Requires GPG decryption for every entry"
  printf "  Continue? [y/N] " >&2; read -r yn </dev/tty || yn=""
  [ "${yn,,}" != "y" ] && { dim "Aborted"; return 0; }
  echo ""
  local ok_c=0 fail_c=0
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    if pass show "$e" >/dev/null 2>&1; then
      ok_c=$((ok_c+1))
    else
      fail "  $e — FAILED"; fail_c=$((fail_c+1))
    fi
  done < <(list_entries)
  echo ""; ok "Verified: $ok_c"
  [ $fail_c -gt 0 ] && warn "Failed: $fail_c" || true
}

# ════════════════════════════════════════════════════════════════
# § STATS / DOCTOR / RECENT / BACKUP
# ════════════════════════════════════════════════════════════════
cmd_stats() {
  _cmd="stats"
  local total otp ssh gpg_k folders
  total="$(find "$PASSWORD_STORE_DIR" -name '*.gpg' 2>/dev/null | wc -l)"
  otp="$(grep -RIl --exclude-dir='.git' -e '^otpauth://' -e '^otp:' \
    "$PASSWORD_STORE_DIR" 2>/dev/null | wc -l || echo 0)"
  ssh="$(find "$PASSWORD_STORE_DIR" -path '*/ssh/*-pub.gpg' 2>/dev/null | wc -l)"
  gpg_k="$(find "$PASSWORD_STORE_DIR" -path '*/gpg/*-pub.gpg' 2>/dev/null | wc -l)"
  folders="$(find "$PASSWORD_STORE_DIR" -type d 2>/dev/null | wc -l)"
  _banner "Store Statistics"
  printf "  %-28s ${C_BOLD}%d${C_RESET}\n" "Total entries"  "$total"
  printf "  %-28s ${C_BOLD}%d${C_RESET}\n" "OTP-enabled"    "$otp"
  printf "  %-28s ${C_BOLD}%d${C_RESET}\n" "SSH keys"       "$ssh"
  printf "  %-28s ${C_BOLD}%d${C_RESET}\n" "GPG keys"       "$gpg_k"
  printf "  %-28s ${C_BOLD}%d${C_RESET}\n" "Folders"        "$folders"
  [ "$PASSX_JSON" = "1" ] && \
    _json_kv total "$total" otp "$otp" ssh "$ssh" gpg "$gpg_k" folders "$folders"
  echo ""
}

cmd_doctor() {
  _cmd="doctor"
  _banner "passx doctor  v${PASSX_VERSION}"
  _section "Required"
  for d in pass gpg; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ${C_GREEN}✔${C_RESET}  %-16s  %s\n" "$d" "$(command -v "$d")" \
      || printf "  ${C_RED}✖${C_RESET}  %-16s  MISSING\n" "$d"
  done
  _section "Recommended"
  for d in fzf xdotool xclip wl-copy xdg-open notify-send oathtool curl sha1sum python3 jq; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ${C_GREEN}✔${C_RESET}  %-16s  %s\n" "$d" "$(command -v "$d")" \
      || printf "  ${C_DIM}–${C_RESET}  %-16s  optional\n" "$d"
  done
  _section "OTP / QR"
  for d in qrencode zbarimg; do
    command -v "$d" >/dev/null 2>&1 \
      && printf "  ${C_GREEN}✔${C_RESET}  %-16s  %s\n" "$d" "$(command -v "$d")" \
      || printf "  ${C_DIM}–${C_RESET}  %-16s  optional\n" "$d"
  done
  _section "Environment"
  printf "  %-30s %s\n" "PASSWORD_STORE_DIR"  "$PASSWORD_STORE_DIR"
  printf "  %-30s %s\n" "PASSX_AUTOSYNC"      "$PASSX_AUTOSYNC"
  printf "  %-30s %ss\n" "PASSX_CLIP_TIMEOUT" "$PASSX_CLIP_TIMEOUT"
  printf "  %-30s %sd\n" "PASSX_MAX_AGE"      "$PASSX_MAX_AGE"
  printf "  %-30s %s\n" "PASSX_NOTIFY"        "$PASSX_NOTIFY"
  printf "  %-30s %s\n" "PASSX_THEME"         "$PASSX_THEME"
  printf "  %-30s %s\n" "PASSX_GEN_LENGTH"    "$PASSX_GEN_LENGTH"
  printf "  %-30s %s\n" "PASSX_GEN_CHARS"     "$PASSX_GEN_CHARS"
  _section "Store"
  if [ -d "$PASSWORD_STORE_DIR" ]; then
    local cnt; cnt="$(find "$PASSWORD_STORE_DIR" -name '*.gpg' 2>/dev/null | wc -l)"
    printf "  ${C_GREEN}✔${C_RESET}  Store exists — %d entries\n" "$cnt"
    [ -d "$PASSWORD_STORE_DIR/.git" ] \
      && printf "  ${C_GREEN}✔${C_RESET}  Git enabled\n" \
      || printf "  ${C_DIM}–${C_RESET}  No git repo  (run: pass git init)\n"
  else
    printf "  ${C_RED}✖${C_RESET}  Store not found: %s\n" "$PASSWORD_STORE_DIR"
  fi
  _section "Clipboard"
  clipboard_available \
    && printf "  ${C_GREEN}✔${C_RESET}  Clipboard available\n" \
    || printf "  ${C_RED}✖${C_RESET}  No clipboard backend\n"
  echo ""
}

cmd_recent() {
  _cmd="recent"
  local n="${1:-10}"
  _banner "Recently Modified — top $n"
  find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n "$n" \
    | sed "s|^[^ ]* $PASSWORD_STORE_DIR/||; s|\.gpg$||" \
    | while IFS= read -r e; do printf "  %s\n" "$e"; done
  echo ""
}

cmd_backup() {
  _cmd="backup"
  local out="${1:-}"; [ -z "$out" ] && err "Usage: passx backup <file.gpg>"
  command -v gpg >/dev/null 2>&1 || err "gpg required"
  _banner "Backup"
  local tmp; tmp="$(mktemp -d)"
  step "Archiving store..."
  tar -C "$(dirname "$PASSWORD_STORE_DIR")" -czf "$tmp/store.tar.gz" \
    "$(basename "$PASSWORD_STORE_DIR")" || { rm -rf "$tmp"; err "tar failed"; }
  step "Encrypting with symmetric passphrase..."
  gpg -c -o "$out" "$tmp/store.tar.gz" || { rm -rf "$tmp"; err "gpg failed"; }
  rm -rf "$tmp"; ok "Backup → $out"
}

# ════════════════════════════════════════════════════════════════
# § CRON-CHECK  (silent unless problems; exit 1 on issues)
# ════════════════════════════════════════════════════════════════
cmd_cron_check() {
  local issues=0
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    [[ "$e" == *-pub ]] || [[ "$e" == *-pvt ]] && continue
    local pw; pw="$(pass show "$e" 2>/dev/null | sed -n '1p')" || continue
    [ -z "$pw" ] && continue
    local len u l n s score
    len=${#pw}
    u=$(printf "%s" "$pw" | grep -c '[A-Z]' 2>/dev/null || true); u=$((u>0?1:0))
    l=$(printf "%s" "$pw" | grep -c '[a-z]' 2>/dev/null || true); l=$((l>0?1:0))
    n=$(printf "%s" "$pw" | grep -c '[0-9]' 2>/dev/null || true); n=$((n>0?1:0))
    s=$(printf "%s" "$pw" | grep -c '[^A-Za-z0-9]' 2>/dev/null || true); s=$((s>0?1:0))
    score=$((u+l+n+s))
    [ "$len" -lt 12 ] || [ "$score" -lt 3 ] && {
      printf "WEAK: %s (len=%d score=%d/4)\n" "$e" "$len" "$score" >&2
      issues=$((issues+1)); }
    [ -d "$PASSWORD_STORE_DIR/.git" ] && {
      local lc days
      lc="$(cd "$PASSWORD_STORE_DIR" && git log -1 --format="%ct" -- "${e}.gpg" 2>/dev/null || echo 0)"
      [ "$lc" -gt 0 ] && {
        days=$(( ($(date +%s) - lc) / 86400 ))
        [ "$days" -gt "$PASSX_MAX_AGE" ] && {
          printf "AGED: %s (%dd)\n" "$e" "$days" >&2; issues=$((issues+1)); }
      }
    }
  done < <(list_entries)
  exit $((issues > 0 ? 1 : 0))
}

# ════════════════════════════════════════════════════════════════
# § FZF SHELL WIDGET  (Ctrl+P binding)
# ════════════════════════════════════════════════════════════════
cmd_fzf_widget() {
  local shell="${1:-bash}"
  case "$shell" in
    bash|zsh)
      cat <<'WIDGET'
# passx fzf-widget — paste into ~/.bashrc or ~/.zshrc
# Ctrl+P → pick a password entry and copy password to clipboard
_passx_widget() {
  local entry
  entry=$(passx search 2>/dev/null)
  if [ -n "$entry" ]; then
    passx copy "$entry" 2>/dev/null
    if [ -n "${ZSH_VERSION:-}" ]; then
      LBUFFER+="$entry"
      zle redisplay
    elif [ -n "${BASH_VERSION:-}" ]; then
      READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${entry}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$(( READLINE_POINT + ${#entry} ))
    fi
  fi
}
if [ -n "${ZSH_VERSION:-}" ]; then
  zle -N _passx_widget
  bindkey '^P' _passx_widget
elif [ -n "${BASH_VERSION:-}" ]; then
  bind -x '"\C-p": _passx_widget'
fi
WIDGET
      ;;
    fish)
      cat <<'FISHWIDGET'
# paste into ~/.config/fish/functions/_passx_widget.fish
function _passx_widget
    set entry (passx search 2>/dev/null)
    if test -n "$entry"
        passx copy $entry 2>/dev/null
        commandline -i $entry
    end
end
bind \cp _passx_widget
FISHWIDGET
      ;;
    *) err "Supported shells: bash zsh fish" ;;
  esac
}

# ════════════════════════════════════════════════════════════════
# § SHELL COMPLETIONS
# ════════════════════════════════════════════════════════════════
cmd_completions() {
  _cmd="completions"
  local shell="${1:-bash}"
  case "$shell" in
    bash) _comp_bash ;;
    zsh)  _comp_zsh  ;;
    fish) _comp_fish ;;
    *)    err "Supported: bash zsh fish" ;;
  esac
}

_comp_bash() {
cat <<'BASH'
# passx bash completions
# Usage: source <(passx completions bash)   or add to ~/.bashrc

_passx_entries() {
  pass ls --flat 2>/dev/null \
    || find "${PASSWORD_STORE_DIR:-$HOME/.password-store}" -name '*.gpg' 2>/dev/null \
       | sed "s|.*\.password-store/||;s|\.gpg$||"
}

_passx() {
  local cur prev cword
  _init_completion 2>/dev/null || {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD
  }

  local all_cmds="add show copy set-field rename clone search otp otp-show otp-fill
    otp-list otp-import otp-export otp-qr audit hibp age lock fill login url open
    rotate strength entropy rm edit note card env dotenv run qr template gen gen-conf
    ssh-add ssh-set ssh-rm ssh-list ssh-copy-id ssh-agent-status
    gpg-add gpg-set gpg-rm gpg-list
    share recipients reencrypt
    import-csv import-bitwarden import-firefox import-chrome import-keepass
    export-bitwarden export-encrypted
    gc lint verify diff watch git sync log doctor recent stats backup
    completions fzf-widget cron-check --version --help"

  if [ "$cword" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$all_cmds" -- "$cur") )
    return 0
  fi

  case "$prev" in
    show|copy|set-field|rename|clone|edit|rm|rotate|strength|entropy|\
    otp|otp-show|otp-fill|otp-import|otp-export|otp-qr|hibp|login|\
    fill|url|open|note|card|env|dotenv|run|share|diff|watch|qr)
      COMPREPLY=( $(compgen -W "$(_passx_entries)" -- "$cur") );;
    ssh-set|ssh-rm|ssh-copy-id)
      COMPREPLY=( $(compgen -W "$(pass ls --flat 2>/dev/null \
        | grep '^ssh/.*-pub$' | sed 's/-pub$//')" -- "$cur") );;
    gpg-set|gpg-rm)
      COMPREPLY=( $(compgen -W "$(pass ls --flat 2>/dev/null \
        | grep '^gpg/.*-pub$' | sed 's/-pub$//')" -- "$cur") );;
    audit)  COMPREPLY=( $(compgen -W "--fix" -- "$cur") );;
    hibp)   COMPREPLY=( $(compgen -W "--all $(_passx_entries)" -- "$cur") );;
    gen)    COMPREPLY=( $(compgen -W "--words --pin --pronounceable --length --store --no-copy" -- "$cur") );;
    completions|fzf-widget)
      COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") );;
    import-csv|import-bitwarden|import-firefox|import-chrome|import-keepass|\
    export-bitwarden|export-encrypted|backup)
      COMPREPLY=( $(compgen -f -- "$cur") );;
  esac
  return 0
}

complete -F _passx passx
BASH
}

_comp_zsh() {
cat <<'ZSH'
#compdef passx
# passx zsh completions
# Usage: source <(passx completions zsh)

_passx() {
  local -a cmds entries ssh_keys gpg_keys
  cmds=(
    'add:Add a new entry'
    'show:Interactive picker / show fields'
    'copy:Copy field to clipboard'
    'set-field:Set a field value'
    'rename:Rename an entry'
    'clone:Clone an entry'
    'search:Fuzzy-search entries'
    'otp:Get OTP code'
    'otp-show:Live OTP display'
    'otp-fill:Type OTP via xdotool'
    'otp-list:List OTP entries'
    'otp-import:Import OTP from QR image'
    'otp-export:Export OTP URL / QR'
    'otp-qr:Show OTP QR in terminal'
    'audit:Audit passwords for weakness'
    'hibp:HaveIBeenPwned check'
    'age:Password age report'
    'lock:Clear clipboard now'
    'fill:Autotype credentials'
    'login:Copy user+password'
    'url:Copy and open URL'
    'open:Alias for url'
    'rotate:Rotate password'
    'strength:Strength report'
    'entropy:Shannon entropy'
    'rm:Delete entry'
    'edit:Edit entry in editor'
    'note:Manage secure notes'
    'card:Credit card helper'
    'env:Output as shell exports'
    'dotenv:Output as .env format'
    'run:Run command with creds injected'
    'qr:Show password as QR code'
    'template:Create entry from template'
    'gen:Generate a password'
    'gen-conf:Generate ~/.config/passx/passx.conf configuration file'
    'ssh-add:Store SSH keypair'
    'ssh-set:Restore SSH key from store'
    'ssh-rm:Remove SSH keypair from store'
    'ssh-list:List SSH keys in store'
    'ssh-copy-id:Install public key to remote'
    'ssh-agent-status:Show ssh-agent keys'
    'gpg-add:Store GPG keypair'
    'gpg-set:Restore GPG key from store'
    'gpg-rm:Remove GPG keypair from store'
    'gpg-list:List GPG keys in store'
    'share:Re-encrypt entry for another GPG key'
    'recipients:Show store recipients'
    'reencrypt:Re-encrypt store with new recipients'
    'import-csv:Import from generic CSV'
    'import-bitwarden:Import from Bitwarden JSON'
    'import-firefox:Import from Firefox CSV'
    'import-chrome:Import from Chrome CSV'
    'import-keepass:Import from KeePass XML'
    'export-bitwarden:Export to Bitwarden JSON'
    'export-encrypted:Export encrypted archive'
    'gc:Garbage collect'
    'lint:Lint store entries'
    'verify:Verify all entries decrypt'
    'diff:Diff entry between commits'
    'watch:Watch entry for changes'
    'git:Pass-through to pass git'
    'sync:Git push+pull'
    'log:Show git history'
    'doctor:Dependency and env check'
    'recent:Recently modified entries'
    'stats:Store statistics'
    'backup:Encrypted backup'
    'completions:Print shell completion script'
    'fzf-widget:Print fzf shell widget'
    'cron-check:Cron-safe audit (silent unless issues)'
    '--version:Print version'
    '--help:Full help'
  )

  _arguments -C '1:command:->cmd' '*:: :->args'
  case $state in
    cmd) _describe 'passx command' cmds ;;
    args)
      entries=( ${(f)"$(pass ls --flat 2>/dev/null)"} )
      ssh_keys=( ${(f)"$(pass ls --flat 2>/dev/null | grep '^ssh/.*-pub$' | sed 's/-pub$//')"} )
      gpg_keys=( ${(f)"$(pass ls --flat 2>/dev/null | grep '^gpg/.*-pub$' | sed 's/-pub$//')"} )
      case $words[1] in
        show|copy|set-field|rename|edit|rm|rotate|strength|entropy|otp|otp-show|\
        otp-fill|otp-import|otp-export|otp-qr|hibp|login|fill|url|open|note|\
        card|env|dotenv|run|share|diff|watch|qr|clone)
          _describe 'entries' entries ;;
        ssh-set|ssh-rm|ssh-copy-id) _describe 'ssh keys' ssh_keys ;;
        gpg-set|gpg-rm) _describe 'gpg keys' gpg_keys ;;
        completions|fzf-widget) _values 'shell' bash zsh fish ;;
        audit) _values 'flags' --fix ;;
        hibp)  _values 'flags' --all; _describe 'entries' entries ;;
        gen)   _values 'flags' --words --pin --pronounceable --length --store --no-copy ;;
        import-*|export-*|backup) _files ;;
      esac ;;
  esac
}
_passx
ZSH
}

_comp_fish() {
cat <<'FISH'
# passx fish completions
# Usage: source (passx completions fish | psub)

set -l cmds add show copy set-field rename clone search otp otp-show otp-fill \
  otp-list otp-import otp-export otp-qr audit hibp age lock fill login url open \
  rotate strength entropy rm edit note card env dotenv run qr template gen gen-conf \
  ssh-add ssh-set ssh-rm ssh-list ssh-copy-id ssh-agent-status \
  gpg-add gpg-set gpg-rm gpg-list share recipients reencrypt \
  import-csv import-bitwarden import-firefox import-chrome import-keepass \
  export-bitwarden export-encrypted gc lint verify diff watch git sync log \
  doctor recent stats backup completions fzf-widget cron-check

complete -c passx -f -n 'not __fish_seen_subcommand_from $cmds' -a "$cmds"

# Entry completions
for cmd in show copy set-field rename edit rm rotate strength entropy otp otp-show \
           otp-fill otp-export otp-qr hibp login fill url open note card env dotenv \
           run share diff watch qr clone
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null)"
end

# SSH key completions
for cmd in ssh-set ssh-rm ssh-copy-id
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null | grep '^ssh/.*-pub\$' | sed 's/-pub\$//')"
end

# GPG key completions
for cmd in gpg-set gpg-rm
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null | grep '^gpg/.*-pub\$' | sed 's/-pub\$//')"
end

# Shell completions
complete -c passx -f -n '__fish_seen_subcommand_from completions fzf-widget' \
  -a "bash zsh fish"

complete -c passx -f -n '__fish_seen_subcommand_from audit' -a '--fix'
complete -c passx -f -n '__fish_seen_subcommand_from hibp'  -a '--all'
complete -c passx -f -n '__fish_seen_subcommand_from gen'   \
  -a '--words --pin --pronounceable --length --store --no-copy'
FISH
}

# ════════════════════════════════════════════════════════════════
# § HELP  (per-command + overview)
# ════════════════════════════════════════════════════════════════
_help() {
  local cmd="${1:-overview}"
  case "$cmd" in

    overview|--help|-h)
      cat <<HELP

${C_BOLD}${C_CYAN}  passx${C_RESET} ${C_DIM}v${PASSX_VERSION}${C_RESET}  —  power-user wrapper for pass

${C_BOLD}  USAGE${C_RESET}
    passx <command> [args...]
    passx <command> --help

${C_BOLD}  CORE${C_RESET}
    ${C_GREEN}show${C_RESET}     [path] [-u|-e|-n|-p|-f]   Interactive picker + field display
    ${C_GREEN}copy${C_RESET}     [path] [-u|-e|-n|-p|-f]   Copy field to clipboard
    ${C_GREEN}add${C_RESET}      <path> [email] [user] [notes] [len]
    ${C_GREEN}edit${C_RESET}     [path]                Edit entry in \$EDITOR
    ${C_GREEN}rm${C_RESET}       [path]         Delete entry (with confirmation)
    ${C_GREEN}rotate${C_RESET}   [path] [len]   Generate new password
    ${C_GREEN}rename${C_RESET}   [old] [new]    Rename / move entry
    ${C_GREEN}clone${C_RESET}    [src] [dst]    Duplicate entry
    ${C_GREEN}search${C_RESET}   [query]        Fuzzy search
    ${C_GREEN}gen${C_RESET}      [len] [--words|--pin|--pronounceable]

${C_BOLD}  FIELDS${C_RESET}
    ${C_GREEN}set-field${C_RESET} <path> <field> [val]
    Use colon syntax in show/copy:  ${C_DIM}passx show github:email${C_RESET}
    Flags: ${C_DIM}-p password  -u username  -e email  -n notes  -f full  -t token${C_RESET}

${C_BOLD}  OTP${C_RESET}
    ${C_GREEN}otp${C_RESET}          [-n]   Copy OTP (−n = print only, no copy)
    ${C_GREEN}otp-show${C_RESET}            Live OTP with progress bar
    ${C_GREEN}otp-fill${C_RESET}            Type OTP into focused field (xdotool)
    ${C_GREEN}otp-list${C_RESET}            List all OTP entries
    ${C_GREEN}otp-import${C_RESET}  <qr>   Import from QR image (zbarimg)
    ${C_GREEN}otp-export${C_RESET}  [--qr <file>]
    ${C_GREEN}otp-qr${C_RESET}              Show OTP QR in terminal
    ${C_GREEN}qr${C_RESET}          [field] Show any field as QR

${C_BOLD}  AUTOMATION${C_RESET}
    ${C_GREEN}fill${C_RESET}     [-e]   Autotype user + TAB + pass (−e = press Enter after)
    ${C_GREEN}login${C_RESET}          Copy username + password together
    ${C_GREEN}url${C_RESET}            Copy URL and open in browser
    ${C_GREEN}run${C_RESET}     <cmd>  Inject creds as env vars — never in shell history

${C_BOLD}  SECRETS${C_RESET}
    ${C_GREEN}note${C_RESET}    [list|show|edit|copy]
    ${C_GREEN}card${C_RESET}    [list|show|(cp-num)copy-number|(cp-cvv)copy-cvv]
    ${C_GREEN}env${C_RESET}     [list|export|dotenv|show]   Output as shell exports or .env format
    ${C_GREEN}dotenv${C_RESET}                     Alias: env dotenv
    ${C_GREEN}template${C_RESET}                   Interactive: web/server/db/api-key/card/wifi/note

${C_BOLD}  SECURITY${C_RESET}
    ${C_GREEN}audit${C_RESET}   [--fix]   Weak / duplicate / aged passwords
    ${C_GREEN}hibp${C_RESET}    [--all]   HaveIBeenPwned (k-anonymity)
    ${C_GREEN}age${C_RESET}     [days]    Password age report
    ${C_GREEN}strength${C_RESET}          4-point strength rating
    ${C_GREEN}entropy${C_RESET}           Shannon entropy in bits
    ${C_GREEN}lock${C_RESET}              Clear clipboard immediately
    ${C_GREEN}share${C_RESET}   <gpg-id>  Encrypt entry for another person
    ${C_GREEN}reencrypt${C_RESET}         Re-encrypt store with new recipients
    ${C_GREEN}recipients${C_RESET}        Show current recipients

${C_BOLD}  SSH KEYS${C_RESET}
    ${C_GREEN}ssh-add${C_RESET}           Store SSH keypair in pass
    ${C_GREEN}ssh-set${C_RESET}           Restore key to ~/.ssh/ + ssh-agent
    ${C_GREEN}ssh-rm${C_RESET}            Remove both -pub and -pvt
    ${C_GREEN}ssh-list${C_RESET}          List stored keys
    ${C_GREEN}ssh-copy-id${C_RESET}       Install public key to remote host
    ${C_GREEN}ssh-agent-status${C_RESET}  Show loaded agent keys

${C_BOLD}  GPG KEYS${C_RESET}
    ${C_GREEN}gpg-add${C_RESET}  /  ${C_GREEN}gpg-set${C_RESET}  /  ${C_GREEN}gpg-rm${C_RESET}  /  ${C_GREEN}gpg-list${C_RESET}

${C_BOLD}  IMPORT / EXPORT${C_RESET}
    ${C_GREEN}import-csv${C_RESET}        /  ${C_GREEN}import-bitwarden${C_RESET}  /  ${C_GREEN}import-firefox${C_RESET}
    ${C_GREEN}import-chrome${C_RESET}     /  ${C_GREEN}import-keepass${C_RESET}
    ${C_GREEN}export-bitwarden${C_RESET}  /  ${C_GREEN}export-encrypted${C_RESET}

${C_BOLD}  MAINTENANCE & CONFIG${C_RESET}
    ${C_GREEN}gc${C_RESET}         Garbage collect (orphaned keys)
    ${C_GREEN}lint${C_RESET}       Check formatting and missing fields
    ${C_GREEN}verify${C_RESET}     Decrypt-test every entry
    ${C_GREEN}diff${C_RESET}       Decrypted diff between git commits
    ${C_GREEN}watch${C_RESET}      Watch entry for changes (git poll)
    ${C_GREEN}gen-conf${C_RESET}   Generate configuration file at ~/.config/passx/passx.conf
    ${C_GREEN}git${C_RESET}        Pass-through: passx git <args>

${C_BOLD}  TOOLS${C_RESET}
    ${C_GREEN}sync${C_RESET}       Git push + pull
    ${C_GREEN}log${C_RESET}        Git history
    ${C_GREEN}doctor${C_RESET}     Dependency + env check
    ${C_GREEN}stats${C_RESET}      Store statistics
    ${C_GREEN}recent${C_RESET}     Recently modified entries
    ${C_GREEN}backup${C_RESET}     Encrypted backup
    ${C_GREEN}completions${C_RESET}  bash|zsh|fish  — print completion script
    ${C_GREEN}fzf-widget${C_RESET}   bash|zsh|fish  — print Ctrl+P shell widget
    ${C_GREEN}cron-check${C_RESET}   Silent audit for cron

${C_BOLD}  ENVIRONMENT VARIABLES (and ~/.config/passx/passx.conf)${C_RESET}
    ${C_DIM}PASSWORD_STORE_DIR${C_RESET}   default: ~/.password-store
    ${C_DIM}PASSX_AUTOSYNC${C_RESET}       auto-push after changes  (false)
    ${C_DIM}PASSX_CLIP_TIMEOUT${C_RESET}   clipboard auto-clear secs (20)
    ${C_DIM}PASSX_MAX_AGE${C_RESET}        audit age threshold days  (180)
    ${C_DIM}PASSX_NOTIFY${C_RESET}         notify-send on events     (true)
    ${C_DIM}PASSX_THEME${C_RESET}          catppuccin|nord|gruvbox|dracula|solarized
    ${C_DIM}PASSX_GEN_LENGTH${C_RESET}     default generated length  (32)
    ${C_DIM}PASSX_GEN_CHARS${C_RESET}      charset for gen_password
    ${C_DIM}PASSX_JSON${C_RESET}           set to 1 for JSON output  (0)
    ${C_DIM}PASSX_DEBUG${C_RESET}          set to 1 for debug log    (0)
    ${C_DIM}PASSX_COLOR${C_RESET}          auto|always|never

HELP
    ;;
    add)    printf "\n${C_BOLD}passx add${C_RESET} <path> [email] [username] [notes] [length]\n\n"
            printf "  Adds a new entry with a generated password.\n"
            printf "  Args are detected by type:  email@addr  →  email field\n"
            printf "                              number       →  password length\n"
            printf "                              first string →  username\n"
            printf "                              second string→  notes\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx add work/github tony@email.com tony 32\n"
            printf "    passx add personal/netflix\n\n" ;;
    show)   printf "\n${C_BOLD}passx show${C_RESET} [path] [flags]\n\n"
            printf "  With no args → fzf picker → action menu (interactive TUI)\n"
            printf "  With path only → action menu for that entry\n"
            printf "  With -u/-e/-n/-p/-f → print that field (scriptable)\n\n"
            printf "  ${C_DIM}Flags:${C_RESET}\n"
            printf "    -p  password     -u  username     -e  email\n"
            printf "    -n  notes        -f / --full      -t  token\n"
            printf "    --json           -h / --help\n\n"
            printf "  ${C_DIM}Colon syntax:${C_RESET}  passx show github:username\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx show                   # fzf picker\n"
            printf "    passx show github            # action menu\n"
            printf "    passx show github -u         # print username\n"
            printf "    passx show github:email      # print email\n"
            printf "    passx show github --full     # print all fields\n\n" ;;
    copy)   printf "\n${C_BOLD}passx copy${C_RESET} [path] [flags]\n\n"
            printf "  Copies a field to clipboard.  Same flags as show.\n"
            printf "  Clipboard auto-clears after PASSX_CLIP_TIMEOUT seconds.\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx copy github            # copy password\n"
            printf "    passx copy github -u         # copy username\n"
            printf "    passx copy github:email      # copy email\n\n" ;;
    otp)    printf "\n${C_BOLD}passx otp${C_RESET} [-n] [path]\n\n"
            printf "  Prints TOTP code and copies to clipboard.\n"
            printf "  -n  print only, do not copy\n\n"
            printf "  ${C_DIM}Related:${C_RESET}  otp-show  otp-fill  otp-list  otp-import  otp-export  otp-qr\n\n" ;;
    gen)    printf "\n${C_BOLD}passx gen${C_RESET} [length] [flags]\n\n"
            printf "  Generates a password and prints it (also copies to clipboard).\n\n"
            printf "  ${C_DIM}Flags:${C_RESET}\n"
            printf "    --words [n]       diceware passphrase (default 4 words)\n"
            printf "    --pin [n]         numeric PIN (default 6 digits)\n"
            printf "    --pronounceable   consonant/vowel alternating\n"
            printf "    --length n / -l n password length\n"
            printf "    --store <path>    also store in pass\n"
            printf "    --no-copy         do not copy to clipboard\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx gen 24\n"
            printf "    passx gen --words 5\n"
            printf "    passx gen --pin 4\n"
            printf "    passx gen --store work/temp-pass\n\n" ;;
    audit)  printf "\n${C_BOLD}passx audit${C_RESET} [--fix]\n\n"
            printf "  Checks all entries for weak, duplicate, or aged passwords.\n"
            printf "  --fix  immediately rotates weak entries\n\n"
            printf "  Threshold: length < 12 or score < 3/4 = weak\n"
            printf "  Age threshold: PASSX_MAX_AGE days (default 180)\n\n" ;;
    hibp)   printf "\n${C_BOLD}passx hibp${C_RESET} [--all] [path]\n\n"
            printf "  Checks password against HaveIBeenPwned database.\n"
            printf "  Uses k-anonymity: only first 5 chars of SHA1 hash are sent.\n"
            printf "  --all  check every entry (1s delay between requests)\n\n" ;;
    run)    printf "\n  ${C_BOLD}PASSX RUN — Credential Injection Tool${C_RESET}\n"
            printf "  Runs a command with secrets injected directly into its memory environment.\n"
            printf "  ${C_DIM}Benefit: No passwords in shell history, no plain-text config files.${C_RESET}\n\n"
            printf "  ${C_BOLD}Usage:${C_RESET} passx run <path> <command> [args...]\n\n"
            printf "  ${C_BOLD}Smart Mappings (Automatic Configuration):${C_RESET}\n"
            printf "    ${C_CYAN}ssh${C_RESET}      → Auto-fills password using 'sshpass' or copies to clipboard.\n"
            printf "    ${C_CYAN}psql${C_RESET}     → Sets: PGPASSWORD, PGUSER, PGHOST, PGPORT, PGDATABASE.\n"
            printf "    ${C_CYAN}mysql${C_RESET}    → Sets: MYSQL_PWD.\n"
            printf "    ${C_CYAN}aws${C_RESET}      → Splits 'token' into AWS_ACCESS_KEY_ID/SECRET.\n\n"
            printf "  ${C_BOLD}Standard Variables (Always exported):${C_RESET}\n"
            printf "    \$PASSX_PASSWORD, \$PASSX_USERNAME, \$PASSX_USER, \$PASSX_EMAIL,\n"
            printf "    \$PASSX_HOST, \$PASSX_PORT, \$PASSX_DATABASE, \$PASSX_TOKEN\n\n"
            printf "  ${C_BOLD}Examples:${C_RESET}\n"
            printf "    passx run servers/vps ssh root@1.2.3.4\n"
            printf "    passx run db/prod psql\n"
            printf "    passx run aws/dev aws s3 ls\n\n" ;;
    env|dotenv)
            printf "\n${C_BOLD}passx env${C_RESET} [path] [export|dotenv]\n\n"
            printf "  Outputs credentials as shell env vars or .env format.\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    eval \$(passx env aws/prod)          # shell exports\n"
            printf "    passx dotenv db/prod > .env         # .env file\n\n" ;;
    completions)
            printf "\n${C_BOLD}passx completions${C_RESET} bash|zsh|fish\n\n"
            printf "  Prints the completion script for your shell.\n\n"
            printf "  ${C_DIM}Setup:${C_RESET}\n"
            printf "    bash:  source <(passx completions bash)\n"
            printf "    zsh:   source <(passx completions zsh)\n"
            printf "    fish:  passx completions fish | source\n\n" ;;
    set-field)
            printf "\n${C_BOLD}passx set-field${C_RESET} [path] [field] [value]\n\n"
            printf "  Add or update a field inside an existing entry.\n\n"
            printf "  ${C_BOLD}Shortcut:${C_RESET} passx set-field <field:value> ${C_DIM}(Select entry via FZF)${C_RESET}\n\n"
            printf "  ${C_DIM}Fields:${C_RESET}   password, username, email, url, notes, token, etc.\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx set-field github url https://github.com\n"
            printf "    passx set-field github username tony\n"
            printf "    passx set-field url:https://github.com    ${C_DIM}# Shortcut usage${C_RESET}\n"
            printf "    passx set-field github myfield          ${C_DIM}# Interactive prompt${C_RESET}\n\n";;
    note)   printf "\n${C_BOLD}passx note${C_RESET} [add|show|edit|copy] [path]\n\n"
            printf "  Manage secure text notes.\n\n"
            printf "  ${C_DIM}Examples:${C_RESET}\n"
            printf "    passx note add               # create new note (interactive)\n"
            printf "    passx note add secrets/diary # create at specific path\n"
            printf "    passx note edit              # edit with \$EDITOR (fzf picker)\n"
            printf "    passx note copy              # copy note to clipboard\n"
            printf "    passx note show              # print note\n\n" ;;
    template)
            printf "\n${C_BOLD}passx template${C_RESET} [-n]\n\n"
            printf "  Create a new entry from a template.\n"
            printf "  Types: web-login server database api-key email-account\n"
            printf "         credit-card software-license wifi note\n\n"
            printf "  ${C_DIM}Flags:${C_RESET}\n"
            printf "    -n  do not print the generated password on screen\n\n"
            printf "  Password is always copied to clipboard after creation.\n\n" ;;
    *)  printf "\n  ${C_DIM}No detailed help for '%s'.  Try: passx --help${C_RESET}\n\n" "$cmd" ;;
  esac
}

# ════════════════════════════════════════════════════════════════
# § ENTRY POINT
# ════════════════════════════════════════════════════════════════
if [ "${1:-}" = "" ]; then
  command -v pass >/dev/null 2>&1 && { pass ls; exit $?; }
  _help overview; exit 0
fi

case "${1:-}" in
  -V|--version)   printf "passx %s\n" "$PASSX_VERSION"; exit 0 ;;
  -h|--help|help) shift; _help "${1:-overview}"; exit 0 ;;

  # ── Core ──────────────────────────────────────────────────
  add)            shift; cmd_add "$@" ;;
  show|pick|ui)   shift; cmd_show "$@" ;;
  copy)           shift; cmd_copy "$@" ;;
  set-field)      shift; cmd_set_field "$@" ;;
  rename)         shift; cmd_rename "$@" ;;
  clone)          shift; cmd_clone "$@" ;;
  edit)           shift; cmd_edit "$@" ;;
  rm|delete)      shift; cmd_rm "$@" ;;
  rotate)         shift; cmd_rotate "$@" ;;
  search)         shift; cmd_search "$@" ;;
  gen)            shift; cmd_gen "$@" ;;
  ls)             pass ls ;;
  # ── OTP ───────────────────────────────────────────────────
  otp)            shift; cmd_otp "$@" ;;
  otp-show)       shift; cmd_otp_show "$@" ;;
  otp-fill)       shift; cmd_otp_fill "$@" ;;
  otp-list)       cmd_otp_list ;;
  otp-import)     shift; cmd_otp_import "$@" ;;
  otp-export)     shift; cmd_otp_export "$@" ;;
  otp-qr)         shift; cmd_otp_qr "$@" ;;
  qr)             shift; cmd_qr "$@" ;;
  # ── Automation ────────────────────────────────────────────
  fill)           shift; cmd_fill "$@" ;;
  login)          shift; cmd_login "$@" ;;
  url|open)       shift; cmd_url "$@" ;;
  run)            shift; cmd_run "$@" ;;
  # ── Secrets ───────────────────────────────────────────────
  note)           shift; cmd_note "$@" ;;
  card)           shift; cmd_card "$@" ;;
  env)            shift; cmd_env "$@" ;;
  dotenv)         shift; cmd_dotenv "$@" ;;
  template|T|t)   cmd_template ;;
  # ── Security ──────────────────────────────────────────────
  strength)       shift; cmd_strength "$@" ;;
  entropy)        shift; cmd_entropy "$@" ;;
  audit)          shift; cmd_audit "$@" ;;
  hibp)           shift; cmd_hibp "$@" ;;
  age)            shift; cmd_age "$@" ;;
  lock)           cmd_lock ;;
  share)          shift; cmd_share "$@" ;;
  recipients)     cmd_recipients ;;
  reencrypt)      cmd_reencrypt ;;
  # ── SSH ───────────────────────────────────────────────────
  ssh-add)        shift; cmd_ssh_add "$@" ;;
  ssh-set)        shift; cmd_ssh_set "$@" ;;
  ssh-rm)         shift; cmd_ssh_rm "$@" ;;
  ssh-list)       cmd_ssh_list ;;
  ssh-copy-id)    shift; cmd_ssh_copy_id "$@" ;;
  ssh-agent-status) cmd_ssh_agent_status ;;
  # ── GPG ───────────────────────────────────────────────────
  gpg-add)        shift; cmd_gpg_add "$@" ;;
  gpg-set)        shift; cmd_gpg_set "$@" ;;
  gpg-rm)         shift; cmd_gpg_rm "$@" ;;
  gpg-list)       cmd_gpg_list ;;

  # ── Import / Export ───────────────────────────────────────
  import-csv)         shift; cmd_import_csv "$@" ;;
  import-bitwarden)   shift; cmd_import_bitwarden "$@" ;;
  import-firefox)     shift; cmd_import_firefox "$@" ;;
  import-chrome)      shift; cmd_import_chrome "$@" ;;
  import-keepass)     shift; cmd_import_keepass "$@" ;;
  export-bitwarden)   shift; cmd_export_bitwarden "$@" ;;
  export-encrypted)   shift; cmd_export_encrypted "$@" ;;
  # ── Maintenance ───────────────────────────────────────────
  gc)             shift; cmd_gc "${1:-}" ;;
  lint)           cmd_lint ;;
  verify)         cmd_verify ;;
  diff)           shift; cmd_diff "$@" ;;
  watch)          shift; cmd_watch "$@" ;;
  gen-conf)       cmd_gen_conf ;;
  git)            shift; cmd_git "$@" ;;
  # ── Tools ─────────────────────────────────────────────────
  sync)           cmd_sync ;;
  log)            shift; cmd_log "$@" ;;
  doctor)         cmd_doctor ;;
  stats)          cmd_stats ;;
  recent)         shift; cmd_recent "$@" ;;
  backup)         shift; cmd_backup "$@" ;;
  completions)    shift; cmd_completions "$@" ;;
  fzf-widget)     shift; cmd_fzf_widget "${1:-bash}" ;;
  cron-check)     cmd_cron_check ;;
  set-field)      shift; cmd_set_field "$@" ;;
  *)
    printf "\n${C_RED}${C_BOLD}  ✖  Unknown command: %s${C_RESET}\n\n" "$1" >&2
    printf "  ${C_DIM}Run ${C_BOLD}passx --help${C_RESET}${C_DIM} for the full command list${C_RESET}\n\n"
    exit 1 ;;
esac

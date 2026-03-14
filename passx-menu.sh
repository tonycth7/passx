#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  passx-menu  v1.2.0  —  rofi / wofi / dmenu launcher            ║
# ╚══════════════════════════════════════════════════════════════════╝
#
#  passx-menu              main picker
#  passx-menu otp          OTP picker — all entries, live codes
#  passx-menu t            new entry from template
#  passx-menu fill         autofill picker
#  passx-menu copy         pick and copy password
#  passx-menu ssh          SSH key manager
#  passx-menu add          quick add
#  passx-menu gen          generate password
#  passx-menu -e <path>    jump to entry action menu
#
# NO set -e  — rofi/dmenu return exit 1 on Escape; we handle errors explicitly

PASSX_MENU_VERSION="1.2.0"

# ══════════════════════════════════════════════════════════════════
# CONFIG  (read passx.conf then menu.conf)
# ══════════════════════════════════════════════════════════════════
PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/passx"

for _f in "$_CONF/passx.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/passx.conf" \
           "$_CONF/menu.conf"; do
  [ -f "$_f" ] && source "$_f" 2>/dev/null || true
done

: "${PASSX_THEME:=catppuccin}"
: "${PASSX_CLIP_TIMEOUT:=20}"
: "${PASSX_NOTIFY:=true}"
: "${PASSX_GEN_LENGTH:=32}"
: "${MENU:=auto}"
: "${DMENU_FONT:=monospace:size=11}"
: "${DMENU_LINES:=18}"
: "${TERMINAL:=}"
: "${AUTOFILL_DELAY:=0.5}"

# ══════════════════════════════════════════════════════════════════
# THEMES
# ══════════════════════════════════════════════════════════════════
_load_theme() {
  case "$PASSX_THEME" in
    catppuccin)
      T_BG="#1e1e2e" T_BG2="#313244" T_FG="#cdd6f4" T_SEL="#89b4fa"
      T_SELBG="#1e3a5f" T_BRD="#89b4fa" T_PC="#89b4fa"
      T_NB="#1e1e2e" T_NF="#cdd6f4" T_SB="#89b4fa" T_SF="#1e1e2e" ;;
    nord)
      T_BG="#2e3440" T_BG2="#3b4252" T_FG="#d8dee9" T_SEL="#81a1c1"
      T_SELBG="#4c566a" T_BRD="#5e81ac" T_PC="#81a1c1"
      T_NB="#2e3440" T_NF="#d8dee9" T_SB="#81a1c1" T_SF="#2e3440" ;;
    gruvbox)
      T_BG="#282828" T_BG2="#3c3836" T_FG="#ebdbb2" T_SEL="#d79921"
      T_SELBG="#504945" T_BRD="#689d6a" T_PC="#fabd2f"
      T_NB="#282828" T_NF="#ebdbb2" T_SB="#d79921" T_SF="#282828" ;;
    dracula)
      T_BG="#282a36" T_BG2="#44475a" T_FG="#f8f8f2" T_SEL="#bd93f9"
      T_SELBG="#44475a" T_BRD="#6272a4" T_PC="#ff79c6"
      T_NB="#282a36" T_NF="#f8f8f2" T_SB="#bd93f9" T_SF="#282a36" ;;
    solarized)
      T_BG="#002b36" T_BG2="#073642" T_FG="#839496" T_SEL="#268bd2"
      T_SELBG="#073642" T_BRD="#2aa198" T_PC="#2aa198"
      T_NB="#002b36" T_NF="#839496" T_SB="#268bd2" T_SF="#002b36" ;;
    *)
      # unknown theme — fall back to catppuccin
      T_BG="#1e1e2e" T_BG2="#313244" T_FG="#cdd6f4" T_SEL="#89b4fa"
      T_SELBG="#1e3a5f" T_BRD="#89b4fa" T_PC="#89b4fa"
      T_NB="#1e1e2e" T_NF="#cdd6f4" T_SB="#89b4fa" T_SF="#1e1e2e" ;;
  esac
}
_load_theme

# ══════════════════════════════════════════════════════════════════
# BACKEND
# ══════════════════════════════════════════════════════════════════
_BACKEND=""
_detect_backend() {
  [ "$MENU" != "auto" ] && { _BACKEND="$MENU"; return; }
  command -v rofi  >/dev/null 2>&1 && { _BACKEND="rofi";  return; }
  command -v wofi  >/dev/null 2>&1 && { _BACKEND="wofi";  return; }
  command -v dmenu >/dev/null 2>&1 && { _BACKEND="dmenu"; return; }
  command -v fzf   >/dev/null 2>&1 && { _BACKEND="fzf";   return; }
  _BACKEND=""
}
_detect_backend

# ══════════════════════════════════════════════════════════════════
# UTILS
# ══════════════════════════════════════════════════════════════════
_notify() {
  [ "$PASSX_NOTIFY" = "true" ] || return 0
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a passx -t 3000 -i dialog-password "${1:-passx}" "${2:-}" 2>/dev/null
  return 0
}

_die() { _notify "passx-menu" "$1"; printf "passx-menu: %s\n" "$1" >&2; exit 1; }

_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

_find_term() {
  [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1 \
    && { printf "%s" "$TERMINAL"; return 0; }
  local t
  for t in alacritty kitty wezterm foot gnome-terminal konsole st xterm; do
    command -v "$t" >/dev/null 2>&1 && { printf "%s" "$t"; return 0; }
  done
  return 1
}

_term() {
  # _term "window title" "bash command"
  local title="$1" cmd="$2"
  local t; t="$(_find_term)" || { _notify "passx-menu" "No terminal found"; return 1; }
  case "$t" in
    alacritty)      alacritty --title "$title" -e bash -c "$cmd" & ;;
    kitty)          kitty --title "$title" bash -c "$cmd" & ;;
    wezterm)        wezterm start -- bash -c "$cmd" & ;;
    foot)           foot --title "$title" bash -c "$cmd" & ;;
    gnome-terminal) gnome-terminal --title "$title" -- bash -c "$cmd" & ;;
    konsole)        konsole -p tabtitle="$title" -e bash -c "$cmd" & ;;
    st)             st -t "$title" -e bash -c "$cmd" & ;;
    *)              $t -e bash -c "$cmd" & ;;
  esac
  return 0
}

# ══════════════════════════════════════════════════════════════════
# MENU WRAPPER
# Returns selected line, or empty string on Escape / no selection
# Always returns exit code 0 — never lets rofi's exit 1 kill us
# ══════════════════════════════════════════════════════════════════
_menu() {
  # _menu "prompt text"  < list_of_items
  local prompt="${1:-passx}"
  local out=""

  case "$_BACKEND" in

    rofi)
      local _r; _r="$(mktemp /tmp/passx-XXXXXX.rasi)" || return 0
      cat > "$_r" <<RASI
* {
  bg:   ${T_BG};   bg2: ${T_BG2};
  fg:   ${T_FG};   sel: ${T_SEL};
  sbg:  ${T_SELBG}; brd: ${T_BRD};
  pc:   ${T_PC};
  font: "${DMENU_FONT}";
}
window       { background-color:@bg;  border-color:@brd; border:2px solid; border-radius:10px; width:540px; }
mainbox      { background-color:transparent; padding:10px; }
inputbar     { background-color:@bg2; text-color:@fg; border-radius:8px;
               padding:8px 12px; margin:0 0 8px 0; }
prompt       { text-color:@pc; padding:0 6px 0 0; }
entry        { text-color:@fg; }
listview     { lines:${DMENU_LINES}; spacing:3px; background-color:transparent; }
element      { background-color:transparent; text-color:@fg;
               padding:6px 12px; border-radius:6px; }
element selected { background-color:@sbg; text-color:@sel; }
element-text { background-color:transparent; text-color:inherit; }
RASI
      out="$(rofi -dmenu -i -p " ${prompt}" -theme "$_r" -no-custom 2>/dev/null)" || true
      rm -f "$_r" ;;

    wofi)
      local _w; _w="$(mktemp /tmp/passx-XXXXXX.css)" || return 0
      {
        printf 'window{background-color:%s;border:2px solid %s;border-radius:10px;}\n' \
          "$T_BG" "$T_BRD"
        printf '#input{background-color:%s;color:%s;border-radius:8px;' \
          "$T_BG2" "$T_FG"
        printf 'margin:6px;padding:6px 10px;border:none;}\n'
        printf '#outer-box{margin:6px;}#scroll{margin:2px;}\n'
        printf '#text{color:%s;padding:4px 10px;}\n' "$T_FG"
        printf '#entry:selected{background-color:%s;border-radius:6px;}\n' "$T_SELBG"
        printf '#text:selected{color:%s;}\n' "$T_SEL"
      } > "$_w"
      out="$(wofi --dmenu --insensitive \
        --prompt " ${prompt}" \
        --lines "$DMENU_LINES" \
        --style "$_w" 2>/dev/null)" || true
      rm -f "$_w" ;;

    dmenu)
      out="$(dmenu -i -p " ${prompt} >" \
        -fn "$DMENU_FONT" -l "$DMENU_LINES" \
        -nb "$T_NB" -nf "$T_NF" \
        -sb "$T_SB" -sf "$T_SF" 2>/dev/null)" || true ;;

    fzf)
      out="$(fzf \
        --prompt=" ${prompt} > " \
        --pointer=">" --marker="+" \
        --layout=reverse --border=rounded \
        --height=50% 2>/dev/null)" || true ;;

    *)
      _die "No menu backend found. Install rofi, wofi, dmenu, or fzf." ;;
  esac

  printf "%s" "$out"
}

# ══════════════════════════════════════════════════════════════════
# ENTRY HELPERS
# ══════════════════════════════════════════════════════════════════

# Cache: decrypt once per session, reuse for all field lookups
_CACHED_ENTRY=""
_CACHED_CONTENT=""

_decrypt() {
  # _decrypt "entry/path"  → decrypted text, cached
  local entry="$1"
  if [ "$entry" = "$_CACHED_ENTRY" ] && [ -n "$_CACHED_CONTENT" ]; then
    printf "%s" "$_CACHED_CONTENT"
    return 0
  fi
  local content
  content="$(pass show "$entry" 2>/dev/null)" || { printf ""; return 1; }
  _CACHED_ENTRY="$entry"
  _CACHED_CONTENT="$content"
  printf "%s" "$content"
}

_field() {
  # _field "entry" "fieldname"  →  value or empty
  local entry="$1" field="$2"
  local content; content="$(_decrypt "$entry")" || return 1
  case "$field" in
    password) printf "%s" "$content" | sed -n '1p' ;;
    full)     printf "%s" "$content" ;;
    *)        printf "%s" "$content" | grep -m1 "^${field}:" | sed "s/^${field}: *//" ;;
  esac
}

_has() {
  # _has "entry" "fieldname"  →  0 if field exists and non-empty
  local v; v="$(_field "$1" "$2" 2>/dev/null)" || return 1
  [ -n "${v:-}" ]
}

_has_otp() {
  local content; content="$(_decrypt "$1")" || return 1
  printf "%s" "$content" | grep -qE '^otpauth://|^otp:' 2>/dev/null
}

_list_entries() {
  # Use find as primary — pass ls --flat is unreliable on some versions
  find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
    | sed "s|^${PASSWORD_STORE_DIR}/||; s|\.gpg$||" \
    | sort
}

# ══════════════════════════════════════════════════════════════════
# CLIPBOARD  (wl-copy → xclip → xsel → clip.exe)
# ══════════════════════════════════════════════════════════════════
_clip() {
  local data="$1" label="${2:-copied}"
  local ok=false

  if command -v wl-copy >/dev/null 2>&1; then
    printf "%s" "$data" | wl-copy 2>/dev/null && ok=true
  elif command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    printf "%s" "$data" | xclip -selection clipboard 2>/dev/null && ok=true
  elif command -v xsel >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    printf "%s" "$data" | xsel --clipboard --input 2>/dev/null && ok=true
  elif command -v clip.exe >/dev/null 2>&1; then
    printf "%s" "$data" | clip.exe 2>/dev/null && ok=true
  fi

  if $ok; then
    _notify "passx" "${label}  (clears in ${PASSX_CLIP_TIMEOUT}s)"
    # auto-clear in background
    local t="$PASSX_CLIP_TIMEOUT"
    ( sleep "$t"
      command -v wl-copy >/dev/null 2>&1 && printf "" | wl-copy 2>/dev/null && exit 0
      command -v xclip   >/dev/null 2>&1 && printf "" | xclip -selection clipboard 2>/dev/null && exit 0
      command -v xsel    >/dev/null 2>&1 && xsel --clipboard --clear 2>/dev/null
    ) &>/dev/null & disown 2>/dev/null || true
  else
    _notify "passx-menu" "No clipboard tool found (install wl-clipboard or xclip)"
  fi
}

# ══════════════════════════════════════════════════════════════════
# OTP  (get code without breaking on missing --no-copy)
# ══════════════════════════════════════════════════════════════════
_otp_code() {
  local entry="$1" code=""

  # try oathtool first (most reliable — no side effects)
  if command -v oathtool >/dev/null 2>&1; then
    local content; content="$(_decrypt "$entry")" || true
    local secret=""
    # otpauth:// URI
    secret="$(printf "%s" "$content" \
      | grep -oE 'secret=[A-Z2-7a-z0-9]+' | head -1 | sed 's/secret=//')"
    # otp: SECRET (bare)
    [ -z "$secret" ] && \
      secret="$(printf "%s" "$content" | grep -m1 '^otp:' | sed 's/^otp: *//' | tr -d '[:space:]')"
    if [ -n "$secret" ]; then
      code="$(oathtool --totp --base32 "${secret}" 2>/dev/null)" || true
    fi
  fi

  # fallback: passx otp (copies to clipboard too, but at least we get the code)
  if [ -z "$code" ] && command -v passx >/dev/null 2>&1; then
    # passx otp outputs the code on stdout when it works
    code="$(passx otp "$entry" 2>/dev/null | grep -E '^[0-9]{6,8}$' | head -1)" || true
  fi

  printf "%s" "$code"
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: otp
# ══════════════════════════════════════════════════════════════════
_cmd_otp() {
  # Show ALL entries — filter to OTP ones after selection
  # (scanning every entry for OTP requires decrypting all of them — too slow)
  # Instead: show all, generate code, notify if none configured

  local entry
  entry="$(_list_entries | _menu "OTP  —  pick entry")"
  [ -z "${entry:-}" ] && return 0

  # Invalidate cache for fresh decrypt
  _CACHED_ENTRY=""

  local code; code="$(_otp_code "$entry")"

  if [ -z "${code:-}" ]; then
    _notify "passx" "No OTP configured for ${entry##*/}"
    return 0
  fi

  local action
  action="$(printf "copy code\ntype code  (xdotool)\nshow code  +  copy\ncopy and type" \
    | _menu "OTP: ${entry##*/}  →  ${code}")"
  [ -z "${action:-}" ] && return 0

  case "$action" in
    "copy code")
      _clip "$code" "OTP: ${entry##*/}" ;;

    "type code"*)
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return 1; }
      _notify "passx" "Switch to target window now…"
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers --delay 50 "$code"
      _notify "passx" "OTP typed: ${entry##*/}" ;;

    "show code"*)
      _clip "$code" "OTP: ${entry##*/}"
      # show with time remaining if oathtool supports it
      local remaining=""
      command -v oathtool >/dev/null 2>&1 \
        && remaining="  ($(( 30 - $(date +%s) % 30 ))s left)"
      printf "%s%s\n\nclose" "$code" "$remaining" | _menu "OTP: ${entry##*/}" >/dev/null ;;

    "copy and type")
      _clip "$code" "OTP: ${entry##*/}"
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return 1; }
      _notify "passx" "Switch to target window…"
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers --delay 50 "$code"
      _notify "passx" "OTP copied + typed: ${entry##*/}" ;;
  esac
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: t  (template)
# ══════════════════════════════════════════════════════════════════
_cmd_template() {
  command -v passx >/dev/null 2>&1 || _die "passx not installed"

  local ttype
  ttype="$(printf \
    "web-login\nserver\ndatabase\napi-key\nemail-account\ncredit-card\nsoftware-license\nwifi\nnote" \
    | _menu "new entry  —  template type")"
  [ -z "${ttype:-}" ] && return 0

  local path
  path="$(printf "" | _menu "store path  (e.g. web/github)")"
  [ -z "${path:-}" ] && return 0

  # Build a command that feeds the template type and path non-interactively
  # passx template is interactive, so we open a terminal with pre-selected type
  local cmd
  cmd="echo 'Creating: ${ttype} at ${path}'; echo; passx template; echo; read -rp 'press enter to close'"

  _term "passx  new ${ttype}" "$cmd" \
    || _notify "passx" "No terminal — run: passx template"
  _notify "passx" "Opening template: ${ttype} → ${path}"
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: fill
# ══════════════════════════════════════════════════════════════════
_cmd_fill() {
  command -v xdotool >/dev/null 2>&1 || _die "xdotool not installed"

  local entry
  entry="$(_list_entries | _menu "autofill  —  pick entry")"
  [ -z "${entry:-}" ] && return 0

  _CACHED_ENTRY=""  # fresh decrypt

  local mode
  mode="$(printf \
    "full  (user  TAB  pass  Enter)\nusername only\npassword only\nsequence  (copy user, then copy pass)" \
    | _menu "fill: ${entry##*/}")"
  [ -z "${mode:-}" ] && return 0

  local user="" pass=""
  user="$(_field "$entry" username 2>/dev/null)" || true
  [ -z "$user" ] && user="$(_field "$entry" email 2>/dev/null)" || true
  pass="$(_field "$entry" password 2>/dev/null)" || true

  if [ -z "$pass" ]; then
    _notify "passx" "Decrypt failed for ${entry##*/}"; return 1
  fi

  _notify "passx" "Switch to target window…"
  sleep "$AUTOFILL_DELAY"

  case "$mode" in
    "full"*)
      [ -n "$user" ] && xdotool type --clearmodifiers --delay 30 "$user"
      xdotool key --clearmodifiers Tab
      sleep 0.15
      xdotool type --clearmodifiers --delay 30 "$pass"
      xdotool key --clearmodifiers Return
      _notify "passx" "Autofilled: ${entry##*/}" ;;

    "username"*)
      [ -n "$user" ] || { _notify "passx" "No username in ${entry##*/}"; return 1; }
      xdotool type --clearmodifiers --delay 30 "$user"
      _notify "passx" "Username typed" ;;

    "password"*)
      xdotool type --clearmodifiers --delay 30 "$pass"
      _notify "passx" "Password typed" ;;

    "sequence"*)
      [ -n "$user" ] && _clip "$user" "Username: ${entry##*/}"
      _notify "passx" "Paste username, then Tab — password coming in 2s"
      sleep 2
      _clip "$pass" "Password: ${entry##*/}" ;;
  esac
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: copy
# ══════════════════════════════════════════════════════════════════
_cmd_copy() {
  local entry
  entry="$(_list_entries | _menu "copy password")"
  [ -z "${entry:-}" ] && return 0

  _CACHED_ENTRY=""
  local pw; pw="$(_field "$entry" password 2>/dev/null)" || true
  [ -z "${pw:-}" ] && { _notify "passx" "Decrypt failed: ${entry##*/}"; return 1; }
  _clip "$pw" "Password: ${entry##*/}"
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: ssh
# ══════════════════════════════════════════════════════════════════
_cmd_ssh() {
  command -v passx >/dev/null 2>&1 || _die "passx not installed"

  local action
  action="$(printf \
    "list stored keys\nadd keypair to store\nrestore key to ~/.ssh\ncopy public key\nssh-copy-id to host\nagent status" \
    | _menu "SSH keys")"
  [ -z "${action:-}" ] && return 0

  case "$action" in
    "list stored keys")
      local r; r="$(passx ssh-list 2>/dev/null | _ansi)"
      [ -z "$r" ] && r="No SSH keys stored"
      printf "%s\n\nclose" "$r" | _menu "SSH keys" >/dev/null ;;

    "add keypair to store")
      _term "passx ssh-add" "passx ssh-add; echo; read -rp 'Done — press enter'" ;;

    "restore key to ~/.ssh")
      local keys; keys="$(passx ssh-list 2>/dev/null | grep -oE '[^ ]+$')" || true
      [ -z "${keys:-}" ] && { _notify "passx" "No SSH keys in store"; return; }
      local k; k="$(printf "%s" "$keys" | _menu "restore which key?")"
      [ -z "${k:-}" ] && return
      passx ssh-set "$k" 2>/dev/null \
        && _notify "passx" "Key restored: $k" \
        || _notify "passx" "Restore failed" ;;

    "copy public key")
      local pub; pub="$(_list_entries | grep -E '\-pub$' | _menu "copy public key")"
      [ -z "${pub:-}" ] && return
      _CACHED_ENTRY=""
      local content; content="$(_field "$pub" full 2>/dev/null)" || true
      [ -n "$content" ] && _clip "$content" "Public key: ${pub##*/}" \
        || _notify "passx" "Decrypt failed" ;;

    "ssh-copy-id to host")
      local key; key="$(_list_entries | grep -E '\-pub$' | _menu "which public key?")"
      [ -z "${key:-}" ] && return
      local host; host="$(printf "" | _menu "host  (user@hostname)")"
      [ -z "${host:-}" ] && return
      _term "passx ssh-copy-id" "passx ssh-copy-id '${key}' '${host}'; echo; read -rp 'Done — press enter'" ;;

    "agent status")
      local r; r="$(passx ssh-agent-status 2>/dev/null | _ansi)"
      [ -z "$r" ] && r="ssh-agent not running or no keys loaded"
      printf "%s\n\nclose" "$r" | _menu "ssh-agent" >/dev/null ;;
  esac
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: add
# ══════════════════════════════════════════════════════════════════
_cmd_add() {
  local path
  path="$(printf "" | _menu "new entry path  (e.g. web/github)")"
  [ -z "${path:-}" ] && return 0
  _term "passx add" "passx add '${path}'; echo; read -rp 'Done — press enter'" \
    || _notify "passx" "No terminal — run: passx add '${path}'"
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: gen
# ══════════════════════════════════════════════════════════════════
_cmd_gen() {
  local mode
  mode="$(printf \
    "random  (${PASSX_GEN_LENGTH} chars)\nwords   (5-word passphrase)\nPIN     (6 digits)\npronounce  (16 chars)" \
    | _menu "generate password")"
  [ -z "${mode:-}" ] && return 0

  local pw=""
  case "$mode" in
    random*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen "$PASSX_GEN_LENGTH" --no-copy 2>/dev/null | head -1)" \
        || pw="$(LC_ALL=C tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom 2>/dev/null | head -c "$PASSX_GEN_LENGTH")" ;;
    words*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen --words 5 --no-copy 2>/dev/null | head -1)" \
        || pw="$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words 2>/dev/null \
                 | shuf -n5 2>/dev/null | tr '\n' '-' | sed 's/-$//')" ;;
    PIN*)
      pw="$(LC_ALL=C tr -dc '0-9' </dev/urandom 2>/dev/null | head -c 6)" ;;
    pronounce*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen --pronounceable --no-copy 2>/dev/null | head -1)" \
        || {
          local cv="bcdfghjklmnprstv" vw="aeiou" r="" i
          for ((i=0;i<16;i++)); do
            ((i%2==0)) && r+="${cv:RANDOM%${#cv}:1}" || r+="${vw:RANDOM%${#vw}:1}"
          done; pw="$r"
        } ;;
  esac

  [ -z "${pw:-}" ] && { _notify "passx" "Generation failed"; return 1; }
  _clip "$pw" "Generated password"

  # Optional: store it
  local store
  store="$(printf "clipboard only\nstore it" | _menu "store password?")"
  [ "${store:-}" = "store it" ] || return 0

  local spath
  spath="$(printf "" | _menu "store path  (e.g. temp/pass)")"
  [ -z "${spath:-}" ] && return 0

  printf "%s\n" "$pw" | pass insert -m -f "$spath" 2>/dev/null
  [ -f "$PASSWORD_STORE_DIR/${spath}.gpg" ] \
    && _notify "passx" "Stored at ${spath}" \
    || _notify "passx" "Store failed"
}

# ══════════════════════════════════════════════════════════════════
# SUB-COMMAND: conf
#   passx-menu conf          — generate menu.conf if missing, then
#                              open interactive settings editor
#   passx-menu conf --gen    — generate/overwrite menu.conf only
# ══════════════════════════════════════════════════════════════════
_MENU_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/passx/menu.conf"

_conf_write_default() {
  mkdir -p "$(dirname "$_MENU_CONF")"
  cat > "$_MENU_CONF" <<'CONF'
# ─────────────────────────────────────────────────────────
#  passx-menu configuration
#  Location: ~/.config/passx/menu.conf
#  All values here override passx.conf and env variables.
#  Edit this file or run:  passx-menu conf
# ─────────────────────────────────────────────────────────

# Launcher backend:  auto | rofi | wofi | dmenu | fzf
MENU="auto"

# Color theme:  catppuccin | nord | gruvbox | dracula | solarized
PASSX_THEME="catppuccin"

# Font for rofi/dmenu (rofi: "Name Size",  dmenu: "Name:size=N")
DMENU_FONT="monospace:size=11"

# Number of visible items in the list
DMENU_LINES="18"

# Clipboard auto-clear timeout in seconds
PASSX_CLIP_TIMEOUT="20"

# Desktop notifications:  true | false
PASSX_NOTIFY="true"

# Seconds to wait before xdotool types (give you time to focus window)
AUTOFILL_DELAY="0.5"

# Preferred terminal emulator for edit/add/template commands
# Leave empty to auto-detect (alacritty, kitty, foot, gnome-terminal...)
TERMINAL=""

# Default generated password length
PASSX_GEN_LENGTH="32"
CONF
}

_conf_read_val() {
  # _conf_read_val KEY  →  current value from conf file or running env
  local key="$1"
  local from_file=""
  [ -f "$_MENU_CONF" ] \
    && from_file="$(grep -m1 "^${key}=" "$_MENU_CONF" \
        | sed 's/^[^=]*=//; s/^"//; s/"$//' 2>/dev/null)" || true
  # running env takes priority (shows what's actually active)
  local from_env="${!key:-}"
  printf "%s" "${from_env:-${from_file:-}}"
}

_conf_set_val() {
  # _conf_set_val KEY VALUE  →  write/update line in menu.conf
  local key="$1" value="$2"
  [ -f "$_MENU_CONF" ] || _conf_write_default

  if grep -q "^${key}=" "$_MENU_CONF" 2>/dev/null; then
    # update existing line
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$_MENU_CONF"
  else
    # append
    printf '%s="%s"\n' "$key" "$value" >> "$_MENU_CONF"
  fi
  # apply live
  export "${key}=${value}"
}

_cmd_conf() {
  local gen_only=false
  [ "${1:-}" = "--gen" ] && gen_only=true

  # Generate conf if it doesn't exist
  if [ ! -f "$_MENU_CONF" ]; then
    _conf_write_default
    printf "passx-menu: created %s\n" "$_MENU_CONF"
  fi

  $gen_only && { printf "passx-menu: conf at %s\n" "$_MENU_CONF"; return 0; }

  # Interactive settings editor — loop until user picks "done"
  while true; do
    # Build menu showing key → current value
    local cur_menu cur_theme cur_font cur_lines cur_clip \
          cur_notify cur_delay cur_term cur_genlen

    cur_menu="$(_conf_read_val MENU)"
    cur_theme="$(_conf_read_val PASSX_THEME)"
    cur_font="$(_conf_read_val DMENU_FONT)"
    cur_lines="$(_conf_read_val DMENU_LINES)"
    cur_clip="$(_conf_read_val PASSX_CLIP_TIMEOUT)"
    cur_notify="$(_conf_read_val PASSX_NOTIFY)"
    cur_delay="$(_conf_read_val AUTOFILL_DELAY)"
    cur_term="$(_conf_read_val TERMINAL)"
    cur_genlen="$(_conf_read_val PASSX_GEN_LENGTH)"

    local setting
    setting="$(printf \
      "launcher         →  %s\ntheme            →  %s\nfont             →  %s\nlist lines       →  %s\nclip timeout     →  %s\nnotifications    →  %s\nautofill delay   →  %s\nterminal         →  %s\npassword length  →  %s\n---\nopen conf file\nreset to defaults\ndone" \
      "${cur_menu:-auto}" \
      "${cur_theme:-catppuccin}" \
      "${cur_font:-monospace:size=11}" \
      "${cur_lines:-18}" \
      "${cur_clip:-20}s" \
      "${cur_notify:-true}" \
      "${cur_delay:-0.5}s" \
      "${cur_term:-(auto)}" \
      "${cur_genlen:-32}" \
      | _menu "passx-menu settings")"

    [ -z "${setting:-}" ] && return 0

    case "$setting" in

      launcher*)
        local v
        v="$(printf "auto\nrofi\nwofi\ndmenu\nfzf" | _menu "launcher")"
        [ -z "${v:-}" ] && continue
        _conf_set_val MENU "$v"
        _detect_backend
        _notify "passx-menu" "Launcher set: $v" ;;

      theme*)
        local v
        v="$(printf "catppuccin\nnord\ngruvbox\ndracula\nsolarized" | _menu "theme")"
        [ -z "${v:-}" ] && continue
        _conf_set_val PASSX_THEME "$v"
        PASSX_THEME="$v"
        _load_theme
        _notify "passx-menu" "Theme set: $v" ;;

      font*)
        local v
        v="$(printf \
          "monospace:size=11\nmonospace:size=12\nmonospace:size=13\nJetBrains Mono:size=11\nFira Code:size=11\nHack:size=11\nIosevka:size=12\nNoto Mono:size=11\ncustom..." \
          | _menu "font  (current: ${cur_font})")"
        [ -z "${v:-}" ] && continue
        if [ "$v" = "custom..." ]; then
          v="$(printf "" | _menu "type font string  (e.g. Hack:size=12)")"
          [ -z "${v:-}" ] && continue
        fi
        _conf_set_val DMENU_FONT "$v"
        DMENU_FONT="$v"
        _notify "passx-menu" "Font set: $v" ;;

      "list lines"*)
        local v
        v="$(printf "10\n12\n15\n18\n20\n25\n30" | _menu "visible list lines  (current: ${cur_lines})")"
        [ -z "${v:-}" ] && continue
        _conf_set_val DMENU_LINES "$v"
        DMENU_LINES="$v"
        _notify "passx-menu" "Lines set: $v" ;;

      "clip timeout"*)
        local v
        v="$(printf "10\n15\n20\n30\n45\n60\n0  (never clear)" \
          | _menu "clipboard clear timeout  (current: ${cur_clip}s)")"
        [ -z "${v:-}" ] && continue
        v="${v%% *}"  # strip " (never clear)" suffix
        _conf_set_val PASSX_CLIP_TIMEOUT "$v"
        PASSX_CLIP_TIMEOUT="$v"
        _notify "passx-menu" "Clip timeout: ${v}s" ;;

      notifications*)
        local v
        v="$(printf "true\nfalse" | _menu "notifications  (current: ${cur_notify})")"
        [ -z "${v:-}" ] && continue
        _conf_set_val PASSX_NOTIFY "$v"
        PASSX_NOTIFY="$v"
        _notify "passx-menu" "Notifications: $v" ;;

      "autofill delay"*)
        local v
        v="$(printf "0.2\n0.3\n0.5\n0.8\n1.0\n1.5\n2.0" \
          | _menu "autofill delay in seconds  (current: ${cur_delay}s)")"
        [ -z "${v:-}" ] && continue
        _conf_set_val AUTOFILL_DELAY "$v"
        AUTOFILL_DELAY="$v"
        _notify "passx-menu" "Autofill delay: ${v}s" ;;

      terminal*)
        local v
        v="$(printf "auto-detect\nalacritty\nkitty\nwezterm\nfoot\ngnome-terminal\nkonsole\nst\nxterm" \
          | _menu "terminal  (current: ${cur_term:-(auto)})")"
        [ -z "${v:-}" ] && continue
        [ "$v" = "auto-detect" ] && v=""
        _conf_set_val TERMINAL "$v"
        TERMINAL="$v"
        _notify "passx-menu" "Terminal: ${v:-(auto)}" ;;

      "password length"*)
        local v
        v="$(printf "16\n20\n24\n28\n32\n40\n48\n64" \
          | _menu "default password length  (current: ${cur_genlen})")"
        [ -z "${v:-}" ] && continue
        _conf_set_val PASSX_GEN_LENGTH "$v"
        PASSX_GEN_LENGTH="$v"
        _notify "passx-menu" "Password length: $v" ;;

      "open conf file")
        local term; term="$(_find_term 2>/dev/null)" || true
        if [ -n "${EDITOR:-}" ] && [ -n "$term" ]; then
          _term "menu.conf" "${EDITOR:-nano} '$_MENU_CONF'; read -rp 'Done — press enter'"
        elif [ -n "$term" ]; then
          _term "menu.conf" "nano '$_MENU_CONF'; read -rp 'Done — press enter'"
        else
          _notify "passx-menu" "No terminal found — edit manually: $_MENU_CONF"
        fi ;;

      "reset to defaults")
        local yn
        yn="$(printf "cancel\nyes — reset menu.conf" | _menu "reset to defaults?")"
        [[ "${yn:-}" == "yes"* ]] || continue
        _conf_write_default
        # reload
        source "$_MENU_CONF" 2>/dev/null || true
        _load_theme
        _detect_backend
        _notify "passx-menu" "Reset to defaults" ;;

      "done"|"---") return 0 ;;

    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ACTION MENU — built dynamically, decrypt only once via cache
# ══════════════════════════════════════════════════════════════════
_build_actions() {
  local entry="$1"

  # Prime cache with one decrypt — all _has/_field calls below reuse it
  _CACHED_ENTRY=""
  _decrypt "$entry" >/dev/null 2>&1 || true

  # Always available
  printf "copy password\n"

  # Field-conditional copies
  _has "$entry" username 2>/dev/null && printf "copy username\n"
  _has "$entry" email    2>/dev/null && printf "copy email\n"
  _has "$entry" token    2>/dev/null && printf "copy token\n"
  _has "$entry" url      2>/dev/null && printf "copy url\n"

  # OTP block
  if _has_otp "$entry" 2>/dev/null; then
    printf "%s\n" "---"
    printf "otp  copy\n"
    command -v xdotool >/dev/null 2>&1 && printf "otp  type\n"
    printf "otp  show\n"
  fi

  # Autofill block (xdotool required)
  if command -v xdotool >/dev/null 2>&1; then
    printf "%s\n" "---"
    printf "autofill  (user+pass)\n"
    printf "type password only\n"
  fi

  # Browser
  _has "$entry" url 2>/dev/null && printf "open url\n"

  # Manage
  printf "%s\n" "---"
  printf "edit\n"
  printf "set field\n"
  printf "rotate password\n"
  printf "rename\n"
  printf "clone\n"
  printf "delete\n"

  # Inspect
  printf "%s\n" "---"
  printf "show entry\n"
  printf "check strength\n"
  printf "check hibp\n"
  printf "%s\n" "---"
  printf "back\n"
}

_run_action() {
  local entry="$1" action="$2"

  case "$action" in

    "copy password")
      local pw; pw="$(_field "$entry" password 2>/dev/null)" || true
      [ -n "$pw" ] && _clip "$pw" "Password: ${entry##*/}" \
        || _notify "passx" "Decrypt failed" ;;

    "copy username")
      local v; v="$(_field "$entry" username 2>/dev/null)" || true
      [ -n "$v" ] && _clip "$v" "Username" || _notify "passx" "No username" ;;

    "copy email")
      local v; v="$(_field "$entry" email 2>/dev/null)" || true
      [ -n "$v" ] && _clip "$v" "Email" || _notify "passx" "No email" ;;

    "copy token")
      local v; v="$(_field "$entry" token 2>/dev/null)" || true
      [ -n "$v" ] && _clip "$v" "Token" || _notify "passx" "No token" ;;

    "copy url")
      local v; v="$(_field "$entry" url 2>/dev/null)" || true
      [ -n "$v" ] && _clip "$v" "URL" || _notify "passx" "No url" ;;

    "otp  copy")
      local code; code="$(_otp_code "$entry")"
      [ -n "$code" ] && _clip "$code" "OTP: ${entry##*/}" \
        || _notify "passx" "OTP failed — not configured?" ;;

    "otp  type")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return; }
      local code; code="$(_otp_code "$entry")"
      [ -z "$code" ] && { _notify "passx" "OTP failed"; return; }
      _notify "passx" "Switch to target window…"
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers --delay 50 "$code"
      _notify "passx" "OTP typed" ;;

    "otp  show")
      local code; code="$(_otp_code "$entry")"
      [ -z "$code" ] && { _notify "passx" "OTP failed"; return; }
      _clip "$code" "OTP: ${entry##*/}"
      local remaining="$(( 30 - $(date +%s) % 30 ))s left"
      printf "%s\n%s\n\nclose" "$code" "$remaining" \
        | _menu "OTP: ${entry##*/}" >/dev/null ;;

    "autofill  (user+pass)")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return; }
      local user="" pass=""
      user="$(_field "$entry" username 2>/dev/null)" || true
      [ -z "$user" ] && user="$(_field "$entry" email 2>/dev/null)" || true
      pass="$(_field "$entry" password 2>/dev/null)" || true
      [ -z "$pass" ] && { _notify "passx" "Decrypt failed"; return; }
      _notify "passx" "Switch to target window…"
      sleep "$AUTOFILL_DELAY"
      [ -n "$user" ] && xdotool type --clearmodifiers --delay 30 "$user"
      xdotool key --clearmodifiers Tab
      sleep 0.15
      xdotool type --clearmodifiers --delay 30 "$pass"
      xdotool key --clearmodifiers Return
      _notify "passx" "Autofilled: ${entry##*/}" ;;

    "type password only")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return; }
      local pass; pass="$(_field "$entry" password 2>/dev/null)" || true
      [ -z "$pass" ] && { _notify "passx" "Decrypt failed"; return; }
      _notify "passx" "Switch to target window…"
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers --delay 30 "$pass"
      _notify "passx" "Password typed" ;;

    "open url")
      local url; url="$(_field "$entry" url 2>/dev/null)" || true
      [ -z "${url:-}" ] && { _notify "passx" "No URL in ${entry##*/}"; return; }
      local opener
      for opener in xdg-open open firefox chromium brave-browser; do
        command -v "$opener" >/dev/null 2>&1 && { "$opener" "$url" &>/dev/null & disown; return; }
      done
      _notify "passx" "No browser found" ;;

    "edit")
      _term "passx edit" "passx edit '${entry}'; echo; read -rp 'Done — press enter'" \
        || _notify "passx" "No terminal — run: passx edit '${entry}'"
      _CACHED_ENTRY=""  # invalidate cache after edit
      ;;

    "set field")
      local field
      field="$(printf "username\nemail\nurl\nnotes\ntoken\npassword\ncustom..." \
        | _menu "which field?")"
      [ -z "${field:-}" ] && return
      [ "$field" = "custom..." ] && {
        field="$(printf "" | _menu "field name")"; [ -z "${field:-}" ] && return; }
      local value
      value="$(printf "" | _menu "value for ${field}")"
      [ -z "${value:-}" ] && return
      passx set-field "$entry" "$field" "$value" 2>/dev/null \
        && { _notify "passx" "Updated: ${field}"; _CACHED_ENTRY=""; } \
        || _notify "passx" "set-field failed" ;;

    "rotate password")
      local r; r="$(passx rotate "$entry" 2>/dev/null | _ansi)" || true
      _CACHED_ENTRY=""
      _notify "passx" "Password rotated: ${entry##*/}" ;;

    "rename")
      local dest; dest="$(printf "" | _menu "rename to  (new/path)")"
      [ -z "${dest:-}" ] && return
      passx rename "$entry" "$dest" 2>/dev/null \
        && _notify "passx" "Renamed → ${dest}" \
        || _notify "passx" "Rename failed"
      return 1 ;;  # exit entry loop — entry no longer exists at old path

    "clone")
      local dest; dest="$(printf "" | _menu "clone to  (new/path)")"
      [ -z "${dest:-}" ] && return
      passx clone "$entry" "$dest" 2>/dev/null \
        && _notify "passx" "Cloned → ${dest}" \
        || _notify "passx" "Clone failed" ;;

    "delete")
      local confirm
      confirm="$(printf "cancel\nyes  —  delete ${entry##*/}" | _menu "confirm delete")"
      [[ "${confirm:-}" == "yes"* ]] || { _notify "passx" "Cancelled"; return; }
      pass rm -f "$entry" 2>/dev/null \
        && _notify "passx" "Deleted: ${entry##*/}" \
        || _notify "passx" "Delete failed"
      return 1 ;;  # entry gone

    "show entry")
      local raw; raw="$(_field "$entry" full 2>/dev/null | _ansi)" || true
      [ -z "${raw:-}" ] && { _notify "passx" "Decrypt failed"; return; }
      printf "%s\n\nclose" "$raw" | _menu "${entry##*/}" >/dev/null ;;

    "check strength")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      local r; r="$(passx strength "$entry" 2>/dev/null | _ansi)"
      printf "%s\n\nclose" "${r:-no output}" | _menu "strength: ${entry##*/}" >/dev/null ;;

    "check hibp")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      _notify "passx" "Checking HIBP…"
      local r; r="$(passx hibp "$entry" 2>/dev/null | _ansi)"
      printf "%s\n\nclose" "${r:-no output}" | _menu "HIBP: ${entry##*/}" >/dev/null ;;

    "back"|"---") return 1 ;;

  esac
  return 0
}

# ══════════════════════════════════════════════════════════════════
# MAIN PICKER
# ══════════════════════════════════════════════════════════════════
_header() {
  printf "  new entry from template\n"
  printf "  autofill service\n"
  printf "  otp picker\n"
  printf "  ssh keys\n"
  printf "  generate password\n"
  printf "  add entry\n"
  printf "  audit\n"
  printf "  doctor\n"
  printf "  settings\n"
  printf "%s\n" "---"
}

_header_action() {
  case "$1" in
    *"new entry from template") _cmd_template ;;
    *"autofill service")        _cmd_fill ;;
    *"otp picker")              _cmd_otp ;;
    *"ssh keys")                _cmd_ssh ;;
    *"generate password")       _cmd_gen ;;
    *"add entry")               _cmd_add ;;
    *"settings")                _cmd_conf ;;
    *"audit")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      _notify "passx" "Running audit…"
      local r; r="$(passx audit 2>/dev/null | _ansi)"
      printf "%s\n\nclose" "${r:-all good}" | _menu "audit" >/dev/null ;;
    *"doctor")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      local r; r="$(passx doctor 2>/dev/null | _ansi)"
      printf "%s\n\nclose" "${r:-ok}" | _menu "doctor" >/dev/null ;;
  esac
}

_entry_loop() {
  local entry="$1"
  _CACHED_ENTRY=""  # always fresh on entry
  while true; do
    local action
    action="$(_build_actions "$entry" | _menu "${entry##*/}")"
    [ -z "${action:-}" ] && return 0
    [ "$action" = "---" ] && continue
    _run_action "$entry" "$action" || return 0
  done
}

_main() {
  [ -z "$_BACKEND" ] && _die "No menu backend. Install rofi, wofi, dmenu, or fzf."

  while true; do
    local chosen
    chosen="$({ _header; _list_entries; } | _menu "passx")"
    [ -z "${chosen:-}" ] && return 0
    [ "$chosen" = "---" ] && continue
    case "$chosen" in
      "  new entry from template"|"  autofill service"|"  otp picker"|\
      "  ssh keys"|"  generate password"|"  add entry"|"  audit"|"  doctor"|"  settings")
        _header_action "$chosen"; continue ;;
    esac
    _entry_loop "$chosen"
  done
}

# ══════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════
_help() {
cat <<'HELP'

passx-menu  v1.2.0  —  rofi / wofi / dmenu launcher for passx

USAGE
  passx-menu              main picker
  passx-menu otp          OTP picker  (all entries, live codes)
  passx-menu t            new entry from template
  passx-menu fill         autofill picker
  passx-menu copy         pick entry and copy password
  passx-menu ssh          SSH key manager
  passx-menu add          quick add entry
  passx-menu gen          generate password to clipboard
  passx-menu conf         interactive settings  (generates menu.conf)
  passx-menu conf --gen   generate menu.conf only  (no interactive)
  passx-menu -e <path>    jump to action menu for <path>
  passx-menu -V           version
  passx-menu -h           this help

ENV
  MENU              rofi | wofi | dmenu | fzf | auto
  PASSX_THEME       catppuccin | nord | gruvbox | dracula | solarized
  PASSX_CLIP_TIMEOUT  clipboard clear (default 20)
  DMENU_FONT        font string (default monospace:size=11)
  DMENU_LINES       list height (default 18)
  TERMINAL          preferred terminal for edit/add
  AUTOFILL_DELAY    seconds before xdotool types (default 0.5)

CONFIG
  ~/.config/passx/passx.conf   inherited from passx
  ~/.config/passx/menu.conf    menu-only overrides

HELP
}

# ══════════════════════════════════════════════════════════════════
# ARG PARSING + DISPATCH
# ══════════════════════════════════════════════════════════════════
SUBCMD=""
DIRECT_ENTRY=""

case "${1:-}" in
  otp|fill|copy|add|gen|ssh|conf) SUBCMD="$1"; shift ;;
  t|template)                SUBCMD="template"; shift ;;
  -h|--help)                 _help; exit 0 ;;
  -V|--version)              printf "passx-menu %s\n" "$PASSX_MENU_VERSION"; exit 0 ;;
  -e|--entry)                DIRECT_ENTRY="${2:-}"; shift 2 2>/dev/null || true ;;
  -m|--menu)                 MENU="${2:-}"; shift 2 2>/dev/null || true; _detect_backend ;;
  --theme)                   PASSX_THEME="${2:-}"; shift 2 2>/dev/null || true; _load_theme ;;
  "") ;;
  *) printf "unknown option: %s\n" "$1" >&2; _help; exit 1 ;;
esac

# sanity
[ -d "$PASSWORD_STORE_DIR" ] \
  || _die "Store not found: $PASSWORD_STORE_DIR  (run: pass init <gpg-id>)"
[ -f "$PASSWORD_STORE_DIR/.gpg-id" ] \
  || _die "Store not initialized  (run: pass init <gpg-id>)"

case "$SUBCMD" in
  otp)      _cmd_otp ;;
  template) _cmd_template ;;
  fill)     _cmd_fill ;;
  copy)     _cmd_copy ;;
  ssh)      _cmd_ssh ;;
  add)      _cmd_add ;;
  gen)      _cmd_gen ;;
  conf)     _cmd_conf "${1:-}" ;;
  "")
    if [ -n "$DIRECT_ENTRY" ]; then
      _entry_loop "$DIRECT_ENTRY"
    else
      _main
    fi ;;
esac

#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  passx-menu  —  dmenu / rofi / wofi launcher for passx              ║
# ║  Version: 1.1.0                                                      ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
#  USAGE
#    passx-menu              — main entry picker
#    passx-menu otp          — OTP-only picker  (copy/type live codes)
#    passx-menu t            — new entry from template
#    passx-menu fill         — autofill service picker
#    passx-menu copy         — pick entry and copy password
#    passx-menu add          — quick add via terminal
#    passx-menu gen          — generate password to clipboard
#    passx-menu -e <path>    — jump to action menu for a specific entry
#
set -euo pipefail
PASSX_MENU_VERSION="1.1.0"

# ══════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════
PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
PASSX_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/passx"

for _cf in \
  "$PASSX_CONF_DIR/passx.conf" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/passx.conf" \
  "$PASSX_CONF_DIR/menu.conf"; do
  [ -f "$_cf" ] && source "$_cf"
done

: "${PASSX_THEME:=catppuccin}"
: "${PASSX_CLIP_TIMEOUT:=20}"
: "${PASSX_NOTIFY:=true}"
: "${PASSX_GEN_LENGTH:=32}"
: "${MENU:=auto}"
: "${DMENU_FONT:=monospace:size=11}"
: "${DMENU_LINES:=20}"
: "${TERMINAL:=}"
: "${AUTOFILL_DELAY:=0.4}"

# ══════════════════════════════════════════════════════════════════════
# THEMES
# ══════════════════════════════════════════════════════════════════════
_load_theme() {
  case "${PASSX_THEME}" in
    catppuccin)
      T_BG="#1e1e2e"; T_BG2="#313244"; T_FG="#cdd6f4"
      T_SEL="#cba6f7"; T_SELBG="#45475a"; T_BORDER="#89b4fa"
      T_PROMPT="#cba6f7"; T_DM_NF="#94e2d5"; T_DM_NB="#1e1e2e"
      T_DM_SF="#1e1e2e"; T_DM_SB="#cba6f7" ;;
    nord)
      T_BG="#2e3440"; T_BG2="#3b4252"; T_FG="#d8dee9"
      T_SEL="#81a1c1"; T_SELBG="#4c566a"; T_BORDER="#5e81ac"
      T_PROMPT="#81a1c1"; T_DM_NF="#d8dee9"; T_DM_NB="#2e3440"
      T_DM_SF="#2e3440"; T_DM_SB="#81a1c1" ;;
    gruvbox)
      T_BG="#282828"; T_BG2="#3c3836"; T_FG="#ebdbb2"
      T_SEL="#d79921"; T_SELBG="#504945"; T_BORDER="#689d6a"
      T_PROMPT="#fabd2f"; T_DM_NF="#ebdbb2"; T_DM_NB="#282828"
      T_DM_SF="#282828"; T_DM_SB="#d79921" ;;
    dracula)
      T_BG="#282a36"; T_BG2="#44475a"; T_FG="#f8f8f2"
      T_SEL="#bd93f9"; T_SELBG="#44475a"; T_BORDER="#6272a4"
      T_PROMPT="#ff79c6"; T_DM_NF="#f8f8f2"; T_DM_NB="#282a36"
      T_DM_SF="#282a36"; T_DM_SB="#bd93f9" ;;
    solarized)
      T_BG="#002b36"; T_BG2="#073642"; T_FG="#839496"
      T_SEL="#268bd2"; T_SELBG="#073642"; T_BORDER="#2aa198"
      T_PROMPT="#2aa198"; T_DM_NF="#839496"; T_DM_NB="#002b36"
      T_DM_SF="#002b36"; T_DM_SB="#268bd2" ;;
    *)
      T_BG="#1a1a2e"; T_BG2="#16213e"; T_FG="#e0e0e0"
      T_SEL="#7c3aed"; T_SELBG="#2d2d44"; T_BORDER="#7c3aed"
      T_PROMPT="#7c3aed"; T_DM_NF="#e0e0e0"; T_DM_NB="#1a1a2e"
      T_DM_SF="#1a1a2e"; T_DM_SB="#7c3aed" ;;
  esac
}
_load_theme

# ══════════════════════════════════════════════════════════════════════
# BACKEND
# ══════════════════════════════════════════════════════════════════════
_detect_backend() {
  [ "$MENU" != "auto" ] && { _BACKEND="$MENU"; return; }
  command -v rofi  >/dev/null 2>&1 && { _BACKEND="rofi";  return; }
  command -v wofi  >/dev/null 2>&1 && { _BACKEND="wofi";  return; }
  command -v dmenu >/dev/null 2>&1 && { _BACKEND="dmenu"; return; }
  _BACKEND="fzf"
}
_detect_backend

# ══════════════════════════════════════════════════════════════════════
# UTILS
# ══════════════════════════════════════════════════════════════════════
_notify() {
  [ "$PASSX_NOTIFY" = "true" ] || return 0
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a passx -t 3000 -i dialog-password "${1:-passx}" "${2:-}" 2>/dev/null || true
}
_die()        { _notify "passx-menu" "$1"; printf "passx-menu: %s\n" "$1" >&2; exit 1; }
_strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

_find_terminal() {
  local t
  [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1 \
    && { printf "%s" "$TERMINAL"; return; }
  for t in alacritty kitty wezterm foot gnome-terminal konsole st xterm; do
    command -v "$t" >/dev/null 2>&1 && { printf "%s" "$t"; return; }
  done
}

_term_exec() {
  local title="$1" cmd="$2"
  local term; term="$(_find_terminal)"
  [ -z "${term:-}" ] && { _notify "passx-menu" "No terminal found"; return 1; }
  case "$term" in
    alacritty)     alacritty --title "$title" -e bash -c "$cmd" & ;;
    kitty)         kitty --title "$title" bash -c "$cmd" & ;;
    wezterm)       wezterm start -- bash -c "$cmd" & ;;
    foot)          foot --title "$title" bash -c "$cmd" & ;;
    gnome-terminal) gnome-terminal --title "$title" -- bash -c "$cmd" & ;;
    konsole)       konsole -e bash -c "$cmd" & ;;
    *)             $term -e bash -c "$cmd" & ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════
# MENU WRAPPER   (_show_menu "prompt" < items)
# ══════════════════════════════════════════════════════════════════════
_show_menu() {
  local prompt="${1:-passx}"
  case "$_BACKEND" in

    rofi)
      local _r; _r="$(mktemp /tmp/passx-XXXXXX.rasi)"
      cat > "$_r" <<RASI
* {
  bg:   ${T_BG};    bg2:  ${T_BG2};
  fg:   ${T_FG};    sel:  ${T_SEL};
  sbg:  ${T_SELBG}; brd:  ${T_BORDER};
  pc:   ${T_PROMPT};
  font: "${DMENU_FONT}";
}
window       { background-color:@bg;  border-color:@brd; border:2px; border-radius:8px; width:520px; }
mainbox      { background-color:transparent; padding:8px; }
inputbar     { background-color:@bg2; text-color:@fg; border-radius:6px; padding:6px 10px; margin:0 0 6px 0; }
prompt       { text-color:@pc; }
entry        { text-color:@fg; }
listview     { lines:${DMENU_LINES}; spacing:2px; background-color:transparent; }
element      { background-color:transparent; text-color:@fg; padding:5px 10px; border-radius:4px; }
element selected { background-color:@sbg; text-color:@sel; }
element-text { background-color:transparent; text-color:inherit; }
RASI
      rofi -dmenu -i -p " ${prompt}" -theme "$_r" -no-custom 2>/dev/null || true
      rm -f "$_r" ;;

    wofi)
      local _w; _w="$(mktemp /tmp/passx-XXXXXX.css)"
      printf 'window{background-color:%s;border:2px solid %s;border-radius:8px;}\n' "$T_BG" "$T_BORDER" > "$_w"
      printf '#input{background-color:%s;color:%s;border-radius:6px;margin:6px;padding:4px 8px;}\n' "$T_BG2" "$T_FG" >> "$_w"
      printf '#outer-box{margin:4px;}#scroll{margin:2px;}\n' >> "$_w"
      printf '#text{color:%s;padding:4px 8px;}\n' "$T_FG" >> "$_w"
      printf '#entry:selected{background-color:%s;}#text:selected{color:%s;}\n' "$T_SELBG" "$T_SEL" >> "$_w"
      wofi --dmenu --insensitive \
        --prompt " ${prompt}" \
        --lines "$DMENU_LINES" \
        --style "$_w" 2>/dev/null || true
      rm -f "$_w" ;;

    dmenu)
      dmenu -i -p " ${prompt} >" \
        -fn "$DMENU_FONT" -l "$DMENU_LINES" \
        -nb "$T_DM_NB" -nf "$T_DM_NF" \
        -sb "$T_DM_SB" -sf "$T_DM_SF" \
        2>/dev/null || true ;;

    fzf|*)
      command -v fzf >/dev/null 2>&1 \
        || _die "No menu backend — install rofi, wofi, dmenu, or fzf"
      fzf --prompt=" ${prompt} > " \
          --pointer=">" --layout=reverse --border=rounded \
          --height=60% 2>/dev/null || true ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════
# ENTRY / FIELD HELPERS
# ══════════════════════════════════════════════════════════════════════
_list_entries() {
  if pass ls --flat 2>/dev/null | head -1 >/dev/null 2>&1; then
    pass ls --flat 2>/dev/null | sort
  else
    find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
      | sed "s|^${PASSWORD_STORE_DIR}/||; s|\.gpg$||" | sort
  fi
}

_get_field() {
  local entry="$1" field="$2"
  case "$field" in
    password) pass show "$entry" 2>/dev/null | sed -n '1p' ;;
    full)     pass show "$entry" 2>/dev/null ;;
    *)        pass show "$entry" 2>/dev/null | grep -m1 "^${field}:" | sed "s/^${field}: *//" ;;
  esac
}

_has_field() {
  local v; v="$(_get_field "$1" "$2" 2>/dev/null)"
  [ -n "${v:-}" ]
}

_has_otp() {
  pass show "$1" 2>/dev/null | grep -qE '^otpauth://|^otp:'
}

# ══════════════════════════════════════════════════════════════════════
# CLIPBOARD
# ══════════════════════════════════════════════════════════════════════
_clip() {
  local data="$1" label="${2:-copied}"
  if command -v wl-copy >/dev/null 2>&1; then
    printf "%s" "$data" | wl-copy 2>/dev/null
  elif command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    printf "%s" "$data" | xclip -selection clipboard 2>/dev/null
  elif command -v clip.exe >/dev/null 2>&1; then
    printf "%s" "$data" | clip.exe 2>/dev/null
    _notify "passx" "$label"; return 0
  else
    _notify "passx-menu" "No clipboard backend"; return 1
  fi
  _notify "passx" "${label} — clears in ${PASSX_CLIP_TIMEOUT}s"
  local t="$PASSX_CLIP_TIMEOUT"
  ( sleep "$t"
    { command -v wl-copy  >/dev/null 2>&1 && printf "" | wl-copy  2>/dev/null; } \
    || { command -v xclip >/dev/null 2>&1 && printf "" | xclip -selection clipboard 2>/dev/null; } \
    || true
  ) & disown 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════
# OTP HELPER  (used by both otp sub-command and action menu)
# ══════════════════════════════════════════════════════════════════════
_get_otp_code() {
  local entry="$1" code=""
  if command -v passx >/dev/null 2>&1; then
    code="$(passx otp "$entry" --no-copy 2>/dev/null | tr -d '[:space:]')" || true
  fi
  if [ -z "${code:-}" ] && command -v oathtool >/dev/null 2>&1; then
    local raw; raw="$(pass show "$entry" 2>/dev/null)"
    local secret
    secret="$(printf "%s" "$raw" | grep -m1 '^otp:' | sed 's/^otp: *//' | tr -d '[:space:]')"
    [ -z "${secret:-}" ] && \
      secret="$(printf "%s" "$raw" | grep -oE 'secret=[^&]+' | sed 's/secret=//' | head -1 | tr -d '[:space:]')"
    [ -n "${secret:-}" ] && code="$(oathtool --totp --base32 "$secret" 2>/dev/null)" || true
  fi
  printf "%s" "$code"
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: otp
# ══════════════════════════════════════════════════════════════════════
_cmd_otp() {
  local otp_entries
  otp_entries="$(
    _list_entries | while IFS= read -r e; do
      pass show "$e" 2>/dev/null | grep -qE '^otpauth://|^otp:' && printf "%s\n" "$e"
    done
  )"
  [ -z "${otp_entries:-}" ] && { _notify "passx" "No OTP entries found"; exit 0; }

  local entry
  entry="$(printf "%s" "$otp_entries" | _show_menu "OTP")"
  [ -z "${entry:-}" ] && exit 0

  local action
  action="$(printf "copy code\ntype code\nshow code" | _show_menu "$entry")"
  [ -z "${action:-}" ] && exit 0

  local code; code="$(_get_otp_code "$entry")"
  [ -z "${code:-}" ] && { _notify "passx" "OTP failed for $entry"; exit 1; }

  case "$action" in
    "copy code")
      _clip "$code" "OTP — ${entry##*/}" ;;
    "type code")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; exit 1; }
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers "$code"
      _notify "passx" "OTP typed — ${entry##*/}" ;;
    "show code")
      _clip "$code" "OTP — ${entry##*/}"
      printf "%s\n---\nclose" "$code" | _show_menu "OTP: ${entry##*/}" >/dev/null ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: t  (template — new entry)
# ══════════════════════════════════════════════════════════════════════
_cmd_template() {
  command -v passx >/dev/null 2>&1 || _die "passx not installed"

  local ttype
  ttype="$(printf \
    "web-login\nserver\ndatabase\napi-key\nemail-account\ncredit-card\nsoftware-license\nwifi\nnote" \
    | _show_menu "new entry — pick type")"
  [ -z "${ttype:-}" ] && exit 0

  local path
  path="$(printf "" | _show_menu "store path  (e.g. web/github)")"
  [ -z "${path:-}" ] && exit 0

  _term_exec "passx template" \
    "passx template; echo; read -rp 'Done — press enter to close'"
  _notify "passx" "Template: ${ttype}"
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: fill
# ══════════════════════════════════════════════════════════════════════
_cmd_fill() {
  command -v xdotool >/dev/null 2>&1 || _die "xdotool required for autofill"

  # list web entries first (have url field), then others
  local all; all="$(_list_entries)"
  local web other entry

  web="$(printf "%s" "$all" | while IFS= read -r e; do
    _has_field "$e" url 2>/dev/null && printf "%s\n" "$e"
  done)" || true

  other="$(printf "%s" "$all" | while IFS= read -r e; do
    _has_field "$e" url 2>/dev/null || printf "%s\n" "$e"
  done)" || true

  entry="$(
    { [ -n "${web:-}" ]   && printf "%s\n" "$web";
      [ -n "${other:-}" ] && printf "%s\n" "$other"; } \
    | _show_menu "autofill"
  )"
  [ -z "${entry:-}" ] && exit 0

  local mode
  mode="$(printf \
    "type user > TAB > type pass > Enter\ntype username only\ntype password only\ncopy user then copy pass" \
    | _show_menu "$entry")"
  [ -z "${mode:-}" ] && exit 0

  local user pass
  user="$(_get_field "$entry" username 2>/dev/null || true)"
  [ -z "${user:-}" ] && user="$(_get_field "$entry" email 2>/dev/null || true)"
  pass="$(_get_field "$entry" password)" || { _notify "passx" "Decrypt failed"; exit 1; }

  sleep "$AUTOFILL_DELAY"

  case "$mode" in
    "type user"*)
      [ -n "${user:-}" ] && xdotool type --clearmodifiers "$user"
      xdotool key Tab; sleep 0.1
      xdotool type --clearmodifiers "$pass"
      xdotool key Return
      _notify "passx" "Autofilled ${entry##*/}" ;;
    "type username"*)
      [ -n "${user:-}" ] && xdotool type --clearmodifiers "$user" \
        || { _notify "passx" "No username in $entry"; exit 1; }
      _notify "passx" "Username typed" ;;
    "type password"*)
      xdotool type --clearmodifiers "$pass"
      _notify "passx" "Password typed" ;;
    "copy user"*)
      [ -n "${user:-}" ] && _clip "$user" "Username — ${entry##*/}"
      sleep 1.2
      _clip "$pass" "Password — ${entry##*/}"
      _notify "passx" "Login ready — user then pass in clipboard" ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: copy
# ══════════════════════════════════════════════════════════════════════
_cmd_copy() {
  local entry
  entry="$(_list_entries | _show_menu "copy password")"
  [ -z "${entry:-}" ] && exit 0
  local pw; pw="$(_get_field "$entry" password)" \
    || { _notify "passx" "Decrypt failed"; exit 1; }
  [ -z "${pw:-}" ] && { _notify "passx" "No password in $entry"; exit 1; }
  _clip "$pw" "Password — ${entry##*/}"
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: add
# ══════════════════════════════════════════════════════════════════════
_cmd_add() {
  local path
  path="$(printf "" | _show_menu "new entry path  (e.g. web/github)")"
  [ -z "${path:-}" ] && exit 0
  _term_exec "passx add" "passx add '${path}'; echo; read -rp 'Done — press enter'"
  _notify "passx" "Adding: ${path}"
}

# ══════════════════════════════════════════════════════════════════════
# SUB-COMMAND: gen
# ══════════════════════════════════════════════════════════════════════
_cmd_gen() {
  local mode
  mode="$(printf \
    "random  (${PASSX_GEN_LENGTH} chars)\nwords   (5 word passphrase)\nPIN     (6 digits)\npronounce  (16 chars)" \
    | _show_menu "generate password")"
  [ -z "${mode:-}" ] && exit 0

  local pw
  case "$mode" in
    random*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen "$PASSX_GEN_LENGTH" --no-copy 2>/dev/null | head -1)" \
        || pw="$(LC_ALL=C tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom | head -c "$PASSX_GEN_LENGTH")" ;;
    words*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen --words 5 --no-copy 2>/dev/null | head -1)" \
        || pw="$(grep -E '^[a-z]{4,8}$' /usr/share/dict/words 2>/dev/null | shuf -n5 | tr '\n' '-' | sed 's/-$//')" ;;
    PIN*)
      pw="$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 6)" ;;
    pronounce*)
      command -v passx >/dev/null 2>&1 \
        && pw="$(passx gen --pronounceable --no-copy 2>/dev/null | head -1)" \
        || {
          local cv="bcdfghjklmnprstv" vw="aeiou" r=""
          for ((i=0;i<16;i++)); do
            ((i%2==0)) && r+="${cv:RANDOM%${#cv}:1}" || r+="${vw:RANDOM%${#vw}:1}"
          done; pw="$r"
        } ;;
  esac

  [ -z "${pw:-}" ] && { _notify "passx" "Generation failed"; exit 1; }
  _clip "$pw" "Generated password"

  local store
  store="$(printf "clipboard only\nstore it" | _show_menu "store this password?")"
  [[ "${store:-}" == "store it" ]] || exit 0

  local spath
  spath="$(printf "" | _show_menu "store path  (e.g. temp/new)")"
  [ -z "${spath:-}" ] && exit 0
  printf "%s\n" "$pw" | pass insert -m -f "$spath" 2>/dev/null \
    && _notify "passx" "Stored at ${spath}" \
    || _notify "passx" "Store failed"
}

# ══════════════════════════════════════════════════════════════════════
# MAIN PICKER — action menu builder
# ══════════════════════════════════════════════════════════════════════
_build_actions() {
  local entry="$1"
  printf "copy password\n"
  _has_field "$entry" username 2>/dev/null && printf "copy username\n"
  _has_field "$entry" email    2>/dev/null && printf "copy email\n"
  _has_field "$entry" token    2>/dev/null && printf "copy token\n"
  _has_field "$entry" url      2>/dev/null && printf "copy url\n"
  if _has_otp "$entry" 2>/dev/null; then
    printf "---\n"
    printf "otp copy\n"
    command -v xdotool >/dev/null 2>&1 && printf "otp type\n"
    printf "otp show\n"
  fi
  if command -v xdotool >/dev/null 2>&1; then
    printf "---\n"
    printf "autofill\n"
    printf "login sequence\n"
  fi
  _has_field "$entry" url 2>/dev/null && printf "open url\n"
  printf "---\n"
  printf "edit\n"
  printf "rotate password\n"
  printf "clone\n"
  printf "rename\n"
  printf "delete\n"
  printf "---\n"
  printf "show entry\n"
  printf "check strength\n"
  printf "check HIBP\n"
  printf "---\n"
  printf "back\n"
}

_run_action() {
  local entry="$1" action="$2"
  case "$action" in

    "copy password")
      local pw; pw="$(_get_field "$entry" password)" || { _notify "passx" "Decrypt failed"; return 1; }
      _clip "$pw" "Password — ${entry##*/}" ;;

    "copy username")
      local u; u="$(_get_field "$entry" username)"
      [ -n "${u:-}" ] && _clip "$u" "Username" || _notify "passx" "No username" ;;

    "copy email")
      local e; e="$(_get_field "$entry" email)"
      [ -n "${e:-}" ] && _clip "$e" "Email" || _notify "passx" "No email" ;;

    "copy token")
      local t; t="$(_get_field "$entry" token)"
      [ -n "${t:-}" ] && _clip "$t" "Token" || _notify "passx" "No token" ;;

    "copy url")
      local url; url="$(_get_field "$entry" url)"
      [ -n "${url:-}" ] && _clip "$url" "URL" || _notify "passx" "No url" ;;

    "otp copy")
      local code; code="$(_get_otp_code "$entry")"
      [ -n "${code:-}" ] && _clip "$code" "OTP — ${entry##*/}" \
        || _notify "passx" "OTP failed" ;;

    "otp type")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return; }
      local code; code="$(_get_otp_code "$entry")"
      [ -z "${code:-}" ] && { _notify "passx" "OTP failed"; return; }
      sleep "$AUTOFILL_DELAY"
      xdotool type --clearmodifiers "$code"
      _notify "passx" "OTP typed" ;;

    "otp show")
      local code; code="$(_get_otp_code "$entry")"
      [ -z "${code:-}" ] && { _notify "passx" "OTP failed"; return; }
      _clip "$code" "OTP — ${entry##*/}"
      printf "%s\n---\nclose" "$code" | _show_menu "OTP: ${entry##*/}" >/dev/null ;;

    "autofill")
      command -v xdotool >/dev/null 2>&1 || { _notify "passx" "xdotool not installed"; return; }
      local u p
      u="$(_get_field "$entry" username 2>/dev/null || true)"
      [ -z "${u:-}" ] && u="$(_get_field "$entry" email 2>/dev/null || true)"
      p="$(_get_field "$entry" password)"
      sleep "$AUTOFILL_DELAY"
      [ -n "${u:-}" ] && xdotool type --clearmodifiers "$u"
      xdotool key Tab; sleep 0.1
      xdotool type --clearmodifiers "$p"
      xdotool key Return
      _notify "passx" "Autofilled ${entry##*/}" ;;

    "login sequence")
      local u p
      u="$(_get_field "$entry" username 2>/dev/null || true)"
      [ -z "${u:-}" ] && u="$(_get_field "$entry" email 2>/dev/null || true)"
      p="$(_get_field "$entry" password)"
      [ -n "${u:-}" ] && _clip "$u" "Username — ${entry##*/}"
      sleep 1.2
      _clip "$p" "Password — ${entry##*/}" ;;

    "open url")
      local url; url="$(_get_field "$entry" url)"
      [ -z "${url:-}" ] && { _notify "passx" "No URL"; return; }
      for opener in xdg-open open firefox chromium-browser; do
        command -v "$opener" >/dev/null 2>&1 && { "$opener" "$url" & disown; return; }
      done
      _notify "passx" "No browser found" ;;

    "edit")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      _term_exec "passx edit" "passx edit '${entry}'; read -rp 'Done — press enter'"
      _notify "passx" "Editing ${entry##*/}" ;;

    "rotate password")
      command -v passx >/dev/null 2>&1 \
        && passx rotate "$entry" 2>/dev/null \
        && _notify "passx" "Rotated ${entry##*/}" \
        || _notify "passx" "Rotate failed" ;;

    "clone")
      local dest; dest="$(printf "" | _show_menu "clone to new path")"
      [ -z "${dest:-}" ] && return
      command -v passx >/dev/null 2>&1 \
        && passx clone "$entry" "$dest" 2>/dev/null \
        && _notify "passx" "Cloned to ${dest}" \
        || _notify "passx" "Clone failed" ;;

    "rename")
      local dest; dest="$(printf "" | _show_menu "rename to new path")"
      [ -z "${dest:-}" ] && return
      command -v passx >/dev/null 2>&1 \
        && passx rename "$entry" "$dest" 2>/dev/null \
        && _notify "passx" "Renamed to ${dest}" \
        || _notify "passx" "Rename failed" ;;

    "delete")
      local yn
      yn="$(printf "cancel\nyes delete ${entry}" | _show_menu "confirm delete?")"
      [[ "${yn:-}" == "yes"* ]] || { _notify "passx" "Cancelled"; return; }
      { command -v passx >/dev/null 2>&1 && passx rm "$entry" 2>/dev/null; } \
        || pass rm "$entry" 2>/dev/null
      _notify "passx" "Deleted ${entry##*/}"
      return 1 ;;

    "show entry")
      local raw; raw="$(pass show "$entry" 2>/dev/null | _strip_ansi)" \
        || { _notify "passx" "Decrypt failed"; return; }
      printf "%s\n---\nclose" "$raw" | _show_menu "${entry##*/}" >/dev/null ;;

    "check strength")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      local r; r="$(passx strength "$entry" 2>/dev/null | _strip_ansi)"
      printf "%s\n---\nclose" "$r" | _show_menu "strength: ${entry##*/}" >/dev/null ;;

    "check HIBP")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      _notify "passx" "Checking HIBP..."
      local r; r="$(passx hibp "$entry" 2>/dev/null | _strip_ansi)"
      printf "%s\n---\nclose" "$r" | _show_menu "HIBP: ${entry##*/}" >/dev/null ;;

    "back"|"---") return 1 ;;

  esac
  return 0
}

# ══════════════════════════════════════════════════════════════════════
# MAIN PICKER
# ══════════════════════════════════════════════════════════════════════
_quick_header() {
  printf "new entry from template\n"
  printf "autofill service\n"
  printf "otp picker\n"
  printf "generate password\n"
  printf "add entry\n"
  printf "doctor\n"
  printf "stats\n"
  printf "---\n"
}

_run_quick() {
  case "$1" in
    "new entry from template") _cmd_template ;;
    "autofill service")        _cmd_fill ;;
    "otp picker")              _cmd_otp ;;
    "generate password")       _cmd_gen ;;
    "add entry")               _cmd_add ;;
    "doctor")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      local r; r="$(passx doctor 2>/dev/null | _strip_ansi)"
      printf "%s\n---\nclose" "$r" | _show_menu "doctor" >/dev/null ;;
    "stats")
      command -v passx >/dev/null 2>&1 || { _notify "passx" "passx not installed"; return; }
      local r; r="$(passx stats 2>/dev/null | _strip_ansi)"
      printf "%s\n---\nclose" "$r" | _show_menu "stats" >/dev/null ;;
  esac
}

_entry_loop() {
  local entry="$1"
  while true; do
    local action
    action="$(_build_actions "$entry" | _show_menu "${entry##*/}")" || return 0
    [ -z "${action:-}" ] && return 0
    [ "$action" = "---" ] && continue
    _run_action "$entry" "$action" || return 0
  done
}

_main_picker() {
  while true; do
    local chosen
    chosen="$({ _quick_header; _list_entries; } | _show_menu "passx")" || true
    [ -z "${chosen:-}" ] && return 0
    [ "$chosen" = "---" ] && continue
    case "$chosen" in
      "new entry from template"|"autofill service"|"otp picker"|\
      "generate password"|"add entry"|"doctor"|"stats")
        _run_quick "$chosen"; continue ;;
    esac
    _entry_loop "$chosen"
  done
}

# ══════════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════════
_help() {
  cat <<EOF

passx-menu ${PASSX_MENU_VERSION}  --  dmenu / rofi / wofi launcher for passx

USAGE
  passx-menu              main entry picker
  passx-menu otp          OTP-only picker
  passx-menu t            new entry from template
  passx-menu fill         autofill service picker
  passx-menu copy         pick entry and copy password
  passx-menu add          type path and open terminal
  passx-menu gen          generate password to clipboard
  passx-menu -e <path>    jump to action menu for an entry
  passx-menu -V           version
  passx-menu -h           this help

ENV
  MENU              rofi | wofi | dmenu | fzf | auto
  PASSX_THEME       catppuccin | nord | gruvbox | dracula | solarized
  PASSX_CLIP_TIMEOUT  seconds before clipboard clears  (default 20)
  DMENU_FONT        font string  (default monospace:size=11)
  DMENU_LINES       visible lines  (default 20)
  TERMINAL          preferred terminal emulator
  AUTOFILL_DELAY    seconds before xdotool types  (default 0.4)

CONFIG
  ~/.config/passx/passx.conf   inherited from passx
  ~/.config/passx/menu.conf    menu-specific overrides

EOF
}

# ══════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING + DISPATCH
# ══════════════════════════════════════════════════════════════════════
DIRECT_ENTRY=""
SUBCMD=""

case "${1:-}" in
  otp|fill|copy|add|gen) SUBCMD="$1"; shift ;;
  t|template)            SUBCMD="template"; shift ;;
  -h|--help)             _help; exit 0 ;;
  -V|--version)          printf "passx-menu %s\n" "$PASSX_MENU_VERSION"; exit 0 ;;
  -e|--entry)            DIRECT_ENTRY="${2:-}"; shift 2 2>/dev/null || true ;;
  -m|--menu)             MENU="${2:-}"; shift 2 2>/dev/null || true; _detect_backend ;;
  --theme)               PASSX_THEME="${2:-}"; shift 2 2>/dev/null || true; _load_theme ;;
esac

# sanity
[ -d "$PASSWORD_STORE_DIR" ] \
  || _die "Store not found: $PASSWORD_STORE_DIR"
[ -f "$PASSWORD_STORE_DIR/.gpg-id" ] \
  || _die "Store not initialized — run: pass init <gpg-id>"

# dispatch
case "$SUBCMD" in
  otp)      _cmd_otp ;;
  template) _cmd_template ;;
  fill)     _cmd_fill ;;
  copy)     _cmd_copy ;;
  add)      _cmd_add ;;
  gen)      _cmd_gen ;;
  "")
    if [ -n "$DIRECT_ENTRY" ]; then
      _entry_loop "$DIRECT_ENTRY"
    else
      _main_picker
    fi ;;
esac

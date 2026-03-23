# passx bash completions v1.7.0
# Auto-loaded from: /usr/share/bash-completion/completions/passx
# Or manually:      source <(passx completions bash)

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

  local all_cmds="add show copy set-field rename clone search find where history otp otp-show otp-fill otp-list otp-import otp-export otp-qr qr fill login url open run snip db note card env dotenv template template-new attach vault team alias pin frecency audit hibp age strength entropy lock share recipients reencrypt ssh ssh-add ssh-set ssh-rm ssh-list ssh-copy-id ssh-agent-status gpg gpg-add gpg-set gpg-rm gpg-list import-csv import-bitwarden import-firefox import-chrome import-keepass export-bitwarden export-encrypted export-age gc lint verify diff watch config setup gen gen-conf tombstone clip-history meta-build sync log doctor stats recent backup ls git completions fzf-widget cron-check --version --help"

  if [ "$cword" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$all_cmds" -- "$cur") )
    return 0
  fi

  case "$prev" in
    show|copy|set-field|rename|clone|edit|rm|rotate|strength|entropy|history|\
    otp|otp-show|otp-fill|otp-import|otp-export|otp-qr|hibp|login|fill|url|\
    open|snip|find|where|note|card|env|dotenv|run|share|diff|watch|qr|attach)
      COMPREPLY=( $(compgen -W "$(_passx_entries)" -- "$cur") );;
    vault)
      COMPREPLY=( $(compgen -W "list add switch use env rm status edit prompt" -- "$cur") );;
    team)
      COMPREPLY=( $(compgen -W "init members add-member rm-member log audit sync status" -- "$cur") );;
    db)
      COMPREPLY=( $(compgen -W "list connect query tunnel" -- "$cur") );;
    alias)
      COMPREPLY=( $(compgen -W "add rm list" -- "$cur") );;
    pin)
      COMPREPLY=( $(compgen -W "add rm list" -- "$cur") );;
    frecency)
      COMPREPLY=( $(compgen -W "list reset" -- "$cur") );;
    tombstone|clip-history)
      COMPREPLY=( $(compgen -W "list clear" -- "$cur") );;
    config)
      COMPREPLY=( $(compgen -W "get set reset show interactive" -- "$cur") );;
    setup)
      COMPREPLY=( $(compgen -W "all deps gpg store git config comp check" -- "$cur") );;
    ssh-set|ssh-rm|ssh-copy-id)
      COMPREPLY=( $(compgen -W "$(pass ls --flat 2>/dev/null \
        | grep '^ssh/.*-pub$' | sed 's/-pub$//')" -- "$cur") );;
    gpg-set|gpg-rm)
      COMPREPLY=( $(compgen -W "$(pass ls --flat 2>/dev/null \
        | grep '^gpg/.*-pub$' | sed 's/-pub$//')" -- "$cur") );;
    audit)
      COMPREPLY=( $(compgen -W "--fix --fix-interactive --report" -- "$cur") );;
    hibp)
      COMPREPLY=( $(compgen -W "--all $(_passx_entries)" -- "$cur") );;
    gen)
      COMPREPLY=( $(compgen -W "--words --pin --pronounceable --length --store --no-copy" -- "$cur") );;
    sync)
      COMPREPLY=( $(compgen -W "status" -- "$cur") );;
    log)
      COMPREPLY=( $(compgen -W "--graph --all" -- "$cur") );;
    completions|fzf-widget)
      COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") );;
    import-csv|import-bitwarden|import-firefox|import-chrome|import-keepass|\
    export-bitwarden|export-encrypted|export-age|backup)
      COMPREPLY=( $(compgen -f -- "$cur") );;
  esac
  return 0
}

complete -F _passx passx

# passx fish completions v1.7.0
# Install: /usr/share/fish/vendor_completions.d/passx.fish  (PKGBUILD)
# Manual:  passx completions fish | source

set -l cmds add show copy set-field rename clone search find where history otp otp-show otp-fill otp-list otp-import otp-export otp-qr qr fill login url open run snip db note card env dotenv template template-new attach vault team alias pin frecency audit hibp age strength entropy lock share recipients reencrypt ssh ssh-add ssh-set ssh-rm ssh-list ssh-copy-id ssh-agent-status gpg gpg-add gpg-set gpg-rm gpg-list import-csv import-bitwarden import-firefox import-chrome import-keepass export-bitwarden export-encrypted export-age gc lint verify diff watch config setup gen gen-conf tombstone clip-history meta-build sync log doctor stats recent backup git ls completions fzf-widget cron-check tombstone clip-history meta-build

complete -c passx -f -n 'not __fish_seen_subcommand_from $cmds' -a "$cmds"

# Entry completions
for cmd in show copy set-field rename clone edit rm rotate strength entropy \
           history otp otp-show otp-fill otp-export otp-qr hibp login \
           fill url open snip find where note card env dotenv run \
           share diff watch qr attach
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null)"
end

# Subcommand completions
complete -c passx -f -n '__fish_seen_subcommand_from vault' \
  -a 'list add switch use env rm status edit prompt'
complete -c passx -f -n '__fish_seen_subcommand_from team' \
  -a 'init members add-member rm-member log audit sync status'
complete -c passx -f -n '__fish_seen_subcommand_from db' \
  -a 'list connect query tunnel'
complete -c passx -f -n '__fish_seen_subcommand_from alias' -a 'add rm list'
complete -c passx -f -n '__fish_seen_subcommand_from pin'   -a 'add rm list'
complete -c passx -f -n '__fish_seen_subcommand_from frecency' -a 'list reset'
complete -c passx -f -n '__fish_seen_subcommand_from tombstone' -a 'list clear'
complete -c passx -f -n '__fish_seen_subcommand_from clip-history' -a 'clear'
complete -c passx -f -n '__fish_seen_subcommand_from config' \
  -a 'get set reset show interactive'
complete -c passx -f -n '__fish_seen_subcommand_from setup' \
  -a 'all deps gpg store git config comp check'
complete -c passx -f -n '__fish_seen_subcommand_from sync' -a 'status'
complete -c passx -f -n '__fish_seen_subcommand_from log'  -a '--graph --all'

for cmd in ssh-set ssh-rm ssh-copy-id
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null | grep '^ssh/.*-pub\$' | sed 's/-pub\$//')"
end
for cmd in gpg-set gpg-rm
  complete -c passx -f -n "__fish_seen_subcommand_from $cmd" \
    -a "(pass ls --flat 2>/dev/null | grep '^gpg/.*-pub\$' | sed 's/-pub\$//')"
end

complete -c passx -f -n '__fish_seen_subcommand_from completions fzf-widget' \
  -a 'bash zsh fish'
complete -c passx -f -n '__fish_seen_subcommand_from audit' \
  -a '--fix --fix-interactive --report'
complete -c passx -f -n '__fish_seen_subcommand_from hibp'  -a '--all'
complete -c passx -f -n '__fish_seen_subcommand_from gen'   \
  -a '--words --pin --pronounceable --length --store --no-copy'

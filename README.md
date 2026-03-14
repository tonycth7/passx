# passx

> a power-user wrapper around `pass` — fast, structured, opinionated.

---

passx is not a new password manager. it sits on top of [`pass`](https://www.passwordstore.org/) — the unix password store — and turns it into something you'd actually want to use every day. the underlying model stays the same: GPG-encrypted files, plain filesystem, git-native. passx adds structure, speed, and a full feature layer without touching what makes pass good.

---

## install

one line:

```sh
curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh | bash
```

the installer handles everything — dependencies, GPG key setup, SSH key, git remote, shell completions. it detects your package manager (apt, pacman, dnf, brew) and asks before touching anything.
  Or
```sh
git clone https://github.com/you/passx
cd passx
chmod +x native-install.sh
bash native-install.sh
```
 for Native-install if you clone the Repo 
the install script handles dependencies, detects your package manager, fetches GPG keys, and walks you through `pass init` interactively.


---

## philosophy

- **don't replace, extend** — pass is the source of truth. passx is the interface.
- **speed first** — clipboard, fzf, fuzzy everything. common actions are one keypress.
- **structured by default** — every entry has username, email, url, otp fields. no freeform chaos.
- **your password, your choice** — generate strong passwords or bring your own. both first-class.
- **security without theater** — k-anonymity HIBP checks, clipboard auto-clear, private-key guards, strength audits.
- **degrade gracefully** — optional tools are optional. works headless, works on Wayland and X11 and WSL, works without fzf.

---

## usage

```sh
# add entries
passx add github tony@mail.com              # generated password
passx add github --password                 # prompt for your own (hidden input + confirm)
passx add github --password myPass123       # supply directly

# access
passx show github                           # fzf action menu
passx copy github                           # copy password  (auto-clears in 20s)
passx copy github -u                        # copy username
passx show github:email                     # print email field directly

# otp
passx otp github                            # copy live TOTP code
passx otp-show github                       # live countdown display
passx otp-fill github                       # type code into focused window

# autofill
passx fill github                           # type user → TAB → pass → Enter
passx login github                          # copy user, then copy pass
passx run servers/vps ssh root@1.2.3.4      # inject creds as env vars

# generate
passx gen                                   # random 32-char password → clipboard
passx gen --words 5                         # 5-word passphrase
passx gen --pin 6                           # numeric PIN
passx gen --pronounceable                   # speakable password

# manage
passx edit github                           # open in $EDITOR (nvim/vim/vi/nano)
passx rotate github                         # generate new password
passx set-field github url https://github.com
passx rename github work/github
passx clone github github-personal

# security
passx audit                                 # weak / duplicate / aged passwords
passx audit --fix                           # auto-rotate weak entries
passx hibp --all                            # check every entry against breach database
passx strength github                       # 4-point strength rating
passx entropy github                        # Shannon entropy in bits

# templates
passx template                              # interactive: web-login, server, db, api-key, card, wifi...

# import
passx import-bitwarden export.json
passx import-firefox logins.csv
passx import-chrome passwords.csv
passx import-keepass keepass.xml

# sync
passx sync                                  # git pull + push
passx log                                   # git history
passx diff github                           # diff entry between commits

# tools
passx doctor                                # dependency and env check
passx stats                                 # store statistics
passx backup                                # encrypted archive export
```

every command has `--help`:

```sh
passx add --help
passx gen --help
passx run --help
```

---

## passx-menu

a rofi / wofi / dmenu launcher that gives you full passx access without a terminal.

```sh
passx-menu              # main picker — entries + quick actions
passx-menu otp          # OTP picker — all entries, live codes, copy or type
passx-menu t            # new entry from template
passx-menu fill         # autofill service picker
passx-menu copy         # pick entry → copy password
passx-menu ssh          # SSH key manager
passx-menu add          # add entry (choose: generate / own password / full terminal)
passx-menu gen          # generate password → clipboard
passx-menu conf         # interactive settings editor
```

**action menu** (per entry) — built dynamically based on what fields exist:

- copy password / username / email / token / url
- OTP → copy / type / show with countdown
- autofill (user + TAB + pass + Enter) or type password only
- open url in browser
- **change password** → rotate (generate new) or set your own (hidden prompt)
- set field — pick from list or type custom field name
- edit in $EDITOR
- rename / clone / delete
- show full entry, check strength, check HIBP

**themes** — catppuccin (default), nord, gruvbox, dracula, solarized — set in `~/.config/passx/menu.conf` or via `passx-menu conf`.

**bind to a key** in your WM — example for dwm/sway/i3:

```sh
# sway / i3
bindsym $mod+p exec passx-menu
bindsym $mod+shift+p exec passx-menu otp
```

---

## entry format

```
mypassword
username: tony
email: tony@mail.com
url: https://github.com
notes: personal account
otp: otpauth://totp/GitHub:tony?secret=JBSWY3DPEHPK3PXP
token: ghp_xxxxxxxxxxxx
```

first line is always the password. everything else is `key: value`. any field name works — passx reads and writes them all. add or update any field with `passx set-field`.

---

## configuration

```sh
passx gen-conf          # generate ~/.config/passx/passx.conf
passx-menu conf         # interactive settings for passx-menu
```

key options in `~/.config/passx/passx.conf`:

```sh
PASSX_AUTOSYNC="false"       # git push/pull on every change
PASSX_CLIP_TIMEOUT="20"      # seconds before clipboard clears
PASSX_MAX_AGE="180"          # days before audit flags entry as aged
PASSX_THEME="catppuccin"     # catppuccin | nord | gruvbox | dracula | solarized
PASSX_GEN_LENGTH="32"        # default password length
PASSX_GEN_CHARS="A-Za-z0-9@#%+=_"
```

all options can also be set as environment variables.

---

## hooks

drop executable scripts in `~/.config/passx/hooks/` to run on events:

```
post-add.sh
post-edit.sh
post-rotate.sh
post-sync.sh
```

---

## dependencies

**required** — `pass`, `gpg`, `git`, `bash ≥ 4`

**optional** — passx degrades gracefully without any of these:

| tool | used for |
|---|---|
| `fzf` | fuzzy picker, search, interactive ui |
| `rofi` / `wofi` / `dmenu` | passx-menu launcher |
| `xdotool` | autofill, login, otp-fill |
| `wl-copy` / `xclip` / `xsel` | clipboard |
| `oathtool` | TOTP codes |
| `qrencode` | QR code generation |
| `zbarimg` | QR code scanning |
| `curl` | HIBP breach check |
| `notify-send` | desktop notifications |
| `sshpass` | SSH credential injection via `passx run` |
| `jq` | JSON export |
| `bat` | syntax-highlighted fzf previews |

---

## status

**v1.0.0** — feature-complete bash implementation. production ready for daily use.

a **Rust rewrite** is planned — same interface, same philosophy, native binary, proper error handling, package-ready for AUR and Homebrew. the bash version stays maintained until then.

---

## license

MIT

---

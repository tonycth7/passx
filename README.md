# passx

> a power-user wrapper around `pass` — fast, structured, and built for the terminal.

---

passx is not a new password manager. it's a layer on top of [`pass`](https://www.passwordstore.org/) — the unix password store — that turns it into something you'd actually want to use every day. the underlying model stays the same: GPG-encrypted files, plain filesystem, git-native. passx just makes working with it faster, cleaner, and a lot more capable.

---

## why

`pass` is perfect in principle — simple, auditable, unix. but using it daily shows the cracks: no structured fields, no autofill, no OTP, no audit, no good UX. passx fills those gaps without replacing what makes pass good.

the philosophy is simple:

- **don't replace, extend** — pass stays the source of truth
- **speed first** — clipboard, fzf, fuzzy everything
- **structured by default** — username, email, url, otp in every entry
- **security without theater** — k-anonymity HIBP checks, clipboard auto-clear, private-key guards, audit reports
- **degrade gracefully** — optional tools are optional. works without fzf, works without a display, works on wayland and X11 and WSL

---

## what's inside

**core** — `add`, `show`, `copy`, `edit`, `rm`, `rotate`, `rename`, `clone`, `set-field`

**search & ui** — fuzzy picker with fzf preview, `search`, `pick`, full interactive `ui` panel

**otp** — `otp`, `otp-show`, `otp-fill`, `otp-import`, `otp-export`, `otp-qr`, QR scanning via webcam

**generation** — random, wordlist (`--words`), PIN (`--pin`), pronounceable — all configurable

**automation** — `fill` autotypes into focused windows via xdotool, `login` does full form fill, `run` injects secrets as env vars (with smart mappings for ssh, psql, mysql, aws)

**security** — `audit` (weak/duplicate/aged passwords), `hibp` (k-anon breach check), `strength`, `entropy`, `share` (GPG-encrypt for a recipient), `reencrypt`, clipboard auto-clear

**ssh & gpg** — manage SSH keys and GPG recipients directly inside the store

**import / export** — Bitwarden, Firefox, Chrome, KeePass CSV, custom CSV, encrypted archive export

**maintenance** — `lint`, `verify`, `doctor`, `gc`, `diff`, `watch`, `stats`, `backup`, `log`

**extras** — `note`, `card`, `template` (web-login, server, database, api-key...), `env`/`dotenv` export, shell completions (bash/zsh/fish), fzf widget, 5 color themes

---

## usage

```sh
passx add github tony@mail.com              # add entry with generated password
passx show github                           # show full entry
passx copy github                           # copy password to clipboard (auto-clears in 20s)
passx otp github                            # copy TOTP code
passx fill github                           # autotype into focused window
passx login github                          # full username+password form fill
passx run servers/vps ssh root@1.2.3.4      # inject secret into command env
passx audit                                 # report weak, duplicate, aged passwords
passx hibp --all                            # check every entry against breach database
passx gen --words 5                         # generate passphrase
passx template                              # create structured entry from template
passx ui                                    # interactive fzf control panel
passx doctor                                # check dependencies and config
```

every command has `--help`:

```sh
passx run --help
passx otp --help
passx gen --help
```

---

## configuration

passx reads from `~/.config/passx/passx.conf`. generate a starter:

```sh
passx gen-conf
```

key options:

```sh
PASSX_AUTOSYNC="false"       # git push/pull on every change
PASSX_CLIP_TIMEOUT="20"      # seconds before clipboard is cleared
PASSX_MAX_AGE="180"          # days before audit flags an entry as aged
PASSX_THEME="catppuccin"     # catppuccin | nord | gruvbox | dracula | solarized
PASSX_GEN_LENGTH="32"        # default generated password length
```

all options can also be set as environment variables.

---

## themes

passx ships with 5 color themes: **catppuccin** (default), **nord**, **gruvbox**, **dracula**, **solarized**. fzf UI, banners, and output all follow the active theme.

```sh
PASSX_THEME=nord passx ui
```

---

## hooks

drop executable scripts in `~/.config/passx/hooks/` to run on events:

```
post-add.sh
post-sync.sh
post-rotate.sh
```

---

## entry format

entries follow a simple structured format that passx reads and writes:

```
<generated-or-typed-password>
username: tony
email: tony@mail.com
url: https://github.com
notes: personal account
otp: otpauth://totp/...
```

any field can be added or updated with `passx set-field`.

---

## status

**v1.0.0** — feature-complete bash prototype. everything described above works.

a future rewrite in **Rust** is planned — same interface, same philosophy, native binary speed, proper error handling, and package-ready distribution (AUR, Homebrew). the bash version will remain maintained until that's ready.

---

## dependencies

**required** — `pass`, `gpg`, `bash ≥ 4`

**optional** (passx degrades gracefully without these):

| tool | used for |
|---|---|
| `fzf` | fuzzy picker, ui, search |
| `xdotool` | autofill, login |
| `wl-copy` / `xclip` | clipboard |
| `oathtool` | TOTP codes |
| `qrencode` | QR generation |
| `zbarimg` | QR scanning |
| `curl` | HIBP breach check |
| `notify-send` | desktop notifications |
| `sshpass` | ssh credential injection |
| `jq` | JSON export |
| `bat` | fzf preview syntax highlighting |

---

## install

```sh
git clone https://github.com/you/passx
cd passx
bash install.sh
```

the install script handles dependencies, detects your package manager, fetches GPG keys, and walks you through `pass init` interactively.

---

## license

MIT

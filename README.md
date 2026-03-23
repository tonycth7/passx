# passx

**A fast, power-user interface for [pass](https://www.passwordstore.org/).**

passx wraps `pass` with an interactive fzf TUI, frecency-ranked pickers, OTP helpers, Wayland/X11 autofill, a database mode, multi-vault support, team vaults, SSH/GPG key storage, import/export from all major password managers, and a full setup wizard.

---

## Install

### Arch Linux (AUR)
```bash
yay -S passx          # or: paru -S passx
```

### One-liner (any distro)
```bash
# System-wide install (/usr/local/bin) — asks for sudo when needed
bash <(curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh)

# User install (~/.local/bin) — no sudo required
curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh | PREFIX=$HOME/.local bash
```

### From cloned repo or extracted tarball
```bash
git clone https://github.com/tonycth7/passx
cd passx
bash install.sh                    # system-wide, asks sudo when needed
PREFIX=$HOME/.local bash install.sh  # user install, no sudo
```

> **Note:** always run with `bash install.sh`, not `./install.sh`.  
> `./install.sh` requires the execute bit (`chmod +x`) and  
> `sudo ./install.sh` fails because sudo uses a restricted PATH.  
> `bash install.sh` / `sudo bash install.sh` always works.

---

## Quick start

If you're new to `pass`:
```bash
passx setup           # interactive wizard: deps, GPG key, store, completions
passx doctor          # verify everything works
```

If you already use `pass`:
```bash
passx doctor          # check what's available
passx show            # open the interactive picker
```

---

## Dependencies

**Required:** `pass`, `gnupg`, `git`, `bash`

**Strongly recommended:** `fzf` (interactive pickers)

**Optional:**

| Tool | Feature |
|------|---------|
| `xdotool` | Autofill on X11 |
| `ydotool` | Autofill on Wayland |
| `oathtool` | TOTP without pass-otp extension |
| `qrencode` | QR code generation |
| `zbar` | QR code scanning |
| `xclip` | X11 clipboard |
| `wl-clipboard` | Wayland clipboard |
| `libnotify` | Desktop notifications |
| `sshpass` | SSH credential injection |
| `jq` | Bitwarden import/export |
| `age` | Modern encryption export |
| `python3` | Shannon entropy calculation |
| `pgcli` / `psql` | PostgreSQL |
| `mycli` / `mysql` | MySQL |

---

## Core usage

```bash
# Interactive picker (frecency-ranked, shows most-used entries first)
passx show
passx copy github          # copy password
passx copy github -u       # copy username
passx show github:email    # print email field
passx copy aws:token       # copy token field

# Add entries
passx add work/github user@company.com tony 32
passx template             # pick a template type interactively
passx template database    # skip picker, go straight to database template

# Search
passx search               # fzf over all entries
passx where github.com     # find entries by URL domain
passx find "tony"          # full-text search (decrypts every entry)
```

---

## OTP

```bash
passx otp github           # print + copy TOTP
passx otp -n github        # print only, don't copy
passx otp-show github      # live countdown display
passx otp-import github    # import from QR image or manual entry
passx otp-qr github        # show QR in terminal
```

---

## Autofill

```bash
passx fill github          # 3s countdown, then type user TAB password
passx fill -e github       # press Enter after password
passx fill --delay 5 github
passx fill --no-delay github
```

Works on X11 (xdotool) and Wayland (ydotool). Shows target window name during countdown.

---

## Database mode

```bash
passx template database    # create a database entry
passx db list              # list all database entries (auto-detects type)
passx db connect prod/pg   # open interactive shell (pgcli or psql)
passx db query prod/pg "SELECT version()"
passx db tunnel prod/pg    # SSH tunnel to remote DB
```

Supports: PostgreSQL, MySQL/MariaDB, Redis, MongoDB, SQLite.
Client preference: pgcli > psql, mycli > mysql.

---

## Multiple vaults

```bash
# Create vaults
passx vault add work
passx vault add personal

# Switch active vault (persists across sessions)
passx vault switch work
passx copy github            # uses work store

# One-off (no side effects)
passx vault use personal -- copy netflix

# Apply vault in current shell session
eval $(passx vault env work)

# Check sync status
passx vault status
```

Each vault is a config file at `~/.config/passx/vaults/NAME` containing:
```bash
export PASSWORD_STORE_DIR="/path/to/store"
```

---

## Team vaults

```bash
# Create a shared store with multiple GPG keys
passx team init myteam

# Activate it
passx vault switch myteam

# Add teammates (re-encrypts entire store for new key)
passx team add-member ABCD1234EF567890

# List members
passx team members

# View activity log
passx team log

# Audit rotation status
passx team audit
```

A team vault is a normal `pass` store with multiple keys in `.gpg-id`. Every entry is encrypted for all members simultaneously.

---

## Security tools

```bash
passx audit               # scan for weak, duplicate, aged passwords
passx audit --fix         # auto-rotate weak entries
passx audit --fix-interactive  # review each one interactively
passx hibp github         # check against HaveIBeenPwned (k-anonymity)
passx hibp --all          # check entire store
passx strength github     # 4-point strength rating
passx entropy github      # Shannon entropy in bits
passx age                 # password age report from git history
```

---

## SSH / GPG key storage

```bash
passx ssh-add             # store SSH keypair in pass
passx ssh-set             # restore key to ~/.ssh/ + ssh-agent
passx ssh                 # fzf picker for stored keys
passx ssh-list

passx gpg-add             # store GPG keypair
passx gpg-set             # restore to keyring
```

---

## Import / Export

```bash
passx import-bitwarden export.json
passx import-csv passwords.csv
passx import-firefox logins.csv
passx import-chrome passwords.csv
passx import-keepass export.xml

passx export-bitwarden out.json      # plaintext — keep secure!
passx export-encrypted backup.gpg    # symmetric GPG
passx export-age backup.tar.age      # age encryption
```

---

## Performance

```bash
# Build metadata cache for instant URL/DB lookups
passx meta-build

# After that these are near-instant:
passx where github.com
passx db list
```

The entry list is cached after first use and invalidated on every write.

---

## Configuration

```bash
passx config              # interactive fzf editor
passx config set PASSX_CLIP_TIMEOUT 30
passx config get PASSX_THEME
passx gen-conf            # generate ~/.config/passx/passx.conf
```

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSX_CLIP_TIMEOUT` | 20 | Clipboard auto-clear (seconds) |
| `PASSX_MAX_AGE` | 180 | Age warning threshold (days) |
| `PASSX_AUTOSYNC` | false | Auto git push after writes |
| `PASSX_THEME` | catppuccin | fzf colour theme |
| `PASSX_GEN_LENGTH` | 32 | Default password length |
| `PASSX_FRECENCY` | true | Frecency-ranked pickers |
| `PASSX_WARN_STALE` | true | Warn when copying old passwords |
| `PASSX_AUTOFILL_DELAY` | 3 | Autofill countdown (seconds) |
| `PASSX_DB_CLIENT` | auto | Database client preference |

---

## Shell completions

Installed automatically by the PKGBUILD or `install.sh`.

To activate in the current session:
```bash
# bash
source /usr/share/bash-completion/completions/passx

# zsh
source /usr/share/zsh/site-functions/_passx

# fish
passx completions fish | source
```

Tab-complete works for all commands, subcommands, and entry paths.

---

## Full command reference

```
passx --help
passx <command> --help
man passx
```

---

## Philosophy

passx is designed like `fzf`, `ripgrep`, and `bat`: small, fast, composable.
It adds a better interface to `pass` without reimplementing encryption.
Your `~/.password-store` stays standard — drop passx any time and `pass` still works.

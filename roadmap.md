# passx — Complete Bash Roadmap

> Single source of truth for what exists, what needs building, and how it all fits together.
> Version tracked against: **passx 1.0.0** (bash, ~3500 lines, 71 commands)

---

## What passx is

A power-user wrapper around `pass` (the standard UNIX password manager).
It keeps the same store format (`.gpg` files + git), adds a full TUI via fzf,
OTP management, autofill, SSH/GPG key storage, team vaults, import/export,
and a complete setup wizard — all in a single portable bash script.

**Core value props that must never be broken:**
- No cloud, no account, fully self-hosted
- Git-native sync (any remote, full history, works offline)
- Standard GPG encryption (auditable, compatible with pass ecosystem)
- Plain text store (grep-able, scriptable, hackable)
- Single file install — copy one script, done

---

## Status legend

```
✅ DONE      — implemented and working in current script
🔧 FIX       — implemented but has a known bug/gap
🆕 NEW       — not yet implemented, needs to be built
⚡ PERF      — performance improvement
🎨 UX        — UX/polish improvement with no new functionality
```

---

## 1. Installation & Setup

### 1.1 `install.sh` — one-liner bootstrap

**Current state:** Exists and works. Covers deps, GPG, store, git, config, completions.

**Problems to fix 🔧:**
- Step label says "Step 7" twice (completions mislabeled)
- `_pick_ssh_url` uses `local` inside a non-function context — needs refactor
- No verification step at the end (does `passx doctor` to confirm everything worked)
- Downloads from `raw.githubusercontent.com` — needs a fallback for offline/AUR installs
- No uninstall option

**New install.sh design 🆕:**
```bash
# One-liner (online):
curl -fsSL https://raw.githubusercontent.com/tonycth7/passx/main/install.sh | bash

# Offline / AUR post-install hook:
install.sh --offline   # skips download step, assumes passx already in PATH

# Repair / re-run:
install.sh --repair    # re-runs all checks, fixes what's broken, skips what's fine
```

Steps (in order, each idempotent):
1. Detect package manager (apt/pacman/dnf/zypper/brew)
2. Install required deps: `pass gpg git curl`
3. Offer optional deps: `fzf xdotool oathtool qrencode zbarimg wl-clipboard xclip notify-send sshpass jq bat ydotool`
4. Download + install `passx` → `/usr/local/bin/passx` or `~/.local/bin/passx`
5. GPG key: use existing / create new ed25519 / skip
6. SSH key: select existing / generate new / skip
7. Password store: clone from git remote / init new / skip
8. Git identity: name + email (defaults from GPG key if just created)
9. Config: `passx gen-conf`
10. Shell completions: write to file (NOT `source <()`)
11. Final: run `passx doctor` and show result

---

### 1.2 `passx setup` — in-script setup wizard

**Status: 🆕 New command**

The install.sh bootstraps passx. Once passx is installed, `passx setup` is the
ongoing configuration tool — re-runnable, idempotent, works post-AUR-install.

```bash
passx setup          # full interactive wizard (same as install.sh minus the download)
passx setup gpg      # just GPG key creation/selection
passx setup store    # just password store + git remote
passx setup keys     # just SSH key selection + agent loading
passx setup git      # just git identity
passx setup config   # just passx.conf generation
passx setup comp     # just shell completions
passx setup check    # same as doctor but with fix prompts
```

**Design rules:**
- Every sub-step checks current state first, skips if already done
- SSH key selection + `_load_ssh_key` (from install.sh) built in
- Tests SSH connection before attempting git clone
- After any sub-step: shows what was done + what to do next

---

## 2. Core Entry Operations

### 2.1 Entry listing & cache ⚡

**Current 🔧:** `list_entries` calls `pass ls --flat` on every invocation.
For 200+ entries this is noticeable (50-100ms+).

**Fix:**
```bash
list_entries() {
  local cache="$PASSX_CACHE_DIR/entries"
  # Invalidate if store directory is newer than cache
  if [ -f "$cache" ] && [ "$PASSWORD_STORE_DIR" -ot "$cache" ]; then
    cat "$cache"; return
  fi
  # Rebuild cache
  local entries
  entries="$(pass ls --flat 2>/dev/null | sort \
    || find "$PASSWORD_STORE_DIR" -name '*.gpg' \
       | sed "s|^$PASSWORD_STORE_DIR/||;s|\.gpg$||" | sort)"
  mkdir -p "$PASSX_CACHE_DIR"
  printf "%s\n" "$entries" > "$cache"
  printf "%s\n" "$entries"
}

# Cache invalidation — add to post-add, post-rm, post-edit, post-rotate hooks:
_invalidate_cache() { rm -f "$PASSX_CACHE_DIR/entries"; }
```

Result: fzf picker appears near-instantly on second invocation.

---

### 2.2 Frecency ranking 🆕

**What it is:** Entries you access most often float to the top of every fzf picker automatically. No config, it just learns.

**How it works:**
```
~/.cache/passx/frecency
# format: last_epoch  access_count  entry_path
1711234567  47  github/work
1711230000  31  gmail/personal
1710000000   2  old/amazon-2018
```

Every `copy`, `fill`, `otp`, `show` appends/updates this file.
Score = `count / sqrt(days_since_last_access + 1)` — same algorithm as Firefox.
`list_entries` sorts by frecency score when `PASSX_FRECENCY=true` (default: true).

```bash
passx frecency list        # show top 20 by score
passx frecency reset       # clear all scores
passx frecency reset github # clear one entry
```

---

### 2.3 `passx where <domain-or-keyword>` 🆕

**The problem:** You're on `github.com` but can't remember if it's stored as
`github`, `work/github`, `dev/github-tony`, or `git/gh`.

```bash
passx where github.com
#  work/github      url: https://github.com
#  dev/github-ci    url: https://github.com/tony/ci

passx where github.com --copy   # copies password of first match
passx where github.com --fill   # autofills first match
```

**Implementation:** Searches `url:` field first (no decryption needed if cached).
Falls back to decrypting and grepping all fields. With cache: sub-second.
Without cache: parallel with `xargs -P4`.

---

### 2.4 `passx alias` 🆕

**The problem:** Entry path `work/services/aws/prod-us-east-1/iam-deploy-user` is
typed a dozen times a day.

```bash
passx alias add aws work/services/aws/prod-us-east-1/iam-deploy-user
passx copy aws          # resolves alias transparently
passx fill aws          # all commands work with aliases
passx alias list        # show all aliases
passx alias rm aws      # remove alias
```

Stored in `~/.config/passx/aliases` as `key=value`. Dispatcher checks aliases
before treating arg as a store path. Completely transparent to all commands.

---

### 2.5 `passx pin` 🆕

Pin entries to always appear at the top of pickers, regardless of frecency.

```bash
passx pin add github/work     # pin it
passx pin rm github/work      # unpin
passx pin list                # show pinned entries
```

Stored in `~/.config/passx/pinned`. Pinned entries show with `📌` marker in fzf.
Takes precedence over frecency ranking.

---

## 3. Search

### 3.1 `passx search` improvements 🎨

**Current:** Supports `--has-otp`, `--has-url`, `--has-username`, `--has-email`.
These work but are slow (decrypt every entry sequentially).

**Improvements needed:**

**Fast path with cache:** Build a metadata cache (not passwords, just fields) on first
access, update on writes:
```
~/.cache/passx/metadata
# format: entry_path  has_otp  has_url  has_username  url_domain
github/work  otp  url:github.com  username
```

With metadata cache, `--has-otp` filter is instant (no decryption).

**New filter flags 🆕:**
```bash
passx search --has-otp          # entries with OTP configured
passx search --has-url          # entries with url field
passx search --has-username     # entries with username field
passx search --has-email        # entries with email field
passx search --weak             # entries that would fail audit
passx search --aged             # entries older than PASSX_MAX_AGE
passx search --no-url           # web-login entries missing a URL (useful for cleanup)
passx search --folder work/     # entries under a path prefix
```

---

### 3.2 `passx find` — full-text search 🆕

Different from `search` (which filters the fzf picker by path):
`find` decrypts entries and searches their content.

```bash
passx find "tony@"             # find entries containing this in any field
passx find --field email "gmail"  # search specific field only
passx find --url github.com    # search url field for domain (same as where)
```

With parallel decryption (`xargs -P4`), searching 100 entries takes ~5-8 seconds
instead of 30+. Progress bar shown during scan.

---

## 4. Clipboard & Autofill

### 4.1 Clipboard — current state ✅

- Wayland (`wl-copy`), X11 (`xclip`), WSL (`clip.exe`) supported
- Hash-aware auto-clear: won't wipe clipboard if user copied something else first
- `passx lock` to clear immediately
- `PASSX_CLIP_TIMEOUT` configurable (default 20s)

### 4.2 `ydotool` Wayland autofill support 🆕

**Current gap:** `cmd_fill` uses `xdotool` which **doesn't work on pure Wayland**.
Anyone running Hyprland, Sway, or pure Wayland gets an error.

```bash
# In cmd_fill, detect display server:
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  # Pure Wayland — use ydotool
  command -v ydotool >/dev/null 2>&1 || err "ydotool required for Wayland autofill (install ydotool + start ydotoold)"
  ydotool type --key-delay 12 --key-hold 12 "$user"
  ydotool key 15:1 15:0   # Tab
  ydotool type --key-delay 10 --key-hold 10 "$passw"
  $enter_after && ydotool key 28:1 28:0  # Return
else
  # X11 / XWayland — use xdotool (existing code)
fi
```

Doctor check added: shows ydotool status for Wayland users.

### 4.3 Expiry warning on copy 🆕

When you copy a password, if it was last rotated over `PASSX_MAX_AGE` days ago,
show a one-line warning at exactly the right moment:

```
  ✔  Password copied
  ⚠  Last rotated 214 days ago — consider: passx rotate github/work
```

Implementation: in `copy_clipboard`, after copying, check git log for that entry's
last modification. One `git log` call, negligible overhead.

### 4.4 `passx clip-history` 🆕

A log of what was copied and when. Entry name + field + timestamp only.
**Never logs the actual value.**

```bash
passx clip-history
# 14:32:01  github/work     password
# 14:28:45  gmail/personal  password
# 14:15:03  aws/prod        token

passx clip-history clear
```

Stored in `~/.cache/passx/clip_log`. Each copy appends one line. `clip-history` shows last 50.

---

## 5. Smart Launch

### 5.1 `passx open` — context-aware launch 🆕

Currently `url` just opens the browser. `open` is smarter:

```bash
passx open github/work     # has url: → open browser
passx open db/prod         # has host: + port: → open in $PASSX_DB_CLIENT (tableplus/dbeaver/pgcli)
passx open servers/vps     # has host: only → open in $TERMINAL with ssh
passx open vpn/work        # has type:vpn → run openvpn/nmcli/wg
```

Detection logic:
- `url:` field present → `xdg-open "$url"`
- `host:` + `port:` both present → database client
- `host:` only → SSH in new terminal
- `type:` field → configurable per-type handler

Handlers configurable in `passx.conf`:
```bash
PASSX_DB_CLIENT="pgcli"
PASSX_SSH_TERMINAL="kitty"
PASSX_VPN_CMD="nmcli connection up"
```

Pluggable via hooks: `~/.config/passx/hooks/open-TYPE.sh`

---

## 6. Multi-Vault Support

### 6.1 `passx vault` 🆕

Multiple independent password stores, each with its own git remote, GPG recipients, and config.

```bash
passx vault list                    # show all vaults + active marker
passx vault add work                # wizard: store path + git remote + GPG key
passx vault switch work             # set active vault for this session
passx vault switch personal         # switch back
passx vault use work -- copy github # run one command against vault without switching
passx vault rm work                 # remove vault config (not the store itself)
passx vault status                  # sync status of all vaults at once
```

**Implementation:**
- Vault configs: `~/.config/passx/vaults/NAME` — one file per vault
- Each file: `PASSWORD_STORE_DIR`, `PASSX_GPG_KEY`, `PASSX_GIT_REMOTE`
- Active vault: `~/.cache/passx/active_vault`
- `passx vault switch` exports `PASSWORD_STORE_DIR` for current session

**Shell prompt integration:**
```bash
# Add to PS1:
$(__passx_vault_prompt)
# shows: [work] or nothing if on default vault
```

---

## 7. Team Vault

### 7.1 Team vault design 🆕

Multi-recipient GPG vault for shared team passwords.
Uses standard `pass init key1 key2 key3` for encryption — fully compatible.

```bash
passx team init work-shared              # wizard: store path + multiple GPG keys
passx team add-member <keyid>           # re-encrypt all entries for new member
passx team rm-member <keyid>            # re-encrypt excluding removed member
passx team members                      # list current recipients
passx team log                          # who created/changed what and when
passx team audit                        # members who haven't rotated passwords
```

**Commit attribution** — built into every write operation:
```bash
# Every pass insert/edit/rotate in a team vault:
_team_commit_msg() {
  local action="$1" entry="$2"
  printf "%s: %s [%s@%s]" "$action" "$entry" "$USER" "$(hostname -s)"
}
```

Git history for team vault looks like:
```
Add github/shared-bot  [alice@laptop]
Rotate db/prod         [bob@workstation]
Add aws/ci-deploy      [alice@laptop]
```

`passx team log` formats this per-entry:
```bash
passx team log github/shared-bot
# 2025-03-01  alice@laptop     created
# 2025-02-15  bob@workstation  rotated password
```

---

## 8. Password Operations

### 8.1 `passx rotate` improvements 🔧 / 🎨

**Current:** Has confirmation prompt (added). Shows old length → new length.

**Missing:**
- `--no-confirm` flag for scripting / `--fix` mode in audit
- Print the new password to screen (behind a `--show` flag, default hidden)
- `passx rotate --all-weak` — rotate all weak passwords with one confirm per entry

### 8.2 `passx audit --fix-interactive` 🆕

Current `--fix` bulk-rotates everything weak with no per-entry confirmation.
This is destructive. Interactive mode:

```
  ✖  [WEAK] old/forum-2018   len=6  score=1/4
  [r]otate  [d]elete  [s]kip  [v]iew entry  [q]uit
  ❯ _
```

```bash
passx audit --fix-interactive   # one-at-a-time with choices
passx audit --fix               # existing: bulk rotate all weak (kept for scripting)
passx audit --report            # output JSON/CSV for piping
```

### 8.3 `passx history <path>` 🆕

Per-entry git history. Currently `passx log` shows store-wide commits.

```bash
passx history github/work
# 2025-03-01  rotated password         [alice@laptop]
# 2024-11-15  added url field
# 2024-11-14  added entry
```

Implementation: `git log --follow -- "${path}.gpg"` parsed into human output.

### 8.4 `passx snip <path>` 🆕

Single-decryption structured output for scripting. Decrypts once, outputs all fields
as shell-safe exports. Designed for `eval`.

```bash
eval "$(passx snip db/prod)"
# Sets: PASSX_PASSWORD PASSX_USER PASSX_EMAIL PASSX_HOST PASSX_PORT
# Also: DB_PROD_PASSWORD DB_PROD_USER (prefixed from path, uppercased)

passx snip db/prod --dotenv > .env.local
# PASSWORD=...
# USERNAME=...
# HOST=...
```

Difference from existing `dotenv`: auto-generates prefixed names from entry path,
designed for `eval` in scripts, decrypts exactly once.

---

## 9. Import / Export

### 9.1 Import merge mode 🆕

Currently `_import_one` skips any entry that already exists.
This makes re-importing after a Bitwarden export update silently discard changes.

```bash
passx import-bitwarden export.json              # current: skip existing
passx import-bitwarden export.json --merge      # new: show diff for conflicts

# Conflict resolution:
#   ┌─ Conflict: github
#   │  stored:   pass123 (rotated 30 days ago)
#   │  imported: hunter2 (from Bitwarden export)
#   │
#   │  [k]eep stored  [i]mport new  [s]kip  [v]iew both
#   └─ ❯ _
```

### 9.2 `passx export-age` 🆕

Export store re-encrypted with `age` (modern, simple alternative to GPG).
Useful for backups where you want simplicity over asymmetric crypto.

```bash
passx export-age backup.tar.age    # prompts for age passphrase
# Restore: age -d backup.tar.age | tar -xz
```

Requires `age` to be installed. Falls back to `passx backup` (GPG symmetric) if not.

---

## 10. Templates

### 10.1 User-defined templates 🆕

Current templates are hardcoded. Let users define their own:

```
# ~/.config/passx/templates/vpn
description: VPN connection
fields:
  username  required
  password  generated
  host      required
  port      optional  default=1194
  type      optional  default=openvpn
```

```bash
passx template          # shows built-in + user templates combined
passx template vpn      # use user-defined template
passx template list     # list all available templates
```

### 10.2 Template field validation 🆕

Current templates collect fields without validating them.
Add per-field validation:

- `url` field: must match `https?://` pattern
- `email` field: must contain `@`
- `port` field: must be numeric, 1-65535
- `host` field: basic hostname/IP format check

Invalid input shows a clear error and re-prompts. No more silent broken entries.

---

## 11. `passx run` expansions 🆕

Current tool integrations: `ssh`, `psql`, `mysql`, `aws`.

**Add:**
```bash
passx run k8s/prod  kubectl get pods        # injects KUBECONFIG context
passx run reg/ghcr  docker pull image:tag   # injects DOCKER_USERNAME + DOCKER_PASSWORD
passx run tf/state  terraform plan          # injects TF_VAR_ prefixed vars
passx run vault/dev vault secrets list      # injects VAULT_TOKEN
passx run smtp/app  msmtp --host ...        # injects SMTP credentials
```

**Provider pattern** — each tool is a small case block in `cmd_run`.
User-extensible via hooks: `~/.config/passx/hooks/run-kubectl.sh`

---

## 12. `passx config` — interactive config editor 🆕

Currently editing `passx.conf` requires knowing what variables exist and their syntax.
`passx config` is an fzf-based config editor:

```bash
passx config
# Opens fzf showing all PASSX_* variables with current value + description
# Select one → prompts for new value → writes to passx.conf

passx config get PASSX_CLIP_TIMEOUT     # print current value
passx config set PASSX_CLIP_TIMEOUT 30  # set without interactive
passx config reset                      # restore all defaults
passx config show                       # pretty-print current config
```

---

## 13. `passx setup` — full wizard (built into script) 🆕

Not a separate install.sh. This is `passx setup`, callable after AUR install.

```bash
passx setup          # full wizard
passx setup gpg      # GPG key only
passx setup store    # store + git remote only
passx setup keys     # SSH key only
passx setup git      # git identity only
passx setup config   # passx.conf only
passx setup comp     # completions only
passx setup check    # doctor + offer to fix
```

**Sources from install.sh:**
- `_select_ssh_key` — scans `~/.ssh`, picks key, generates `.pub` if missing
- `_load_ssh_key` — loads into agent, prompts passphrase once, caches
- `_test_ssh` — tests connection before clone attempt
- `_pick_ssh_url` — interactive git host + repo picker
- `_setup_remote` — adds remote + first push
- GPG key creation (Ed25519 batch)

**What's removed from install.sh logic:**
- The download/install step (already running passx)
- Package manager detection (stays in install.sh only)

The result: install.sh bootstraps everything from zero.
`passx setup` handles everything from "passx is installed."

---

## 14. Performance

### 14.1 Entry list cache ⚡
As described in §2.1. Makes all fzf pickers near-instant on repeat use.

### 14.2 Metadata cache ⚡
Stores per-entry: `has_otp`, `has_url`, `url_domain`, `has_username`, `has_email`.
Updated on every write. Makes `search --has-otp` and `where` instant.

### 14.3 Parallel operations ⚡

`audit`, `search --has-*`, `find`, `verify` all decrypt entries sequentially.
With `xargs -P4`:

```bash
# In cmd_audit inner loop:
_audit_one() {
  local entry="$1"
  local pw; pw="$(pass show "$entry" 2>/dev/null | sed -n '1p')" || return
  # ... scoring logic ...
  printf "%s\t%s\t%s\n" "$entry" "$len" "$score"
}
export -f _audit_one
printf "%s\n" "$entries" | xargs -P4 -I{} bash -c '_audit_one "$@"' _ {}
```

Reduces audit time from ~60s (200 entries) to ~15-20s. Not perfect (bash has
overhead per xargs job) but meaningfully faster.

### 14.4 GPG agent keepalive ⚡

After any decrypt, touch the agent cache file to reset the TTL:
```bash
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
```

Prevents GPG from asking for passphrase on every command within a session.

---

## 15. UX Polish

### 15.1 `passx show` preview improvements 🎨

Current preview shows: username, email, url, notes, otp indicator, password dots.

**Add:**
- Strength rating (`★★★★` or `☆☆☆☆`) without decrypting password value
- Days since last rotation (from git log)
- Frecency score indicator (`🔥` for top 10 most accessed)
- `📌` marker for pinned entries

### 15.2 `passx note` preview 🎨

Current note picker shows entry paths but no content preview.
Show first 3 lines of note body in fzf preview pane.

### 15.3 `passx fill` — show active window name 🆕

Before the countdown, show which window will receive keystrokes:
```
  ⌨  Autofilling github/work in 3s...
  Target: Firefox — github.com · Login (X11)
```

Implementation: `xdotool getactivewindow getwindowname` before countdown starts.
Lets user verify they're filling the right window.

### 15.4 Consistent `--no-confirm` flag 🎨

Several destructive commands (`rm`, `rotate`, `audit --fix`) have confirmation prompts.
Add `--no-confirm` / `-y` / `--force` flag to all of them for scripting use.

### 15.5 `passx ls` — tree view 🎨

Currently `passx ls` just calls `pass ls` which shows a tree.
Enhance with:
```bash
passx ls                        # tree (current, delegates to pass ls)
passx ls --flat                 # flat list (for piping)
passx ls work/                  # subtree only
passx ls --count                # entry count per folder
```

---

## 16. Security

### 16.1 Expiry warning on copy 🆕
As described in §4.3. One-line warning when copying a stale password.

### 16.2 `passx audit` improvements 🆕
- SHA1 hash for dupe detection (done ✅)
- `--fix-interactive` mode (§8.2)
- `--report` flag for JSON/CSV output
- Add check: entries with password on line 1 being a URL (wrong format)
- Add check: duplicate usernames across entries (identity leak risk)

### 16.3 Background HIBP monitoring 🆕

Currently HIBP is manual: `passx hibp`.

Add to cron/systemd timer via `passx cron-check`:
```bash
# Already exists: passx cron-check (exits 1 if issues)
# New: add HIBP check to cron mode
passx cron-check --hibp    # checks HIBP for all entries, notifies if breached
```

Sends desktop notification via `notify-send` when a breach is found.
Rate-limited: checks one entry per second, respects HIBP API limits.

### 16.4 `passx tombstone` 🆕

When you delete an entry, record its path + deletion time in a local log.
Useful for auditing: "when did we remove the old AWS key?"

```bash
passx tombstone list    # show deleted entries with dates
passx tombstone clear   # clear the log
```

Stored in `~/.config/passx/tombstone`. `cmd_rm` appends to it automatically.

---

## 17. Attachment Support 🆕

Store binary files (SSH private keys, certificates, license files, 2FA backup codes)
as GPG-encrypted blobs alongside a text entry.

```bash
passx attach add github id_ed25519      # encrypt and store file
passx attach get github id_ed25519      # decrypt and write to stdout
passx attach get github id_ed25519 > ~/.ssh/id_ed25519  # restore
passx attach ls github                  # list attachments for an entry
passx attach rm github id_ed25519       # remove attachment
```

**Implementation:** Stored as `entry-name.attach.filename.gpg` alongside the
main `entry-name.gpg`. Fully compatible with pass (pass doesn't touch these files).
`cmd_add` gains `--attach <file>` flag.

---

## 18. AUR Packaging

### 18.1 `passx` AUR package

```
passx/
├── PKGBUILD
├── passx.install        # post-install: echo "run 'passx setup' to configure"
├── passx-1.0.0.tar.gz   # source archive containing:
│   ├── passx            # the main script (no .sh extension for installed name)
│   ├── passx-menu       # the dmenu/rofi wrapper
│   ├── install.sh       # standalone bootstrap
│   ├── completions/
│   │   ├── passx.bash
│   │   ├── _passx        # zsh
│   │   └── passx.fish
│   ├── passx.1           # man page
│   └── README.md
```

**PKGBUILD (simple):**
```bash
pkgname=passx
pkgver=1.0.0
pkgdesc="Power-user wrapper around pass with TUI, OTP, autofill, and team vaults"
depends=(pass gpg git)
optdepends=(
  'fzf: interactive picker and search'
  'xdotool: X11 autofill'
  'ydotool: Wayland autofill'
  'oathtool: TOTP without pass-otp extension'
  'qrencode: QR code generation'
  'zbar: QR code scanning'
  'xclip: X11 clipboard'
  'wl-clipboard: Wayland clipboard'
  'libnotify: desktop notifications'
  'sshpass: SSH credential injection'
  'jq: JSON export/import'
  'bat: syntax-highlighted previews'
)

package() {
  install -Dm755 passx        "$pkgdir/usr/bin/passx"
  install -Dm755 passx-menu   "$pkgdir/usr/bin/passx-menu"
  install -Dm644 passx.1      "$pkgdir/usr/share/man/man1/passx.1"
  install -Dm644 completions/passx.bash \
    "$pkgdir/usr/share/bash-completion/completions/passx"
  install -Dm644 completions/_passx \
    "$pkgdir/usr/share/zsh/site-functions/_passx"
  install -Dm644 completions/passx.fish \
    "$pkgdir/usr/share/fish/vendor_completions.d/passx.fish"
}
```

### 18.2 Man page

Auto-generated from `--help` output using a simple awk script, or written manually.
Required for proper AUR package. Covers all commands + environment variables.

---

## 19. Summary: What Needs to Be Built

### Priority 1 — Ship quality / install story
| Item | Effort | Impact |
|------|--------|--------|
| `passx setup` command | Medium (port install.sh wizard) | Critical for AUR |
| New `install.sh` (fix label bug, add verify step) | Small | High |
| Entry list cache | Small (~20 lines) | High — every picker faster |
| `passx config` interactive editor | Medium | High — discoverability |
| Frecency ranking | Medium (~60 lines) | Very high — daily UX |

### Priority 2 — Core power features
| Item | Effort | Impact |
|------|--------|--------|
| `passx where <domain>` | Small (~30 lines) | High — daily annoyance solved |
| `passx alias` | Small (~40 lines) | High for deep store trees |
| `passx vault` multi-vault | Medium (~100 lines) | High — enables team use |
| Expiry warning on copy | Tiny (~10 lines) | High — right-time nudging |
| `ydotool` Wayland autofill | Small (~20 lines) | High for Wayland users |
| `passx history <path>` | Tiny (~15 lines) | Medium |

### Priority 3 — Quality of life
| Item | Effort | Impact |
|------|--------|--------|
| `passx find` full-text search | Medium (~60 lines) | High for large stores |
| `audit --fix-interactive` | Small (~40 lines) | Medium — safer than --fix |
| `passx open` smart launch | Medium (~50 lines) | High for dev workflows |
| `passx snip` | Small (~30 lines) | High for scripting |
| Import merge mode | Medium (~80 lines) | High for migrations |
| User-defined templates | Medium (~50 lines) | Medium |
| Template field validation | Small (~30 lines) | Medium |
| `passx tombstone` | Tiny (~20 lines) | Medium |
| `passx clip-history` | Small (~25 lines) | Medium |

### Priority 4 — Advanced
| Item | Effort | Impact |
|------|--------|--------|
| Team vault + attribution | Medium (~100 lines) | High for teams |
| Attachment support | Medium (~80 lines) | Medium |
| `passx run` expansions | Small (~40 lines) | Medium for devops |
| Background HIBP in cron | Small (~20 lines) | Medium |
| Metadata cache | Medium (~80 lines) | High — enables fast search |
| Parallel audit | Medium (~40 lines) | Medium |
| AUR PKGBUILD + man page | Medium | Critical for AUR |
| `passx pin` | Small (~25 lines) | Medium |

---

## 20. Config Variables — Complete List

Current:
```bash
PASSWORD_STORE_DIR="$HOME/.password-store"   # pass store location
PASSX_AUTOSYNC="false"                        # auto push after writes
PASSX_CLIP_TIMEOUT="20"                       # clipboard clear seconds
PASSX_MAX_AGE="180"                           # audit age threshold (days)
PASSX_NOTIFY="true"                           # notify-send events
PASSX_DEBUG="0"                               # write trace to log
PASSX_THEME="catppuccin"                      # fzf colors (catppuccin/nord/gruvbox/dracula/solarized)
PASSX_COLOR="auto"                            # color output (auto/always/never)
PASSX_GEN_LENGTH="32"                         # generated password length
PASSX_GEN_CHARS="A-Za-z0-9@#%+=_"            # generated password charset
PASSX_JSON="0"                                # JSON output where possible
```

New (to add):
```bash
PASSX_FRECENCY="true"                         # frecency-ranked pickers
PASSX_WARN_ON_STALE="true"                    # expiry warning on copy
PASSX_ACTIVE_VAULT=""                         # active vault name (blank = default)
PASSX_DB_CLIENT="pgcli"                       # passx open: database client
PASSX_SSH_TERMINAL="$TERMINAL"               # passx open: SSH terminal
PASSX_AUTOFILL_DELAY="3"                     # fill countdown seconds (replaces hardcoded 3)
PASSX_PARALLEL_JOBS="4"                      # parallel GPG ops for audit/search
PASSX_TOMBSTONE="true"                       # record deletions in tombstone log
```

---

*passx — small, fast, powerful. No cloud. No account. Yours.*

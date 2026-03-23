# Maintainer: tony <tonycth@proton.me>
# AUR: https://aur.archlinux.org/packages/passx

pkgname=passx
pkgver=1.7.0
pkgrel=1
pkgdesc="Power-user wrapper around pass — fzf TUI, OTP, autofill, DB mode, multi-vault"
arch=('any')
url="https://github.com/tonycth7/passx"
license=('GPL3')

# Runtime: pass + gpg are mandatory; everything else is optional
depends=('pass' 'gnupg' 'git' 'bash')
optdepends=(
    'fzf: interactive picker and search (strongly recommended)'
    'xdotool: X11 autofill (passx fill)'
    'ydotool: Wayland autofill (passx fill on Wayland/Hyprland/Sway)'
    'oathtool: TOTP without pass-otp extension'
    'oath-toolkit: alternative OTP backend'
    'qrencode: QR code generation'
    'zbar: QR code scanning for OTP import'
    'xclip: X11 clipboard'
    'wl-clipboard: Wayland clipboard (wl-copy/wl-paste)'
    'libnotify: desktop notifications'
    'sshpass: SSH credential injection'
    'jq: JSON export/import'
    'bat: syntax-highlighted entry previews'
    'age: modern encryption for passx export-age'
    'python: Shannon entropy calculation'
    'pgcli: PostgreSQL client with autocomplete'
    'mycli: MySQL client with autocomplete'
)

# Source: tarball from GitHub releases
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/tonycth7/passx/archive/v${pkgver}.tar.gz")
sha256sums=('SKIP')  # replace with actual checksum before publishing

# For local development / testing without GitHub release:
# source=("${pkgname}-${pkgver}.tar.gz")

prepare() {
    cd "${pkgname}-${pkgver}"
    # Ensure the scripts are executable
    chmod +x passx passx-menu install.sh 2>/dev/null || true
}

check() {
    # Quick smoke test — just verify the script parses cleanly
    cd "${pkgname}-${pkgver}"
    bash -n passx || return 1
}

package() {
    cd "${pkgname}-${pkgver}"

    # ── Main binaries ─────────────────────────────────────────────
    install -Dm755 passx      "${pkgdir}/usr/bin/passx"
    install -Dm755 passx-menu "${pkgdir}/usr/bin/passx-menu"

    # ── Man page ──────────────────────────────────────────────────
    install -Dm644 passx.1    "${pkgdir}/usr/share/man/man1/passx.1"

    # ── Shell completions ─────────────────────────────────────────
    install -Dm644 completions/passx.bash \
        "${pkgdir}/usr/share/bash-completion/completions/passx"
    install -Dm644 completions/_passx \
        "${pkgdir}/usr/share/zsh/site-functions/_passx"
    install -Dm644 completions/passx.fish \
        "${pkgdir}/usr/share/fish/vendor_completions.d/passx.fish"

    # ── Documentation ─────────────────────────────────────────────
    install -Dm644 README.md  "${pkgdir}/usr/share/doc/${pkgname}/README.md"
    install -Dm644 LICENSE    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}

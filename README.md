# gp-openconnect-widget

A lightweight, native GlobalProtect VPN widget for the Omarchy top bar, powered by `openconnect`.

Features:
- **No GUI client license needed**: Uses open-source `openconnect --protocol=gp`.
- **Seamless Bar Integration**: 1-click switching with neighboring Omarchy widgets (Wi-Fi, Bluetooth), dismiss with `Escape`.
- **MFA Push Friendly**: Fixed single-request loop with configurable budget (60s) preventing repeated authenticator pushes on MFA/push authentication.
- **Secure Keyring Storage**: User credentials and gateway are stored securely using your desktop keyring (`secret-tool` / libsecret). Passwords are never stored in plaintext or logged.
- **Passwordless Polkit Support**: Optional Polkit rule so members of the `wheel` group don't get interrupted by system password dialogs.

Click the **VPN** icon in the bar to open the connection flow:
1. Enter the GlobalProtect gateway and validate it.
2. Enter the username and password.
3. The widget connects and updates status automatically.

---

## Contents

```
bin/                     -> Helper CLI scripts called by the widget
  gp-vpn-connect
  gp-vpn-credentials
  gp-vpn-disconnect
  gp-vpn-gateway-check
  gp-vpn-status
config/
  50-openconnect.rules.example -> Polkit rule example for passwordless execution
  gateway.conf.example         -> Legacy fallback config
packaging/
  aur/
    PKGBUILD                   -> Arch Linux AUR package definition
    gp-openconnect-widget.install
plugin/                  -> Omarchy shell widget (Quickshell / QML)
  manifest.json
  Widget.qml
install.sh               -> Local installer script
uninstall.sh             -> Local uninstaller script
LICENSE                  -> MIT License
```

---

## Installation

### Option 1: Arch Linux / AUR (Recommended)

Install using your preferred AUR helper:

```bash
yay -S gp-openconnect-widget-git
# or
paru -S gp-openconnect-widget-git
```

Or build manually from source:

```bash
git clone https://github.com/yanuarpmbd/omarchy-gp-vpn-widget.git gp-openconnect-widget
cd gp-openconnect-widget/packaging/aur
makepkg -si
```

After installation, enable the widget in Omarchy:

```bash
omarchy plugin enable bol.gpvpn --section right
omarchy restart shell
```

---

### Option 2: Local Script Install

If you prefer installing directly without pacman/AUR:

```bash
git clone https://github.com/yanuarpmbd/omarchy-gp-vpn-widget.git gp-openconnect-widget
cd gp-openconnect-widget
./install.sh
```

This will:
- Validate the plugin manifest against Omarchy's schema.
- Install the plugin into `~/.config/omarchy/plugins/bol.gpvpn`.
- Copy CLI helper binaries into `~/.local/bin/`.
- Automatically register and enable the widget in the Omarchy bar.

---

## Configuration & Usage

- **Left-click** the VPN icon: connects if disconnected, disconnects if connected.
- **Right-click**: Ignored.
- **Escape**: Closes the popup panel.
- **Switching panels**: Clicking another bar widget (Wi-Fi, Bluetooth) directly switches panels seamlessly.
- **Configure gateway via CLI**:
  ```bash
  omarchy bar set bol.gpvpn gpGateway vpn.company.com
  ```

---

## Privilege Authentication (Polkit)

The VPN connection and interface configuration requires root privileges via `openconnect`.

To allow members of the `wheel` administrative group to connect without entering their sudo password each time:

```bash
sudo cp config/50-openconnect.rules.example /etc/polkit-1/rules.d/50-openconnect.rules
sudo chmod 644 /etc/polkit-1/rules.d/50-openconnect.rules
```

*(Note: If installed via the AUR package, this rule is installed automatically).*

---

## Uninstallation

### Via AUR:
```bash
yay -R gp-openconnect-widget-git
```

### Via local script:
```bash
./uninstall.sh
```

---

## License

[MIT](LICENSE) © 2026 yanuarpmbd

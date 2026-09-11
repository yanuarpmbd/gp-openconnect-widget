# omarchy-gp-vpn-widget

A simple GlobalProtect VPN widget for the Omarchy top bar, using `openconnect`
(no paid GUI client, no trial license).

Click the **VPN** icon in the bar to open the connection flow:

1. Enter the GlobalProtect gateway and validate it.
2. Enter the username and password and validate the credentials.
3. The widget shows **Connected** only after openconnect succeeds.

After a successful connection, the username and password are saved in the
desktop keyring (`secret-tool`/GNOME Keyring), not in a plain-text config file.

## Contents

```
plugin/                 -> Omarchy shell widget (Quickshell/QML)
  manifest.json
  Widget.qml
bin/                     -> CLI scripts called by the widget
  gp-vpn-connect
  gp-vpn-credentials
  gp-vpn-disconnect
  gp-vpn-gateway-check
  gp-vpn-status
config/
  gateway.conf.example    -> optional fallback if gateway isn't set via UI
install.sh
uninstall.sh
```

## Install

```bash
cd ~/Projects/omarchy-gp-vpn-widget
./install.sh
```

This will:
- Validate the plugin manifest against Omarchy's schema
- Copy `plugin/` to `~/.config/omarchy/plugins/bol.gpvpn` (user-owned plugin,
  never touches `/usr/share/omarchy`)
- Copy `bin/*` scripts to `~/.local/bin`
- Create `~/.config/omarchy-gp-vpn/gateway.conf` as an optional fallback
- Rescan and enable the widget in the bar's right section

Make sure `~/.local/bin` is on your `$PATH` (default on Omarchy).

## Configure the gateway (CLI)

```bash
omarchy bar set bol.gpvpn gpGateway vpn.company.com
```

The gateway is stored per-widget in `~/.config/omarchy/shell.json`, like any
other Omarchy widget setting. (This build of Omarchy does not offer a
generic right-click "Customize" form for third-party plugins — only certain
first-party widgets implement their own settings popup — so the CLI command
above is the supported way to set it.)

## Usage

- **Left-click** the VPN icon: connects if disconnected, disconnects if
  connected.
- **Right-click** is ignored.
- The gateway is checked before the credential form is shown.
- Credentials are checked by a real `openconnect --protocol=gp` connection.
- The password is sent through stdin and is never passed as a command-line
  argument.
- A successful username/password pair is saved in the desktop keyring and is
  pre-filled on the next connection attempt.
- The icon polls status every 5 seconds by checking for a running
  `openconnect` process, and highlights when connected.

## Uninstall

```bash
./uninstall.sh
```

Removes the widget from the bar, the plugin folder, and the scripts from
`~/.local/bin`. `~/.config/omarchy-gp-vpn/gateway.conf` is intentionally left
behind (delete manually if you want a full clean-up).

## Privilege authentication

The connection flow runs `openconnect` through `pkexec`, so Omarchy displays a
system authentication dialog when root privileges are required. This is
separate from the GlobalProtect username/password fields. The VPN password is
sent to openconnect through stdin and is never used for privilege escalation.

If your system policy already allows openconnect without a prompt, no dialog
will appear.

## Why not integrate into the Network widget?

The built-in Network widget (`omarchy.network`) is a large first-party
plugin (~2000 lines). The only way to extend it is
`omarchy plugin clone omarchy.network`, which forks the entire file and puts
you on the hook for reconciling every future Omarchy update to Network
yourself. A small standalone widget avoids that maintenance burden while
still sitting right next to the Network icon in the bar.

## Why not NetworkManager's openconnect plugin?

`networkmanager-openconnect` is already installed and works too, but
GlobalProtect gateways using browser-based SSO/SAML login aren't always
handled well by the NM secret-agent flow in Hyprland/Omarchy. Calling
`openconnect` directly in a floating terminal is more reliable across
GlobalProtect auth methods.

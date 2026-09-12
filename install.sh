#!/bin/bash
# Installs gp-openconnect-widget (GlobalProtect VPN bar widget) for Omarchy.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

PLUGIN_ID="bol.gpvpn"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DEST="$HOME/.local/bin"
CONF_DIR="$HOME/.config/gp-openconnect-widget"
CONF_FILE="$CONF_DIR/gateway.conf"

command -v omarchy >/dev/null 2>&1 || { echo "omarchy CLI not found; this installer only supports Omarchy."; exit 1; }
command -v openconnect >/dev/null 2>&1 || echo "Warning: 'openconnect' is not installed yet. Install it with: sudo pacman -S openconnect"

echo "Validating plugin manifest..."
omarchy plugin validate "$SCRIPT_DIR/plugin"

echo "Copying plugin to $PLUGIN_DEST ..."
mkdir -p "$HOME/.config/omarchy/plugins"
rm -rf "$PLUGIN_DEST"
cp -r "$SCRIPT_DIR/plugin" "$PLUGIN_DEST"

echo "Copying CLI scripts to $BIN_DEST ..."
mkdir -p "$BIN_DEST"
cp "$SCRIPT_DIR"/bin/gp-vpn-* "$BIN_DEST/"
chmod +x "$BIN_DEST"/gp-vpn-*

mkdir -p "$CONF_DIR"
if [[ ! -f $CONF_FILE ]]; then
  cp "$SCRIPT_DIR/config/gateway.conf.example" "$CONF_FILE"
fi

echo "Rescanning & enabling the plugin in the Omarchy shell..."
omarchy-shell shell rescanPlugins >/dev/null || true
omarchy plugin enable "$PLUGIN_ID" --section right
omarchy restart shell >/dev/null 2>&1 || true

cat <<EOF

Done.

Next steps:
1. Left-click the "VPN" icon in your Omarchy top bar.
2. Enter your gateway, then username and password in the connection flow.
3. (Optional) see the README.md section "Privilege Authentication" for
   details about the passwordless Polkit rule.
EOF

#!/bin/bash
# Uninstalls gp-openconnect-widget for Omarchy.
set -euo pipefail

PLUGIN_ID="bol.gpvpn"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DEST="$HOME/.local/bin"

echo "Removing the widget from the plugin registry (if registered)..."
omarchy plugin remove "$PLUGIN_ID" --yes 2>/dev/null || true

if [[ -d $PLUGIN_DIR ]]; then
  echo "Removing plugin folder $PLUGIN_DIR ..."
  rm -rf "$PLUGIN_DIR"
fi

echo "Removing CLI scripts from $BIN_DEST ..."
rm -f "$BIN_DEST"/gp-vpn-*

echo "Done."

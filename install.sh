#!/bin/bash
# Installs Ralph globally by symlinking ralph.sh into ~/.local/bin/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"

mkdir -p "$INSTALL_DIR"
ln -sf "$SCRIPT_DIR/ralph.sh" "$INSTALL_DIR/ralph"
ln -sf "$SCRIPT_DIR/ralph-ext.sh" "$INSTALL_DIR/ralph-ext"

echo "✅  Ralph installed → $INSTALL_DIR/ralph"
echo "✅  Ralph (ext) installed → $INSTALL_DIR/ralph-ext"
echo ""
echo "Make sure $INSTALL_DIR is in your PATH. If it isn't, add this to your shell config:"
echo ""
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""

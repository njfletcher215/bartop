#!/bin/bash
set -euo pipefail

die() {
    printf 'Error: %s\n' "${1:-Unknown error}" >&2
    exit 1
}

info() {
    printf '%s\n' "$1"
}

# Resolve repo root (directory containing this script)
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="$REPO_ROOT/src"
EXAMPLE_CONFIG="$REPO_ROOT/example-config.json"
EXAMPLE_WAYBAR_CONFIG="$REPO_ROOT/example-waybar-config.jsonc"

BIN_DIR="/usr/bin"
CONFIG_DIR="${HOME}/.config/bartop"
CONFIG_FILE="${CONFIG_DIR}/config.json"
WAYBAR_CONFIG_FILE="${CONFIG_DIR}/waybar-config.jsonc"

# Sanity checks
[[ -d "$SRC_DIR" ]] || die "Missing src/ directory"
[[ -f "$EXAMPLE_CONFIG" ]] || die "Missing example-config.json"

mkdir -p -- "$BIN_DIR"
mkdir -p -- "$CONFIG_DIR"

install_script() {
    local src="$1"
    local dst="$2"

    [[ -f "$src" ]] || die "Missing script: $src"

    install -m 0755 "$src" "$dst"
    info "Installed $(basename "$dst") -> $dst"
}

# Install commands
install_script "$SRC_DIR/bartop.sh"       "$BIN_DIR/bartop"
install_script "$SRC_DIR/bartop-poll.sh"  "$BIN_DIR/bartop-poll"
install_script "$SRC_DIR/bartop-read.sh"  "$BIN_DIR/bartop-read"

# Install default config if none already exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    install -m 0644 "$EXAMPLE_CONFIG" "$CONFIG_FILE"
    info "Installed default config -> $CONFIG_FILE"
else
    info "Config already exists, skipping default config install: $CONFIG_FILE"
fi

# Install default waybar-config if none already exists
if [[ ! -f "$WAYBAR_CONFIG_FILE" ]]; then
    install -m 0644 "$EXAMPLE_WAYBAR_CONFIG" "$WAYBAR_CONFIG_FILE"
    info "Installed default waybar config -> $CONFIG_FILE"
else
    info "Waybar config already exists, skipping default config install: $WAYBAR_CONFIG_FILE"
fi

info "bartop installation complete"
info "Ensure $BIN_DIR is in your PATH"
info "Ensure $EXAMPLE_WAYBAR_CONFIG is included in your main waybar config file"


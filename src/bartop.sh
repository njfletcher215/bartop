#!/bin/bash
set -euo pipefail

die() {
    printf 'Error: %s\n' "${1:-Unknown error}" >&2
    exit 2
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

need jq
need flock
need bartop-poll
need bartop-read

WIDGET="${1:-}"
[[ -n "$WIDGET" ]] || die "Missing widget name (ex: bartop cpu)"

CONFIG="${BARTOP_CONFIG:-$HOME/.config/bartop/config.json}"
[[ -f "$CONFIG" ]] || die "Config not found: $CONFIG"

STATE_DIR="${BARTOP_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/bartop}"
mkdir -p -- "$STATE_DIR"

LOCKFILE="$STATE_DIR/poll.lock"
PIDFILE="$STATE_DIR/poll.pid"

# Read poll config (with defaults)
POLL_TIME="$(jq -r '.poll.time // 2' "$CONFIG")"
POLL_LOGFILE="$(jq -r '.poll.logfile // "/tmp/bartop/last-glance.json"' "$CONFIG")"
POLL_PLUGINS="$(jq -r '.poll.plugins // "cpu,percpu,load,mem,memswap,fs,network,gpu"' "$CONFIG")"

is_poller_running() {
    local pid
    [[ -s "$PIDFILE" ]] || return 1
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    [[ -n "${pid:-}" ]] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

start_poller_if_needed() {
    # Fast-path: if it's running, do nothing and DO NOT lock/wait.
    if is_poller_running; then
        return 0
    fi

    # Try to start it -- if another bartop instance is already starting it, just continue
    (
        flock -xn 9 || exit 0

        # Re-check under lock (race-safe)
        if is_poller_running; then
            exit 0
        fi

        mkdir -p -- "${POLL_LOGFILE%/*}"
        [[ -s "$POLL_LOGFILE" ]] || printf '{}' > "$POLL_LOGFILE"

        bartop-poll -t "$POLL_TIME" -l "$POLL_LOGFILE" "$POLL_PLUGINS" \
            >/dev/null 2>&1 &

        printf '%s\n' "$!" > "$PIDFILE"
    ) 9>"$LOCKFILE"
}

start_poller_if_needed

# Validate widget exists
WIDGET_EXISTS="$(jq -r --arg w "$WIDGET" '(.widgets // {}) | has($w)' "$CONFIG")"
[[ "$WIDGET_EXISTS" == "true" ]] || die "Unknown widget '$WIDGET' (no .widgets.$WIDGET in $CONFIG)"

# Pull widget + fallback values
W_LOGFILE="$(jq -r --arg w "$WIDGET" '.widgets[$w].logfile // .poll.logfile // "/tmp/bartop/last-glance.json"' "$CONFIG")"
W_PLUGINS="$(jq -r --arg w "$WIDGET" '.widgets[$w].plugins // .poll.plugins // "cpu,percpu,load,mem,memswap,fs,network,gpu"' "$CONFIG")"

mkdir -p -- "${W_LOGFILE%/*}"
[[ -s "$W_LOGFILE" ]] || printf '{}' > "$W_LOGFILE"

# Build args for bartop-read:
args=()
if jq -e --arg w "$WIDGET" '.widgets[$w] | type=="object" and has("format")' "$CONFIG" >/dev/null 2>&1; then
    val="$(jq -r --arg w "$WIDGET" '.widgets[$w].format' "$CONFIG")"
    args+=(-f "$val")
fi
if jq -e --arg w "$WIDGET" '.widgets[$w] | type=="object" and has("tooltip_format")' "$CONFIG" >/dev/null 2>&1; then
    val="$(jq -r --arg w "$WIDGET" '.widgets[$w].tooltip_format' "$CONFIG")"
    args+=(-t "$val")
fi
if jq -e --arg w "$WIDGET" '.widgets[$w] | type=="object" and has("percentage_format")' "$CONFIG" >/dev/null 2>&1; then
    val="$(jq -r --arg w "$WIDGET" '.widgets[$w].percentage_format' "$CONFIG")"
    args+=(-p "$val")
fi
args+=(-l "$W_LOGFILE")

exec bartop-read "${args[@]}" "$W_PLUGINS"

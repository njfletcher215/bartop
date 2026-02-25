#!/bin/bash
set -euo pipefail

# defaults
TIME=2
LOGFILE="/tmp/bartop/last-glance.json"
PLUGINS="cpu,percpu,load,mem,memswap,fs,network,gpu"

print_help() {
    cat <<'EOF'
Usage:
    log-last-glance [-t SECONDS] [-l LOGFILE] [PLUGINS]

Continuously runs glances in stdout-json mode, overwriting a logfile each poll.

Options:
    -t --time SECONDS       Poll interval [default: 2]
    -l --logfile LOGFILE    Output file [default: /tmp/glances.json]
    -h --help               Show this help

Examples:
    log-last-glance -t 2 -l /tmp/log-last-glance-output.json cpu,mem,network
    log-last-glance --time 60 --logfile ~/.cache/last-glance.json
EOF
}

die_help() {
    local msg="${1:-}"
    if [[ -n "$msg" ]]; then
        printf 'Error: %s\n\n' "$msg" >&2
    fi
    print_help >&2
    exit 2
}

normalized=()
for opt in "$@"; do
    case "$opt" in
        --time) normalized+=(-t) ;;
        --logfile) normalized+=(-l) ;;
        --help) normalized+=(-h) ;;
        *) normalized+=("$opt") ;;
    esac
done
set -- "${normalized[@]}"
unset normalized

while getopts ":t:l:h" opt; do
    case "$opt" in
        t)  TIME="$OPTARG"                                  ;;
        l)  LOGFILE="$OPTARG"                               ;;
        h)  print_help ; exit 0                             ;;
        \?) die_help "Unknown option -$OPTARG"              ;;
        :)  die_help "Option -$OPTARG requires an argument" ;;
    esac
done
shift $((OPTIND - 1))

PLUGINS="${1:-$PLUGINS}"

# make parent directories if required
DIR="${LOGFILE%/*}"
[[ "$DIR" == "$LOGFILE" ]] && DIR="."
mkdir -p -- "$DIR"

TMP="${LOGFILE}.tmp"
glances --stdout-json $PLUGINS -t $TIME |
    # convert output to proper json format
    sed -nE "s/^([^:]+):[[:space:]]*b'(.*)'\$/{\"\\1\":\\2}/p" |
    # merge each line into the json file
    while IFS= read -r upd; do
        # If logfile doesnt exist yet, populate with an empty JSON object
        [[ -s "$LOGFILE" ]] || printf '{}' > "$LOGFILE"

        jq -s '.[0] * .[1]' "$LOGFILE" <(printf '%s\n' "$upd") > "$TMP" && mv -f "$TMP" "$LOGFILE"
    done


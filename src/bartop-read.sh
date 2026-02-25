#!/bin/bash
set -euo pipefail

ORIGINAL_ARGS=("$@")

# defaults
PLUGINS='cpu,percpu,load,mem,memswap,fs,network,gpu'
FORMAT='  {cpu.total}'
TOOLTIP_FORMAT=''
PERCENTAGE_FORMAT='{cpu.total}'
LOGFILE='/tmp/bartop/last-glance.json'

print_help() {
    cat <<'EOF'
Usage:
    bartop-read [-f FORMAT] [-t TOOLTIP_FORMAT] [-p PERCENTAGE_FORMAT] [-l LOGFILE] [PLUGINS]

Watches the LOGFILE and parses its data on change,
printing a json object in the wayland-required format
(`{"text": "$text", "alt": "$alt", "tooltip": "$tooltip", "class": "$class", "percentage": $percentage }`)
setting $text, $tooltip, and $percentage to FORMAT, TOOLTIP_FORMAT, and PERCENTAGE_FORMAT,
formatted with the data from the LOGFILE

Options:
    -f --format FORMAT                          Format string for the value of "text"
    -t --tooltip-format TOOLTIP_FORMAT          Format string for the value of "tooltip"
    -p --percentage-format PERCENTAGE_FORMAT    Format string for the value of "percentage"
    -l --logfile FILE                           Input file [default: /tmp/bartop/last-glance.json]
    [PLUGINS]                                   JSON keys to read (if using bartop-poll, the outermost keys are the glances plugins the data came from) [default: cpu,percpu,load,mem,memswap,fs,network,gpu]

Examples:
    bartop-read -f " {cpu.total}" -p "{cpu.total}" -l /tmp/bartop/last-glance.json cpu,percpu,load,mem,memswap,fs,network,gpu
    bartop-read --format "CPU" --tooltip-format "0: {percpu[0].total}\n1: {percpu[1].total}" percpu
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
        --format) normalized+=(-f) ;;
        --tooltip-format) normalized+=(-t) ;;
        --percentage-format) normalized+=(-p) ;;
        --logfile) normalized+=(-l) ;;
        --help) normalized+=(-h) ;;
        *) normalized+=("$opt") ;;
    esac
done
set -- "${normalized[@]}"
unset normalized

while getopts ":f:t:p:l:h" opt; do
    case "$opt" in
        f)  FORMAT="$OPTARG"                                ;;
        t)  TOOLTIP_FORMAT="$OPTARG"                        ;;
        p)  PERCENTAGE_FORMAT="$OPTARG"                     ;;
        l)  LOGFILE="$OPTARG"                               ;;
        h)  print_help ; exit 0                             ;;
        \?) die_help "Unknown option -$OPTARG"              ;;
        :)  die_help "Option -$OPTARG requires an argument" ;;
    esac
done
shift $((OPTIND - 1))

PLUGINS="${1:-$PLUGINS}"

DIR="${LOGFILE%/*}"
[[ "$DIR" == "$LOGFILE" ]] && DIR="."
FILE="${LOGFILE##*/}"

# replace {plugin.var} constructions with their values
# literal braces may be printed by escaping the first brace (ex. \{foo})
# whitespace is stripped, so { foo.bar }, {foo . bar}, etc are all valid
format_string() {
    local fstring data fkey jqkey val
    fstring="$1"
    data="$2"

    while [[ $fstring =~ (^|[^\\])(\{([^}]+)\}) ]]; do
        # Parse the regex:
        #
        # group 1 (unused) is the character before the format string,
        # needed to verify that the format key is not escaped
        #
        # group 2 is the format key
        fkey="${BASH_REMATCH[2]}"
        # group 3 is the jq key (the text inside the format key,
        # with whitespace stripped and '.' prepended)
        jqkey=".$(echo "${BASH_REMATCH[3]}" | sed 's/[[:blank:]]//g')"

        val=$(echo $data | jq -c "$jqkey")

        # strip quotes from strings
        val=${val#\"}; val=${val%\"}
        val=${val#\'}; val=${val%\'}

        # change unfound keys to 'Err'
        if [[ $val == null ]]; then
            val="Err"
        # make byte fields human-readible
        elif [[
            "$jqkey" == .fs*.@(size|used|free) ||
            "$jqkey" == .mem.@(total|available|used|free|active|inactive|buffers|cached|shared) ||
            "$jqkey" == .memswap.@(total|used|free) ||
            "$jqkey" == .network*.bytes_*
        ]]; then
            val=$(numfmt --to=iec --suffix=B --format='%.2f' $val)
            # if ending in .00B, strip the decimal portion (since no actual conversion occurred)
            [[ "$val" == *.00B ]] && val="${val%.00B}B"
        # round load average fields to 4 decimal places
        elif [[ "$jqkey" == .load.min* ]]; then
            val=$(printf '%.4f' $val)
        fi

        # substitute $val for the format key
        fstring="${fstring/"$fkey"/"$val"}"
    done;

    # remove the leading backslash from any escaped format keys
    fstring=$(printf '%s' "$fstring" | sed 's/\\{/{/g')

    echo "$fstring"
    return 0
}

# pull the data for each plugin from the logfile using jq,
# and combine into a single json object
refresh_data() {
    local jq_obj=""
    local plugin

    IFS=',' read -ra plugins <<< "$PLUGINS"

    for plugin in "${plugins[@]}"; do
        plugin="${plugin#"${plugin%%[![:space:]]*}"}"
        plugin="${plugin%"${plugin##*[![:space:]]}"}"

        [[ -z "$plugin" ]] && continue

        if [[ -n "$jq_obj" ]]; then
            jq_obj+=", "
        fi
        jq_obj+="\"$plugin\": .$plugin"
    done

    jq -c "{ $jq_obj }" "$LOGFILE"
}

# refresh the data from logfile, then export in the waybar-required format:
# {"text": $text, "tooltip": $tooltip, "percentage": $percentage}
# NOTE: "alt" and "class" are not currently supported
export_json() {
    local data text tooltip percentage

    data="$(refresh_data)"
    text="$(format_string "$FORMAT" "$data")"
    tooltip="$(format_string "$TOOLTIP_FORMAT" "$data")"
    percentage="$(format_string "$PERCENTAGE_FORMAT" "$data")"

    jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --argjson percentage "$(printf '%s' "$percentage" | jq -Rs 'tonumber? // -1')" \
        '{text: $text, tooltip: $tooltip, percentage: $percentage}'
}

# Subcommand that watchexec will call
if [[ "${BARTOP_EMIT-}" == "1" ]]; then
    export_json
    exit 0
fi

watchexec -w "$DIR" -f "$FILE" --quiet --shell=none -- env BARTOP_EMIT=1 "$0" -f "$FORMAT" -t "$TOOLTIP_FORMAT" -p "$PERCENTAGE_FORMAT" -l "$LOGFILE" "$PLUGINS"


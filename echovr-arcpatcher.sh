#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HERE/configuration.conf"

SLUG="echo-vr"
SLUG_FROM_ARG=""
MAX_LAUNCHES="25"
RIFTLIFT_LOG=""
SHADER_ROOT_OVERRIDE=""

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

[[ -n "${1:-}" ]] && { SLUG="$1"; SLUG_FROM_ARG="1"; }
[[ -n "${2:-}" ]] && MAX_LAUNCHES="$2"

PASSWD_HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
HOME_DIR="${HOME:-$PASSWD_HOME}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "$HOME_DIR" ]] || die "Could not determine the home directory."

SHADER_ROOT="$HOME_DIR/.local/state/echo-vr/shaders"
FALLBACK_ROOT_1="$HOME_DIR/.local/share/echo-vr/shaders"

if [[ -n "$PASSWD_HOME" ]]; then
    FALLBACK_ROOT_2="$PASSWD_HOME/Documents/echo-vr/shaders"
else
    FALLBACK_ROOT_2="$HOME_DIR/Documents/echo-vr/shaders"
fi

select_root() {
    local root="$1"
    local dir
    local probe

    mkdir -p \
        "$root/dumped" \
        "$root/overrides/arc/fp32" \
        2>/dev/null || return 1

    for dir in \
        "$root/dumped" \
        "$root/overrides/arc/fp32"
    do
        probe="$dir/.write-test-$$"
        if ! ( : > "$probe" ) 2>/dev/null; then
            rm -f "$probe" 2>/dev/null
            return 1
        fi
        rm -f "$probe"
    done

    printf '%s\n' "$root"
}

if [[ -n "$SHADER_ROOT_OVERRIDE" ]]; then
    if selected_root="$(select_root "$SHADER_ROOT_OVERRIDE")"; then
        SHADER_ROOT="$selected_root"
    else
        die "SHADER_ROOT_OVERRIDE is set but not writable: $SHADER_ROOT_OVERRIDE"
    fi
else
    for root in "$SHADER_ROOT" "$FALLBACK_ROOT_1" "$FALLBACK_ROOT_2"; do
        if selected_root="$(select_root "$root")"; then
            SHADER_ROOT="$selected_root"
            break
        fi
    done
fi

[[ -d "$SHADER_ROOT" ]] || die "Could not create a usable shader directory."

DUMP="$SHADER_ROOT/dumped"
OVERRIDE="$SHADER_ROOT/overrides/arc/fp32"
LOG="${RIFTLIFT_LOG:-$HOME_DIR/.local/share/riftlift/diagnostics/proton/steam-0.log}"
PATCHER="$HERE/patcher.py"

for tool in riftlift python3 spirv-dis spirv-as spirv-val; do
    command -v "$tool" >/dev/null 2>&1 || {
        [[ "$tool" == spirv-* ]] && die "'$tool' not found. Make sure you have installed spirv-tools and try again."
        die "'$tool' not found in PATH"
    }
done

[[ -f "$PATCHER" ]] || die "The python script must be present next to this script! ($PATCHER)"

mkdir -p "$DUMP" "$OVERRIDE"

resolve_slug() {
    local listing
    local known
    local candidates
    local count

    listing="$(riftlift list 2>/dev/null)" || die "'riftlift list' failed. Is RiftLift installed and working?"
    known="$(printf '%s\n' "$listing" | awk '$1 ~ /^[a-z0-9]+(-[a-z0-9]+)*$/ {print $1}')"

    if printf '%s\n' "$known" | grep -qxF -- "$SLUG"; then
        return 0
    fi

    if [[ -n "$SLUG_FROM_ARG" ]]; then
        echo "ERROR: RiftLift has no game with the slug '$SLUG'. Your games:" >&2
        printf '%s\n' "$listing" | sed 's/^/  /' >&2
        exit 1
    fi

    candidates="$(printf '%s\n' "$listing" | awk '$1 ~ /^[a-z0-9]+(-[a-z0-9]+)*$/ && tolower($0) ~ /echo/ {print $1}')"
    count=0
    [[ -n "$candidates" ]] && count="$(printf '%s\n' "$candidates" | wc -l)"

    if [[ "$count" -eq 1 ]]; then
        echo "The slug '$SLUG' wasn't found, so '$candidates' is being used instead (the only Echo game in 'riftlift list')."
        SLUG="$candidates"
        return 0
    fi

    if [[ "$count" -gt 1 ]]; then
        echo "ERROR: the slug '$SLUG' wasn't found and several games look like Echo VR:" >&2
        printf '%s\n' "$candidates" | sed 's/^/  /' >&2
        echo "Pick one and run: $0 <slug>" >&2
        exit 1
    fi

    echo "ERROR: the slug '$SLUG' wasn't found and no game in RiftLift looks like Echo VR. Your games:" >&2
    printf '%s\n' "$listing" | sed 's/^/  /' >&2
    exit 1
}

resolve_slug

echo "Echo VR ArcPatcher"
echo "(for the very small amount of Intel Arc users :3)"
echo "  slug:        $SLUG"
echo "  shader root: $SHADER_ROOT"
echo "  dump dir:    $DUMP"
echo "  overrides:   $OVERRIDE"
echo "  max runs:    $MAX_LAUNCHES"
echo

SCAN_STATUS=""

run_scan() {
    local out

    out="$(python3 "$PATCHER" scan "$DUMP" "$OVERRIDE")"
    echo "$out"

    if echo "$out" | grep -q '^  FAILED '; then
        SCAN_STATUS="stuck"
    elif echo "$out" | grep -q '^  patched '; then
        SCAN_STATUS="progress"
    else
        SCAN_STATUS="clean"
    fi
}

echo "Scanning existing dump in $DUMP for unpatched shaders..."
run_scan
if [[ "$SCAN_STATUS" == "stuck" ]]; then
    echo
    echo "STOPPING: a shader above needs manual review before this can continue."
    echo "Its file is under: $DUMP"
    exit 1
fi
echo

for ((i = 1; i <= MAX_LAUNCHES; i++)); do
    echo "LAUNCH $i OF $MAX_LAUNCHES"
    echo "RiftLift's terminal output will be provided below"
    sleep 1.5
    echo

    before="$(stat -c %Y "$LOG" 2>/dev/null || echo 0)"

    VKD3D_SHADER_DUMP_PATH="$DUMP" \
    VKD3D_SHADER_OVERRIDE="$OVERRIDE" \
    VKD3D_DEBUG=warn \
        riftlift launch "$SLUG"

    after="$(stat -c %Y "$LOG" 2>/dev/null || echo 0)"

    if [[ "$after" -le "$before" ]]; then
        die "The Proton log didn't update ($LOG). Is \"Debug logging\" turned on in RiftLift?"
    fi

    echo
    echo "Checking the shader dump for anything new..."
    run_scan

    if [[ "$SCAN_STATUS" == "stuck" ]]; then
        echo
        echo "STOPPING: a shader above needs manual review before this can continue."
        echo "Its file is under: $DUMP"
        exit 1
    fi

    if [[ "$SCAN_STATUS" == "progress" ]]; then
        echo
        echo "Patched a new shader!!! relaunching to dump more shaders :3"
        echo
        continue
    fi

    hashes="$(grep -oE 'FP64 operations in shader [0-9a-f]{16}' "$LOG" | awk '{print $NF}' | sort -u)"
    stuck=0

    for h in $hashes; do
        if [[ ! -f "$OVERRIDE/$h.spv" ]]; then
            echo "  $h: warned in the log but never patched (not found in the dump folder)."
            echo "      The dump variable may not be reaching the game for this shader."
            stuck=1
        fi
    done

    if [[ "$stuck" -eq 1 ]]; then
        echo
        echo "STOPPING: a warned shader never showed up to be patched."
        exit 1
    fi

    echo
    echo "No new FP64 shaders found, in the dump or the log."
    echo "Either the game got past shader compilation, or it stopped for a different reason."
    echo "Overrides in place: $(find "$OVERRIDE" -name '*.spv' | wc -l)"
    echo "Check the newest game log: $HOME_DIR/.local/share/riftlift/diagnostics/game/"
    exit 0
done

echo "Reached the launch limit ($MAX_LAUNCHES)... :("
echo "Run it again to keep going"
echo "Overrides in place: $(find "$OVERRIDE" -name '*.spv' | wc -l)"

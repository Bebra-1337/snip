#!/usr/bin/env bash
# snip.sh — shell half of bebra/snip. The Luau service starts it detached;
# results go back to the service via `noctalia msg plugin bebra/snip:service all <event> <payload>`.
#
#   freeze                 wayfreeze on top (the frozen frame is grabbed on demand)
#   unfreeze               drop the freeze
#   shot   <mode>          region|window|screen|all → grab the frozen frame → noctalia annotate
#   color                  hyprpicker → clipboard
#   ocr | qr               region → tesseract / zbarimg → clipboard
#   rec-select <mode>      region|window|screen → emits recReady "<kind>|<target>|<showbar>"
#   rec-start <kind> <target> <audioOut> <audioIn> <dir> <fps> <codec>   (gpu-screen-recorder)
#   rec-stop
#   rec-status             exit 0 while a recording runs
#
# The freeze is wayfreeze only, so the menu opens immediately. Screenshots are
# taken from the frozen overlay at the moment the user picks a mode (not from
# the live screen); with a hardware cursor the pointer is not in the frame.
#
# Colors for slurp come from env: SNIP_BORDER, SNIP_BOX (hex #rrggbb[aa]).
# User-facing messages are sent as translation keys (notify/error "<key>|<value>");
# the service translates them into Noctalia's current language.

set -uo pipefail

PLUGIN="bebra/snip"
RUN="${XDG_RUNTIME_DIR:-/tmp}/noctalia-snip"
FREEZE_PID="$RUN/wayfreeze.pid"
REC_PID="$RUN/rec.pid"
REC_LOG="$RUN/rec.log"
mkdir -p "$RUN"

BORDER="${SNIP_BORDER:-#ffffff}"
BOX="${SNIP_BOX:-#ffffff22}"
DIM="#00000066"

# Hit area around a client: Hyprland draws the border outside the client box.
BORDER_MARGIN=2

emit() { noctalia msg plugin "$PLUGIN:service" all "$@" >/dev/null 2>&1 || true; }
note() { emit notify "$1|${2:-}"; }
fail() { emit error "$1|${2:-}"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || fail missing "$1"; }

# ── Freeze ───────────────────────────────────────────────────────────────────

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

unfreeze() {
    if alive "$FREEZE_PID"; then kill "$(cat "$FREEZE_PID")" 2>/dev/null; fi
    rm -f "$FREEZE_PID"
}

freeze() {
    need grim; need slurp; need wayfreeze
    unfreeze
    setsid wayfreeze --hide-cursor >/dev/null 2>&1 &
    echo $! > "$FREEZE_PID"
    # The menu must map after wayfreeze so it stacks above it on the overlay layer.
    for _ in $(seq 40); do
        hyprctl layers -j 2>/dev/null | grep -q '"wayfreeze"' && return 0
        sleep 0.025
    done
}

# ── Geometry ─────────────────────────────────────────────────────────────────
# Geometry strings are "X,Y WxH" in layout (logical) coordinates.

monitors() { hyprctl monitors -j; }

# `slurp -r` list lines are "<hit box>|<client box>": the hit box includes the
# border, the label is the exact client geometry used for the grab.
window_boxes() {
    local ws
    ws=$(monitors | jq -c '[.[] | .activeWorkspace.id, .specialWorkspace.id] | map(select(. != 0))')
    hyprctl clients -j | jq -r --argjson ws "$ws" --argjson m "$BORDER_MARGIN" '
        sort_by(.focusHistoryID) | .[]
        | select(.mapped and (.hidden | not) and (.workspace.id as $w | $ws | index($w)))
        | "\(.at[0] - $m),\(.at[1] - $m) \(.size[0] + 2 * $m)x\(.size[1] + 2 * $m)|\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

monitor_under_cursor() {
    local pos
    pos=$(hyprctl cursorpos -j)
    monitors | jq -r --argjson p "$pos" '
        map(. + {lw: ((.width / .scale) | floor), lh: ((.height / .scale) | floor)})
        | (map(select(.x <= $p.x and $p.x < .x + .lw and .y <= $p.y and $p.y < .y + .lh)) + map(select(.focused)))
        | first | "\(.name) \(.x),\(.y) \(.lw)x\(.lh)"'
}

layout_bounds() {
    monitors | jq -r '
        (map(.x) | min) as $x |
        (map(.y) | min) as $y |
        (map(.x + ((.width / .scale) | floor)) | max) as $x2 |
        (map(.y + ((.height / .scale) | floor)) | max) as $y2 |
        "\($x) \($y) \($x2) \($y2)"'
}

# Clamp a window box to the layout so grim never gets an off-screen region.
clamp_geom() { # "x,y WxH" → clamped geometry
    local geom="$1" x y w h bx by bx2 by2
    IFS=', x' read -r x y w h <<< "$geom"
    [ -n "$x" ] && [ -n "$w" ] || return 1
    read -r bx by bx2 by2 < <(layout_bounds)
    [ -n "$bx2" ] || { printf '%s' "$geom"; return 0; }
    [ "$x" -lt "$bx" ] && { w=$((w - (bx - x))); x=$bx; }
    [ "$y" -lt "$by" ] && { h=$((h - (by - y))); y=$by; }
    [ $((x + w)) -gt "$bx2" ] && w=$((bx2 - x))
    [ $((y + h)) -gt "$by2" ] && h=$((by2 - y))
    [ "$w" -gt 0 ] && [ "$h" -gt 0 ] || return 1
    printf '%s' "$x,$y ${w}x${h}"
}

slurp_region() { slurp -d -b "$DIM" -c "$BORDER" -s "#00000000" -w 2 -f '%x,%y %wx%h'; }
slurp_window() {
    # slurp's %l includes the leading separator, so the raw line is "<hit>||<client>";
    # take everything after the last '|' — the exact client geometry.
    window_boxes | slurp -r -b "$DIM" -c "$BORDER" -B "$BOX" -w 3 -f '%x,%y %wx%h|%l' | sed 's/.*|//'
}

# select <mode> → prints geometry; for "screen" prints "NAME X,Y WxH".
select_geom() {
    case "$1" in
        region) need slurp; slurp_region ;;
        window) need slurp; slurp_window ;;
        screen) monitor_under_cursor ;;
        *)      return 1 ;;
    esac
}

# ── Actions ──────────────────────────────────────────────────────────────────

shot() {
    need grim
    # Let the menu panel unmap before grabbing the frozen overlay.
    sleep 0.1
    local sel geom out
    out="$RUN/snip-$(date +%Y%m%d-%H%M%S).png"
    case "$1" in
        region)
            sel=$(select_geom region) || { unfreeze; exit 0; }
            grim -g "$sel" "$out" || { unfreeze; fail crop; }
            ;;
        window)
            sel=$(select_geom window) || { unfreeze; exit 0; }
            geom=$(clamp_geom "$sel") || { unfreeze; exit 0; }
            grim -g "$geom" "$out" || { unfreeze; fail crop; }
            ;;
        screen)
            sel=$(monitor_under_cursor) || { unfreeze; exit 0; }
            sel="${sel%% *}"
            [ -n "$sel" ] || { unfreeze; fail monitor; }
            grim -o "$sel" "$out" || { unfreeze; fail crop; }
            ;;
        all)
            grim "$out" || { unfreeze; fail crop; }
            ;;
        *)
            unfreeze
            return 1
            ;;
    esac
    unfreeze
    noctalia msg annotate "$out" >/dev/null || fail annotate
}

color() {
    need hyprpicker
    unfreeze
    local hex
    hex=$(hyprpicker -a -f hex 2>/dev/null) || exit 0
    [ -n "$hex" ] && note color "$hex"
}

region_crop() { # → path of a region grabbed from the frozen frame
    need slurp; need grim
    local geom out="$RUN/$1.png"
    geom=$(select_geom region) || { unfreeze; exit 0; }
    grim -g "$geom" "$out" || { unfreeze; fail crop; }
    unfreeze
    echo "$out"
}

ocr() {
    need tesseract
    local img text
    img=$(region_crop ocr) || exit $?
    [ -n "$img" ] || exit 0
    text=$(magick "$img" -resize 200% -colorspace Gray - | tesseract - - -l "${SNIP_OCR_LANG:-eng+rus}" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/./,$!d')
    [ -n "$text" ] || { note no_text; exit 0; }
    printf '%s' "$text" | wl-copy
    note text "$(printf '%s' "$text" | head -c 200)"
}

qr() {
    need zbarimg
    local img text
    img=$(region_crop qr) || exit $?
    [ -n "$img" ] || exit 0
    text=$(zbarimg -q --raw "$img" 2>/dev/null)
    [ -n "$text" ] || { note no_qr; exit 0; }
    printf '%s' "$text" | wl-copy
    note qr "$(printf '%s' "$text" | head -c 200)"
}

# ── Recording ────────────────────────────────────────────────────────────────

# Does the recording area cover where the recbar panel opens (top-center of the focused monitor)?
covers_bar() { # covers_bar <kind> <target>
    local kind="$1" target="$2"
    local fm
    fm=$(monitors | jq -r '.[] | select(.focused) | "\(.name) \(.x) \(.y) \((.width / .scale) | floor)"')
    read -r fname fx fy fw <<< "$fm"
    if [ "$kind" = monitor ]; then [ "$target" = "$fname" ]; return; fi
    local x y w h bx1 bx2 by2
    IFS=', x' read -r x y w h <<< "$target"
    bx1=$((fx + fw / 2 - 130)); bx2=$((fx + fw / 2 + 130)); by2=$((fy + 80))
    [ "$x" -lt "$bx2" ] && [ $((x + w)) -gt "$bx1" ] && [ "$y" -lt "$by2" ] && [ $((y + h)) -gt "$fy" ]
}

rec_select() {
    local sel kind target show=1
    sel=$(select_geom "$1") || { unfreeze; exit 0; }
    unfreeze
    if [ "$1" = screen ]; then kind=monitor; target="${sel%% *}"; else kind=region; target="$sel"; fi
    covers_bar "$kind" "$target" && show=0
    emit recReady "$kind|$target|$show"
}

rec_start() { # kind target audioOut audioIn dir fps codec
    need gpu-screen-recorder
    local kind="$1" target="$2" aout="$3" ain="$4" dir="$5" fps="$6" codec="$7"
    local out args=() audio=""
    alive "$REC_PID" && exit 0
    dir="${dir/#\~/$HOME}"
    mkdir -p "$dir"
    out="$dir/snip_$(date +%Y%m%d_%H%M%S).mp4"
    if [ "$kind" = monitor ]; then
        args+=(-w "$target")
    else
        local x y w h
        IFS=', x' read -r x y w h <<< "$target"
        # Encoders want even dimensions.
        args+=(-w region -region "$((w / 2 * 2))x$((h / 2 * 2))+$x+$y")
    fi
    # Both sources in one -a are mixed into a single track.
    [ "$aout" = true ] && audio="default_output"
    [ "$ain" = true ] && audio="${audio:+$audio|}default_input"
    [ -n "$audio" ] && args+=(-a "$audio" -ac aac)
    gpu-screen-recorder "${args[@]}" -c mp4 -k "$codec" -f "$fps" -cursor yes -o "$out" > "$REC_LOG" 2>&1 &
    echo $! > "$REC_PID"
    emit recStarted "$out"
    wait "$(cat "$REC_PID")"
    rm -f "$REC_PID"
    if [ -s "$out" ] && ffprobe -v error "$out" >/dev/null 2>&1; then
        printf 'file://%s' "$out" | wl-copy --type text/uri-list
        emit recStopped "$out"
    else
        rm -f "$out"
        emit recFailed "$(tail -n 3 "$REC_LOG" | tr '\n' ' ')"
    fi
}

# gpu-screen-recorder finalizes on SIGINT; force-kill if it hangs so the bind always stops it.
rec_stop() {
    alive "$REC_PID" || return 0
    local pid
    pid=$(cat "$REC_PID")
    kill -INT "$pid"
    for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.2; done
    kill -KILL "$pid"
}

case "${1:-}" in
    freeze)     freeze ;;
    unfreeze)   unfreeze ;;
    shot)       shot "${2:-region}" ;;
    color)      color ;;
    ocr)        ocr ;;
    qr)         qr ;;
    rec-select) rec_select "${2:-region}" ;;
    rec-start)  shift; rec_start "$@" ;;
    rec-stop)   rec_stop ;;
    rec-status) alive "$REC_PID" ;;
    *)          echo "usage: snip.sh freeze|unfreeze|shot|color|ocr|qr|rec-select|rec-start|rec-stop|rec-status" >&2; exit 1 ;;
esac

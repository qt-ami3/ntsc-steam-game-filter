#!/usr/bin/env bash
# ntsc-steam.sh — Wrap a Steam game with real-time NTSC/VHS video + audio effects.
#
# Video: gamescope ReShade shader (composite bleed, noise, scanlines, etc.)
# Audio: PipeWire filter-chain virtual sink (tape EQ, bandwidth limit)
#
# Steam launch option:
#   ~/.local/bin/ntsc-steam.sh %command%
#   ~/.local/bin/ntsc-steam.sh --ntsc-strength 0.5 %command%
#
# --ntsc-strength N  Scale all effect intensities by N (default: 1.0)
#                    0.5 = half strength, 2.0 = double, 0 = disabled
# --no-fullscreen    Don't force gamescope fullscreen; let the app decide
#
# Requires: gamescope (sudo pacman -S gamescope)
# Shader:   ~/.local/share/gamescope/reshade/Shaders/ntsc  (no extension)
# Audio:    ~/.config/ntsc-steam/vhs-audio.conf

set -euo pipefail

SHADER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gamescope/reshade/Shaders"
SHADER_INSTALL="$SHADER_DIR/ntsc"
AUDIO_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ntsc-steam/vhs-audio.conf"
VHS_AUDIO_PID=""
SHADER_SCALED=""
NTSC_STRENGTH=1.0
FORCE_FULLSCREEN=1

# ── Parse --ntsc-strength / --no-fullscreen ────────────────────────────────────
_newargs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ntsc-strength) NTSC_STRENGTH="$2"; shift 2 ;;
        --no-fullscreen) FORCE_FULLSCREEN=0; shift ;;
        *) _newargs+=("$1"); shift ;;
    esac
done
set -- ${_newargs[@]+"${_newargs[@]}"}

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    if [[ -n "$VHS_AUDIO_PID" ]]; then
        [[ -n "${PREV_DEFAULT_SINK:-}" ]] && pactl set-default-sink "$PREV_DEFAULT_SINK" 2>/dev/null || true
        kill "$VHS_AUDIO_PID" 2>/dev/null || true
        echo "[ntsc-steam] VHS audio filter stopped."
    fi
    [[ -n "${_HYPR_FOCUS_PID:-}" ]] && kill "$_HYPR_FOCUS_PID" 2>/dev/null || true
    [[ -n "$SHADER_SCALED" ]] && rm -f "$SHADER_SCALED" 2>/dev/null || true
}
trap cleanup EXIT

# ── Sanity checks ─────────────────────────────────────────────────────────────

if ! command -v gamescope &>/dev/null; then
    echo "[ntsc-steam] ERROR: gamescope not found." >&2
    echo "[ntsc-steam] Install it with:  sudo pacman -S gamescope" >&2
    echo "[ntsc-steam] Launching game without NTSC effect..." >&2
    exec "$@"
fi

if [[ ! -f "$SHADER_INSTALL" ]]; then
    echo "[ntsc-steam] ERROR: NTSC shader not found at: $SHADER_INSTALL" >&2
    exec "$@"
fi

# ── Scale shader if --ntsc-strength was given ─────────────────────────────────
# Generates a temp shader with all default uniform values multiplied by the
# strength factor, then passes that file to gamescope instead of the base one.

SHADER_EFFECT="ntsc"
if [[ "$NTSC_STRENGTH" != "1.0" && "$NTSC_STRENGTH" != "1" ]]; then
    SHADER_SCALED="$SHADER_DIR/ntsc_scaled"
    python3 - "$NTSC_STRENGTH" "$SHADER_INSTALL" << 'PYEOF' > "$SHADER_SCALED"
import re, sys
strength = float(sys.argv[1])
with open(sys.argv[2]) as f:
    src = f.read()
result = re.sub(
    r'(>\s*=\s*)(\d+\.?\d*)(\s*;)',
    lambda m: m.group(1) + f'{float(m.group(2)) * strength:.4f}' + m.group(3),
    src
)
print(result, end='')
PYEOF
    SHADER_EFFECT="ntsc_scaled"
    echo "[ntsc-steam] NTSC strength: ${NTSC_STRENGTH}x (scaled shader written)"
fi

# ── VHS audio filter-chain ────────────────────────────────────────────────────
# Starts a PipeWire client that creates a "VHS Audio" virtual sink.
# The game is then directed to this sink via PULSE_SINK so all audio
# passes through the tape EQ before reaching the real output device.

if [[ -f "$AUDIO_CONF" ]]; then
    pipewire --config "$AUDIO_CONF" &
    VHS_AUDIO_PID=$!
    sleep 0.4   # let the virtual sink register in PipeWire
    export PULSE_SINK=effect_input.vhs_audio
    # Also set as default sink — many games ignore PULSE_SINK and use the default
    PREV_DEFAULT_SINK="$(pactl get-default-sink 2>/dev/null || true)"
    pactl set-default-sink effect_input.vhs_audio 2>/dev/null || true
    echo "[ntsc-steam] VHS audio filter started (PID $VHS_AUDIO_PID)"
else
    echo "[ntsc-steam] WARN: audio config not found at $AUDIO_CONF — skipping audio effect" >&2
fi

# ── Detect output resolution ──────────────────────────────────────────────────

W=0; H=0

if command -v hyprctl &>/dev/null; then
    read -r W H <<< "$(
        hyprctl monitors -j 2>/dev/null \
        | python3 -c "
import json, sys
monitors = json.load(sys.stdin)
focused  = next((m for m in monitors if m.get('focused')), monitors[0])
print(focused['width'], focused['height'])
" 2>/dev/null
    )" || true
fi

if [[ "${W:-0}" -lt 1 ]] && command -v wlr-randr &>/dev/null; then
    read -r W H <<< "$(
        wlr-randr 2>/dev/null \
        | awk '/current/{gsub("x"," "); print $1, $2; exit}'
    )" || true
fi

[[ "${W:-0}" -lt 1 ]] && W=1920
[[ "${H:-0}" -lt 1 ]] && H=1080

echo "[ntsc-steam] Running at ${W}x${H} with shader: $SHADER_EFFECT"


# ── Launch via gamescope ──────────────────────────────────────────────────────
# The gamescope WSI layer is an "XWayland Bypass" — it only hooks X11/XWayland
# surfaces. Strip WAYLAND_DISPLAY from the game's env so SDL falls back to
# DISPLAY=:N (gamescope's Xwayland), which the WSI layer correctly intercepts.

_gs_fullscreen=(); [[ "$FORCE_FULLSCREEN" -eq 1 ]] && _gs_fullscreen=(-f)

# ── Hyprland: force focus after gamescope window appears ──────────────────────
# Hyprland doesn't grant gamescope pointer/input focus on open, causing mouse
# and controller events to be dropped until a workspace switch re-focuses it.
# Poll until the gamescope client appears, then dispatch focuswindow.
_HYPR_FOCUS_PID=""
if command -v hyprctl &>/dev/null; then
    (
        for _ in $(seq 1 20); do
            sleep 0.3
            hyprctl clients -j 2>/dev/null \
            | python3 -c "
import json, sys
clients = json.load(sys.stdin)
sys.exit(0 if any('gamescope' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && {
                hyprctl dispatch focuswindow class:gamescope 2>/dev/null
                break
            }
        done
    ) &
    _HYPR_FOCUS_PID=$!
fi

gamescope \
    -W "$W" -H "$H" \
    -w "$W" -h "$H" \
    ${_gs_fullscreen[@]+"${_gs_fullscreen[@]}"} \
    --grab \
    -r 0 \
    --reshade-effect "$SHADER_EFFECT" \
    --reshade-technique-idx 0 \
    -- \
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
    "$@"

# trap EXIT fires here → cleanup() kills the audio filter and removes temp shader

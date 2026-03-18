#!/usr/bin/env bash
# ntsc-steam.sh — Wrap a Steam game with real-time NTSC/VHS video + audio effects.
#
# Video: gamescope ReShade shader (composite bleed, noise, scanlines, etc.)
# Audio: PipeWire filter-chain virtual sink (tape EQ, bandwidth limit)
#
# Steam launch option:
#   ~/.local/bin/ntsc-steam.sh %command%
#
# Requires: gamescope (sudo pacman -S gamescope)
# Shader:   ~/.local/share/gamescope/reshade/Shaders/ntsc  (no extension)
# Audio:    ~/.config/ntsc-steam/vhs-audio.conf

set -euo pipefail

SHADER_INSTALL="${XDG_DATA_HOME:-$HOME/.local/share}/gamescope/reshade/Shaders/ntsc"
AUDIO_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ntsc-steam/vhs-audio.conf"
VHS_AUDIO_PID=""

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    if [[ -n "$VHS_AUDIO_PID" ]]; then
        kill "$VHS_AUDIO_PID" 2>/dev/null || true
        echo "[ntsc-steam] VHS audio filter stopped."
    fi
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

# ── VHS audio filter-chain ────────────────────────────────────────────────────
# Starts a PipeWire client that creates a "VHS Audio" virtual sink.
# The game is then directed to this sink via PULSE_SINK so all audio
# passes through the tape EQ before reaching the real output device.

if [[ -f "$AUDIO_CONF" ]]; then
    pipewire --config "$AUDIO_CONF" &
    VHS_AUDIO_PID=$!
    sleep 0.4   # let the virtual sink register in PipeWire
    export PULSE_SINK=effect_input.vhs_audio
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

echo "[ntsc-steam] Running at ${W}x${H} with shader: $SHADER_INSTALL"

# ── Disable Steam overlay Vulkan layer ────────────────────────────────────────
# The layer JSON's actual disable key is DISABLE_VK_LAYER_VALVE_steam_overlay_1.
# Without this it intercepts vkCreateSwapchainKHR before gamescope's WSI layer.
export DISABLE_VK_LAYER_VALVE_steam_overlay_1=1

# ── Launch via gamescope ──────────────────────────────────────────────────────
# The gamescope WSI layer is an "XWayland Bypass" — it only hooks X11/XWayland
# surfaces. Strip WAYLAND_DISPLAY from the game's env so SDL falls back to
# DISPLAY=:N (gamescope's Xwayland), which the WSI layer correctly intercepts.

gamescope \
    -W "$W" -H "$H" \
    -w "$W" -h "$H" \
    -r 0 \
    --reshade-effect ntsc \
    --reshade-technique-idx 0 \
    -- \
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 \
    "$@"

# trap EXIT fires here → cleanup() kills the audio filter

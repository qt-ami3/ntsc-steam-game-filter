#!/usr/bin/env bash
# ntsc-steam.sh — Wrap a Steam game with a real-time NTSC/VHS effect via gamescope.
#
# Steam launch option:
#   ~/.local/bin/ntsc-steam.sh %command%
#
# Requires: gamescope (sudo pacman -S gamescope)
# Shader:   ~/.local/share/gamescope/reshade/Shaders/ntsc.fx

set -euo pipefail

SHADER_INSTALL="${XDG_DATA_HOME:-$HOME/.local/share}/gamescope/reshade/Shaders/ntsc.fx"

# ── Sanity checks ─────────────────────────────────────────────────────────────

if ! command -v gamescope &>/dev/null; then
    echo "[ntsc-steam] ERROR: gamescope not found." >&2
    echo "[ntsc-steam] Install it with:  sudo pacman -S gamescope" >&2
    echo "[ntsc-steam] Launching game without NTSC effect..." >&2
    exec "$@"
fi

if [[ ! -f "$SHADER_INSTALL" ]]; then
    echo "[ntsc-steam] ERROR: NTSC shader not found at: $SHADER_INSTALL" >&2
    echo "[ntsc-steam] Run: cp ~/.config/ntsc-steam/ntsc.fx \"$SHADER_INSTALL\"" >&2
    exec "$@"
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
# The layer JSON's actual disable key is DISABLE_VK_LAYER_VALVE_steam_overlay_1,
# not VK_LOADER_LAYERS_DISABLE. Without this the overlay intercepts
# vkCreateSwapchainKHR before gamescope's WSI layer can hook it.
export DISABLE_VK_LAYER_VALVE_steam_overlay_1=1

# ── Launch via gamescope ──────────────────────────────────────────────────────
# -W/-H  = output (host) resolution
# -w/-h  = game render resolution (same → no upscale)
# -r 0   = uncapped refresh rate
#
# The gamescope WSI layer is an "XWayland Bypass" — it only hooks X11/XWayland
# surfaces. With --expose-wayland active, SDL2/SDL3 games connect their Vulkan
# surface to gamescope's Wayland socket directly, which the WSI layer doesn't
# recognise as a gamescope surface → "non-gamescope swapchain" error.
#
# Fix: drop --expose-wayland and strip WAYLAND_DISPLAY from the game's env via
# `env -u WAYLAND_DISPLAY` so SDL falls back to DISPLAY=:N (gamescope's own
# Xwayland), which the XWayland-bypass WSI layer correctly intercepts.

exec gamescope \
    -W "$W" -H "$H" \
    -w "$W" -h "$H" \
    -r 0 \
    --reshade-effect ntsc \
    --reshade-technique-idx 0 \
    -- \
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 \
    "$@"

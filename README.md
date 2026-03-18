# gamescope-ntsc

A real-time NTSC/VHS analog video effect for Steam games on Linux, applied via [gamescope](https://github.com/ValveSoftware/gamescope)'s ReShade shader support.

Simulates composite color bleeding, chroma shift, luma/chroma noise, scanlines, VHS tape wobble, and head-switching glitches — in the style of [ntsc-rs](https://ntsc.rs).

![effect preview](https://user-images.githubusercontent.com/placeholder/preview.png)

---

## Requirements

- Linux with a Wayland compositor (tested on Hyprland)
- [gamescope](https://github.com/ValveSoftware/gamescope) ≥ 3.14

```bash
sudo pacman -S gamescope   # Arch / CachyOS
```

---

## Installation

### 1. Copy the shader

```bash
mkdir -p ~/.local/share/gamescope/reshade/Shaders
cp shader/ntsc.fx ~/.local/share/gamescope/reshade/Shaders/ntsc.fx
# gamescope looks up shaders by name without extension too
cp shader/ntsc.fx ~/.local/share/gamescope/reshade/Shaders/ntsc
```

### 2. Install the launch script

```bash
cp script/ntsc-steam.sh ~/.local/bin/ntsc-steam.sh
chmod +x ~/.local/bin/ntsc-steam.sh
```

### 3. Set the Steam launch option

In Steam → right-click a game → **Properties** → **Launch Options**:

```
~/.local/bin/ntsc-steam.sh %command%
```

---

## How it works

`ntsc-steam.sh` wraps the game with `gamescope`, which runs as a nested Wayland compositor and applies the NTSC ReShade shader to every composited frame via its Vulkan post-processing pipeline.

Key environment variables set by the script:

| Variable | Value | Reason |
|---|---|---|
| `DISABLE_VK_LAYER_VALVE_steam_overlay_1` | `1` | Prevents Steam overlay Vulkan layer from intercepting `vkCreateSwapchainKHR` before gamescope's WSI layer |
| `SDL_VIDEODRIVER` | `x11` | Forces SDL2 games to use gamescope's Xwayland instead of connecting directly to the host Wayland compositor |
| `WAYLAND_DISPLAY` | *(unset)* | Prevents non-SDL games from connecting to the host compositor and bypassing gamescope's swapchain hook |

---

## Effects

| Parameter | Default | Description |
|---|---|---|
| `ChromaBleed` | 0.80 | Horizontal color smear (composite bandwidth limiting) |
| `ChromaShiftPixels` | 2.0 | Luma/chroma misalignment in pixels |
| `LumaNoise` | 0.025 | Brightness noise (white snow) |
| `ChromaNoise` | 0.050 | Color noise (rainbow interference) |
| `ScanlineStrength` | 0.25 | Interlaced scanline gap darkness |
| `VHSWobble` | 0.40 | Horizontal tape warping |
| `HeadSwitching` | 0.60 | Glitch band at bottom of frame |

---

## Troubleshooting

**Game doesn't launch**
- Make sure gamescope is installed: `which gamescope`
- Check the shader exists: `ls ~/.local/share/gamescope/reshade/Shaders/ntsc`

**Game launches but no filter**
- Confirm the pipeline is active by temporarily swapping to the test shader:
  edit `ntsc-steam.sh`, change `--reshade-effect ntsc` → `--reshade-effect ntsc_test`, copy `shader/ntsc_test` to the Shaders folder, and relaunch. The screen should turn red/greyscale.
- Check gamescope logs: add `GAMESCOPE_RESHADE_DEBUG=1` before `exec gamescope` in the script.

**`createswapchainKHR: non-gamescope swapchain` error**
- The `env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11` part of the script handles this. Make sure you are using the latest version of `ntsc-steam.sh`.

---

## License

MIT

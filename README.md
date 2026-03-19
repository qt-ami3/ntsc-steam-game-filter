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

Optional flags can be prepended:

```
~/.local/bin/ntsc-steam.sh --ntsc-strength 0.5 --no-fullscreen %command%
```

| Flag | Default | Description |
|---|---|---|
| `--ntsc-strength N` | `1.0` | Scale all effect intensities (0 = off, 0.5 = half, 2.0 = double) |
| `--no-fullscreen` | *(fullscreen)* | Run gamescope as a window instead of forcing fullscreen |

---

## How it works

`ntsc-steam.sh` wraps the game with `gamescope`, which runs as a nested Wayland compositor and applies the NTSC ReShade shader to every composited frame via its Vulkan post-processing pipeline.

Key environment variables set by the script:

| Variable | Value | Reason |
|---|---|---|
| `SDL_VIDEODRIVER` | `x11` | Forces SDL2 games to use gamescope's Xwayland instead of connecting directly to the host Wayland compositor |
| `WAYLAND_DISPLAY` | *(unset)* | Prevents non-SDL games from connecting to the host compositor and bypassing gamescope's swapchain hook |
| `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS` | `1` | Keeps joystick events flowing when the gamescope window loses focus |

---

## Audio effect

The script automatically starts a PipeWire virtual sink called **"VHS Audio"** that routes the game's audio through a tape EQ before it reaches your speakers:

| Stage | Setting | Effect |
|---|---|---|
| HP @ 40 Hz | Q=0.7 | Remove sub-bass rumble |
| Peaking +4 dB @ 90 Hz | Q=1.1 | Tape head bass resonance / warmth |
| Peaking +1.5 dB @ 350 Hz | Q=1.4 | Low-mid tape congestion |
| Peaking -3 dB @ 3 kHz | Q=0.85 | Upper-mid presence dip (loss of clarity) |
| High shelf -9 dB @ 5 kHz | Q=0.8 | High-frequency rolloff |
| LP @ 8 kHz | Q=1.1 | Hard VHS LP-mode bandwidth ceiling |

The audio filter starts when the game launches and is automatically stopped when you exit.

To disable the audio effect only, delete or move `~/.config/ntsc-steam/vhs-audio.conf`.

### Optional: wow & flutter (requires LADSPA)

For pitch instability simulation, install the TAP plugins and add this node to `vhs-audio.conf` inside `filter.graph.nodes`:

```bash
sudo pacman -S ladspa-tap-plugins
```

```
{ type = ladspa  name = flutter  plugin = tap_chorusflanger  label = tap_chorusflanger
  control = { "0" = 0   "1" = 2.5   "2" = 0.15   "3" = 0.0   "4" = 1   "5" = 0.5 } }
```
Then add `{ output = "lp:Out" input = "flutter:In" }` as the final link.

---

## Video effects
|---|---|---|
| `ChromaBleed` | 0.80 | Horizontal color smear (composite bandwidth limiting) |
| `ChromaShiftPixels` | 2.0 | Luma/chroma misalignment in pixels |
| `LumaNoise` | 0.025 | Brightness noise (white snow) |
| `ChromaNoise` | 0.050 | Color noise (rainbow interference) |
| `ScanlineStrength` | 0.25 | Interlaced scanline gap darkness |
| `VHSWobble` | 0.40 | Horizontal tape warping |
| `HeadSwitching` | 0.60 | Glitch band at bottom of frame |

---

## Known limitations

**Steam Input (controllers via Steam's controller remapping) does not work.**
Games running inside gamescope's nested Xwayland don't receive Steam Input events. Raw evdev controllers (recognised directly by the game or SDL without Steam's remapping layer) are unaffected. If you rely on Steam Input for button remapping or gyro, you'll need to run the game without ntsc-steam.

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

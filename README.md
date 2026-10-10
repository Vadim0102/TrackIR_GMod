# gmcl_TrackIR (fork)

> **2024 update (upstream):** it seems that the natural point policy for the SDK changed, but I have no idea where my TrackIR device is.

![](http://puu.sh/dTvQb/1c1e78fd52.png)

Greetings! `gmcl_TrackIR` is a clientside Windows module providing a simple interface to the TrackIR software
(see below for how it works).

This fork keeps the original module and API untouched and extends the example Lua script with a proper
on/off switch, automatic device detection, a settings menu and a few quality-of-life options.
Original module and script by [ExtReMLapin](https://github.com/ExtReMLapin/TrackIR_GMod).

---

## What this fork adds

- **Full on/off switch**, from the console or from the menu. When the plugin is off it removes all of its hooks and timers, stops polling the device and tells the server to reset your head/spine bones.
- **Auto-enable**: the plugin turns itself on when a TrackIR device is found, turns itself off when the device goes quiet, and keeps looking while it is off.
- **Settings menu** under **Q → Utilities → TrackIR**.
- **Real crosshair** (where you actually aim, since your view is not locked to your aim) is now configurable: on/off, style, size, outline, color and alpha.
- **Game crosshair** (the stock HUD crosshair) can be hidden or shown independently.
- **Sensitivity** per axis (pitch, yaw, roll, head movement) and optional inversion of pitch and yaw.
- **Angle limits** per axis. The "nice" soft limit still applies.
- **Center command** to use your current head position as the zero point.
- **Camera and view-addon friendly**: looking through the Camera tool no longer makes the view follow your head, and head tracking is added onto the view instead of replacing it, so camera weapons and view-bob/tilt addons keep working on top of it.
- **Sync options**: choose whether your head and/or body lean are sent to the server (visible to other players), and how often.
- **Server switch** `sv_trackir_allow` to forbid TrackIR on a server. The server also clamps the values it receives from clients.
- **Localization**: the menu and console messages follow the game language (`gmod_language`): Russian for `ru`, English for everything else.
- **Safer startup**: the module is loaded with `pcall`, so a missing or broken module no longer throws errors every tick.

### Installation

Same as upstream: put the module (`gmcl_TrackIR_*.dll`) into `garrysmod/lua/bin/` and the script into `garrysmod/lua/autorun/`.
Run TrackIR software first, then start the game.

### Console commands and ConVars

All client ConVars are saved between sessions.

| Command / ConVar | Default | Description |
|---|---|---|
| `trackir_enabled` | `1` | Master switch. `0` turns the whole plugin off. |
| `trackir_autoenable` | `1` | Enable only while a TrackIR device is found. |
| `trackir_toggle` | | Flip `trackir_enabled`. |
| `trackir_recheck` | | Look for the device again right now. |
| `trackir_center` | | Use the current head position as the center. |
| `trackir_reset` | | Reset all settings to defaults (the master switch is left alone). |
| `trackir_status` | | Print the module's version / status / debug info to the console (refreshes the data first). |
| `trackir_debug` | `0` | Print what the device detection sees, for troubleshooting auto-enable. |
| `trackir_camera_mode` | `0` | While looking through a camera (Camera tool etc.): `0` ignore TrackIR so the camera stays put, `1` apply TrackIR on top of the camera view. |
| `trackir_chain` | `1` | `1`: add head movement onto the view so other addons can stack on top of it. `0`: replace the view (old behaviour). |
| `trackir_crosshair_real` | `1` | Show the real crosshair. |
| `trackir_crosshair_real_style` | `1` | `0` square, `1` rounded, `2` circle outline. |
| `trackir_crosshair_real_size` | `10` | Real crosshair size. |
| `trackir_crosshair_real_outline` | `1` | Dark outline around the real crosshair. |
| `trackir_crosshair_real_r/g/b/a` | `64/134/195/170` | Real crosshair color and alpha. |
| `trackir_crosshair_game` | `1` | Show the stock game crosshair. |
| `trackir_sens_pitch/yaw/roll` | `1` | Sensitivity per axis. |
| `trackir_sens_pos` | `1` | Head movement sensitivity. |
| `trackir_invert_pitch` / `trackir_invert_yaw` | `0` | Invert an axis. |
| `trackir_limit_pitch` | `70` | Max pitch angle. |
| `trackir_limit_yaw` | `130` | Max yaw angle. |
| `trackir_limit_roll` | `70` | Max roll angle. |
| `trackir_position` | `1` | Use head movement (X axis). |
| `trackir_send_head` | `1` | Sync head to the server. |
| `trackir_send_body` | `1` | Sync body lean to the server. |
| `trackir_netrate` | `66` | Network updates per second (the old hardcoded tickrate). |
| `sv_trackir_allow` | `1` | **Server.** Allow players to use TrackIR. |

### How the master switch and auto-enable interact

| `trackir_enabled` | `trackir_autoenable` | Result |
|---|---|---|
| `0` | any | Plugin is off. |
| `1` | `0` | Plugin is on, no device check. |
| `1` | `1` | Plugin is on only while a device is found. |

### When the device is re-checked (auto-enable)

- when the game starts, or a map / server is joined
- when the ESC menu (pause) is closed
- when the game window loses or regains focus
- when you run `trackir_recheck` or press the button in the menu

The module can only be loaded while the game window has focus, so if the game starts in the background the check waits until you focus it.

**How "device found" is decided:** while probing (up to 5 seconds), the plugin calls `TrackIR.Update()` every tick and checks the six axes. If any of them returns something other than zero, the device is considered present and the plugin turns on. A running tracker practically never reports exact zeros on every axis, while a missing device or closed TrackIR software does.

**Turning off by itself:** once running in auto mode, the plugin watches the same data. If it gets nothing but exact zeros for 5 seconds (opentrack closed, tracker stopped), it switches itself off. While it is off in auto mode, it looks for the device again every 10 seconds, so starting opentrack later works without touching ESC or the window. Both timings are constants at the top of the script (`PROBE_TIME`, `AUTO_RETRY`).

What is *not* used, and why:

- `get_Status`: with opentrack it returns `0` both with and without data flowing.
- The frame counter in `get_Debug` (`Frame = N`): it can keep ticking while the tracker is stopped, so it says nothing about real head data. It is only printed in debug mode.

Things to know:

- The module only refreshes its numbers when `Update()` is called. If you print `get_Debug` yourself without calling it, you will see stale (often all-zero) values. `trackir_status` calls `Update()` first for that reason.
- If you sit perfectly still *and* your tracker software outputs exact zeros for 5 seconds, auto mode will turn off. That should not happen with a live tracker, but if it does for you, increase `PROBE_TIME`.

If auto-enable doesn't behave, set `trackir_debug 1` and run `trackir_recheck`. The console will show what the detection saw (sum of the axes and the frame counter before/after).

### Cameras and other view addons

- **Camera tool and other camera entities.** These switch the player's view entity. By default (`trackir_camera_mode 0`) the plugin leaves the view alone while you look through one, so the camera stays exactly where you placed it. Set `trackir_camera_mode 1` if you do want your head movement applied on top of the camera.
- **Stacking with other addons (`trackir_chain 1`, default).** A `CalcView` hook that returns a view table wins over every other hook, and it also stops `WEAPON:CalcView` from running. That broke camera weapons and addons like view-bob/tilt ones. Now the plugin adds its rotation to the `origin`/`angles` the hooks receive, in place, and returns nothing, so everything that runs after it works on top of the head-tracked view. This is the approach the GMod wiki recommends for `CalcView`. `trackir_chain 0` brings back the old "replace the view" behaviour.
- **Limit:** hook order decides who runs first, and it is not under the plugin's control. An addon whose `CalcView` hook happens to run *before* the plugin's and returns a view will hide the plugin's effect. If you find one like that, please open an issue with the addon name.

### Tips

- Use different profiles in the TrackIR software depending on what you do: *Default* for FPS/fight gamemodes where you need to aim, *Smooth* for walking or piloting helicopters/planes (see the WAC support notes below).
- If the camera feels off-center, look straight ahead and run `trackir_center`.

---

## Module

**API features:**

- *Easy implantation*, with examples showing how to convert raw variables to in-game variables (to `Angle()` or to °).
- *6 DOF API support* (Pitch, Yaw, Roll, X, Y, Z).
- *All TrackIR features.* Important: depending on what you are going to do with TrackIR, you'd better use different profiles in the TrackIR software (*Default* for FPS/fight gamemodes where you need to aim, *Smooth* for walking or piloting helicopters/planes).

**Example features:**

- 4DOF support (Pitch, Yaw and Roll + lean left or right).
- Angle limit (so you don't break your neck).
- "Nice" angle limit system: when you turn your head and "hit" the angle limit, the camera movement is not brutally stopped.

### API guide

![](http://puu.sh/gvJ2u/5004204308.png)

All functions are stored in the `TrackIR` table after the module has been loaded:

```txt
] lua_run_cl PrintTable(TrackIR)
	[...]
	Update	=	function: 0x0219b60ac978
	get_Debug	=	function: 0x0219b60ac9b0
	get_Pitch	=	function: 0x0219b60ac6f8
	get_Roll	=	function: 0x0219b60ac7a0
	get_Status	=	function: 0x0219b60ac878
	get_Ver	=	function: 0x0219b60ac940
	get_X	=	function: 0x0219b60ac730
	get_Y	=	function: 0x0219b60ac840
	get_Yaw	=	function: 0x0219b60ac768
	get_Z	=	function: 0x0219b60ac7d8
```

**Functions returning coordinates:**
`TrackIR.get_X`, `TrackIR.get_Y`, `TrackIR.get_Z`, `TrackIR.get_Pitch`, `TrackIR.get_Yaw`, `TrackIR.get_Roll`

**Functions returning debug information:**
`TrackIR.get_Debug` returns debug info: if everything is working it returns the raw variables formatted, otherwise a message.

**Functions returning information:**
`TrackIR.get_Ver` (not really tested), `TrackIR.get_Status`

**Functions returning nothing:**
`TrackIR.Update` requests an update for all the coordinates. Run it every time you want to update the view; it's best to do what the example script does.

### GLua functions you'll love

`TrackIR_Deg_ToRealDeg` converts raw values (from the API) to degrees:

```lua
local function map(value, low1, high1, low2, high2)
	return (low2 + (value - low1) * (high2 - low2) / (high1 - low1))
end

local function TrackIR_Deg_ToRealDeg(deg1)
	deg1 = deg1 or 0
	return map(deg1, -16383, 16383, -180, 180)
end
```

---

## Requirements

- TrackIR USB device
- TrackIR software
- Windows (OSX and Linux support would need contacting NaturalPoint first)

**Copyright (c) 2006-2019 NaturalPoint Inc. All Rights Reserved**

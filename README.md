<div align="center">

# ⚡ BWX // Bloxstrike Utility Suite

![Version](https://img.shields.io/badge/Version-6.1_Performance-00e5ff?style=for-the-badge&logo=git)
![Platform](https://img.shields.io/badge/Platform-Roblox-e2231a?style=for-the-badge&logo=roblox)
![Language](https://img.shields.io/badge/Language-Luau-2b2d31?style=for-the-badge&logo=lua)
![Status](https://img.shields.io/badge/Status-Undetected-00ff88?style=for-the-badge&logo=shield)

**The ultimate, high-performance utility suite designed specifically for Bloxstrike.**
Engineered with advanced metamethod hooks, true silent aim, and zero-lag instant ESP rendering.

</div>

## 📥 Get the Script

```lua
loadstring(game:HttpGet("[https://raw.githubusercontent.com/bwx330-dev/bwx-bloxstrike/main/bwx-bloxstrike.lua](https://raw.githubusercontent.com/bwx330-dev/bwx-bloxstrike/main/bwx-bloxstrike.lua)"))()
```

**⚠️ Executor Requirement:**
This version relies on `hookfunction`, `getrawmetatable`, and `hookmetamethod`. Entry-level executors such as Xeno and Solara are not supported; use a high-tier executor like Wave, AWP.gg, or Script-Ware.

## 📖 Overview

BWX is engineered from the ground up to bypass the common pitfalls of Roblox exploitation, where poorly implemented module hooks break weapon purchasing or shooting mechanics.

In v6.1, BWX utilizes position-decoupled metamethod hooking via `__newindex` so the game cannot apply vertical or horizontal recoil to your camera while your character continues to move freely. It also includes an event-driven smoke removal system that prevents frame rate drops.

## 🚀 Features

**🎯 Combat (Hooked)**
* **LMB Aimlock:** Smooth, magnetized target tracking activated by holding Left Click.
* **True No Recoil:** Locks pitch and yaw via `__newindex` so the camera stays frozen during spray while movement remains unrestricted.
* **No Spread:** Hooks `Workspace.Raycast` to force bullets toward the exact center of the camera.
* **Hitbox Expander:** Visually expands the enemy head hitbox for easier hit registration.

**👁️ Visuals (Instant ESP)**
* **Instant Box ESP:** Bypasses `StreamingEnabled` limitations by reading player objects directly.
* **Tracers:** Renders snaplines from the bottom of your screen to enemy positions.
* **Health & Names:** Displays dynamic health bars, display names, and real-time distance tracking.
* **No Smoke:** Event-driven smoke grenade removal with zero performance impact.

**🛡️ Misc & Movement**
* **Deep Anti-Flash:** Scans `Lighting` and `PlayerGui` to wipe flashbang effects immediately.
* **Native Bhop:** Hold **Space** to jump automatically upon landing.
* **Unload Script:** Press **RightShift** to cleanly remove all hooks and UI without restarting the game.

## ⚙️ Technical Architecture

* **Position Decoupling:** The `__newindex` hook intercepts camera `CFrame` updates, stripping rotational recoil when you shoot while preserving the positional vector so you can walk, jump, and aim normally.
* **Safe Replication:** Weapon modules are never hooked directly; intercepting only the bullet trajectory and camera matrix prevents the server from rejecting buy or shoot actions.
* **Event-Driven Performance:** World modifications like Anti-Flash and No Smoke run on `DescendantAdded` events rather than `RenderStepped` loops, maintaining a locked 60+ FPS.

## 📜 Usage & Keybinds

1. Launch **Bloxstrike** on Roblox.
2. Open a compatible high-tier executor (Wave or AWP.gg).
3. Execute the `loadstring` script provided above.
4. Press **K** to toggle the configuration menu.

**Default Keybinds**
* **K:** Toggle Menu
* **LMB (Hold):** Trigger Aimlock & No Recoil
* **Space (Hold):** Auto Bunnyhop
* **RightShift:** Unload Script

## 📝 Changelog

* **v6.1 (Current):** Fixed No Smoke FPS drop by switching to event-driven detection and added the Unload keybind.
* **v6.0:** Fixed horizontal recoil and implemented True No Recoil via position decoupling.
* **v5.6:** Resolved Aimlock conflict with camera lock.
* **v5.0:** Complete rewrite for stable metamethod hooks.
* **v4.0:** Introduced Silent Aim and Instant ESP.

<div align="center">
  <i>Built for personal use. Use at your own risk.</i>
</div>

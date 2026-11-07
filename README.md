![Version](https://img.shields.io/badge/version-3.11-green)

# ⚡ BWX // Bloxstrike Utility Suite (v3.11)

A high-performance, non-invasive utility suite designed for **Bloxstrike** (Roblox). 
Optimized specifically for **Xeno** and modern executors. Built with a focus on engine stability, zero replication stalls, and frame-perfect rendering.

## 🚀 Features

### Combat
*   **LMB Aimlock:** Smooth, magnetized target tracking activated by holding Left Click (LMB). Only locks onto targets within the FOV radius.
*   **Silent Aim (Hitbox Expander):** Dynamically expands the Head hitbox for magnetic bullet registration. Includes safe memory restoration when disabled.
*   **FOV Customization:** Adjustable FOV radius and color.
*   **Wallcheck:** Optional visibility check to only lock onto visible enemies.
*   **Advanced Team Check:** Multi-tier team resolution (TeamId, TeamColor, Role, FFA Gamemode detection).

### Visuals (ESP)
*   **2D Box ESP:** Rigid physics-root bounding boxes with health bars, names, and distance tags.
*   **Skeleton ESP:** Full R15/Bloxstrike bone tracking.
*   **Snaplines / Tracers:** Lines tracking from the bottom or center of the screen to the target.
*   **Player Radar (Minimap):** Top-left 2D radar that tracks enemy positions relative to your camera. Adjustable zoom.
*   **C4 Objective Tracker:** Highlights the planted bomb or dropped C4 with distance markers.
*   **Occlusion/Streaming Fix:** Position Caching system renders ESP for 1 second after an enemy is culled by `StreamingEnabled` (prevents ESP from instantly disappearing behind walls).

### Weapon Mods
*   **No Recoil (Safe Hook):** Hooks `CameraController` to strip weapon kick rotation without breaking the client-server replication state machine (no buy-menu delays).
*   **No Spread (Attribute Overwrite):** Scans equipped tools and ReplicatedStorage to force `Spread` properties to 0.
*   **Auto Reload:** Monitors current ammo and automatically simulates the 'R' keypress when the magazine is empty.
*   **Anti-Flashbang:** Instant blind wipe by suppressing Lighting `BlurEffect` and GUI overlays.

### Movement
*   **Auto Bunnyhop:** Hold Space to automatically jump upon landing.

---

## 🛠️ Technical Architecture

*   **Non-Invasive Hook Framework:** Unlike standard exploits that break weapon purchasing, BWX uses a strict safe-hook on `weaponKick` and `getWeaponKickRotation`, ensuring the replication engine remains 100% native.
*   **Zero-GC Drawing Pool:** Drawings are recycled and reused rather than destroyed every frame, preventing CPU frame-time spikes and stutters.
*   **Safe Memory Restoration:** Hitboxes and hooked functions are cleanly reverted upon unload via `env.BWXUnload()` to prevent crashing.
*   **FFA / Deathmatch Aware:** Automatically disables team checks if the game mode is detected as Deathmatch or FFA.

---

## 📜 Usage

1. Launch **Bloxstrike** on Roblox.
2. Open your executor (**Xeno** recommended).
3. Paste the script and execute.
4. Press **K** or **Insert** to toggle the UI.

### Keybinds
*   `K` / `Insert` - Toggle Menu
*   `LMB` (Hold) - Trigger Aimlock & No Recoil
*   `Space` (Hold) - Bunnyhop

---

## 📝 Changelog

*   **v3.11** - Added Auto Reload, Player Radar (Minimap), and improved UI sliders.
*   **v3.10** - Implemented Safe CameraHook for No Recoil. Fixed Crosshair rising issue.
*   **v3.8** - Non-invasive No Spread (Property Overwrite). Removed unstable raycast hooks.
*   **v3.6** - Added Position Caching for `StreamingEnabled` (ESP no longer vanishes behind walls).
*   **v3.4** - Fixed FOV logic, team checks, and memory leaks.

---
*Created for private use. Optimized for Xeno & Synapse.*

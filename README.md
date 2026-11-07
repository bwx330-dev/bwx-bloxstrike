![Version](https://img.shields.io/badge/version-3.14-green)

<div align="center">

# ⚡ BWX // Bloxstrike Utility Suite

![Version](https://img.shields.io/badge/Version-3.14_Stable-00e5ff?style=for-the-badge&logo=git)
![Platform](https://img.shields.io/badge/Platform-Roblox-e2231a?style=for-the-badge&logo=roblox)
![Language](https://img.shields.io/badge/Language-Luau-2b2d31?style=for-the-badge&logo=lua)
![Status](https://img.shields.io/badge/Status-Undetected-00ff88?style=for-the-badge&logo=shield)

**A high-performance, non-invasive utility suite designed specifically for Bloxstrike.**
Built with a strict focus on engine stability, zero replication stalls, and frame-perfect rendering.

</div>

---

## 📖 Overview

BWX (Bloxstrike Utility Suite) is not just another script. It is engineered from the ground up to bypass the common pitfalls of Roblox exploitation—specifically **Replication Stalls**. Many cheats break your ability to buy weapons or shoot because they hook critical game modules. BWX avoids this entirely by using safe, non-invasive memory reading and rendering techniques.

Whether you need a smooth LMB Aimlock or a complex 5-second position caching ESP, BWX delivers it without compromising your game client.

---

## 🚀 Features

### 🎯 Combat
| Feature | Description |
| :--- | :--- |
| **LMB Aimlock** | Magnetized target tracking activated by holding Left Click. Only locks onto targets within the FOV radius. |
| **Silent Aim (Hitbox)** | Dynamically expands the Head hitbox for magnetic bullet registration. Includes safe memory restoration. |
| **Advanced FOV** | Customizable FOV radius and color with real-time rendering. |
| **Team Resolution** | Multi-tier team checking (TeamId, TeamColor, Role) with FFA/Deathmatch auto-detection. |

### 👁️ Visuals (ESP)
| Feature | Description |
| :--- | :--- |
| **2D Box ESP** | Rigid physics-root bounding boxes with health bars, names, and distance tags. |
| **Ghost Cache (5s)** | When an enemy is occluded by a wall and the game culls their model, ESP remains visible (fading out) for 5 seconds based on their last known velocity. |
| **C4 Tracker** | Highlights the planted bomb or dropped C4 with distance markers. |
| **Snaplines / Tracers** | Lines tracking from the bottom or center of the screen to the target. |

### 🛡️ Misc & Movement
| Feature | Description |
| :--- | :--- |
| **Deep Anti-Flash** | Scans Lighting (`ColorCorrection`, `Blur`) and `PlayerGui` to instantly wipe flashbang effects. |
| **Native Bhop** | Hold Space to automatically jump upon landing using engine-native Humanoid states. |
| **Auto-Reload** | *(Experimental)* Simulates 'R' keypress when ammo hits 0. |

---

## ⚙️ Technical Architecture (Why BWX is Safe)

1. **Zero-Hook No Recoil:** 
   We **removed** all `CameraController` hooks in v3.14. Hooking this module causes Bloxstrike's server to reject your weapon state, breaking your ability to buy or shoot. BWX prioritizes **Game Stability > Recoil Removal**.
2. **Zero-GC Drawing Pool:** 
   ESP drawings are recycled rather than destroyed every frame, preventing CPU frame-time spikes and stutters.
3. **Safe Memory Restoration:** 
   Hitboxes and hooked functions are cleanly reverted upon unload via `env.BWXUnload()` to prevent crashing.
4. **StreamingEnabled Mitigation:** 
   The Ghost Cache system stores the last known `Vector3` position of an entity before the game unloads their model. This mimics "Spectate Mode" ESP while you are alive.

---

## 📜 Usage

1. Launch **Bloxstrike** on Roblox.
2. Open your executor (**Xeno** recommended for best performance).
3. Paste the `v3.14` script and execute.
4. Press **K** or **Insert** to toggle the UI.

### Keybinds
| Key | Action |
| :--- | :--- |
| `K` / `Insert` | Toggle Menu |
| `LMB` (Hold) | Trigger Aimlock |
| `Space` (Hold) | Auto Bunnyhop |

---

## 📝 Changelog

* **v3.14 (Current)** - **Fully Stable Edition.** Removed all CameraController hooks to fix buy/shoot bugs. Added 5s Ghost Cache ESP. Deep Anti-Flash & Native Bhop.
* **v3.13** - Safe Camera Hook attempt (failed, caused replication stall).
* **v3.11** - Added Radar (removed in v3.12), Auto Reload.
* **v3.10** - Non-invasive property overwrites.
* **v3.6** - Introduced Position Caching for StreamingEnabled.
* **v3.3** - Initial Zero-GC Engine release.

---
<div align="center">
  <i>Built for personal use. Optimized for Xeno.</i>
</div>

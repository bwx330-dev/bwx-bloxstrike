<div align="center">

# ⚡ BWX // Bloxstrike Utility Suite

![Version](https://img.shields.io/badge/Version-6.1_Performance-00e5ff?style=for-the-badge&logo=git)
![Platform](https://img.shields.io/badge/Platform-Roblox-e2231a?style=for-the-badge&logo=roblox)
![Language](https://img.shields.io/badge/Language-Luau-2b2d31?style=for-the-badge&logo=lua)
![Status](https://img.shields.io/badge/Status-Undetected-00ff88?style=for-the-badge&logo=shield)

**The ultimate, high-performance utility suite designed specifically for Bloxstrike.**
Engineered with advanced metamethod hooks, true silent aim, and zero-lag instant ESP rendering.

</div>

---

## 📥 Get the Script

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/bwx330-dev/bwx-bloxstrike/main/bwx-bloxstrike.lua"))()
⚠️ EXECUTOR REQUIREMENT:
This version uses hookfunction, getrawmetatable, and hookmetamethod.
Xeno and Solara WILL NOT WORK. You must use a high-tier executor like Wave, AWP.gg, or Script-Ware.

📖 Overview
BWX is not just another script. It is engineered from the ground up to bypass the common pitfalls of Roblox exploitation. Many cheats break your ability to buy weapons or shoot because they hook critical game modules incorrectly.

In v6.1, we utilize Position-Decoupled Metamethod Hooking (__newindex). This means the game cannot apply vertical or horizontal recoil to your camera, but your character can still walk and move completely freely. We also feature an Event-Driven No Smoke system that ensures 0 FPS drops.

🚀 Features
🎯 Combat (Hooked)
Feature	Description
LMB Aimlock	Smooth, magnetized target tracking activated by holding Left Click.
True No Recoil	__newindex Pitch & Yaw lock. Camera is completely frozen during spray, but movement remains free.
No Spread	Hooks Workspace.Raycast. Bullets are forced to the exact center of the camera.
Hitbox Expander	Visually expands the enemy's head hitbox for easy registration.
👁️ Visuals (Instant ESP)
Feature	Description
Instant Box ESP	Bypasses Stream
ingEnabled
 limitations by directly reading player objects.
Tracers	Renders lines from the bottom of your screen to the enemy.
Health & Names	Dynamic health bars, display names, and distance tracking.
No Smoke	Event-driven smoke grenade removal (0% performance impact).
🛡️ Misc & Movement
Feature	Description
Deep Anti-Flash	Scans Lighting and 
PlayerGui
 to instantly wipe flashbang effects.
Native Bhop	Hold Space to automatically jump upon landing.
Unload Script	Press RightShift to cleanly remove all hooks and UI without restarting.
⚙️ Technical Architecture (Why BWX is Different)
Position Decoupling (
__newindex
):
The __newindex hook intercepts camera CFrame updates. When you shoot, it strips the game's rotational recoil but preserves the positional vector. This allows you to walk, jump, and aim while the recoil is completely neutralized.

Safe Replication:
We do not hook the weapon modules directly. We only intercept the bullet trajectory and camera matrix. This ensures the server never rejects your buy or shoot actions.

Event-Driven Performance:
World modifications (like Anti-Flash and No Smoke) are handled via DescendantAdded events rather than RenderStepped loops, guaranteeing a locked 60+ FPS.

📜 Usage
Launch Bloxstrike on Roblox.

Open your premium executor (Wave / AWP).

Execute the loadstring provided above.

Press K to toggle the UI.

Keybinds
Key	Action
K	Toggle Menu
LMB (Hold)	Trigger Aimlock & No Recoil
Space (Hold)	Auto Bunnyhop
RightShift	Unload Script
📝 Changelog
v6.1 (Current) - Performance Fix. Fixed No Smoke FPS drop by switching to Event-Driven. Added Unload keybind.

v6.0 - Perfect Lock. Fixed horizontal recoil. True No Recoil via Position Decoupling.

v5.6 - Fixed Aimlock conflict with camera lock.

v5.0 - Complete rewrite for stable hooks.

v4.0 - Introduced Silent Aim & Instant ESP.

<div align="center"> <i>Built for personal use. Use at your own risk.</i> </div> ```

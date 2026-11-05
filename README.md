<div align="center">

# ⚡ BWX // Bloxstrike Utility Suite

**High-Performance Client Automation & Combat Engine for Roblox Bloxstrike**

[![Luau](https://img.shields.io/badge/Language-Luau-00A2FF?style=for-the-badge&logo=lua)](https://luau-lang.org/)
[![Game](https://img.shields.io/badge/Roblox-Bloxstrike-E02424?style=for-the-badge&logo=roblox)](https://www.roblox.com/games/7633926880)
[![Status](https://img.shields.io/badge/Status-Undetected%20%2F%20Operational-50E696?style=for-the-badge)]()
[![Platform](https://img.shields.io/badge/Platform-Windows%20%2F%20Xeno-18181B?style=for-the-badge)]()

<br/>

</div>

---

## 🚀 Quick Execution (Xeno / Universal)

Salin one-liner di bawah ini dan paste langsung ke executor Anda (Xeno, Wave, Solara, etc.):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/bwx330-dev/bwx-bloxstrike/main/bwx-bloxstrike.lua"))()
```

---

## 🎯 Fitur Utama

### 🔫 1. Combat & Target Acquisition
* **Silent Aim:** Intersepsi metatable raycast (`Workspace.Raycast` dan `FindPartOnRayWithIgnoreList`) langsung mengarahkan vektor tembakan ke target tanpa mengubah arah pandang kamera asli.
* **Camera Aim Assist:** Interpolasi `CFrame.lookAt` dengan pengaturan *smoothness* responsif untuk tracking halus saat menekan `MouseButton2`.
* **Dynamic FOV Circle:** Visualisasi radius target dengan warna dan ketebalan yang dapat dikustomisasi.
* **Bone Selection:** Opsi prioritas penargetan (`Head`, `UpperTorso`, atau `HumanoidRootPart`).
* **Team & Visibility Check:** Memfilter rekan satu tim (CT/T) dan mengabaikan target di balik tembok tebal.

### 👁️ 2. Visuals & Spatial ESP (Drawing API)
* **2D Bounding Box ESP:** Kalkulasi aspect ratio dinamis dari proyeksi 3D ke 2D viewport.
* **Health Bar & Percentage:** Bar status darah real-time dengan gradasi warna HSV (Hijau ➔ Kuning ➔ Merah).
* **Distance & Player Nametags:** Menampilkan jarak meter dan display name target secara akurat.
* **Tracers / Snaplines:** Garis pelacak asal layar (Bottom / Center) menuju posisi kaki musuh.
* **C4 Objective Tracker:** Mendeteksi lokasi bom aktif di seluruh map lengkap dengan indikator jarak.

### ⚙️ 3. Weapon Modifications
* **No Recoil:** Meredam getaran kamera (`camera punch`) dan kalkulasi recoil recoil-spring.
* **No Spread:** Menjaga lintasan peluru tetap lurus pada titik tengah crosshair.
* **Anti-Flashbang:** Otomatis menghapus visual blur dan overlay putih `Flash/Blind` pada `PlayerGui` dan `Lighting`.

### 🏃 4. Movement Mechanics
* **Auto-Bunnyhop (Bhop):** Deteksi kontak material lantai (`FloorMaterial ~= Air`) setiap frame untuk melompat seketika saat tombol `Space` ditahan tanpa kehilangan kecepatan momentum.

---

## ⌨️ Kontrol & Keybinds

| Tombol | Fungsi |
| :--- | :--- |
| **`Insert`** atau **`Right Shift`** | Membuka / Menutup menu antarmuka (Toggle UI) |
| **`Right Click (Hold)`** | Mengaktifkan Aim Assist tracking |
| **`Space (Hold)`** | Melakukan auto-bunnyhop terus menerus |

---

## 🛠️ Arsitektur & Teknologi

* **Runtime:** Luau JIT Compatibility Layer.
* **Rendering Engine:** Core Drawing Library (Zero Part-Lag & No Geometry Leak).
* **Hooking Vector:** `hookmetamethod(game, "__namecall")` & `hookfunction(workspace.Raycast)`.
* **Memory Management:** Auto-destructor lifecycle (`environment.BWXUnload`) untuk mencegah memory leak saat inject ulang.

---

<div align="center">
<sub>Built & Maintained by <a href="https://github.com/bwx330-dev">bwx330-dev</a></sub>
</div>

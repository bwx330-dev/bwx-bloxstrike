--[[
    ⚡ BWX // Bloxstrike Utility Suite (v3.11 Radar & Auto Reload Edition)
    Optimized for Xeno & Modern Executors
    Target: Roblox Bloxstrike (7633926880)

    Architectural Updates in v3.11:
      NEW: Auto Reload
        - Monitors equipped Tool ammo (Attributes/Values).
        - Simulates 'R' keypress automatically when ammo hits 0.
      NEW: Player Radar / Minimap
        - Drawing-based 2D Radar in the top-left corner.
        - Renders enemy blips relative to the LocalPlayer's Camera.
        - Clamped to radar bounds, rotates with camera.
      PRESERVED CORE ARCHITECTURE:
        - Safe CameraHook No Recoil (Zero replication stall).
        - Non-invasive property/attribute overwrite No Spread.
        - LMB Aimlock (MouseButton1) with smooth 0.22 tracking.
        - Position Caching ESP with 1-second grace period.
        - Head-only Hitbox Expander with safe memory restoration.
        - Multi-tier team normalization and FFA check.
        - Robust dual-target dead check (IsModelDead).
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end
if env.CybrionUnload then pcall(env.CybrionUnload) end
if env.BloxStrikeUnload then pcall(env.BloxStrikeUnload) end

local Config = {
    Combat = {
        AimLock = true,
        AimLockStrength = 0.22,
        SilentAim = true,
        HitboxSize = 8,
        HitPart = "Head",
        FOV = 130,
        VisibleCheck = false,
        TeamCheck = true,
        ShowFOV = true,
        FOVColor = Color3.fromRGB(50, 230, 150)
    },
    Visuals = {
        Enabled = true,
        TeamCheck = true,
        BoxESP = true,
        EnemyColor = Color3.fromRGB(245, 75, 75),
        TeamColor = Color3.fromRGB(65, 150, 255),
        Tracers = false,
        TracerOrigin = "Bottom",
        NameESP = true,
        HealthBar = true,
        DistanceESP = true,
        MaxDistance = 5000,
        C4Tracker = true,
        C4Color = Color3.fromRGB(250, 195, 60),
        Radar = true,        -- NEW
        RadarSize = 120,     -- NEW
        RadarZoom = 0.5      -- NEW
    },
    WeaponMods = {
        NoRecoil = true,
        NoSpread = true,
        AntiFlash = true,
        AutoReload = true    -- NEW
    },
    Movement = {
        Bhop = true
    },
    UI = {
        MenuOpen = false
    }
}

local Runtime = {
    Active = true,
    Target = nil,
    TargetPart = nil,
    DrawingPool = {},
    OriginalSizes = {},
    CachedPositions = {},
    FOVDrawing = nil,
    C4Drawing = nil,
    NoticeDrawing = nil,
    NoticeStart = os.clock(),
    Connections = {},
    Hooks = {},
    RecoilHookInstalled = false,
    LastHookCheck = 0,
    LastC4Check = 0,
    CachedC4 = nil,
    LastReloadTime = 0, -- NEW
    RadarBg = nil,      -- NEW
    RadarBorder = nil,  -- NEW
    RadarBlips = {}     -- NEW
}

local WallParams = RaycastParams.new()
WallParams.FilterType = Enum.RaycastFilterType.Exclude
WallParams.IgnoreWater = true

-- FOV Circle
Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5
Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.75
Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

-- Radar Setup
Runtime.RadarBg = Drawing.new("Circle")
Runtime.RadarBg.Filled = true
Runtime.RadarBg.Color = Color3.fromRGB(15, 17, 19)
Runtime.RadarBg.Transparency = 0.6
Runtime.RadarBg.NumSides = 32
Runtime.RadarBg.Visible = false

Runtime.RadarBorder = Drawing.new("Circle")
Runtime.RadarBorder.Filled = false
Runtime.RadarBorder.Color = Color3.fromRGB(50, 230, 150)
Runtime.RadarBorder.Thickness = 1.5
Runtime.RadarBorder.NumSides = 32
Runtime.RadarBorder.Visible = false

-- C4 Text
Runtime.C4Drawing = Drawing.new("Text")
Runtime.C4Drawing.Size = 13
Runtime.C4Drawing.Center = true
Runtime.C4Drawing.Outline = true
Runtime.C4Drawing.Color = Config.Visuals.C4Color
Runtime.C4Drawing.Visible = false

-- Banner
Runtime.NoticeDrawing = Drawing.new("Text")
Runtime.NoticeDrawing.Size = 14
Runtime.NoticeDrawing.Center = true
Runtime.NoticeDrawing.Outline = true
Runtime.NoticeDrawing.Color = Color3.fromRGB(50, 230, 150)
Runtime.NoticeDrawing.Position = Vector2.new(Camera.ViewportSize.X / 2, 40)
Runtime.NoticeDrawing.Text = "⚡ BWX BLOXSTRIKE READY [Tekan K / Insert untuk Menu]"
Runtime.NoticeDrawing.Visible = true

-- =========================================================================
-- SAFE HOOKS (No Recoil & No Spread)
-- =========================================================================
local function SetupNoRecoil()
    if Runtime.RecoilHookInstalled then return end
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local camModuleScript = controllers and controllers:FindFirstChild("CameraController")
    
    if camModuleScript and camModuleScript:IsA("ModuleScript") then
        local ok, camModule = pcall(require, camModuleScript)
        if ok and type(camModule) == "table" then
            if type(camModule.weaponKick) == "function" and not Runtime.Hooks["weaponKick"] then
                local oldKick = camModule.weaponKick
                camModule.weaponKick = function(...)
                    local result = oldKick(...)
                    if Config.WeaponMods.NoRecoil and result then
                        if typeof(result) == "CFrame" then return CFrame.new(result.Position)
                        elseif typeof(result) == "Vector3" then return Vector3.zero end
                    end
                    return result
                end
                Runtime.Hooks["weaponKick"] = function() camModule.weaponKick = oldKick end
            end

            if type(camModule.getWeaponKickRotation) == "function" and not Runtime.Hooks["getWeaponKickRotation"] then
                local oldRot = camModule.getWeaponKickRotation
                camModule.getWeaponKickRotation = function(...)
                    local result = oldRot(...)
                    if Config.WeaponMods.NoRecoil and result then
                        if typeof(result) == "CFrame" then return CFrame.new()
                        elseif typeof(result) == "Vector3" then return Vector3.zero end
                    end
                    return result
                end
                Runtime.Hooks["getWeaponKickRotation"] = function() camModule.getWeaponKickRotation = oldRot end
            end
            Runtime.RecoilHookInstalled = true
        end
    end
end
pcall(SetupNoRecoil)

local function ApplyNoSpread()
    if not Config.WeaponMods.NoSpread then return end
    local myChar = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
    if myChar then
        local tool = myChar:FindFirstChildOfClass("Tool")
        if tool then
            for _, attr in ipairs({"Spread", "BaseSpread", "MinSpread", "MaxSpread", "CurrentSpread", "Inaccuracy", "WeaponSpread"}) do
                if tool:GetAttribute(attr) ~= nil and tool:GetAttribute(attr) ~= 0 then pcall(function() tool:SetAttribute(attr, 0) end) end
            end
            for _, name in ipairs({"Spread", "BaseSpread", "MinSpread", "MaxSpread", "Inaccuracy"}) do
                local val = tool:FindFirstChild(name, true)
                if val and (val:IsA("NumberValue") or val:IsA("IntValue")) and val.Value ~= 0 then pcall(function() val.Value = 0 end) end
            end
        end
        for _, attr in ipairs({"Spread", "BaseSpread", "MinSpread", "MaxSpread", "Inaccuracy"}) do
            if myChar:GetAttribute(attr) ~= nil and myChar:GetAttribute(attr) ~= 0 then pcall(function() myChar:SetAttribute(attr, 0) end) end
            if LocalPlayer:GetAttribute(attr) ~= nil and LocalPlayer:GetAttribute(attr) ~= 0 then pcall(function() LocalPlayer:SetAttribute(attr, 0) end) end
        end
    end
end

local function ApplyAutoReload()
    if not Config.WeaponMods.AutoReload then return end
    local now = os.clock()
    if now - Runtime.LastReloadTime < 1.0 then return end -- Cooldown

    local myChar = LocalPlayer.Character
    if not myChar then return end
    local tool = myChar:FindFirstChildOfClass("Tool")
    if not tool then return end

    local ammo = tool:GetAttribute("Ammo") or tool:GetAttribute("CurrentAmmo") or tool:GetAttribute("Mag")
    local ammoVal = tool:FindFirstChild("Ammo") or tool:FindFirstChild("CurrentAmmo") or tool:FindFirstChild("Mag")
    if ammoVal and ammoVal:IsA("ValueBase") then ammo = ammoVal.Value end

    if tonumber(ammo) == 0 then
        Runtime.LastReloadTime = now
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
    end
end

local function NormalizeTeam(val)
    if val == nil then return nil end
    local s = tostring(val):lower()
    if s == "1" or s == "ct" or s:find("counter") or s:find("blue") then return "CT"
    elseif s == "2" or s == "t" or s:find("terror") or s:find("red") or s:find("orange") then return "T" end
    return s
end

local function GetEntityTeam(model, player)
    if model then
        local mTeam = model:GetAttribute("Team") or model:GetAttribute("TeamId") or model:GetAttribute("TeamName") or model:GetAttribute("Role") or model:GetAttribute("TeamColor")
        local norm = NormalizeTeam(mTeam); if norm then return norm end
    end
    if player then
        if player.Team then local norm = NormalizeTeam(player.Team.Name); if norm then return norm end end
        local pTeam = player:GetAttribute("Team") or player:GetAttribute("TeamId") or player:GetAttribute("TeamName") or player:GetAttribute("Role") or player:GetAttribute("TeamColor")
        local norm = NormalizeTeam(pTeam); if norm then return norm end
        if player.TeamColor then
            local tc = tostring(player.TeamColor):lower()
            if tc:find("blue") or tc:find("cobalt") or tc:find("cyan") then return "CT" end
            if tc:find("red") or tc:find("orange") or tc:find("yellow") then return "T" end
        end
    end
    if model then
        local look = model:GetAttribute("CharacterName")
        if look then
            local ctLook = Workspace:GetAttribute("CTCharacter"); local tLook = Workspace:GetAttribute("TCharacter")
            if ctLook and look == ctLook then return "CT" end; if tLook and look == tLook then return "T" end
            local lookLower = tostring(look):lower()
            if lookLower:find("ct") or lookLower:find("counter") or lookLower:find("swat") or lookLower:find("sas") or lookLower:find("seal") or lookLower:find("fbi") or lookLower:find("gsg") then return "CT" end
            if lookLower:find("terror") or lookLower:find("phoenix") or lookLower:find("anarchist") or lookLower:find("balkan") or lookLower:find("leet") or lookLower:find("separatist") or lookLower:find("pirate") then return "T" end
        end
    end
    return nil
end

local function IsTeammate(model, player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer or (model and model.Name == LocalPlayer.Name) then return true end
    local gm = tostring(Workspace:GetAttribute("Gamemode") or ""):lower()
    if gm:find("deathmatch") or gm:find("ffa") then return false end
    local myChar = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
    if not myChar then return false end
    local myTeam = GetEntityTeam(myChar, LocalPlayer); if not myTeam then return false end
    local targetTeam = GetEntityTeam(model, player); if not targetTeam then return false end
    return myTeam == targetTeam
end

local function GetOrCreateDrawing(id)
    local draw = Runtime.DrawingPool[id]
    if not draw then
        draw = { BoxOutline = Drawing.new("Square"), Box = Drawing.new("Square"), HealthOutline = Drawing.new("Line"), Health = Drawing.new("Line"), Name = Drawing.new("Text"), Distance = Drawing.new("Text"), Tracer = Drawing.new("Line") }
        draw.BoxOutline.Thickness = 3; draw.BoxOutline.Filled = false; draw.BoxOutline.Color = Color3.new(0, 0, 0); draw.BoxOutline.Transparency = 0.8; draw.BoxOutline.Visible = false
        draw.Box.Thickness = 1; draw.Box.Filled = false; draw.Box.Transparency = 1; draw.Box.Visible = false
        draw.HealthOutline.Thickness = 3; draw.HealthOutline.Color = Color3.new(0, 0, 0); draw.HealthOutline.Visible = false
        draw.Health.Thickness = 1; draw.Health.Visible = false
        draw.Name.Size = 13; draw.Name.Center = true; draw.Name.Outline = true; draw.Name.Color = Color3.fromRGB(240, 240, 240); draw.Name.Visible = false
        draw.Distance.Size = 11; draw.Distance.Center = true; draw.Distance.Outline = true; draw.Distance.Color = Color3.fromRGB(180, 180, 180); draw.Distance.Visible = false
        draw.Tracer.Thickness = 1; draw.Tracer.Transparency = 0.7; draw.Tracer.Visible = false
        Runtime.DrawingPool[id] = draw
    end
    return draw
end

local function HideDrawing(draw)
    if draw.BoxOutline.Visible then draw.BoxOutline.Visible = false end
    if draw.Box.Visible then draw.Box.Visible = false end
    if draw.HealthOutline.Visible then draw.HealthOutline.Visible = false end
    if draw.Health.Visible then draw.Health.Visible = false end
    if draw.Name.Visible then draw.Name.Visible = false end
    if draw.Distance.Visible then draw.Distance.Visible = false end
    if draw.Tracer.Visible then draw.Tracer.Visible = false end
end

local function DestroyDrawing(draw)
    for _, item in pairs(draw) do pcall(function() item.Visible = false; item:Remove() end) end
end

local function LocateC4()
    local now = os.clock()
    if now - Runtime.LastC4Check > 1.0 then
        Runtime.LastC4Check = now
        local c4 = Workspace:FindFirstChild("C4", true) or Workspace:FindFirstChild("Bomb", true) or Workspace:FindFirstChild("PlantedC4", true)
        if c4 then
            if c4:IsA("BasePart") then Runtime.CachedC4 = c4
            elseif c4:IsA("Model") then Runtime.CachedC4 = c4.PrimaryPart or c4:FindFirstChildWhichIsA("BasePart") end
        else Runtime.CachedC4 = nil end
    end
    return Runtime.CachedC4
end

local function IsModelDead(model, player)
    if model then
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        local mDead = model:GetAttribute("Dead") or model:GetAttribute("IsDead")
        if mDead == true or tostring(mDead) == "true" then return true end
        local hp = tonumber(model:GetAttribute("Health")); if hp and hp <= 0 then return true end
    end
    if player then
        local pDead = player:GetAttribute("Dead") or player:GetAttribute("IsDead")
        if pDead == true or tostring(pDead) == "true" then return true end
        local hp = tonumber(player:GetAttribute("Health")); if hp and hp <= 0 then return true end
    end
    return false
end

local function ApplyHitbox(model)
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        if not Runtime.OriginalSizes[head] then
            Runtime.OriginalSizes[head] = { Part = head, Model = model, Size = head.Size, Transparency = head.Transparency, CanCollide = head.CanCollide }
        end
        local s = Config.Combat.HitboxSize
        head.Size = Vector3.new(s, s, s); head.Transparency = 0.65; head.CanCollide = false
    end
end

local function ResetAllHitboxes()
    for head, data in pairs(Runtime.OriginalSizes) do
        if head and head.Parent then pcall(function() head.Size = data.Size; head.Transparency = data.Transparency; head.CanCollide = data.CanCollide end) end
    end
    table.clear(Runtime.OriginalSizes)
end

local function SetupAntiFlash()
    local function MuteFlash(child)
        if Config.WeaponMods.AntiFlash and child:IsA("BlurEffect") and child.Name:lower():find("flash") then
            child.Size = 0
            child:GetPropertyChangedSignal("Size"):Connect(function() if Config.WeaponMods.AntiFlash and child.Size > 0 then child.Size = 0 end end)
        end
    end
    for _, obj in ipairs(Lighting:GetChildren()) do MuteFlash(obj) end
    table.insert(Runtime.Connections, Lighting.ChildAdded:Connect(MuteFlash))
end
pcall(SetupAntiFlash)

local function GuardMatchUI()
    local chars = Workspace:FindFirstChild("Characters")
    local myChar = chars and chars:FindFirstChild(LocalPlayer.Name)
    if myChar and not IsModelDead(myChar, LocalPlayer) then
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pGui then
            local menu = pGui:FindFirstChild("Menu") or pGui:FindFirstChild("MainMenu")
            if menu and menu:IsA("ScreenGui") and menu.Enabled then
                menu.Enabled = false
                if not Config.UI.MenuOpen then pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end) end
            end
        end
    end
end

-- MASTER RENDER LOOP
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    GuardMatchUI()
    ApplyNoSpread()
    ApplyAutoReload()

    local now = os.clock()
    if now - Runtime.LastHookCheck > 2.0 then
        Runtime.LastHookCheck = now
        if not Runtime.RecoilHookInstalled then pcall(SetupNoRecoil) end
    end

    if Runtime.NoticeDrawing and Runtime.NoticeDrawing.Visible then
        if now - Runtime.NoticeStart > 5.0 then Runtime.NoticeDrawing.Visible = false end
    end

    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = Camera.CFrame.Position
    local visualsOn = Config.Visuals.Enabled
    local maxDist = Config.Visuals.MaxDistance
    local fov = Config.Combat.FOV

    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center; Runtime.FOVDrawing.Radius = fov; Runtime.FOVDrawing.Color = Config.Combat.FOVColor; Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    -- RADAR SETUP
    local radarCenter = Vector2.new(100, 100 + 36) -- Top-left, avoiding Roblox topbar
    local radarRadius = Config.Visuals.RadarSize / 2
    if Config.Visuals.Radar then
        Runtime.RadarBg.Position = radarCenter
        Runtime.RadarBg.Radius = radarRadius
        Runtime.RadarBg.Visible = true
        
        Runtime.RadarBorder.Position = radarCenter
        Runtime.RadarBorder.Radius = radarRadius
        Runtime.RadarBorder.Visible = true
    else
        Runtime.RadarBg.Visible = false
        Runtime.RadarBorder.Visible = false
    end

    if not Config.Combat.SilentAim and next(Runtime.OriginalSizes) then ResetAllHitboxes() end

    local activeIds = {}
    local bestCandidate = nil
    local bestScreenDist = fov
    local bestHitPart = nil

    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local player = Players:GetPlayerFromCharacter(model)
                local id = model.Name
                if not IsModelDead(model, player) then
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    local head = model:FindFirstChild("Head")
                    if root and head then
                        activeIds[id] = true
                        local isTeam = IsTeammate(model, player)
                        local rootPos = root.Position
                        local dist = (rootPos - camPos).Magnitude
                        local hp = tonumber(model:GetAttribute("Health")) or (player and tonumber(player:GetAttribute("Health"))) or 100
                        local maxHp = tonumber(model:GetAttribute("MaxHealth")) or 100
                        local displayName = (player and player.DisplayName) or model.Name

                        Runtime.CachedPositions[id] = { Position = rootPos, LastSeen = now, Team = isTeam, DisplayName = displayName, Player = player, Health = hp, MaxHealth = maxHp }
                        if Config.Combat.SilentAim and not isTeam then ApplyHitbox(model) end

                        -- RADAR DRAWING
                        if Config.Visuals.Radar and not isTeam and dist <= maxDist then
                            local relative = Camera.CFrame:PointToObjectSpace(rootPos)
                            local rx = radarCenter.X + (relative.X * Config.Visuals.RadarZoom)
                            local ry = radarCenter.Y + (relative.Z * Config.Visuals.RadarZoom)
                            
                            -- Clamp to circle
                            local distToCenter = (Vector2.new(rx, ry) - radarCenter).Magnitude
                            if distToCenter > radarRadius then
                                local dir = (Vector2.new(rx, ry) - radarCenter).Unit
                                rx = radarCenter.X + dir.X * radarRadius
                                ry = radarCenter.Y + dir.Y * radarRadius
                            end

                            if not Runtime.RadarBlips[id] then
                                Runtime.RadarBlips[id] = Drawing.new("Circle")
                                Runtime.RadarBlips[id].Radius = 3
                                Runtime.RadarBlips[id].Filled = true
                                Runtime.RadarBlips[id].NumSides = 8
                            end
                            local blip = Runtime.RadarBlips[id]
                            blip.Position = Vector2.new(rx, ry)
                            blip.Color = Config.Visuals.EnemyColor
                            blip.Visible = true
                        elseif Runtime.RadarBlips[id] then
                            Runtime.RadarBlips[id].Visible = false
                        end

                        local draw = GetOrCreateDrawing(id)
                        if visualsOn and not (Config.Visuals.TeamCheck and isTeam) and dist <= maxDist then
                            local topPos, topOn = Camera:WorldToViewportPoint(rootPos + Vector3.new(0, 3.0, 0))
                            local botPos, botOn = Camera:WorldToViewportPoint(rootPos - Vector3.new(0, 3.5, 0))
                            if topPos.Z > 0 and botPos.Z > 0 then
                                local height = math.abs(botPos.Y - topPos.Y)
                                local width = height * 0.58
                                local boxPos = Vector2.new(topPos.X - width / 2, topPos.Y)
                                local onScreen = (boxPos.X + width >= 0) and (boxPos.X <= vp.X) and (botPos.Y >= 0) and (topPos.Y <= vp.Y)
                                if onScreen then
                                    local col = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor
                                    if Config.Visuals.BoxESP then
                                        draw.BoxOutline.Size = Vector2.new(width, height); draw.BoxOutline.Position = boxPos; draw.BoxOutline.Visible = true
                                        draw.Box.Size = Vector2.new(width, height); draw.Box.Position = boxPos; draw.Box.Color = col; draw.Box.Visible = true
                                    else draw.BoxOutline.Visible = false; draw.Box.Visible = false end
                                    if Config.Visuals.HealthBar then
                                        local ratio = math.clamp(hp / maxHp, 0, 1); local barHeight = height * ratio; local barX = boxPos.X - 5
                                        draw.HealthOutline.From = Vector2.new(barX, boxPos.Y); draw.HealthOutline.To = Vector2.new(barX, boxPos.Y + height); draw.HealthOutline.Visible = true
                                        draw.Health.From = Vector2.new(barX, boxPos.Y + height); draw.Health.To = Vector2.new(barX, boxPos.Y + height - barHeight); draw.Health.Color = Color3.fromHSV(ratio * 0.32, 1, 1); draw.Health.Visible = true
                                    else draw.HealthOutline.Visible = false; draw.Health.Visible = false end
                                    if Config.Visuals.NameESP then
                                        draw.Name.Text = displayName; draw.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); draw.Name.Visible = true
                                    else draw.Name.Visible = false end
                                    if Config.Visuals.DistanceESP then
                                        draw.Distance.Text = string.format("[%dm]", math.floor(dist)); draw.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); draw.Distance.Visible = true
                                    else draw.Distance.Visible = false end
                                    if Config.Visuals.Tracers then
                                        local origin = (Config.Visuals.TracerOrigin == "Bottom") and Vector2.new(vp.X / 2, vp.Y) or center
                                        draw.Tracer.From = origin; draw.Tracer.To = Vector2.new(topPos.X, boxPos.Y + height); draw.Tracer.Color = col; draw.Tracer.Visible = true
                                    else draw.Tracer.Visible = false end
                                else HideDrawing(draw) end
                            else HideDrawing(draw) end
                        else HideDrawing(draw) end

                        if not isTeam then
                            local targetPart = (Config.Combat.HitPart == "Head" and head) or (Config.Combat.HitPart == "UpperTorso" and (model:FindFirstChild("UpperTorso") or root)) or root
                            local partScreen, partOn = Camera:WorldToViewportPoint(targetPart.Position)
                            if partOn and partScreen.Z > 0 then
                                local sDist = (Vector2.new(partScreen.X, partScreen.Y) - center).Magnitude
                                if sDist < bestScreenDist then bestScreenDist = sDist; bestCandidate = model; bestHitPart = targetPart end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Cleanup Radar Blips for lost players
    for id, blip in pairs(Runtime.RadarBlips) do
        if not activeIds[id] then
            blip:Remove()
            Runtime.RadarBlips[id] = nil
        end
    end

    -- Position Caching ESP
    if visualsOn then
        for id, cached in pairs(Runtime.CachedPositions) do
            if not activeIds[id] then
                if cached.Player and IsModelDead(nil, cached.Player) then Runtime.CachedPositions[id] = nil
                else
                    local elapsed = now - cached.LastSeen
                    if elapsed <= 1.0 then
                        activeIds[id] = true
                        local isTeam = cached.Team
                        if not (Config.Visuals.TeamCheck and isTeam) then
                            local rootPos = cached.Position; local dist = (rootPos - camPos).Magnitude
                            if dist <= maxDist then
                                local topPos, topOn = Camera:WorldToViewportPoint(rootPos + Vector3.new(0, 3.0, 0))
                                local botPos, botOn = Camera:WorldToViewportPoint(rootPos - Vector3.new(0, 3.5, 0))
                                if topPos.Z > 0 and botPos.Z > 0 then
                                    local height = math.abs(botPos.Y - topPos.Y); local width = height * 0.58
                                    local boxPos = Vector2.new(topPos.X - width / 2, topPos.Y)
                                    local onScreen = (boxPos.X + width >= 0) and (boxPos.X <= vp.X) and (botPos.Y >= 0) and (topPos.Y <= vp.Y)
                                    local draw = GetOrCreateDrawing(id)
                                    if onScreen then
                                        local col = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor
                                        if Config.Visuals.BoxESP then
                                            draw.BoxOutline.Size = Vector2.new(width, height); draw.BoxOutline.Position = boxPos; draw.BoxOutline.Visible = true
                                            draw.Box.Size = Vector2.new(width, height); draw.Box.Position = boxPos; draw.Box.Color = col; draw.Box.Visible = true
                                        else draw.BoxOutline.Visible = false; draw.Box.Visible = false end
                                        if Config.Visuals.HealthBar then
                                            local ratio = math.clamp(cached.Health / cached.MaxHealth, 0, 1); local barHeight = height * ratio; local barX = boxPos.X - 5
                                            draw.HealthOutline.From = Vector2.new(barX, boxPos.Y); draw.HealthOutline.To = Vector2.new(barX, boxPos.Y + height); draw.HealthOutline.Visible = true
                                            draw.Health.From = Vector2.new(barX, boxPos.Y + height); draw.Health.To = Vector2.new(barX, boxPos.Y + height - barHeight); draw.Health.Color = Color3.fromHSV(ratio * 0.32, 1, 1); draw.Health.Visible = true
                                        else draw.HealthOutline.Visible = false; draw.Health.Visible = false end
                                        if Config.Visuals.NameESP then draw.Name.Text = cached.DisplayName; draw.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); draw.Name.Visible = true else draw.Name.Visible = false end
                                        if Config.Visuals.DistanceESP then draw.Distance.Text = string.format("[%dm]", math.floor(dist)); draw.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); draw.Distance.Visible = true else draw.Distance.Visible = false end
                                        if Config.Visuals.Tracers then
                                            local origin = (Config.Visuals.TracerOrigin == "Bottom") and Vector2.new(vp.X / 2, vp.Y) or center
                                            draw.Tracer.From = origin; draw.Tracer.To = Vector2.new(topPos.X, boxPos.Y + height); draw.Tracer.Color = col; draw.Tracer.Visible = true
                                        else draw.Tracer.Visible = false end
                                    else
                                        local d = Runtime.DrawingPool[id]; if d then HideDrawing(d) end
                                    end
                                else
                                    local d = Runtime.DrawingPool[id]; if d then HideDrawing(d) end
                                end
                            else
                                local d = Runtime.DrawingPool[id]; if d then HideDrawing(d) end
                            end
                        else
                            local d = Runtime.DrawingPool[id]; if d then HideDrawing(d) end
                        end
                    else
                        Runtime.CachedPositions[id] = nil
                    end
                end
            end
        end
    end

    for id, draw in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then DestroyDrawing(draw); Runtime.DrawingPool[id] = nil end
    end

    for head, data in pairs(Runtime.OriginalSizes) do
        local model = data.Model
        if not head.Parent or not head:IsDescendantOf(Workspace) or (model and (not model:IsDescendantOf(Workspace) or IsModelDead(model, Players:GetPlayerFromCharacter(model)))) then
            pcall(function() head.Size = data.Size; head.Transparency = data.Transparency; head.CanCollide = data.CanCollide end)
            Runtime.OriginalSizes[head] = nil
        end
    end

    if bestHitPart and Config.Combat.VisibleCheck then
        local myChar = chars and chars:FindFirstChild(LocalPlayer.Name)
        local filterList = {Camera}; if myChar then table.insert(filterList, myChar) end
        WallParams.FilterDescendantsInstances = filterList
        local dir = bestHitPart.Position - camPos
        local hit = Workspace:Raycast(camPos, dir, WallParams)
        if hit and not hit.Instance:IsDescendantOf(bestCandidate) then bestHitPart = nil; bestCandidate = nil end
    end

    Runtime.Target = bestCandidate
    Runtime.TargetPart = bestHitPart

    if visualsOn and Config.Visuals.C4Tracker then
        local c4 = LocateC4()
        if c4 and c4.Parent then
            local c4Screen, onScreen = Camera:WorldToViewportPoint(c4.Position)
            if onScreen and c4Screen.Z > 0 then
                local dist = math.floor((c4.Position - camPos).Magnitude)
                Runtime.C4Drawing.Text = string.format("[ C4 BOMB // %dm ]", dist)
                Runtime.C4Drawing.Position = Vector2.new(c4Screen.X, c4Screen.Y)
                Runtime.C4Drawing.Visible = true
            else Runtime.C4Drawing.Visible = false end
        else Runtime.C4Drawing.Visible = false end
    else Runtime.C4Drawing.Visible = false end

    local isFiring = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    if Config.Combat.AimLock and Runtime.TargetPart and not Config.UI.MenuOpen and not UserInputService:GetFocusedTextBox() then
        if isFiring then
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end) end
            local targetPos = Runtime.TargetPart.Position
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
            if onScreen and screenPos.Z > 0 then
                local delta = Vector2.new(screenPos.X - center.X, screenPos.Y - center.Y)
                if mousemoverel then
                    local sens = Config.Combat.AimLockStrength
                    mousemoverel(delta.X * sens, delta.Y * sens)
                else
                    local currentCF = Camera.CFrame
                    local targetLook = CFrame.lookAt(currentCF.Position, targetPos)
                    Camera.CFrame = currentCF:Lerp(targetLook, Config.Combat.AimLockStrength)
                end
            end
        end
    end

    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if not UserInputService:GetFocusedTextBox() then
            local char = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
        end
    end
end))

local function BuildUI()
    local Theme = {
        Background = Color3.fromRGB(15, 17, 19), Header = Color3.fromRGB(22, 25, 29), Surface = Color3.fromRGB(28, 32, 38),
        Stroke = Color3.fromRGB(45, 52, 62), Accent = Color3.fromRGB(50, 230, 150), Text = Color3.fromRGB(240, 245, 248), Muted = Color3.fromRGB(140, 150, 165)
    }
    local target = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BWX_SuiteUI"; screenGui.ResetOnSpawn = false; screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; screenGui.Enabled = Config.UI.MenuOpen; screenGui.Parent = target
    local main = Instance.new("Frame")
    main.Name = "Main"; main.Size = UDim2.fromOffset(540, 370); main.Position = UDim2.fromScale(0.3, 0.25); main.BackgroundColor3 = Theme.Background; main.BorderSizePixel = 0; main.Active = true; main.Parent = screenGui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = main
    local mainStroke = Instance.new("UIStroke"); mainStroke.Color = Theme.Stroke; mainStroke.Thickness = 1; mainStroke.Parent = main
    local header = Instance.new("Frame")
    header.Name = "Header"; header.Size = UDim2.new(1, 0, 0, 42); header.BackgroundColor3 = Theme.Header; header.BorderSizePixel = 0; header.Parent = main
    local headerCorner = Instance.new("UICorner"); headerCorner.CornerRadius = UDim.new(0, 8); headerCorner.Parent = header
    local headerBottom = Instance.new("Frame"); headerBottom.Size = UDim2.new(1, 0, 0, 8); headerBottom.Position = UDim2.new(0, 0, 1, -8); headerBottom.BackgroundColor3 = Theme.Header; headerBottom.BorderSizePixel = 0; headerBottom.Parent = header
    local title = Instance.new("TextLabel"); title.Text = "⚡ BWX // BLOXSTRIKE"; title.Font = Enum.Font.GothamBold; title.TextSize = 14; title.TextColor3 = Theme.Accent; title.TextXAlignment = Enum.TextXAlignment.Left; title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 14, 0, 0); title.Size = UDim2.new(0.6, 0, 1, 0); title.Parent = header
    local hint = Instance.new("TextLabel"); hint.Text = "Toggle: [K] / [Insert]"; hint.Font = Enum.Font.Gotham; hint.TextSize = 11; hint.TextColor3 = Theme.Muted; hint.TextXAlignment = Enum.TextXAlignment.Right; hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0.4, 0, 0, 0); hint.Size = UDim2.new(0.56, 0, 1, 0); hint.Parent = header
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = input.Position; startPos = main.Position end end)
    UserInputService.InputChanged:Connect(function(input) if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then local delta = input.Position - dragStart; main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    local sidebar = Instance.new("Frame"); sidebar.Size = UDim2.new(0, 130, 1, -42); sidebar.Position = UDim2.new(0, 0, 0, 42); sidebar.BackgroundColor3 = Theme.Header; sidebar.BorderSizePixel = 0; sidebar.Parent = main
    local sidebarLayout = Instance.new("UIListLayout"); sidebarLayout.Padding = UDim.new(0, 4); sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; sidebarLayout.Parent = sidebar
    local sidebarPadding = Instance.new("UIPadding"); sidebarPadding.PaddingTop = UDim.new(0, 8); sidebarPadding.Parent = sidebar
    local container = Instance.new("Frame"); container.Size = UDim2.new(1, -138, 1, -50); container.Position = UDim2.new(0, 134, 0, 46); container.BackgroundTransparency = 1; container.Parent = main
    local pages = {}; local tabs = {"Combat", "Visuals", "Gun Mods", "Movement"}; local activeTab = nil
    for _, name in ipairs(tabs) do
        local page = Instance.new("ScrollingFrame"); page.Name = name; page.Size = UDim2.new(1, 0, 1, 0); page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 3; page.ScrollBarImageColor3 = Theme.Accent; page.CanvasSize = UDim2.new(0, 0, 0, 0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = false; page.Parent = container
        local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 6); layout.Parent = page
        local padding = Instance.new("UIPadding"); padding.PaddingRight = UDim.new(0, 8); padding.PaddingTop = UDim.new(0, 4); padding.Parent = page
        pages[name] = page
    end
    local tabButtons = {}
    local function SwitchTab(tabName)
        for name, page in pairs(pages) do page.Visible = (name == tabName) end
        for name, btn in pairs(tabButtons) do if name == tabName then btn.BackgroundColor3 = Theme.Surface; btn.TextColor3 = Theme.Accent else btn.BackgroundColor3 = Theme.Header; btn.TextColor3 = Theme.Muted end end
        activeTab = tabName
    end
    for _, name in ipairs(tabs) do
        local btn = Instance.new("TextButton"); btn.Size = UDim2.new(1, -12, 0, 32); btn.BackgroundColor3 = Theme.Header; btn.Text = name; btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 12; btn.TextColor3 = Theme.Muted; btn.BorderSizePixel = 0; btn.Parent = sidebar
        local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 6); btnCorner.Parent = btn
        btn.MouseButton1Click:Connect(function() SwitchTab(name) end); tabButtons[name] = btn
    end
    local function CreateToggle(parent, titleText, initialVal, callback)
        local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 36); frame.BackgroundColor3 = Theme.Surface; frame.BorderSizePixel = 0; frame.Parent = parent
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = frame
        local label = Instance.new("TextLabel"); label.Text = titleText; label.Font = Enum.Font.GothamMedium; label.TextSize = 12; label.TextColor3 = Theme.Text; label.TextXAlignment = Enum.TextXAlignment.Left; label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 10, 0, 0); label.Size = UDim2.new(0.7, 0, 1, 0); label.Parent = frame
        local switch = Instance.new("TextButton"); switch.Size = UDim2.new(0, 42, 0, 22); switch.Position = UDim2.new(1, -52, 0.5, -11); switch.BackgroundColor3 = initialVal and Theme.Accent or Theme.Stroke; switch.Text = ""; switch.BorderSizePixel = 0; switch.Parent = frame
        local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = switch
        local dot = Instance.new("Frame"); dot.Size = UDim2.new(0, 16, 0, 16); dot.Position = initialVal and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8); dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255); dot.BorderSizePixel = 0; dot.Parent = switch
        local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
        local current = initialVal
        switch.MouseButton1Click:Connect(function() current = not current; switch.BackgroundColor3 = current and Theme.Accent or Theme.Stroke; dot.Position = current and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8); callback(current) end)
    end
    local function CreateSlider(parent, titleText, min, max, initialVal, suffix, callback)
        local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 48); frame.BackgroundColor3 = Theme.Surface; frame.BorderSizePixel = 0; frame.Parent = parent
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = frame
        local label = Instance.new("TextLabel"); label.Text = titleText; label.Font = Enum.Font.GothamMedium; label.TextSize = 12; label.TextColor3 = Theme.Text; label.TextXAlignment = Enum.TextXAlignment.Left; label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 10, 0, 6); label.Size = UDim2.new(0.6, 0, 0, 16); label.Parent = frame
        local valLabel = Instance.new("TextLabel"); valLabel.Text = tostring(initialVal) .. suffix; valLabel.Font = Enum.Font.GothamBold; valLabel.TextSize = 11; valLabel.TextColor3 = Theme.Accent; valLabel.TextXAlignment = Enum.TextXAlignment.Right; valLabel.BackgroundTransparency = 1; valLabel.Position = UDim2.new(0.6, 0, 0, 6); valLabel.Size = UDim2.new(0.38, 0, 0, 16); valLabel.Parent = frame
        local barBg = Instance.new("TextButton"); barBg.Text = ""; barBg.Size = UDim2.new(1, -20, 0, 6); barBg.Position = UDim2.new(0, 10, 0, 30); barBg.BackgroundColor3 = Theme.Stroke; barBg.BorderSizePixel = 0; barBg.Parent = frame
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = barBg
        local fill = Instance.new("Frame"); local initialRatio = math.clamp((initialVal - min) / (max - min), 0, 1); fill.Size = UDim2.new(initialRatio, 0, 1, 0); fill.BackgroundColor3 = Theme.Accent; fill.BorderSizePixel = 0; fill.Parent = barBg
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill
        local sliding = false
        local function UpdateSlide(x) local ratio = math.clamp((x - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1); local value = math.floor(min + (max - min) * ratio); fill.Size = UDim2.new(ratio, 0, 1, 0); valLabel.Text = tostring(value) .. suffix; callback(value) end
        barBg.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true; UpdateSlide(input.Position.X) end end)
        UserInputService.InputChanged:Connect(function(input) if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then UpdateSlide(input.Position.X) end end)
        UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end end)
    end
    local function CreateDropdown(parent, titleText, options, currentOption, callback)
        local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 36); frame.BackgroundColor3 = Theme.Surface; frame.BorderSizePixel = 0; frame.Parent = parent
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = frame
        local label = Instance.new("TextLabel"); label.Text = titleText; label.Font = Enum.Font.GothamMedium; label.TextSize = 12; label.TextColor3 = Theme.Text; label.TextXAlignment = Enum.TextXAlignment.Left; label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 10, 0, 0); label.Size = UDim2.new(0.5, 0, 1, 0); label.Parent = frame
        local btn = Instance.new("TextButton"); btn.Size = UDim2.new(0, 120, 0, 24); btn.Position = UDim2.new(1, -128, 0.5, -12); btn.BackgroundColor3 = Theme.Header; btn.Text = currentOption .. " ▼"; btn.Font = Enum.Font.GothamBold; btn.TextSize = 11; btn.TextColor3 = Theme.Accent; btn.BorderSizePixel = 0; btn.Parent = frame
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 4); bc.Parent = btn
        local currIndex = 1; for i, opt in ipairs(options) do if opt == currentOption then currIndex = i break end end
        btn.MouseButton1Click:Connect(function() currIndex = currIndex % #options + 1; local nextOpt = options[currIndex]; btn.Text = nextOpt .. " ▼"; callback(nextOpt) end)
    end
    local combatPage = pages["Combat"]
    CreateToggle(combatPage, "Aim Lock (Hold LMB / Fire)", Config.Combat.AimLock, function(v) Config.Combat.AimLock = v end)
    CreateSlider(combatPage, "Aim Lock Smoothness", 5, 100, math.floor(Config.Combat.AimLockStrength * 100), "%", function(v) Config.Combat.AimLockStrength = v / 100 end)
    CreateToggle(combatPage, "Silent Aim (Head Hitbox Expander)", Config.Combat.SilentAim, function(v) Config.Combat.SilentAim = v; if not v then ResetAllHitboxes() end end)
    CreateSlider(combatPage, "Hitbox Size", 3, 16, Config.Combat.HitboxSize, " studs", function(v) Config.Combat.HitboxSize = v end)
    CreateToggle(combatPage, "Show FOV Circle", Config.Combat.ShowFOV, function(v) Config.Combat.ShowFOV = v end)
    CreateSlider(combatPage, "FOV Radius", 30, 400, Config.Combat.FOV, "px", function(v) Config.Combat.FOV = v end)
    CreateDropdown(combatPage, "Target Hit Part", {"Head", "UpperTorso", "HumanoidRootPart"}, Config.Combat.HitPart, function(v) Config.Combat.HitPart = v end)
    CreateToggle(combatPage, "Visibility Check (Wallcheck)", Config.Combat.VisibleCheck, function(v) Config.Combat.VisibleCheck = v end)
    
    local visualsPage = pages["Visuals"]
    CreateToggle(visualsPage, "Master ESP Switch", Config.Visuals.Enabled, function(v) Config.Visuals.Enabled = v end)
    CreateToggle(visualsPage, "Team Check (Filter CT / T)", Config.Visuals.TeamCheck, function(v) Config.Visuals.TeamCheck = v end)
    CreateToggle(visualsPage, "2D Box ESP (Rigid Physics Root)", Config.Visuals.BoxESP, function(v) Config.Visuals.BoxESP = v end)
    CreateToggle(visualsPage, "Health Bar", Config.Visuals.HealthBar, function(v) Config.Visuals.HealthBar = v end)
    CreateToggle(visualsPage, "Player Names", Config.Visuals.NameESP, function(v) Config.Visuals.NameESP = v end)
    CreateToggle(visualsPage, "Distance Tag", Config.Visuals.DistanceESP, function(v) Config.Visuals.DistanceESP = v end)
    CreateToggle(visualsPage, "Snaplines / Tracers", Config.Visuals.Tracers, function(v) Config.Visuals.Tracers = v end)
    CreateToggle(visualsPage, "C4 Bomb Tracker", Config.Visuals.C4Tracker, function(v) Config.Visuals.C4Tracker = v end)
    CreateSlider(visualsPage, "Max ESP Distance", 500, 8000, Config.Visuals.MaxDistance, "m", function(v) Config.Visuals.MaxDistance = v end)
    CreateToggle(visualsPage, "Player Radar (Minimap)", Config.Visuals.Radar, function(v) Config.Visuals.Radar = v end)
    CreateSlider(visualsPage, "Radar Zoom", 1, 10, math.floor(Config.Visuals.RadarZoom * 10), "x", function(v) Config.Visuals.RadarZoom = v / 10 end)

    local modsPage = pages["Gun Mods"]
    CreateToggle(modsPage, "No Recoil (Safe Hook)", Config.WeaponMods.NoRecoil, function(v) Config.WeaponMods.NoRecoil = v end)
    CreateToggle(modsPage, "No Spread (Attribute Overwrite)", Config.WeaponMods.NoSpread, function(v) Config.WeaponMods.NoSpread = v end)
    CreateToggle(modsPage, "Auto Reload", Config.WeaponMods.AutoReload, function(v) Config.WeaponMods.AutoReload = v end)
    CreateToggle(modsPage, "Anti-Flashbang (Instant Blind Wipe)", Config.WeaponMods.AntiFlash, function(v) Config.WeaponMods.AntiFlash = v end)

    local movePage = pages["Movement"]
    CreateToggle(movePage, "Auto Bunnyhop (Bhop)", Config.Movement.Bhop, function(v) Config.Movement.Bhop = v end)
    
    SwitchTab("Combat")
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.Insert) then
            Config.UI.MenuOpen = not Config.UI.MenuOpen; screenGui.Enabled = Config.UI.MenuOpen
            if not Config.UI.MenuOpen then pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end) end
        end
    end)
    return screenGui
end
local GuiInstance = BuildUI()

env.BWXUnload = function()
    Runtime.Active = false
    ResetAllHitboxes(); table.clear(Runtime.CachedPositions)
    for _, conn in ipairs(Runtime.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Runtime.Connections)
    for _, unhook in pairs(Runtime.Hooks) do pcall(unhook) end
    table.clear(Runtime.Hooks)
    if Runtime.FOVDrawing then pcall(function() Runtime.FOVDrawing:Remove() end) end
    if Runtime.C4Drawing then pcall(function() Runtime.C4Drawing:Remove() end) end
    if Runtime.NoticeDrawing then pcall(function() Runtime.NoticeDrawing:Remove() end) end
    if Runtime.RadarBg then pcall(function() Runtime.RadarBg:Remove() end) end
    if Runtime.RadarBorder then pcall(function() Runtime.RadarBorder:Remove() end) end
    for id, blip in pairs(Runtime.RadarBlips) do pcall(function() blip:Remove() end) end
    table.clear(Runtime.RadarBlips)
    for _, draw in pairs(Runtime.DrawingPool) do DestroyDrawing(draw) end
    table.clear(Runtime.DrawingPool)
    if GuiInstance then pcall(function() GuiInstance:Destroy() end) end
    env.BWXUnload = nil; env.CybrionUnload = nil; env.BloxStrikeUnload = nil
end
env.CybrionUnload = env.BWXUnload
env.BloxStrikeUnload = env.BWXUnload

print("[BWX] Suite v3.11 Loaded. Radar & Auto Reload Engine.")

--[[
    ⚡ BWX // Bloxstrike Utility Suite
    Powered by Rayfield Interface Suite (Official GitHub)
    Target: Roblox Bloxstrike (7633926880)
    Architecture:
      - Memory & Controller Recoil Suppression (CameraController Hook)
      - Instantaneous Bullet Cam-Flick & Network Dispatch Restoration (True Silent Aim)
      - Real-Time Direct Entity ESP (Workspace.Characters Live Rigs, Zero Lag)
      - Snappy Hard-Lock Aim Assist
      - Zero Raycast Pollution (Native Engine Ground & Buy-Zone Checks Untouched)
      - Rayfield UI Hub (Toggle with [K])
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

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Global Unload of prior instances
local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end
if env.CybrionUnload then pcall(env.CybrionUnload) end
if env.BloxStrikeUnload then pcall(env.BloxStrikeUnload) end

-- Configuration Table
local Config = {
    Combat = {
        SilentAim = true,
        AimAssist = true,
        AimLockStrength = 0.95, -- Snappy lock (0.1 to 1.0)
        HitPart = "Head",
        FOV = 130,
        HitChance = 100,
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
        MaxDistance = 4500,
        C4Tracker = true,
        C4Color = Color3.fromRGB(250, 195, 60)
    },
    WeaponMods = {
        NoRecoil = true,
        NoSpread = true,
        AntiFlash = true
    },
    Movement = {
        Bhop = true
    }
}

local Runtime = {
    Active = true,
    Target = nil,
    TargetPart = nil,
    DrawingPool = {},
    FOVDrawing = nil,
    C4Drawing = nil,
    Connections = {},
    Hooks = {},
    LastC4Check = 0,
    CachedC4 = nil,
    ViewSaved = nil,
    CombatantsCache = {},
    LastCombatantsUpdate = 0
}

-- Safe hook utility function
local function SafeHook(fn, replacement)
    if type(fn) ~= "function" or not hookfunction then return nil end
    local ok, orig = pcall(hookfunction, fn, replacement)
    if ok and type(orig) == "function" then
        return orig
    end
    return nil
end

-- Shared Raycast Params for Wallcheck (Zero Allocations)
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

-- C4 Objective Text
Runtime.C4Drawing = Drawing.new("Text")
Runtime.C4Drawing.Size = 13
Runtime.C4Drawing.Center = true
Runtime.C4Drawing.Outline = true
Runtime.C4Drawing.Color = Config.Visuals.C4Color
Runtime.C4Drawing.Visible = false

-- Team Resolution (Accurate for Bloxstrike CT vs T)
local function GetEntityTeam(model, player)
    if player and player.Team then
        return player.Team.Name
    end
    if player then
        local attr = player:GetAttribute("Team")
        if attr then return tostring(attr) end
    end
    if model then
        local look = model:GetAttribute("CharacterName")
        if look then
            if look == Workspace:GetAttribute("CTCharacter") then return "Counter-Terrorists" end
            if look == Workspace:GetAttribute("TCharacter") then return "Terrorists" end
        end
    end
    return nil
end

local function IsTeammate(model, player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer or (model and model.Name == LocalPlayer.Name) then return true end

    local myTeam = GetEntityTeam(LocalPlayer.Character, LocalPlayer)
    local targetTeam = GetEntityTeam(model, player)
    if myTeam and targetTeam then
        return myTeam == targetTeam
    end
    return false
end

-- Drawing Allocation Pool (Indexed by unique ID)
local function GetOrCreateDrawing(id)
    local draw = Runtime.DrawingPool[id]
    if not draw then
        draw = {
            BoxOutline = Drawing.new("Square"),
            Box = Drawing.new("Square"),
            HealthOutline = Drawing.new("Line"),
            Health = Drawing.new("Line"),
            Name = Drawing.new("Text"),
            Distance = Drawing.new("Text"),
            Tracer = Drawing.new("Line")
        }

        draw.BoxOutline.Thickness = 3
        draw.BoxOutline.Filled = false
        draw.BoxOutline.Color = Color3.new(0, 0, 0)
        draw.BoxOutline.Transparency = 0.8
        draw.BoxOutline.Visible = false

        draw.Box.Thickness = 1
        draw.Box.Filled = false
        draw.Box.Transparency = 1
        draw.Box.Visible = false

        draw.HealthOutline.Thickness = 3
        draw.HealthOutline.Color = Color3.new(0, 0, 0)
        draw.HealthOutline.Visible = false

        draw.Health.Thickness = 1
        draw.Health.Visible = false

        draw.Name.Size = 13
        draw.Name.Center = true
        draw.Name.Outline = true
        draw.Name.Color = Color3.fromRGB(240, 240, 240)
        draw.Name.Visible = false

        draw.Distance.Size = 11
        draw.Distance.Center = true
        draw.Distance.Outline = true
        draw.Distance.Color = Color3.fromRGB(180, 180, 180)
        draw.Distance.Visible = false

        draw.Tracer.Thickness = 1
        draw.Tracer.Transparency = 0.7
        draw.Tracer.Visible = false

        Runtime.DrawingPool[id] = draw
    end
    return draw
end

local function HideDrawing(draw)
    draw.BoxOutline.Visible = false
    draw.Box.Visible = false
    draw.HealthOutline.Visible = false
    draw.Health.Visible = false
    draw.Name.Visible = false
    draw.Distance.Visible = false
    draw.Tracer.Visible = false
end

local function DestroyDrawing(draw)
    for _, item in pairs(draw) do
        pcall(function()
            item.Visible = false
            item:Remove()
        end)
    end
end

-- Fast C4 Locator
local function LocateC4()
    local now = os.clock()
    if now - Runtime.LastC4Check > 0.8 then
        Runtime.LastC4Check = now
        local found = nil
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name == "C4" or obj.Name == "Bomb" or obj.Name == "PlantedC4" then
                if obj:IsA("BasePart") then
                    found = obj
                    break
                elseif obj:IsA("Model") then
                    found = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                    if found then break end
                end
            end
        end
        Runtime.CachedC4 = found
    end
    return Runtime.CachedC4
end

-- Fast Wallcheck (Single raycast only for candidate)
local function CheckVisible(part, origin)
    if not Config.Combat.VisibleCheck then return true end
    origin = origin or Camera.CFrame.Position
    local dir = part.Position - origin

    local myChar = LocalPlayer.Character or (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name))
    WallParams.FilterDescendantsInstances = {Camera, myChar}
    local hit = Workspace:Raycast(origin, dir, WallParams)
    if hit and hit.Instance:IsDescendantOf(part.Parent) then
        return true
    end
    return hit == nil
end

-- Rate-Limited Entity Caching (Refreshed at 25Hz to eliminate per-frame allocations)
local function UpdateCombatantsCache()
    local now = os.clock()
    if now - Runtime.LastCombatantsUpdate < 0.04 and #Runtime.CombatantsCache > 0 then
        return Runtime.CombatantsCache
    end
    Runtime.LastCombatantsUpdate = now

    local list = {}
    local seen = {}

    -- 1. Scan Bloxstrike Characters folder (Primary real-time rigs)
    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local head = model:FindFirstChild("Head")
                local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                local hum = model:FindFirstChildOfClass("Humanoid")
                local dead = (hum and hum.Health <= 0) or tostring(model:GetAttribute("Dead")) == "true"

                if head and root and not dead then
                    local id = model.Name
                    seen[id] = true
                    table.insert(list, {
                        Id = id,
                        Model = model,
                        Head = head,
                        Root = root,
                        Humanoid = hum,
                        Player = Players:FindFirstChild(id)
                    })
                end
            end
        end
    end

    -- 2. Fallback: Players list (for spectating or non-standard spawns)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not seen[player.Name] then
            local char = player.Character
            if char and char:IsA("Model") then
                local head = char:FindFirstChild("Head")
                local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                local hum = char:FindFirstChildOfClass("Humanoid")
                local dead = (hum and hum.Health <= 0) or tostring(player:GetAttribute("Dead")) == "true" or tostring(char:GetAttribute("Dead")) == "true"

                if head and root and not dead then
                    table.insert(list, {
                        Id = player.Name,
                        Model = char,
                        Head = head,
                        Root = root,
                        Humanoid = hum,
                        Player = player
                    })
                end
            end
        end
    end

    Runtime.CombatantsCache = list
    return list
end

-- Target Selection for Combat
local function SelectTarget(combatants)
    local best = nil
    local bestPart = nil
    local minDistance = Config.Combat.FOV
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, data in ipairs(combatants) do
        if not IsTeammate(data.Model, data.Player) then
            local hitPart = data.Model:FindFirstChild(Config.Combat.HitPart) or data.Head or data.Root
            if hitPart then
                local screenPos, onScreen = Camera:WorldToViewportPoint(hitPart.Position)
                if onScreen and screenPos.Z > 0 then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                    if dist < minDistance then
                        if CheckVisible(hitPart, nil) then
                            minDistance = dist
                            best = data
                            bestPart = hitPart
                        end
                    end
                end
            end
        end
    end

    return best, bestPart
end

-- ==========================================
-- BLOXSTRIKE RECOIL & SILENT AIM ENGINE
-- ==========================================

-- 1. Hook CameraController (Weapon Kick, Recoil, Rotation)
local function HookRecoilController()
    local Controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local CamControllerModule = Controllers and Controllers:FindFirstChild("CameraController")
    if CamControllerModule and CamControllerModule:IsA("ModuleScript") then
        local ok, camModule = pcall(require, CamControllerModule)
        if ok and type(camModule) == "table" then
            if type(camModule.weaponKick) == "function" then
                local origKick
                origKick = SafeHook(camModule.weaponKick, function(...)
                    if Config.WeaponMods.NoRecoil then return end
                    return origKick(...)
                end)
                if origKick then
                    table.insert(Runtime.Hooks, function() pcall(hookfunction, camModule.weaponKick, origKick) end)
                else
                    local old = camModule.weaponKick
                    camModule.weaponKick = function(...)
                        if Config.WeaponMods.NoRecoil then return end
                        return old(...)
                    end
                    table.insert(Runtime.Hooks, function() camModule.weaponKick = old end)
                end
            end

            if type(camModule.setWeaponRecoil) == "function" then
                local origRecoil
                origRecoil = SafeHook(camModule.setWeaponRecoil, function(...)
                    if Config.WeaponMods.NoRecoil then return end
                    return origRecoil(...)
                end)
                if origRecoil then
                    table.insert(Runtime.Hooks, function() pcall(hookfunction, camModule.setWeaponRecoil, origRecoil) end)
                else
                    local old = camModule.setWeaponRecoil
                    camModule.setWeaponRecoil = function(...)
                        if Config.WeaponMods.NoRecoil then return end
                        return old(...)
                    end
                    table.insert(Runtime.Hooks, function() camModule.setWeaponRecoil = old end)
                end
            end

            if type(camModule.getWeaponKickRotation) == "function" then
                local origRot
                origRot = SafeHook(camModule.getWeaponKickRotation, function(...)
                    if Config.WeaponMods.NoRecoil then return Vector3.zero end
                    return origRot(...)
                end)
                if origRot then
                    table.insert(Runtime.Hooks, function() pcall(hookfunction, camModule.getWeaponKickRotation, origRot) end)
                else
                    local old = camModule.getWeaponKickRotation
                    camModule.getWeaponKickRotation = function(...)
                        if Config.WeaponMods.NoRecoil then return Vector3.zero end
                        return old(...)
                    end
                    table.insert(Runtime.Hooks, function() camModule.getWeaponKickRotation = old end)
                end
            end
        end
    end
end
pcall(HookRecoilController)

-- 2. Resolve Remotes ModuleScript
local function GetRemotesModule()
    local database = ReplicatedStorage:FindFirstChild("Database")
    local security = database and database:FindFirstChild("Security")
    local remotes = security and security:FindFirstChild("Remotes")
    if not (remotes and remotes:IsA("ModuleScript")) then
        for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
            if desc.Name == "Remotes" and desc:IsA("ModuleScript") and desc.Parent and desc.Parent.Name == "Security" then
                remotes = desc
                break
            end
        end
    end
    if remotes and remotes:IsA("ModuleScript") then
        local ok, mod = pcall(require, remotes)
        if ok and type(mod) == "table" then
            return mod
        end
    end
    return nil
end

-- 3. Hook Bullet & Gun Classes via getgc for True Silent Aim & No Spread
local function HookGunClasses()
    local bulletClass = nil
    local gunClass = nil

    if getgc then
        for _, entry in ipairs(getgc(true)) do
            if type(entry) == "table" then
                if not bulletClass and rawget(entry, "getTrueSpread") and rawget(entry, "getSpreadForConfig") then
                    bulletClass = entry
                end
                if not gunClass and rawget(entry, "getSpread") and rawget(entry, "shoot") and rawget(entry, "setupRecoil") then
                    gunClass = entry
                end
                if bulletClass and gunClass then break end
            end
        end
    end

    -- Hook Bullet Spread to 0
    if bulletClass then
        local spreadMethods = {"getTrueSpread", "getSpreadForConfig", "getMovementSpreadForConfig", "getBaseSpreadForConfig", "getBaseSpread"}
        for _, method in ipairs(spreadMethods) do
            if type(bulletClass[method]) == "function" then
                local origSpread
                origSpread = SafeHook(bulletClass[method], function(...)
                    local val = origSpread(...)
                    if type(val) == "number" and (Config.WeaponMods.NoSpread or Runtime.ViewSaved) then
                        return 0
                    end
                    return val
                end)
                if origSpread then
                    table.insert(Runtime.Hooks, function() pcall(hookfunction, bulletClass[method], origSpread) end)
                else
                    local oldMethod = bulletClass[method]
                    bulletClass[method] = function(...)
                        local val = oldMethod(...)
                        if type(val) == "number" and (Config.WeaponMods.NoSpread or Runtime.ViewSaved) then
                            return 0
                        end
                        return val
                    end
                    table.insert(Runtime.Hooks, function() bulletClass[method] = oldMethod end)
                end
            end
        end

        -- Instantaneous Camera Flick during Bullet Creation (Bypasses server direction check)
        if type(bulletClass.create) == "function" then
            local origCreate
            origCreate = SafeHook(bulletClass.create, function(...)
                if Config.Combat.SilentAim and Runtime.TargetPart and Camera then
                    if math.random(1, 100) <= Config.Combat.HitChance then
                        Runtime.ViewSaved = Runtime.ViewSaved or Camera.CFrame
                        Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, Runtime.TargetPart.Position)
                    end
                end
                return origCreate(...)
            end)
            if origCreate then
                table.insert(Runtime.Hooks, function() pcall(hookfunction, bulletClass.create, origCreate) end)
            else
                local oldCreate = bulletClass.create
                bulletClass.create = function(...)
                    if Config.Combat.SilentAim and Runtime.TargetPart and Camera then
                        if math.random(1, 100) <= Config.Combat.HitChance then
                            Runtime.ViewSaved = Runtime.ViewSaved or Camera.CFrame
                            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, Runtime.TargetPart.Position)
                        end
                    end
                    return oldCreate(...)
                end
                table.insert(Runtime.Hooks, function() bulletClass.create = oldCreate end)
            end
        end
    end

    -- Hook ShootWeapon Network Remote to instantly restore Camera synchronously
    local net = GetRemotesModule()
    local shootRemote = net and net.Inventory and net.Inventory.ShootWeapon
    if shootRemote and type(shootRemote.Send) == "function" then
        local origSend
        origSend = SafeHook(shootRemote.Send, function(...)
            if Runtime.ViewSaved and Camera then
                Camera.CFrame = Runtime.ViewSaved
                Runtime.ViewSaved = nil
            end
            return origSend(...)
        end)
        if origSend then
            table.insert(Runtime.Hooks, function() pcall(hookfunction, shootRemote.Send, origSend) end)
        else
            local oldSend = shootRemote.Send
            shootRemote.Send = function(...)
                if Runtime.ViewSaved and Camera then
                    Camera.CFrame = Runtime.ViewSaved
                    Runtime.ViewSaved = nil
                end
                return oldSend(...)
            end
            table.insert(Runtime.Hooks, function() shootRemote.Send = oldSend end)
        end
    end
end
pcall(HookGunClasses)

-- Event-Driven Anti-Flash
local function SetupAntiFlash()
    local function MuteFlash(child)
        if Config.WeaponMods.AntiFlash and child:IsA("BlurEffect") and child.Name:lower():find("flash") then
            child.Size = 0
            child:GetPropertyChangedSignal("Size"):Connect(function()
                if Config.WeaponMods.AntiFlash and child.Size > 0 then child.Size = 0 end
            end)
        end
    end
    for _, obj in ipairs(Lighting:GetChildren()) do MuteFlash(obj) end
    table.insert(Runtime.Connections, Lighting.ChildAdded:Connect(MuteFlash))

    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then
        table.insert(Runtime.Connections, pGui.DescendantAdded:Connect(function(item)
            if Config.WeaponMods.AntiFlash and (item:IsA("Frame") or item:IsA("ImageLabel")) then
                if item.Name:lower():find("flash") or item.Name:lower():find("blind") or item.Name:lower():find("whiteout") then
                    item.Visible = false
                end
            end
        end))
    end
end
pcall(SetupAntiFlash)

-- ==========================================
-- MASTER RENDER LOOP (Real-Time Synchronous)
-- ==========================================
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    -- 0. Safety View Restoration Guard (Restores camera before frame renders if shot completed)
    if Runtime.ViewSaved and Camera then
        Camera.CFrame = Runtime.ViewSaved
        Runtime.ViewSaved = nil
    end

    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = Camera.CFrame.Position
    local visualsOn = Config.Visuals.Enabled
    local maxDist = Config.Visuals.MaxDistance

    -- 1. FOV Circle
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Radius = Config.Combat.FOV
        Runtime.FOVDrawing.Color = Config.Combat.FOVColor
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    -- 2. Extract Living Combatants (Cached for zero GC allocations)
    local combatants = UpdateCombatantsCache()

    -- 3. Target Selection
    local bestTarget, bestPart = SelectTarget(combatants)
    Runtime.Target = bestTarget
    Runtime.TargetPart = bestPart

    -- 4. ESP Rendering (Pixel-Perfect Synchronous)
    local activeIds = {}

    for _, data in ipairs(combatants) do
        local id = data.Id
        activeIds[id] = true
        local draw = GetOrCreateDrawing(id)

        if not visualsOn then
            HideDrawing(draw)
            continue
        end

        local isTeam = IsTeammate(data.Model, data.Player)
        if Config.Visuals.TeamCheck and isTeam then
            HideDrawing(draw)
            continue
        end

        local dist = (data.Root.Position - camPos).Magnitude
        if dist > maxDist then
            HideDrawing(draw)
            continue
        end

        -- Direct Head and Feet Viewport Projection (Locked to real animated positions)
        local headWorld = data.Head.Position + Vector3.new(0, 0.6, 0)
        local feetWorld = data.Root.Position - Vector3.new(0, 3.0, 0)

        local topPos, topOn = Camera:WorldToViewportPoint(headWorld)
        local botPos, botOn = Camera:WorldToViewportPoint(feetWorld)

        if topPos.Z > 0 and botPos.Z > 0 and (topOn or botOn) then
            local height = math.abs(botPos.Y - topPos.Y)
            local width = height * 0.62
            local boxPos = Vector2.new(topPos.X - width / 2, topPos.Y)
            local color = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor

            -- Bounding Box
            if Config.Visuals.BoxESP then
                draw.BoxOutline.Size = Vector2.new(width, height)
                draw.BoxOutline.Position = boxPos
                draw.BoxOutline.Visible = true

                draw.Box.Size = Vector2.new(width, height)
                draw.Box.Position = boxPos
                draw.Box.Color = color
                draw.Box.Visible = true
            else
                draw.BoxOutline.Visible = false
                draw.Box.Visible = false
            end

            -- Health Bar
            if Config.Visuals.HealthBar then
                local hum = data.Humanoid
                local hp = hum and hum.Health or tonumber(data.Model:GetAttribute("Health")) or 100
                local maxHp = hum and hum.MaxHealth or tonumber(data.Model:GetAttribute("MaxHealth")) or 100
                local ratio = math.clamp(hp / maxHp, 0, 1)

                local barHeight = height * ratio
                local barX = boxPos.X - 5

                draw.HealthOutline.From = Vector2.new(barX, boxPos.Y)
                draw.HealthOutline.To = Vector2.new(barX, boxPos.Y + height)
                draw.HealthOutline.Visible = true

                draw.Health.From = Vector2.new(barX, boxPos.Y + height)
                draw.Health.To = Vector2.new(barX, boxPos.Y + height - barHeight)
                draw.Health.Color = Color3.fromHSV(ratio * 0.32, 1, 1)
                draw.Health.Visible = true
            else
                draw.HealthOutline.Visible = false
                draw.Health.Visible = false
            end

            -- Name
            if Config.Visuals.NameESP then
                draw.Name.Text = (data.Player and data.Player.DisplayName) or data.Model.Name
                draw.Name.Position = Vector2.new(topPos.X, boxPos.Y - 15)
                draw.Name.Visible = true
            else
                draw.Name.Visible = false
            end

            -- Distance
            if Config.Visuals.DistanceESP then
                draw.Distance.Text = string.format("[%dm]", math.floor(dist))
                draw.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2)
                draw.Distance.Visible = true
            else
                draw.Distance.Visible = false
            end

            -- Tracers
            if Config.Visuals.Tracers then
                local origin = (Config.Visuals.TracerOrigin == "Bottom") and Vector2.new(vp.X / 2, vp.Y) or center
                draw.Tracer.From = origin
                draw.Tracer.To = Vector2.new(topPos.X, boxPos.Y + height)
                draw.Tracer.Color = color
                draw.Tracer.Visible = true
            else
                draw.Tracer.Visible = false
            end
        else
            HideDrawing(draw)
        end
    end

    -- Cleanup Unused Drawings
    for id, draw in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then
            DestroyDrawing(draw)
            Runtime.DrawingPool[id] = nil
        end
    end

    -- 5. C4 Objective Tracker
    if visualsOn and Config.Visuals.C4Tracker then
        local c4 = LocateC4()
        if c4 and c4.Parent then
            local c4Screen, onScreen = Camera:WorldToViewportPoint(c4.Position)
            if onScreen and c4Screen.Z > 0 then
                local dist = math.floor((c4.Position - camPos).Magnitude)
                Runtime.C4Drawing.Text = string.format("[ C4 BOMB // %dm ]", dist)
                Runtime.C4Drawing.Position = Vector2.new(c4Screen.X, c4Screen.Y)
                Runtime.C4Drawing.Visible = true
            else
                Runtime.C4Drawing.Visible = false
            end
        else
            Runtime.C4Drawing.Visible = false
        end
    else
        Runtime.C4Drawing.Visible = false
    end

    -- 6. Snappy Aim Assist (Hard-Lock on Right Click)
    if Config.Combat.AimAssist and Runtime.TargetPart then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local currentCF = Camera.CFrame
            local targetLook = CFrame.lookAt(currentCF.Position, Runtime.TargetPart.Position)
            Camera.CFrame = currentCF:Lerp(targetLook, Config.Combat.AimLockStrength)
        end
    end

    -- 7. Bunnyhop
    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if not UserInputService:GetFocusedTextBox() then
            local char = LocalPlayer.Character or (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name))
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial ~= Enum.Material.Air then
                hum.Jump = true
            end
        end
    end
end))

-- ==========================================
-- RAYFIELD UI INITIALIZATION (Official GitHub)
-- ==========================================
local function InitRayfield()
    local ok, Rayfield = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
    end)

    if not ok or type(Rayfield) ~= "table" then
        warn("[BWX] Rayfield failed to load via network.")
        return
    end

    local Window = Rayfield:CreateWindow({
        Name = "BWX // Bloxstrike",
        LoadingTitle = "BWX Utility Suite",
        LoadingSubtitle = "Bloxstrike Edition",
        ConfigurationSaving = { Enabled = false },
        Discord = { Enabled = false },
        KeySystem = false
    })

    -- Combat Tab
    local TabCombat = Window:CreateTab("Combat", 4483362458)
    TabCombat:CreateToggle({
        Name = "Silent Aim (Bullet Redirection)",
        CurrentValue = Config.Combat.SilentAim,
        Callback = function(v) Config.Combat.SilentAim = v end
    })
    TabCombat:CreateToggle({
        Name = "Aim Assist (Hold Right Click)",
        CurrentValue = Config.Combat.AimAssist,
        Callback = function(v) Config.Combat.AimAssist = v end
    })
    TabCombat:CreateSlider({
        Name = "Aim Lock Strength",
        Range = {10, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = math.floor(Config.Combat.AimLockStrength * 100),
        Callback = function(v) Config.Combat.AimLockStrength = v / 100 end
    })
    TabCombat:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = Config.Combat.ShowFOV,
        Callback = function(v) Config.Combat.ShowFOV = v end
    })
    TabCombat:CreateSlider({
        Name = "FOV Radius",
        Range = {30, 400},
        Increment = 5,
        Suffix = "px",
        CurrentValue = Config.Combat.FOV,
        Callback = function(v) Config.Combat.FOV = v end
    })
    TabCombat:CreateDropdown({
        Name = "Hit Target Part",
        Options = {"Head", "UpperTorso", "HumanoidRootPart"},
        CurrentOption = Config.Combat.HitPart,
        Callback = function(v) Config.Combat.HitPart = v end
    })
    TabCombat:CreateToggle({
        Name = "Visibility Check (Wallcheck)",
        CurrentValue = Config.Combat.VisibleCheck,
        Callback = function(v) Config.Combat.VisibleCheck = v end
    })

    -- Visuals Tab
    local TabVisuals = Window:CreateTab("Visuals", 4483362458)
    TabVisuals:CreateToggle({
        Name = "Master ESP Switch",
        CurrentValue = Config.Visuals.Enabled,
        Callback = function(v) Config.Visuals.Enabled = v end
    })
    TabVisuals:CreateToggle({
        Name = "Team Check (Filter CT / T)",
        CurrentValue = Config.Visuals.TeamCheck,
        Callback = function(v) Config.Visuals.TeamCheck = v end
    })
    TabVisuals:CreateToggle({
        Name = "2D Box ESP",
        CurrentValue = Config.Visuals.BoxESP,
        Callback = function(v) Config.Visuals.BoxESP = v end
    })
    TabVisuals:CreateToggle({
        Name = "Health Bar",
        CurrentValue = Config.Visuals.HealthBar,
        Callback = function(v) Config.Visuals.HealthBar = v end
    })
    TabVisuals:CreateToggle({
        Name = "Player Names",
        CurrentValue = Config.Visuals.NameESP,
        Callback = function(v) Config.Visuals.NameESP = v end
    })
    TabVisuals:CreateToggle({
        Name = "Distance Tag",
        CurrentValue = Config.Visuals.DistanceESP,
        Callback = function(v) Config.Visuals.DistanceESP = v end
    })
    TabVisuals:CreateToggle({
        Name = "Snaplines / Tracers",
        CurrentValue = Config.Visuals.Tracers,
        Callback = function(v) Config.Visuals.Tracers = v end
    })
    TabVisuals:CreateToggle({
        Name = "C4 Bomb Tracker",
        CurrentValue = Config.Visuals.C4Tracker,
        Callback = function(v) Config.Visuals.C4Tracker = v end
    })
    TabVisuals:CreateSlider({
        Name = "Max ESP Distance",
        Range = {500, 8000},
        Increment = 250,
        Suffix = "m",
        CurrentValue = Config.Visuals.MaxDistance,
        Callback = function(v) Config.Visuals.MaxDistance = v end
    })

    -- Gun Mods Tab
    local TabMods = Window:CreateTab("Gun Mods", 4483362458)
    TabMods:CreateToggle({
        Name = "No Recoil (Controller Kick & Punch Hook)",
        CurrentValue = Config.WeaponMods.NoRecoil,
        Callback = function(v) Config.WeaponMods.NoRecoil = v end
    })
    TabMods:CreateToggle({
        Name = "No Spread (Zero Bullet Spread)",
        CurrentValue = Config.WeaponMods.NoSpread,
        Callback = function(v) Config.WeaponMods.NoSpread = v end
    })
    TabMods:CreateToggle({
        Name = "Anti-Flashbang (Instant Blind Wipe)",
        CurrentValue = Config.WeaponMods.AntiFlash,
        Callback = function(v) Config.WeaponMods.AntiFlash = v end
    })

    -- Movement Tab
    local TabMove = Window:CreateTab("Movement", 4483362458)
    TabMove:CreateToggle({
        Name = "Auto Bunnyhop (Bhop)",
        CurrentValue = Config.Movement.Bhop,
        Callback = function(v) Config.Movement.Bhop = v end
    })

    Rayfield:Notify({
        Title = "BWX Loaded",
        Content = "Bloxstrike Engine Ready. Tekan [K] untuk menyembunyikan/menampilkan UI.",
        Duration = 6
    })
end

task.spawn(InitRayfield)

-- Global Unload Handler
env.BWXUnload = function()
    Runtime.Active = false

    for _, conn in ipairs(Runtime.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Runtime.Connections)

    for _, unhook in ipairs(Runtime.Hooks) do pcall(unhook) end
    table.clear(Runtime.Hooks)

    if Runtime.FOVDrawing then pcall(function() Runtime.FOVDrawing:Remove() end) end
    if Runtime.C4Drawing then pcall(function() Runtime.C4Drawing:Remove() end) end

    for _, draw in pairs(Runtime.DrawingPool) do
        DestroyDrawing(draw)
    end
    table.clear(Runtime.DrawingPool)

    env.BWXUnload = nil
    env.CybrionUnload = nil
    env.BloxStrikeUnload = nil
end
env.CybrionUnload = env.BWXUnload
env.BloxStrikeUnload = env.BWXUnload

print("[BWX] Engine Initialized with Zero-Lag Pipeline & Rayfield UI.")

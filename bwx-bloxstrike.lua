--[[
    ⚡ BWX // Bloxstrike Utility Suite (v4.0 Premium Edition)
    Target: Roblox Bloxstrike
    REQUIREMENT: Must run on High-Tier Executors (Wave, AWP, Script-Ware).
    Functions used: hookfunction, hookmetamethod, getrawmetatable, setreadonly.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Check Capabilities
if not hookfunction or not hookmetamethod then
    return game:GetService("StarterGui"):SetCore("SendNotification", {Title = "BWX Error", Text = "Executor missing hookfunction/hookmetamethod!"})
end

local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end

local Config = {
    Combat = {
        SilentAim = true,
        HitboxSize = 8,
        HitPart = "Head",
        FOV = 130,
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
        NameESP = true,
        HealthBar = true,
        DistanceESP = true,
        MaxDistance = 5000,
    },
    WeaponMods = {
        NoRecoil = true,
        NoSpread = true,
        AntiFlash = true
    },
    Movement = { Bhop = true },
    UI = { MenuOpen = false }
}

local Runtime = {
    Active = true,
    DrawingPool = {},
    OriginalSizes = {},
    FOVDrawing = nil,
    Hooks = {},
    Connections = {}
}

local WallParams = RaycastParams.new()
WallParams.FilterType = Enum.RaycastFilterType.Exclude
WallParams.IgnoreWater = true

Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5; Runtime.FOVDrawing.NumSides = 48; Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.75; Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor; Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

-- =========================================================================
-- PREMIUM HOOKS (No Recoil & Silent Aim)
-- =========================================================================
local function SetupHooks()
    -- 1. Hook CameraController (No Recoil & No Spread)
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local camModuleScript = controllers and controllers:FindFirstChild("CameraController")
    if camModuleScript and camModuleScript:IsA("ModuleScript") then
        local ok, camModule = pcall(require, camModuleScript)
        if ok and type(camModule) == "table" then
            -- Hook Weapon Kick (Recoil)
            if type(camModule.weaponKick) == "function" and not Runtime.Hooks["weaponKick"] then
                local oldKick = camModule.weaponKick
                camModule.weaponKick = function(...)
                    if Config.WeaponMods.NoRecoil then return end
                    return oldKick(...)
                end
                Runtime.Hooks["weaponKick"] = function() camModule.weaponKick = oldKick end
            end
            
            -- Hook getWeaponKickRotation (Recoil)
            if type(camModule.getWeaponKickRotation) == "function" and not Runtime.Hooks["getWeaponKickRotation"] then
                local oldRot = camModule.getWeaponKickRotation
                camModule.getWeaponKickRotation = function(...)
                    if Config.WeaponMods.NoRecoil then return CFrame.new() end
                    return oldRot(...)
                end
                Runtime.Hooks["getWeaponKickRotation"] = function() camModule.getWeaponKickRotation = oldRot end
            end
        end
    end

    -- 2. Hook Workspace.Raycast (Silent Aim / True No Spread)
    local oldRaycast
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if method == "Raycast" and self == Workspace then
            if Config.Combat.SilentAim or Config.WeaponMods.NoSpread then
                local origin = args[1]
                local direction = args[2]
                -- Jika peluru ditembakkan dari dekat kamera (senjata player)
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local distToCam = (origin - Camera.CFrame.Position).Magnitude
                    if distToCam < 15 then
                        -- Cari musuh terdekat di layar
                        local targetPos = nil
                        local closestDist = Config.Combat.FOV
                        
                        for _, p in pairs(Players:GetPlayers()) do
                            if p ~= LocalPlayer and p.Character then
                                local head = p.Character:FindFirstChild("Head")
                                if head and not IsTeammate(p) then
                                    local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                                    if onScreen then
                                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)).Magnitude
                                        if dist < closestDist then
                                            closestDist = dist
                                            targetPos = head.Position
                                        end
                                    end
                                end
                            end
                        end
                        
                        -- Arahkan peluru ke musuh (Silent Aim)
                        if targetPos and Config.Combat.SilentAim then
                            args[2] = (targetPos - origin).Unit * direction.Magnitude
                        elseif Config.WeaponMods.NoSpread then
                            -- Jika nggak ada musuh, buang spread (lurus ke depan)
                            args[2] = Camera.CFrame.LookVector * direction.Magnitude
                        end
                    end
                end
            end
        end
        
        return oldNamecall(self, unpack(args))
    end)
    
    setreadonly(mt, true)
    Runtime.Hooks["namecall"] = function()
        local mt2 = getrawmetatable(game)
        setreadonly(mt2, false)
        mt2.__namecall = oldNamecall
        setreadonly(mt2, true)
    end
end
pcall(SetupHooks)

-- =========================================================================
-- TEAM & ESP LOGIC
-- =========================================================================
local function IsTeammate(player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer then return true end
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    local myTeam = myChar:GetAttribute("Team") or myChar:GetAttribute("TeamId")
    local pTeam = player:GetAttribute("Team") or player:GetAttribute("TeamId")
    return myTeam == pTeam
end

local function IsDead(plr)
    if not plr.Character then return true end
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return true end
    if plr.Character:GetAttribute("Dead") == true then return true end
    return false
end

local function GetDrawings(id)
    local d = Runtime.DrawingPool[id]
    if not d then
        d = {
            BoxOutline = Drawing.new("Square"), Box = Drawing.new("Square"),
            HealthOutline = Drawing.new("Line"), Health = Drawing.new("Line"),
            Name = Drawing.new("Text"), Distance = Drawing.new("Text")
        }
        d.BoxOutline.Thickness = 3; d.BoxOutline.Color = Color3.new(0, 0, 0); d.BoxOutline.Visible = false
        d.Box.Thickness = 1; d.Box.Visible = false
        d.HealthOutline.Thickness = 3; d.HealthOutline.Color = Color3.new(0, 0, 0); d.HealthOutline.Visible = false
        d.Health.Thickness = 2; d.Health.Visible = false
        d.Name.Size = 13; d.Name.Center = true; d.Name.Outline = true; d.Name.Visible = false
        d.Distance.Size = 11; d.Distance.Center = true; d.Distance.Outline = true; d.Distance.Visible = false
        Runtime.DrawingPool[id] = d
    end
    return d
end

local function HideAll(d)
    if d then
        d.BoxOutline.Visible = false; d.Box.Visible = false
        d.HealthOutline.Visible = false; d.Health.Visible = false
        d.Name.Visible = false; d.Distance.Visible = false
    end
end

local function DestroyAll(d)
    for _, v in pairs(d) do pcall(function() v:Remove() end) end
end

-- =========================================================================
-- RENDER LOOP (Instant ESP)
-- =========================================================================
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local now = os.clock()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local activeIds = {}
    
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not IsDead(p) then
            local char = p.Character
            if char then
                local head = char:FindFirstChild("Head")
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                
                if head and root and hum then
                    local id = p.Name
                    activeIds[id] = true
                    local isTeam = IsTeammate(p)
                    local dist = (root.Position - Camera.CFrame.Position).Magnitude
                    
                    if dist <= Config.Visuals.MaxDistance and not (Config.Visuals.TeamCheck and isTeam) then
                        local topPos, onTop = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
                        local botPos, onBot = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
                        
                        if onTop and onBot and topPos.Z > 0 and botPos.Z > 0 then
                            local height = math.abs(botPos.Y - topPos.Y)
                            local width = height * 0.58
                            local boxPos = Vector2.new(topPos.X - width/2, topPos.Y)
                            local d = GetDrawings(id)
                            local col = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor
                            
                            if Config.Visuals.BoxESP then
                                d.BoxOutline.Size = Vector2.new(width, height); d.BoxOutline.Position = boxPos; d.BoxOutline.Visible = true
                                d.Box.Size = Vector2.new(width, height); d.Box.Position = boxPos; d.Box.Color = col; d.Box.Visible = true
                            end
                            
                            if Config.Visuals.HealthBar then
                                local hpRatio = hum.Health / hum.MaxHealth
                                local barH = height * hpRatio
                                d.HealthOutline.From = Vector2.new(boxPos.X - 5, boxPos.Y); d.HealthOutline.To = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.HealthOutline.Visible = true
                                d.Health.From = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.Health.To = Vector2.new(boxPos.X - 5, boxPos.Y + height - barH); d.Health.Color = Color3.fromHSV(hpRatio * 0.3, 1, 1); d.Health.Visible = true
                            end
                            
                            if Config.Visuals.NameESP then
                                d.Name.Text = p.DisplayName; d.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); d.Name.Visible = true
                            end
                            
                            if Config.Visuals.DistanceESP then
                                d.Distance.Text = string.format("[%dm]", math.floor(dist)); d.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); d.Distance.Visible = true
                            end
                            
                            -- Apply Hitbox (Silent Aim visual)
                            if Config.Combat.SilentAim then
                                if not Runtime.OriginalSizes[head] then
                                    Runtime.OriginalSizes[head] = {Size = head.Size, Transparency = head.Transparency, CanCollide = head.CanCollide}
                                end
                                head.Size = Vector3.new(Config.Combat.HitboxSize, Config.Combat.HitboxSize, Config.Combat.HitboxSize)
                                head.Transparency = 0.65
                                head.CanCollide = false
                            end
                        else
                            HideAll(Runtime.DrawingPool[id])
                        end
                    else
                        HideAll(Runtime.DrawingPool[id])
                    end
                end
            end
        end
    end

    -- Cleanup
    for id, d in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then
            DestroyAll(d); Runtime.DrawingPool[id] = nil
        end
    end

    -- Restore hitboxes if off
    if not Config.Combat.SilentAim then
        for h, data in pairs(Runtime.OriginalSizes) do
            if h and h.Parent then
                h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide
            end
        end
        table.clear(Runtime.OriginalSizes)
    end

    -- Bhop Native
    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
    end
end))

-- =========================================================================
-- UNLOAD
-- =========================================================================
env.BWXUnload = function()
    Runtime.Active = false
    for _, conn in ipairs(Runtime.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Runtime.Connections)
    for _, unhook in pairs(Runtime.Hooks) do pcall(unhook) end
    table.clear(Runtime.Hooks)
    if Runtime.FOVDrawing then Runtime.FOVDrawing:Remove() end
    for _, d in pairs(Runtime.DrawingPool) do DestroyAll(d) end
    table.clear(Runtime.DrawingPool)
    for h, data in pairs(Runtime.OriginalSizes) do
        if h and h.Parent then h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide end
    end
    table.clear(Runtime.OriginalSizes)
end
env.BWXUnload = env.BWXUnload

print("[BWX] Suite v4.0 Premium Loaded. Hooks Active.")

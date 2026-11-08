--[[
    ⚡ BWX // Bloxstrike Utility Suite (v4.5 Aster-Fixed)
    Target: Roblox Bloxstrike
    Fixes: Accurate Team Check, Tracers Added, Safe No Recoil/Spread.
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

local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end

local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()

local Config = {
    Combat = {
        AimLock = true,
        AimLockStrength = 0.22,
        Hitbox = true,
        HitboxSize = 8,
        FOV = 130,
        ShowFOV = true,
        FOVColor = Color3.fromRGB(50, 230, 150)
    },
    Visuals = {
        Enabled = true,
        TeamCheck = true,
        BoxESP = true,
        Tracers = true,
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
    Movement = { Bhop = true }
}

local Runtime = {
    Active = true,
    DrawingPool = {},
    OriginalSizes = {},
    FOVDrawing = nil,
    TargetPart = nil,
    Connections = {},
    Hooks = {},
    LastPitch = nil,
    LastYaw = nil
}

Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5
Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.75
Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

-- =========================================================================
-- ACCURATE TEAM CHECK (v3.14 Logic)
-- =========================================================================
local function NormalizeTeam(val)
    if val == nil then return nil end
    local s = tostring(val):lower()
    if s == "1" or s == "ct" or s:find("counter") or s:find("blue") then return "CT" end
    if s == "2" or s == "t" or s:find("terror") or s:find("red") or s:find("orange") then return "T" end
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
    
    local myChar = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
    if not myChar then return false end
    
    local myTeam = GetEntityTeam(myChar, LocalPlayer)
    local targetTeam = GetEntityTeam(model, player)
    
    if myTeam and targetTeam then return myTeam == targetTeam end
    return false
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
    end
    return false
end

-- =========================================================================
-- SAFE HOOKS (No Recoil via Raycast/CFrame, No Spread)
-- =========================================================================
local function SetupHooks()
    -- 1. No Spread Hook (Safe Direction override)
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if method == "Raycast" and self == Workspace then
            if Config.WeaponMods.NoSpread then
                local origin = args[1]
                local direction = args[2]
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local distToCam = (origin - Camera.CFrame.Position).Magnitude
                    -- Only affect bullets fired near the camera
                    if distToCam < 15 then
                        args[2] = Camera.CFrame.LookVector * direction.Magnitude
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

    -- 2. No Recoil Hook (Safe Camera Kick override)
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
                        if typeof(result) == "CFrame" then 
                            return CFrame.new(result.Position) 
                        elseif typeof(result) == "Vector3" then 
                            return Vector3.zero 
                        end
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
        end
    end
end
pcall(SetupHooks)

-- =========================================================================
-- DRAWINGS & TRACERS
-- =========================================================================
local function GetDrawings(id)
    local d = Runtime.DrawingPool[id]
    if not d then
        d = {
            BoxOutline = Drawing.new("Square"), Box = Drawing.new("Square"),
            HealthOutline = Drawing.new("Line"), Health = Drawing.new("Line"),
            Name = Drawing.new("Text"), Distance = Drawing.new("Text"),
            Tracer = Drawing.new("Line")
        }
        d.BoxOutline.Thickness = 3; d.BoxOutline.Color = Color3.new(0, 0, 0); d.BoxOutline.Visible = false
        d.Box.Thickness = 1; d.Box.Visible = false
        d.HealthOutline.Thickness = 3; d.HealthOutline.Color = Color3.new(0, 0, 0); d.HealthOutline.Visible = false
        d.Health.Thickness = 2; d.Health.Visible = false
        d.Name.Size = 13; d.Name.Center = true; d.Name.Outline = true; d.Name.Visible = false
        d.Distance.Size = 11; d.Distance.Center = true; d.Distance.Outline = true; d.Distance.Visible = false
        d.Tracer.Thickness = 1; d.Tracer.Transparency = 0.7; d.Tracer.Visible = false
        Runtime.DrawingPool[id] = d
    end
    return d
end

local function HideAll(d)
    if d then
        d.BoxOutline.Visible = false; d.Box.Visible = false
        d.HealthOutline.Visible = false; d.Health.Visible = false
        d.Name.Visible = false; d.Distance.Visible = false
        d.Tracer.Visible = false
    end
end

local function DestroyAll(d)
    for _, v in pairs(d) do pcall(function() v:Remove() end) end
end

-- =========================================================================
-- RENDER LOOP
-- =========================================================================
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local activeIds = {}
    
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Radius = Config.Combat.FOV
        Runtime.FOVDrawing.Color = Config.Combat.FOVColor
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    if Config.WeaponMods.AntiFlash then
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") then
                if obj.Enabled and (obj.Name:lower():find("flash") or obj.Brightness > 1) then obj.Enabled = false end
            end
        end
    end

    local bestCandidate = nil
    local bestScreenDist = Config.Combat.FOV
    local bestHitPart = nil

    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local player = Players:GetPlayerFromCharacter(model) or Players:FindFirstChild(model.Name)
                
                if not IsModelDead(model, player) then
                    local head = model:FindFirstChild("Head")
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    
                    if head and root then
                        local id = model.Name
                        activeIds[id] = true
                        local isTeam = IsTeammate(model, player)
                        local dist = (root.Position - Camera.CFrame.Position).Magnitude
                        local hp = (hum and hum.Health) or tonumber(model:GetAttribute("Health")) or 100
                        local maxHp = (hum and hum.MaxHealth) or tonumber(model:GetAttribute("MaxHealth")) or 100
                        local displayName = (player and player.DisplayName) or model.Name

                        -- Hitbox Expander
                        if Config.Combat.Hitbox and not isTeam then
                            if not Runtime.OriginalSizes[head] then
                                Runtime.OriginalSizes[head] = {Size = head.Size, Transparency = head.Transparency, CanCollide = head.CanCollide}
                            end
                            head.Size = Vector3.new(Config.Combat.HitboxSize, Config.Combat.HitboxSize, Config.Combat.HitboxSize)
                            head.Transparency = 0.65
                            head.CanCollide = false
                        end

                        -- ESP Render
                        if Config.Visuals.Enabled and not (Config.Visuals.TeamCheck and isTeam) and dist <= Config.Visuals.MaxDistance then
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
                                else
                                    d.BoxOutline.Visible = false; d.Box.Visible = false
                                end
                                
                                if Config.Visuals.Tracers then
                                    d.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
                                    d.Tracer.To = Vector2.new(topPos.X, botPos.Y)
                                    d.Tracer.Color = col
                                    d.Tracer.Visible = true
                                else
                                    d.Tracer.Visible = false
                                end

                                if Config.Visuals.HealthBar then
                                    local hpRatio = math.clamp(hp / maxHp, 0, 1)
                                    local barH = height * hpRatio
                                    d.HealthOutline.From = Vector2.new(boxPos.X - 5, boxPos.Y); d.HealthOutline.To = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.HealthOutline.Visible = true
                                    d.Health.From = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.Health.To = Vector2.new(boxPos.X - 5, boxPos.Y + height - barH); d.Health.Color = Color3.fromHSV(hpRatio * 0.3, 1, 1); d.Health.Visible = true
                                else
                                    d.HealthOutline.Visible = false; d.Health.Visible = false
                                end
                                
                                if Config.Visuals.NameESP then
                                    d.Name.Text = displayName; d.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); d.Name.Visible = true
                                else d.Name.Visible = false end
                                
                                if Config.Visuals.DistanceESP then
                                    d.Distance.Text = string.format("[%dm]", math.floor(dist)); d.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); d.Distance.Visible = true
                                else d.Distance.Visible = false end
                            else
                                HideAll(Runtime.DrawingPool[id])
                            end
                        else
                            HideAll(Runtime.DrawingPool[id])
                        end

                        -- Aimlock Target Selection
                        if Config.Combat.AimLock and not isTeam then
                            local partScreen, partOn = Camera:WorldToViewportPoint(head.Position)
                            if partOn and partScreen.Z > 0 then
                                local sDist = (Vector2.new(partScreen.X, partScreen.Y) - center).Magnitude
                                if sDist < bestScreenDist then
                                    bestScreenDist = sDist
                                    bestCandidate = model
                                    bestHitPart = head
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for id, d in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then
            DestroyAll(d); Runtime.DrawingPool[id] = nil
        end
    end

    if not Config.Combat.Hitbox then
        for h, data in pairs(Runtime.OriginalSizes) do
            if h and h.Parent then
                h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide
            end
        end
        table.clear(Runtime.OriginalSizes)
    end

    Runtime.TargetPart = bestHitPart

    -- LMB Aimlock
    local isFiring = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    if Config.Combat.AimLock and Runtime.TargetPart and not UserInputService:GetFocusedTextBox() then
        if isFiring then
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then 
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end) 
            end
            local targetPos = Runtime.TargetPart.Position
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
            if onScreen and screenPos.Z > 0 then
                local delta = Vector2.new(screenPos.X - center.X, screenPos.Y - center.Y)
                if mousemoverel then
                    mousemoverel(delta.X * Config.Combat.AimLockStrength, delta.Y * Config.Combat.AimLockStrength)
                end
            end
        end
    end

    -- Bhop
    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
    end
end))

-- =========================================================================
-- ASTER UI
-- =========================================================================
local Window = Aster:CreateWindow({
    Title = "BWX // Bloxstrike",
    Subtitle = "v4.5 Fixed",
    ToggleUIKeybind = "K",
    Theme = "Cybrion",
    Weather = "Matrix",
})

local CombatTab = Window:Tab({ Name = "Combat", Icon = "crosshair" })
CombatTab:Section("Aimlock")
CombatTab:Toggle({ Name = "LMB Aimlock", Flag = "AimLock", Default = Config.Combat.AimLock, Callback = function(v) Config.Combat.AimLock = v end })
CombatTab:Slider({ Name = "Aim Smoothness", Flag = "AimStr", Min = 5, Max = 100, Default = 22, Suffix = "%", Callback = function(v) Config.Combat.AimLockStrength = v / 100 end })
CombatTab:Section("Hitbox")
CombatTab:Toggle({ Name = "Hitbox Expander", Flag = "Hitbox", Default = Config.Combat.Hitbox, Callback = function(v) Config.Combat.Hitbox = v end })
CombatTab:Slider({ Name = "Hitbox Size", Flag = "HitboxSize", Min = 3, Max = 16, Default = 8, Suffix = " studs", Callback = function(v) Config.Combat.HitboxSize = v end })
CombatTab:Slider({ Name = "FOV Radius", Flag = "FOV", Min = 30, Max = 400, Default = 130, Suffix = "px", Callback = function(v) Config.Combat.FOV = v end })
CombatTab:Toggle({ Name = "Show FOV Circle", Flag = "ShowFOV", Default = true, Callback = function(v) Config.Combat.ShowFOV = v end })

local VisualsTab = Window:Tab({ Name = "Visuals", Icon = "eye" })
VisualsTab:Section("ESP")
VisualsTab:Toggle({ Name = "Master ESP", Flag = "MasterESP", Default = true, Callback = function(v) Config.Visuals.Enabled = v end })
VisualsTab:Toggle({ Name = "Box ESP", Flag = "BoxESP", Default = true, Callback = function(v) Config.Visuals.BoxESP = v end })
VisualsTab:Toggle({ Name = "Tracers", Flag = "Tracers", Default = true, Callback = function(v) Config.Visuals.Tracers = v end })
VisualsTab:Toggle({ Name = "Health Bar", Flag = "HealthBar", Default = true, Callback = function(v) Config.Visuals.HealthBar = v end })
VisualsTab:Toggle({ Name = "Name Tags", Flag = "NameESP", Default = true, Callback = function(v) Config.Visuals.NameESP = v end })
VisualsTab:Toggle({ Name = "Distance Tag", Flag = "DistanceESP", Default = true, Callback = function(v) Config.Visuals.DistanceESP = v end })
VisualsTab:Slider({ Name = "Max Distance", Flag = "MaxDist", Min = 500, Max = 8000, Default = 5000, Suffix = "m", Callback = function(v) Config.Visuals.MaxDistance = v end })

local ModsTab = Window:Tab({ Name = "Gun Mods", Icon = "cog" })
ModsTab:Section("Recoil & Spread")
ModsTab:Toggle({ Name = "No Recoil (Safe Hook)", Flag = "NoRecoil", Default = true, Callback = function(v) Config.WeaponMods.NoRecoil = v end })
ModsTab:Toggle({ Name = "No Spread (Safe Raycast)", Flag = "NoSpread", Default = true, Callback = function(v) Config.WeaponMods.NoSpread = v end })
ModsTab:Section("Misc")
ModsTab:Toggle({ Name = "Anti-Flashbang", Flag = "AntiFlash", Default = true, Callback = function(v) Config.WeaponMods.AntiFlash = v end })
ModsTab:Toggle({ Name = "Auto Bunnyhop", Flag = "Bhop", Default = true, Callback = function(v) Config.Movement.Bhop = v end })

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
    if Aster and Aster.Destroy then pcall(function() Aster:Destroy() end) end
    env.BWXUnload = nil
end
env.BWXUnload = env.BWXUnload

print("[BWX] Suite v4.5 Loaded. Accurate Teams, Tracers & Safe Hooks.")

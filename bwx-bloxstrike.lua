--[[
    ⚡ BWX // Bloxstrike Utility Suite (v4.2 Aster-UI Edition)
    Target: Roblox Bloxstrike
    REQUIREMENT: High-Tier Executors (Wave, AWP, Script-Ware)
    UI Library: Aster-UI by podivichdev
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

if not hookfunction or not hookmetamethod then
    return game:GetService("StarterGui"):SetCore("SendNotification", {Title = "BWX Error", Text = "Executor missing hookfunction/hookmetamethod!"})
end

local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end

-- =========================================================================
-- LOAD ASTER-UI
-- =========================================================================
local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local Config = {
    Combat = {
        SilentAim = true,
        HitboxSize = 8,
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

-- FOV Drawing
Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5
Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.75
Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

-- =========================================================================
-- TEAM & UTILITY FUNCTIONS
-- =========================================================================
local function IsTeammate(player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer then return true end
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    
    local myTeam = myChar:GetAttribute("Team") or myChar:GetAttribute("TeamId") or myChar:GetAttribute("TeamName")
    local pTeam = player:GetAttribute("Team") or player:GetAttribute("TeamId") or player:GetAttribute("TeamName")
    
    if not myTeam or not pTeam then
        local function Normalize(v)
            if not v then return nil end
            local s = tostring(v):lower()
            if s == "1" or s:find("ct") or s:find("counter") or s:find("blue") then return "CT" end
            if s == "2" or s:find("terror") or s:find("red") or s:find("orange") then return "T" end
            return s
        end
        return Normalize(myTeam) == Normalize(pTeam)
    end
    return myTeam == pTeam
end

local function IsDead(plr)
    if not plr.Character then return true end
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return true end
    if plr.Character:GetAttribute("Dead") == true then return true end
    return false
end

-- =========================================================================
-- HOOKS
-- =========================================================================
local function SetupHooks()
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local camModuleScript = controllers and controllers:FindFirstChild("CameraController")
    if camModuleScript and camModuleScript:IsA("ModuleScript") then
        local ok, camModule = pcall(require, camModuleScript)
        if ok and type(camModule) == "table" then
            if type(camModule.weaponKick) == "function" and not Runtime.Hooks["weaponKick"] then
                local oldKick = camModule.weaponKick
                camModule.weaponKick = function(...)
                    if Config.WeaponMods.NoRecoil then return end
                    return oldKick(...)
                end
                Runtime.Hooks["weaponKick"] = function() camModule.weaponKick = oldKick end
            end
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
                
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local distToCam = (origin - Camera.CFrame.Position).Magnitude
                    if distToCam < 15 then
                        local targetPos = nil
                        local closestDist = Config.Combat.FOV
                        
                        for _, p in pairs(Players:GetPlayers()) do
                            if p ~= LocalPlayer and not IsDead(p) and not IsTeammate(p) then
                                local head = p.Character and p.Character:FindFirstChild("Head")
                                if head then
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
                        
                        if targetPos and Config.Combat.SilentAim then
                            args[2] = (targetPos - origin).Unit * direction.Magnitude
                        elseif Config.WeaponMods.NoSpread then
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
-- DRAWING MANAGER
-- =========================================================================
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

    for id, d in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then
            DestroyAll(d); Runtime.DrawingPool[id] = nil
        end
    end

    if not Config.Combat.SilentAim then
        for h, data in pairs(Runtime.OriginalSizes) do
            if h and h.Parent then
                h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide
            end
        end
        table.clear(Runtime.OriginalSizes)
    end

    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
    end
end))

-- =========================================================================
-- ASTER-UI FRAMEWORK
-- =========================================================================
local Window = Aster:CreateWindow({
    Title = "BWX // Bloxstrike",
    Subtitle = "v4.2 Aster Edition",
    LoadingTitle = "BWX Suite",
    LoadingSubtitle = "Loading Aster-UI...",
    ToggleUIKeybind = "K", -- Ganti keybind di sini (bisa "RightShift")
    ConfigurationSaving = {
        FolderName = "BWXConfigs",
        FileName = "Bloxstrike"
    },
    Theme = "Cybrion",
    Weather = "Matrix",
})

-- =========================================================================
-- TAB: COMBAT
-- =========================================================================
local CombatTab = Window:Tab({ Name = "Combat", Icon = "crosshair" })
CombatTab:Section("Silent Aim")
CombatTab:Toggle({
    Name = "Enable Silent Aim",
    Flag = "SilentAim",
    Default = Config.Combat.SilentAim,
    Callback = function(v) Config.Combat.SilentAim = v end
})
CombatTab:Slider({
    Name = "FOV Radius",
    Flag = "FOV",
    Min = 30, Max = 400,
    Default = Config.Combat.FOV,
    Suffix = "px",
    Callback = function(v) Config.Combat.FOV = v end
})
CombatTab:Toggle({
    Name = "Show FOV Circle",
    Flag = "ShowFOV",
    Default = Config.Combat.ShowFOV,
    Callback = function(v) Config.Combat.ShowFOV = v end
})
CombatTab:Section("Hitbox")
CombatTab:Slider({
    Name = "Hitbox Size",
    Flag = "HitboxSize",
    Min = 3, Max = 16,
    Default = Config.Combat.HitboxSize,
    Suffix = " studs",
    Callback = function(v) Config.Combat.HitboxSize = v end
})
CombatTab:Toggle({
    Name = "Team Check",
    Flag = "TeamCheck",
    Default = Config.Combat.TeamCheck,
    Callback = function(v) Config.Combat.TeamCheck = v; Config.Visuals.TeamCheck = v end
})

-- =========================================================================
-- TAB: VISUALS
-- =========================================================================
local VisualsTab = Window:Tab({ Name = "Visuals", Icon = "eye" })
VisualsTab:Section("ESP")
VisualsTab:Toggle({
    Name = "Master ESP",
    Flag = "MasterESP",
    Default = Config.Visuals.Enabled,
    Callback = function(v) Config.Visuals.Enabled = v end
})
VisualsTab:Toggle({
    Name = "Box ESP",
    Flag = "BoxESP",
    Default = Config.Visuals.BoxESP,
    Callback = function(v) Config.Visuals.BoxESP = v end
})
VisualsTab:Toggle({
    Name = "Health Bar",
    Flag = "HealthBar",
    Default = Config.Visuals.HealthBar,
    Callback = function(v) Config.Visuals.HealthBar = v end
})
VisualsTab:Toggle({
    Name = "Name Tags",
    Flag = "NameESP",
    Default = Config.Visuals.NameESP,
    Callback = function(v) Config.Visuals.NameESP = v end
})
VisualsTab:Toggle({
    Name = "Distance Tag",
    Flag = "DistanceESP",
    Default = Config.Visuals.DistanceESP,
    Callback = function(v) Config.Visuals.DistanceESP = v end
})
VisualsTab:Slider({
    Name = "Max ESP Distance",
    Flag = "MaxDistance",
    Min = 500, Max = 8000,
    Default = Config.Visuals.MaxDistance,
    Suffix = "m",
    Callback = function(v) Config.Visuals.MaxDistance = v end
})

-- =========================================================================
-- TAB: GUN MODS
-- =========================================================================
local GunModsTab = Window:Tab({ Name = "Gun Mods", Icon = "gun" })
GunModsTab:Section("Recoil & Spread")
GunModsTab:Toggle({
    Name = "No Recoil (Hooked)",
    Flag = "NoRecoil",
    Default = Config.WeaponMods.NoRecoil,
    Callback = function(v) Config.WeaponMods.NoRecoil = v end
})
GunModsTab:Toggle({
    Name = "No Spread (Hooked)",
    Flag = "NoSpread",
    Default = Config.WeaponMods.NoSpread,
    Callback = function(v) Config.WeaponMods.NoSpread = v end
})
GunModsTab:Section("Misc")
GunModsTab:Toggle({
    Name = "Anti-Flashbang",
    Flag = "AntiFlash",
    Default = Config.WeaponMods.AntiFlash,
    Callback = function(v) Config.WeaponMods.AntiFlash = v end
})

-- =========================================================================
-- TAB: MOVEMENT
-- =========================================================================
local MovementTab = Window:Tab({ Name = "Movement", Icon = "footprints" })
MovementTab:Section("Movement")
MovementTab:Toggle({
    Name = "Auto Bunnyhop",
    Flag = "Bhop",
    Default = Config.Movement.Bhop,
    Callback = function(v) Config.Movement.Bhop = v end
})

-- =========================================================================
-- CLEANUP
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
    if Aster and Aster.Destroy then pcall(function() Aster:Destroy() end) end
    env.BWXUnload = nil
end
env.BWXUnload = env.BWXUnload

print("[BWX] Suite v4.2 Aster Edition Loaded.")

--[[
    ⚡ BWX // Bloxstrike Utility Suite (v4.3 Aster-UI Fixed)
    Target: Roblox Bloxstrike
    REQUIREMENT: Premium Executors (Wave, AWP)
    Note: Removed Raycast hooks to fix shooting. Using LMB Aimlock + Workspace ESP.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
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
        SilentAim = true, -- This now acts as Hitbox Expander
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
    Connections = {}
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
-- TEAM & UTILITY
-- =========================================================================
local function NormalizeTeam(val)
    if val == nil then return nil end
    local s = tostring(val):lower()
    if s == "1" or s == "ct" or s:find("counter") or s:find("blue") then return "CT" end
    if s == "2" or s == "t" or s:find("terror") or s:find("red") or s:find("orange") then return "T" end
    return s
end

local function IsTeammate(model, player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer or (model and model.Name == LocalPlayer.Name) then return true end
    
    local myChar = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
    if not myChar then return false end
    
    local mTeam = myChar:GetAttribute("Team") or myChar:GetAttribute("TeamId") or myChar:GetAttribute("CharacterName")
    local tTeam = (model and (model:GetAttribute("Team") or model:GetAttribute("TeamId") or model:GetAttribute("CharacterName"))) 
               or (player and (player:GetAttribute("Team") or player:GetAttribute("TeamId")))
               
    local myNorm = NormalizeTeam(mTeam)
    local tNorm = NormalizeTeam(tTeam)
    if myNorm and tNorm then return myNorm == tNorm end
    return false
end

local function IsDead(model, player)
    if model then
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        if model:GetAttribute("Dead") == true or tostring(model:GetAttribute("Health")) == "0" then return true end
    end
    if player then
        if player:GetAttribute("Dead") == true then return true end
    end
    return false
end

-- =========================================================================
-- ESP & HITBOX LOGIC
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

    local bestCandidate = nil
    local bestScreenDist = Config.Combat.FOV
    local bestHitPart = nil

    -- Iterate through Workspace.Characters
    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local player = Players:GetPlayerFromCharacter(model) or Players:FindFirstChild(model.Name)
                
                if not IsDead(model, player) then
                    local head = model:FindFirstChild("Head")
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    
                    if head and root and hum then
                        local id = model.Name
                        activeIds[id] = true
                        local isTeam = IsTeammate(model, player)
                        local dist = (root.Position - Camera.CFrame.Position).Magnitude
                        local hp = tonumber(model:GetAttribute("Health")) or hum.Health or 100
                        local maxHp = tonumber(model:GetAttribute("MaxHealth")) or hum.MaxHealth or 100
                        local displayName = (player and player.DisplayName) or model.Name

                        -- Hitbox Expander (Visual Silent Aim)
                        if Config.Combat.SilentAim and not isTeam then
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
                                end
                                
                                if Config.Visuals.HealthBar then
                                    local hpRatio = math.clamp(hp / maxHp, 0, 1)
                                    local barH = height * hpRatio
                                    d.HealthOutline.From = Vector2.new(boxPos.X - 5, boxPos.Y); d.HealthOutline.To = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.HealthOutline.Visible = true
                                    d.Health.From = Vector2.new(boxPos.X - 5, boxPos.Y + height); d.Health.To = Vector2.new(boxPos.X - 5, boxPos.Y + height - barH); d.Health.Color = Color3.fromHSV(hpRatio * 0.3, 1, 1); d.Health.Visible = true
                                end
                                
                                if Config.Visuals.NameESP then
                                    d.Name.Text = displayName; d.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); d.Name.Visible = true
                                end
                                
                                if Config.Visuals.DistanceESP then
                                    d.Distance.Text = string.format("[%dm]", math.floor(dist)); d.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); d.Distance.Visible = true
                                end
                            else
                                HideAll(Runtime.DrawingPool[id])
                            end
                        else
                            HideAll(Runtime.DrawingPool[id])
                        end

                        -- Aimlock Target Selection (LMB)
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

    if not Config.Combat.SilentAim then
        for h, data in pairs(Runtime.OriginalSizes) do
            if h and h.Parent then
                h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide
            end
        end
        table.clear(Runtime.OriginalSizes)
    end

    Runtime.TargetPart = bestHitPart

    -- LMB Aimlock Logic
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
-- ASTER-UI FRAMEWORK
-- =========================================================================
local Window = Aster:CreateWindow({
    Title = "BWX // Bloxstrike",
    Subtitle = "v4.3 Stable UI",
    ToggleUIKeybind = "K",
    Theme = "Cybrion",
    Weather = "Matrix",
})

local CombatTab = Window:Tab({ Name = "Combat", Icon = "crosshair" })
CombatTab:Section("Aimlock & Hitbox")
CombatTab:Toggle({
    Name = "LMB Aimlock",
    Flag = "AimLock",
    Default = Config.Combat.AimLock,
    Callback = function(v) Config.Combat.AimLock = v end
})
CombatTab:Slider({
    Name = "Aim Smoothness",
    Flag = "AimStr",
    Min = 5, Max = 100,
    Default = 22,
    Suffix = "%",
    Callback = function(v) Config.Combat.AimLockStrength = v / 100 end
})
CombatTab:Toggle({
    Name = "Hitbox Expander (Silent)",
    Flag = "SilentAim",
    Default = Config.Combat.SilentAim,
    Callback = function(v) Config.Combat.SilentAim = v end
})
CombatTab:Slider({
    Name = "Hitbox Size",
    Flag = "HitboxSize",
    Min = 3, Max = 16,
    Default = Config.Combat.HitboxSize,
    Suffix = " studs",
    Callback = function(v) Config.Combat.HitboxSize = v end
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
    Name = "Show FOV",
    Flag = "ShowFOV",
    Default = Config.Combat.ShowFOV,
    Callback = function(v) Config.Combat.ShowFOV = v end
})

local VisualsTab = Window:Tab({ Name = "Visuals", Icon = "eye" })
VisualsTab:Section("ESP")
VisualsTab:Toggle({ Name = "Master ESP", Flag = "MasterESP", Default = true, Callback = function(v) Config.Visuals.Enabled = v end })
VisualsTab:Toggle({ Name = "Box ESP", Flag = "BoxESP", Default = true, Callback = function(v) Config.Visuals.BoxESP = v end })
VisualsTab:Toggle({ Name = "Health Bar", Flag = "HealthBar", Default = true, Callback = function(v) Config.Visuals.HealthBar = v end })
VisualsTab:Toggle({ Name = "Name Tags", Flag = "NameESP", Default = true, Callback = function(v) Config.Visuals.NameESP = v end })
VisualsTab:Toggle({ Name = "Distance", Flag = "DistanceESP", Default = true, Callback = function(v) Config.Visuals.DistanceESP = v end })
VisualsTab:Slider({ Name = "Max Distance", Flag = "MaxDist", Min = 500, Max = 8000, Default = 5000, Suffix = "m", Callback = function(v) Config.Visuals.MaxDistance = v end })

local ModsTab = Window:Tab({ Name = "Misc", Icon = "cog" })
ModsTab:Toggle({ Name = "Anti-Flashbang", Flag = "AntiFlash", Default = true, Callback = function(v) Config.WeaponMods.AntiFlash = v end })
ModsTab:Toggle({ Name = "Auto Bunnyhop", Flag = "Bhop", Default = true, Callback = function(v) Config.Movement.Bhop = v end })

env.BWXUnload = function()
    Runtime.Active = false
    for _, conn in ipairs(Runtime.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Runtime.Connections)
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

print("[BWX] Suite v4.3 Loaded. Fixed UI & Shooting.")

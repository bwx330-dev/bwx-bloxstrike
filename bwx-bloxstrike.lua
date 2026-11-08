--[[
    ⚡ BWX // Bloxstrike Utility Suite (v7.5 Aster-NeckBone)
    Target: Roblox Bloxstrike
    Changes: Added "Neck" option to Target Bone.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end

while not Camera or not Camera.Parent do
    task.wait(0.1)
    Camera = Workspace.CurrentCamera
end

local Aster
local success, err = pcall(function()
    Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()
end)
if not success or not Aster then
    return game:GetService("StarterGui"):SetCore("SendNotification", {Title = "BWX Error", Text = "Failed to load Aster-UI: " .. tostring(err)})
end

local Config = {
    Combat = {
        AimLock = true, AimLockStrength = 0.25, TeamCheck = true,
        TargetBone = "Head", Triggerbot = false,
        Hitbox = true, HitboxSize = 5, FOV = 180,
        ShowFOV = true, FOVColor = Color3.fromRGB(50, 230, 150)
    },
    Visuals = {
        Enabled = true, BoxESP = true, Tracers = true,
        EnemyColor = Color3.fromRGB(245, 75, 75),
        NameESP = true, HealthBar = true, DistanceESP = true, MaxDistance = 5000,
    },
    WeaponMods = { NoRecoil = true, NoSpread = true, AntiFlash = true }
}

local Runtime = {
    Active = true, DrawingPool = {}, OriginalSizes = {}, FOVDrawing = nil,
    TargetPart = nil, Connections = {}, Hooks = {},
    LockCamera = false, LockedCFrame = nil, IsAimlocking = false, IsUpdating = false,
    LastTrigger = 0, FlashObjects = {}
}

Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5; Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false; Runtime.FOVDrawing.Transparency = 0.75
Runtime.FOVDrawing.Radius = Config.Combat.FOV; Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
Runtime.FOVDrawing.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

-- =========================================================================
-- FLASH DETECTION
-- =========================================================================
local function ClearFlash(obj)
    if not Config.WeaponMods.AntiFlash then return end
    local isMatch = false
    local name = tostring(obj.Name):lower()
    
    if name:find("flash") or name:find("blind") or name:find("stun") or name:find("whiteout") then isMatch = true end
    if not isMatch and obj:IsA("ColorCorrectionEffect") and (obj.Brightness > 0.3 or obj.Contrast > 0.3) then isMatch = true end
    if not isMatch and obj:IsA("BlurEffect") and obj.Size > 5 then isMatch = true end
    if not isMatch and (obj:IsA("Frame") or obj:IsA("ImageLabel")) then
        local bg = obj.BackgroundColor3
        if bg.R > 0.9 and bg.G > 0.9 and bg.B > 0.9 then
            if obj:IsA("Frame") and obj.BackgroundTransparency < 0.85 then isMatch = true
            elseif obj:IsA("ImageLabel") and obj.ImageTransparency < 0.85 then isMatch = true end
        end
    end
    
    if isMatch then
        if not table.find(Runtime.FlashObjects, obj) then table.insert(Runtime.FlashObjects, obj) end
        pcall(function()
            if obj:IsA("ColorCorrectionEffect") or obj:IsA("BlurEffect") or obj:IsA("Highlight") then obj.Enabled = false
            elseif obj:IsA("ScreenGui") then obj.Enabled = false
            elseif obj:IsA("Frame") or obj:IsA("ImageLabel") or obj:IsA("TextLabel") then obj.Visible = false end
        end)
    end
end

task.spawn(function() for _, obj in ipairs(Lighting:GetDescendants()) do pcall(ClearFlash, obj) end end)
table.insert(Runtime.Connections, Lighting.DescendantAdded:Connect(function(obj) pcall(ClearFlash, obj) end))
local pGui = LocalPlayer:WaitForChild("PlayerGui")
table.insert(Runtime.Connections, pGui.DescendantAdded:Connect(function(obj) pcall(ClearFlash, obj) end))

task.spawn(function()
    while Runtime.Active do
        task.wait(0.2)
        if Config.WeaponMods.AntiFlash then
            for i = #Runtime.FlashObjects, 1, -1 do
                local obj = Runtime.FlashObjects[i]
                if not obj or not obj.Parent then table.remove(Runtime.FlashObjects, i)
                else
                    pcall(function()
                        if obj:IsA("ColorCorrectionEffect") or obj:IsA("BlurEffect") then if obj.Enabled then obj.Enabled = false end
                        elseif obj:IsA("ScreenGui") then if obj.Enabled then obj.Enabled = false end
                        elseif obj:IsA("Frame") or obj:IsA("ImageLabel") or obj:IsA("TextLabel") then if obj.Visible then obj.Visible = false end end
                    end)
                end
            end
        end
    end
end)

-- =========================================================================
-- STRICT TEAM CHECK
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
    if not Config.Combat.TeamCheck then return false end
    if player == LocalPlayer or (model and model.Name == LocalPlayer.Name) then return true end
    if player and LocalPlayer.Team and player.Team then if LocalPlayer.Team == player.Team then return true end end
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
-- SAFE HOOKS
-- =========================================================================
local function SetupHooks()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    local oldNewIndex = mt.__newindex
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if method == "Raycast" and self == Workspace then
            if Config.WeaponMods.NoSpread then
                local origin = args[1]; local direction = args[2]
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    if (origin - Workspace.CurrentCamera.CFrame.Position).Magnitude < 15 then
                        args[2] = Workspace.CurrentCamera.CFrame.LookVector * direction.Magnitude
                    end
                end
            end
        end
        return oldNamecall(self, unpack(args))
    end)

    mt.__newindex = newcclosure(function(self, key, value)
        if self == Workspace.CurrentCamera and key == "CFrame" and Runtime.LockCamera and not Runtime.IsUpdating then
            if Runtime.IsAimlocking then
                Runtime.LockedCFrame = value
                return oldNewIndex(self, key, value)
            elseif Runtime.LockedCFrame then
                local lockX, lockY = Runtime.LockedCFrame:ToEulerAnglesYXZ()
                Runtime.IsUpdating = true
                oldNewIndex(self, key, CFrame.new(value.Position) * CFrame.fromEulerAnglesYXZ(lockX, lockY, 0))
                Runtime.IsUpdating = false
                return
            end
        end
        return oldNewIndex(self, key, value)
    end)
    
    setreadonly(mt, true)
    
    Runtime.Hooks["cleanup_mt"] = function()
        local mt2 = getrawmetatable(game)
        setreadonly(mt2, false)
        mt2.__namecall = oldNamecall
        mt2.__newindex = oldNewIndex
        setreadonly(mt2, true)
    end
end
pcall(SetupHooks)

-- =========================================================================
-- DRAWINGS
-- =========================================================================
local function GetDrawings(id)
    local d = Runtime.DrawingPool[id]
    if not d then
        d = { BoxOutline = Drawing.new("Square"), Box = Drawing.new("Square"), HealthOutline = Drawing.new("Line"), Health = Drawing.new("Line"), Name = Drawing.new("Text"), Distance = Drawing.new("Text"), Tracer = Drawing.new("Line") }
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
        d.Name.Visible = false; d.Distance.Visible = false; d.Tracer.Visible = false
    end
end

local function DestroyAll(d)
    for _, v in pairs(d) do pcall(function() v:Remove() end) end
end

-- =========================================================================
-- RENDER LOOP
-- =========================================================================
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local vp = Workspace.CurrentCamera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local activeIds = {}
    
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center; Runtime.FOVDrawing.Radius = Config.Combat.FOV
        Runtime.FOVDrawing.Color = Config.Combat.FOVColor; Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    local bestCandidate, bestScreenDist, bestHitPart = nil, Config.Combat.FOV, nil

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
                        local isTeam = IsTeammate(model, player)
                        local dist = (root.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
                        local hp = (hum and hum.Health) or tonumber(model:GetAttribute("Health")) or 100
                        local maxHp = (hum and hum.MaxHealth) or tonumber(model:GetAttribute("MaxHealth")) or 100
                        local displayName = (player and player.DisplayName) or model.Name

                        if Config.Combat.Hitbox and not isTeam then
                            if not Runtime.OriginalSizes[head] then
                                Runtime.OriginalSizes[head] = {Size = head.Size, Transparency = head.Transparency, CanCollide = head.CanCollide}
                            end
                            head.Size = Vector3.new(Config.Combat.HitboxSize, Config.Combat.HitboxSize, Config.Combat.HitboxSize)
                            head.Transparency = 0.65; head.CanCollide = false
                        end

                        if Config.Visuals.Enabled and not isTeam and dist <= Config.Visuals.MaxDistance then
                            activeIds[id] = true
                            local topPos, onTop = Workspace.CurrentCamera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
                            local botPos, onBot = Workspace.CurrentCamera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
                            
                            if onTop and onBot and topPos.Z > 0 and botPos.Z > 0 then
                                local height = math.abs(botPos.Y - topPos.Y); local width = height * 0.58
                                local boxPos = Vector2.new(topPos.X - width/2, topPos.Y)
                                local d = GetDrawings(id)
                                
                                if Config.Visuals.BoxESP then
                                    d.BoxOutline.Size = Vector2.new(width, height); d.BoxOutline.Position = boxPos; d.BoxOutline.Visible = true
                                    d.Box.Size = Vector2.new(width, height); d.Box.Position = boxPos; d.Box.Color = Config.Visuals.EnemyColor; d.Box.Visible = true
                                else d.BoxOutline.Visible = false; d.Box.Visible = false end
                                
                                if Config.Visuals.Tracers then
                                    d.Tracer.From = Vector2.new(vp.X / 2, vp.Y); d.Tracer.To = Vector2.new(topPos.X, botPos.Y)
                                    d.Tracer.Color = Config.Visuals.EnemyColor; d.Tracer.Visible = true
                                else d.Tracer.Visible = false end

                                if Config.Visuals.HealthBar then
                                    local hpRatio = math.clamp(hp / maxHp, 0, 1); local barH = height * hpRatio; local barX = boxPos.X - 5
                                    d.HealthOutline.From = Vector2.new(barX, boxPos.Y); d.HealthOutline.To = Vector2.new(barX, boxPos.Y + height); d.HealthOutline.Visible = true
                                    d.Health.From = Vector2.new(barX, boxPos.Y + height); d.Health.To = Vector2.new(barX, boxPos.Y + height - barH); d.Health.Color = Color3.fromHSV(hpRatio * 0.3, 1, 1); d.Health.Visible = true
                                else d.HealthOutline.Visible = false; d.Health.Visible = false end
                                
                                if Config.Visuals.NameESP then d.Name.Text = displayName; d.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14); d.Name.Visible = true else d.Name.Visible = false end
                                if Config.Visuals.DistanceESP then d.Distance.Text = string.format("[%dm]", math.floor(dist)); d.Distance.Position = Vector2.new(topPos.X, boxPos.Y + height + 2); d.Distance.Visible = true else d.Distance.Visible = false end
                            else HideAll(Runtime.DrawingPool[id]) end
                        elseif Runtime.DrawingPool[id] then HideAll(Runtime.DrawingPool[id]) end

                        if Config.Combat.AimLock and not isTeam then
                            local targetPart = head
                            if Config.Combat.TargetBone == "Torso" then 
                                targetPart = root
                            elseif Config.Combat.TargetBone == "Neck" then
                                -- Calculate virtual neck position (between head and upper torso)
                                local basePart = model:FindFirstChild("UpperTorso") or root
                                targetPart = {Position = head.Position:Lerp(basePart.Position, 0.25)}
                            elseif Config.Combat.TargetBone == "Closest" then
                                local headScreen, headOn = Workspace.CurrentCamera:WorldToViewportPoint(head.Position)
                                local rootScreen, rootOn = Workspace.CurrentCamera:WorldToViewportPoint(root.Position)
                                if headOn and rootOn then
                                    local headDist = (Vector2.new(headScreen.X, headScreen.Y) - center).Magnitude
                                    local rootDist = (Vector2.new(rootScreen.X, rootScreen.Y) - center).Magnitude
                                    if rootDist < headDist then targetPart = root end
                                end
                            end
                            
                            local partScreen, partOn = Workspace.CurrentCamera:WorldToViewportPoint(targetPart.Position)
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

    for id, d in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then DestroyAll(d); Runtime.DrawingPool[id] = nil end
    end

    if not Config.Combat.Hitbox then
        for h, data in pairs(Runtime.OriginalSizes) do
            if h and h.Parent then h.Size = data.Size; h.Transparency = data.Transparency; h.CanCollide = data.CanCollide end
        end
        table.clear(Runtime.OriginalSizes)
    end

    Runtime.TargetPart = bestHitPart
    local isFiring = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    local now = tick()

    if Config.Combat.AimLock and Runtime.TargetPart and isFiring and not UserInputService:GetFocusedTextBox() then
        Runtime.IsAimlocking = true
        local targetPos = Runtime.TargetPart.Position
        Workspace.CurrentCamera.CFrame = Workspace.CurrentCamera.CFrame:Lerp(CFrame.lookAt(Workspace.CurrentCamera.CFrame.Position, targetPos), Config.Combat.AimLockStrength)
        Runtime.IsAimlocking = false
    end

    if Config.WeaponMods.NoRecoil and isFiring and not UserInputService:GetFocusedTextBox() then
        if not Runtime.LockCamera then
            Runtime.LockedCFrame = Workspace.CurrentCamera.CFrame; Runtime.LockCamera = true
        end
    else
        Runtime.LockCamera = false; Runtime.LockedCFrame = nil
    end

    if Config.Combat.Triggerbot and Runtime.TargetPart and not isFiring and not UserInputService:GetFocusedTextBox() then
        if now - Runtime.LastTrigger > 0.12 then
            Runtime.LastTrigger = now
            VirtualInputManager:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, true, game, 1)
            VirtualInputManager:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, false, game, 1)
        end
    end
end))

-- =========================================================================
-- ASTER UI
-- =========================================================================
local Window = Aster:CreateWindow({
    Title = "BWX // Bloxstrike", Subtitle = "v7.5 Aster-NeckBone",
    ToggleUIKeybind = "K", Theme = "Cybrion", Weather = "Matrix",
})

local CombatTab = Window:Tab({ Name = "Combat", Icon = "crosshair" })
CombatTab:Section("Aimlock")
CombatTab:Toggle({ Name = "LMB Aimlock", Flag = "AimLock", Default = Config.Combat.AimLock, Callback = function(v) Config.Combat.AimLock = v end })
CombatTab:Slider({ Name = "Aim Smoothness", Flag = "AimStr", Min = 5, Max = 100, Default = 25, Suffix = "%", Callback = function(v) Config.Combat.AimLockStrength = v / 100 end })
CombatTab:Dropdown({ Name = "Target Bone", Flag = "TargetBone", Options = {"Head", "Neck", "Torso", "Closest"}, Default = "Head", Callback = function(v) Config.Combat.TargetBone = v end })
CombatTab:Toggle({ Name = "Team Check", Flag = "TeamCheck", Default = Config.Combat.TeamCheck, Callback = function(v) Config.Combat.TeamCheck = v end })
CombatTab:Section("Triggerbot")
CombatTab:Toggle({ Name = "Auto-Fire", Flag = "Triggerbot", Default = Config.Combat.Triggerbot, Callback = function(v) Config.Combat.Triggerbot = v end })
CombatTab:Section("Hitbox")
CombatTab:Toggle({ Name = "Hitbox Expander", Flag = "Hitbox", Default = Config.Combat.Hitbox, Callback = function(v) Config.Combat.Hitbox = v end })
CombatTab:Slider({ Name = "Hitbox Size", Flag = "HitboxSize", Min = 3, Max = 20, Default = 5, Suffix = " studs", Callback = function(v) Config.Combat.HitboxSize = v end })
CombatTab:Slider({ Name = "FOV Radius", Flag = "FOV", Min = 30, Max = 400, Default = 180, Suffix = "px", Callback = function(v) Config.Combat.FOV = v end })
CombatTab:Toggle({ Name = "Show FOV", Flag = "ShowFOV", Default = true, Callback = function(v) Config.Combat.ShowFOV = v end })

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
ModsTab:Toggle({ Name = "No Recoil (Full Lock)", Flag = "NoRecoil", Default = true, Callback = function(v) Config.WeaponMods.NoRecoil = v end })
ModsTab:Toggle({ Name = "No Spread (Safe Raycast)", Flag = "NoSpread", Default = true, Callback = function(v) Config.WeaponMods.NoSpread = v end })
ModsTab:Toggle({ Name = "Anti-Flashbang", Flag = "AntiFlash", Default = true, Callback = function(v) Config.WeaponMods.AntiFlash = v end })

local MiscTab = Window:Tab({ Name = "Misc", Icon = "cog" })
MiscTab:Button({ Name = "UNLOAD SCRIPT (RightShift)", Callback = function() if env.BWXUnload then env.BWXUnload() end end })

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
    local sg = game:GetService("CoreGui"):FindFirstChild("AsterUI") or LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("AsterUI")
    if sg then sg:Destroy() end
    print("[BWX] Unloaded Successfully.")
    env.BWXUnload = nil
end
env.BWXUnload = env.BWXUnload

UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        if env.BWXUnload then env.BWXUnload() end
    end
end)

print("[BWX] Suite v7.5 Loaded. Neck Bone Added.")

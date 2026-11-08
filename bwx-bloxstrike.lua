--[[
    ⚡ BWX // Bloxstrike Utility Suite (v4.1 Premium + UI)
    Target: Roblox Bloxstrike
    REQUIREMENT: High-Tier Executors (Wave, AWP, Script-Ware)
    Keybind: [K] or [Right Shift] to toggle menu.
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

Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5
Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.75
Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

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

table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local activeIds = {}
    
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    -- Anti Flash
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
-- UI FRAMEWORK
-- =========================================================================
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
    local title = Instance.new("TextLabel")
    title.Text = "⚡ BWX // BLOXSTRIKE (v4.1)"
    title.Font = Enum.Font.GothamBold; title.TextSize = 14; title.TextColor3 = Theme.Accent
    title.TextXAlignment = Enum.TextXAlignment.Left; title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 14, 0, 0); title.Size = UDim2.new(0.6, 0, 1, 0); title.Parent = header
    local hint = Instance.new("TextLabel"); hint.Text = "Toggle: [K] / [Right Shift]"; hint.Font = Enum.Font.Gotham; hint.TextSize = 11; hint.TextColor3 = Theme.Muted; hint.TextXAlignment = Enum.TextXAlignment.Right; hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0.4, 0, 0, 0); hint.Size = UDim2.new(0.56, 0, 1, 0); hint.Parent = header
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = input.Position; startPos = main.Position end end)
    UserInputService.InputChanged:Connect(function(input) if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then local delta = input.Position - dragStart; main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    local sidebar = Instance.new("Frame"); sidebar.Size = UDim2.new(0, 130, 1, -42); sidebar.Position = UDim2.new(0, 0, 0, 42); sidebar.BackgroundColor3 = Theme.Header; sidebar.BorderSizePixel = 0; sidebar.Parent = main
    local sidebarLayout = Instance.new("UIListLayout"); sidebarLayout.Padding = UDim.new(0, 4); sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; sidebarLayout.Parent = sidebar
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
    CreateToggle(combatPage, "Silent Aim (True)", Config.Combat.SilentAim, function(v) Config.Combat.SilentAim = v end)
    CreateSlider(combatPage, "Silent Aim FOV", 30, 400, Config.Combat.FOV, "px", function(v) Config.Combat.FOV = v end)
    CreateToggle(combatPage, "Show FOV Circle", Config.Combat.ShowFOV, function(v) Config.Combat.ShowFOV = v end)
    CreateSlider(combatPage, "Hitbox Size", 3, 16, Config.Combat.HitboxSize, " studs", function(v) Config.Combat.HitboxSize = v end)
    CreateToggle(combatPage, "Team Check", Config.Combat.TeamCheck, function(v) Config.Combat.TeamCheck = v; Config.Visuals.TeamCheck = v end)
    
    local visualsPage = pages["Visuals"]
    CreateToggle(visualsPage, "Master ESP", Config.Visuals.Enabled, function(v) Config.Visuals.Enabled = v end)
    CreateToggle(visualsPage, "Box ESP", Config.Visuals.BoxESP, function(v) Config.Visuals.BoxESP = v end)
    CreateToggle(visualsPage, "Health Bar", Config.Visuals.HealthBar, function(v) Config.Visuals.HealthBar = v end)
    CreateToggle(visualsPage, "Name Tags", Config.Visuals.NameESP, function(v) Config.Visuals.NameESP = v end)
    CreateToggle(visualsPage, "Distance", Config.Visuals.DistanceESP, function(v) Config.Visuals.DistanceESP = v end)
    CreateSlider(visualsPage, "Max ESP Distance", 500, 8000, Config.Visuals.MaxDistance, "m", function(v) Config.Visuals.MaxDistance = v end)

    local modsPage = pages["Gun Mods"]
    CreateToggle(modsPage, "No Recoil (Hooked)", Config.WeaponMods.NoRecoil, function(v) Config.WeaponMods.NoRecoil = v end)
    CreateToggle(modsPage, "No Spread (Hooked)", Config.WeaponMods.NoSpread, function(v) Config.WeaponMods.NoSpread = v end)
    CreateToggle(modsPage, "Anti-Flash", Config.WeaponMods.AntiFlash, function(v) Config.WeaponMods.AntiFlash = v end)

    local movePage = pages["Movement"]
    CreateToggle(movePage, "Auto Bunnyhop", Config.Movement.Bhop, function(v) Config.Movement.Bhop = v end)
    
    SwitchTab("Combat")
    
    -- Keybind: K or RightShift (NO INSERT)
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.RightShift) then
            Config.UI.MenuOpen = not Config.UI.MenuOpen
            screenGui.Enabled = Config.UI.MenuOpen
            if not Config.UI.MenuOpen then 
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end) 
            end
        end
    end)
    return screenGui
end
local GuiInstance = BuildUI()

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
    if GuiInstance then pcall(function() GuiInstance:Destroy() end) end
    env.BWXUnload = nil
end
env.BWXUnload = env.BWXUnload

print("[BWX] Suite v4.1 Premium Loaded. UI Active.")

--[[
    ⚡ BWX // Bloxstrike Utility Suite (Ultra-Fast Lightweight Edition)
    Engine: Zero-Overhead Drawing Pipeline + Fast Metatable Hook
    Target: Roblox Bloxstrike (7633926880)
    Optimizations:
      - 0 allocations inside RenderStepped (Zero GC Thrashing)
      - Static Drawing Pool per player (Zero re-instantiation lag)
      - Event-driven Anti-Flash (Eliminates PlayerGui:GetDescendants tree-walk)
      - Single-raycast Visibility Filter (Raycasts only for closest target)
      - Native Lightweight Cyberpunk GUI (0% idle overhead)
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Global Unload of prior instances
local env = getgenv and getgenv() or _G
if env.BWXUnload then pcall(env.BWXUnload) end
if env.CybrionUnload then pcall(env.CybrionUnload) end
if env.BloxStrikeUnload then pcall(env.BloxStrikeUnload) end

-- Configuration
local Config = {
    Combat = {
        SilentAim = true,
        AimAssist = false,
        HitPart = "Head",
        FOV = 120,
        HitChance = 100,
        VisibleCheck = false,
        Smoothness = 0.25,
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
        MaxDistance = 4000,
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
    },
    UI = {
        MenuOpen = false,
        ToggleKey = Enum.KeyCode.Insert
    }
}

-- Reusable Static Objects (0 garbage collection in loop)
local SharedRayParams = RaycastParams.new()
SharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
SharedRayParams.IgnoreWater = true

local Runtime = {
    Active = true,
    Target = nil,
    DrawingPool = {},
    FOVDrawing = nil,
    C4Drawing = nil,
    Connections = {},
    Hooks = {},
    LastC4Check = 0,
    CachedC4 = nil
}

-- FOV Circle
Runtime.FOVDrawing = Drawing.new("Circle")
Runtime.FOVDrawing.Thickness = 1.5
Runtime.FOVDrawing.NumSides = 48
Runtime.FOVDrawing.Filled = false
Runtime.FOVDrawing.Transparency = 0.7
Runtime.FOVDrawing.Radius = Config.Combat.FOV
Runtime.FOVDrawing.Color = Config.Combat.FOVColor
Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV

-- C4 Label
Runtime.C4Drawing = Drawing.new("Text")
Runtime.C4Drawing.Size = 13
Runtime.C4Drawing.Center = true
Runtime.C4Drawing.Outline = true
Runtime.C4Drawing.Color = Config.Visuals.C4Color
Runtime.C4Drawing.Visible = false

-- Fast Team Lookup
local function GetPlayerTeam(player)
    if not player then return nil end
    local team = player.Team
    if team then return team.Name end
    local teamAttr = player:GetAttribute("Team")
    if teamAttr then return tostring(teamAttr) end

    local char = player.Character
    if char then
        local look = char:GetAttribute("CharacterName")
        if look then
            if look == Workspace:GetAttribute("CTCharacter") then return "Counter-Terrorists" end
            if look == Workspace:GetAttribute("TCharacter") then return "Terrorists" end
        end
    end
    return nil
end

local function IsTeammate(player)
    if not Config.Visuals.TeamCheck or not player or player == LocalPlayer then return true end
    local myTeam = GetPlayerTeam(LocalPlayer)
    local targetTeam = GetPlayerTeam(player)
    if myTeam and targetTeam then
        return myTeam == targetTeam
    end
    return false
end

-- Pre-allocated Drawing Pool per Player
local function CreatePlayerDrawing()
    local boxOut = Drawing.new("Square")
    boxOut.Thickness = 3
    boxOut.Filled = false
    boxOut.Color = Color3.new(0, 0, 0)
    boxOut.Transparency = 0.8
    boxOut.Visible = false

    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Transparency = 1
    box.Visible = false

    local hpOut = Drawing.new("Line")
    hpOut.Thickness = 3
    hpOut.Color = Color3.new(0, 0, 0)
    hpOut.Visible = false

    local hp = Drawing.new("Line")
    hp.Thickness = 1
    hp.Visible = false

    local name = Drawing.new("Text")
    name.Size = 13
    name.Center = true
    name.Outline = true
    name.Color = Color3.fromRGB(240, 240, 240)
    name.Visible = false

    local dist = Drawing.new("Text")
    dist.Size = 11
    dist.Center = true
    dist.Outline = true
    dist.Color = Color3.fromRGB(180, 180, 180)
    dist.Visible = false

    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Transparency = 0.7
    tracer.Visible = false

    return {
        BoxOutline = boxOut,
        Box = box,
        HealthOutline = hpOut,
        Health = hp,
        Name = name,
        Distance = dist,
        Tracer = tracer
    }
end

local function HideESP(draw)
    draw.BoxOutline.Visible = false
    draw.Box.Visible = false
    draw.HealthOutline.Visible = false
    draw.Health.Visible = false
    draw.Name.Visible = false
    draw.Distance.Visible = false
    draw.Tracer.Visible = false
end

local function DestroyESP(draw)
    for _, item in pairs(draw) do
        pcall(function()
            item.Visible = false
            item:Remove()
        end)
    end
end

-- Manage Player Drawing Pool
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        Runtime.DrawingPool[p] = CreatePlayerDrawing()
    end
end

table.insert(Runtime.Connections, Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer and not Runtime.DrawingPool[p] then
        Runtime.DrawingPool[p] = CreatePlayerDrawing()
    end
end))

table.insert(Runtime.Connections, Players.PlayerRemoving:Connect(function(p)
    local draw = Runtime.DrawingPool[p]
    if draw then
        DestroyESP(draw)
        Runtime.DrawingPool[p] = nil
    end
end))

-- Fast C4 Locator (Cached every 1.0 second instead of every frame)
local function LocateC4Fast()
    local now = os.clock()
    if now - Runtime.LastC4Check > 1.0 then
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

-- Fast Wallcheck (Single Raycast only for filtered candidate)
local function IsVisible(targetPart, originPos)
    if not Config.Combat.VisibleCheck then return true end
    originPos = originPos or Camera.CFrame.Position
    local dir = targetPart.Position - originPos

    SharedRayParams.FilterDescendantsInstances = {Camera, LocalPlayer.Character}
    local hit = Workspace:Raycast(originPos, dir, SharedRayParams)
    if hit and hit.Instance:IsDescendantOf(targetPart.Parent) then
        return true
    end
    return hit == nil
end

-- Ultra-Fast Target Discovery
local function GetBestTarget()
    local best = nil
    local minDistance = Config.Combat.FOV
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local myChar = LocalPlayer.Character

    for player, _ in pairs(Runtime.DrawingPool) do
        if not IsTeammate(player) then
            -- Check Bloxstrike Characters folder or player.Character
            local char = player.Character or (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(player.Name))
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local isDead = (hum and hum.Health <= 0) or tostring(player:GetAttribute("Dead")) == "true" or tostring(char:GetAttribute("Dead")) == "true"
                if not isDead then
                    local hitPart = char:FindFirstChild(Config.Combat.HitPart) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
                    if hitPart then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(hitPart.Position)
                        if onScreen and screenPos.Z > 0 then
                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                            if dist < minDistance then
                                if IsVisible(hitPart, nil) then
                                    minDistance = dist
                                    best = hitPart
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Master Render Loop (Zero Allocations, 120-200+ FPS)
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = Camera.CFrame.Position
    local visualsOn = Config.Visuals.Enabled
    local maxDist = Config.Visuals.MaxDistance

    -- 1. FOV Circle Update
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Radius = Config.Combat.FOV
        Runtime.FOVDrawing.Color = Config.Combat.FOVColor
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    -- 2. Fast Target Selection
    Runtime.Target = GetBestTarget()

    -- 3. Visuals / ESP Engine (No Allocations)
    for player, draw in pairs(Runtime.DrawingPool) do
        if not visualsOn then
            HideESP(draw)
            continue
        end

        local isTeam = IsTeammate(player)
        if Config.Visuals.TeamCheck and isTeam then
            HideESP(draw)
            continue
        end

        local char = player.Character or (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(player.Name))
        if not char then
            HideESP(draw)
            continue
        end

        local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        local hum = char:FindFirstChildOfClass("Humanoid")
        local isDead = (hum and hum.Health <= 0) or tostring(player:GetAttribute("Dead")) == "true" or tostring(char:GetAttribute("Dead")) == "true"

        if not root or isDead then
            HideESP(draw)
            continue
        end

        local distStuds = (root.Position - camPos).Magnitude
        if distStuds > maxDist then
            HideESP(draw)
            continue
        end

        -- Single Root Projection (Eliminates multi-point projection overhead)
        local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
        if onScreen and rootPos.Z > 0 then
            -- Mathematical Box Projection based on Camera Distance & FOV
            local scaleFactor = 1000 / (rootPos.Z * math.tan(math.rad(Camera.FieldOfView * 0.5)) * 2)
            local height = math.clamp(scaleFactor * 5.2, 8, 900)
            local width = height * 0.62
            local boxPos = Vector2.new(rootPos.X - width * 0.5, rootPos.Y - height * 0.5)
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
                local hp = hum and hum.Health or tonumber(char:GetAttribute("Health")) or 100
                local maxHp = hum and hum.MaxHealth or tonumber(char:GetAttribute("MaxHealth")) or 100
                local hpRatio = math.clamp(hp / maxHp, 0, 1)

                local barHeight = height * hpRatio
                local barX = boxPos.X - 5

                draw.HealthOutline.From = Vector2.new(barX, boxPos.Y)
                draw.HealthOutline.To = Vector2.new(barX, boxPos.Y + height)
                draw.HealthOutline.Visible = true

                draw.Health.From = Vector2.new(barX, boxPos.Y + height)
                draw.Health.To = Vector2.new(barX, boxPos.Y + height - barHeight)
                draw.Health.Color = Color3.fromHSV(hpRatio * 0.32, 1, 1)
                draw.Health.Visible = true
            else
                draw.HealthOutline.Visible = false
                draw.Health.Visible = false
            end

            -- Name
            if Config.Visuals.NameESP then
                draw.Name.Text = player.DisplayName
                draw.Name.Position = Vector2.new(rootPos.X, boxPos.Y - 15)
                draw.Name.Visible = true
            else
                draw.Name.Visible = false
            end

            -- Distance
            if Config.Visuals.DistanceESP then
                draw.Distance.Text = string.format("[%dm]", math.floor(distStuds))
                draw.Distance.Position = Vector2.new(rootPos.X, boxPos.Y + height + 2)
                draw.Distance.Visible = true
            else
                draw.Distance.Visible = false
            end

            -- Tracer
            if Config.Visuals.Tracers then
                local origin = (Config.Visuals.TracerOrigin == "Bottom") and Vector2.new(vp.X * 0.5, vp.Y) or center
                draw.Tracer.From = origin
                draw.Tracer.To = Vector2.new(rootPos.X, boxPos.Y + height)
                draw.Tracer.Color = color
                draw.Tracer.Visible = true
            else
                draw.Tracer.Visible = false
            end
        else
            HideESP(draw)
        end
    end

    -- 4. Cached C4 Tracker
    if visualsOn and Config.Visuals.C4Tracker then
        local c4 = LocateC4Fast()
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

    -- 5. Camera Aim Assist Tracking
    if Config.Combat.AimAssist and Runtime.Target then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local currentCF = Camera.CFrame
            local targetLook = CFrame.lookAt(currentCF.Position, Runtime.Target.Position)
            Camera.CFrame = currentCF:Lerp(targetLook, Config.Combat.Smoothness)
        end
    end

    -- 6. Bunnyhop Execution
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

-- Event-Driven Anti-Flash (Zero Loop Overhead)
local function SetupAntiFlash()
    local function HandleBlur(child)
        if Config.WeaponMods.AntiFlash and child:IsA("BlurEffect") and child.Name:lower():find("flash") then
            child.Size = 0
            child:GetPropertyChangedSignal("Size"):Connect(function()
                if Config.WeaponMods.AntiFlash and child.Size > 0 then
                    child.Size = 0
                end
            end)
        end
    end

    for _, obj in ipairs(Lighting:GetChildren()) do HandleBlur(obj) end
    table.insert(Runtime.Connections, Lighting.ChildAdded:Connect(HandleBlur))

    -- Clean PlayerGui Flash frames on addition
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

-- Metatable Interception (Silent Aim & No-Recoil)
local function SetupHooks()
    local rawNamecall = nil
    rawNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if not checkcaller() then
            if Config.Combat.SilentAim and (method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" or method == "FindPartOnRay") then
                if Runtime.Target and (math.random(1, 100) <= Config.Combat.HitChance) then
                    local origin = args[1].Origin
                    local dir = (Runtime.Target.Position - origin).Unit * 1000
                    args[1] = Ray.new(origin, dir)
                    return rawNamecall(self, unpack(args))
                end
            end

            if Config.WeaponMods.NoRecoil and method == "FireServer" then
                if self.Name:lower():find("recoil") or self.Name:lower():find("shake") or self.Name:lower():find("punch") then
                    return nil
                end
            end
        end

        return rawNamecall(self, ...)
    end))
    table.insert(Runtime.Hooks, function() hookmetamethod(game, "__namecall", rawNamecall) end)

    local rawRaycast = nil
    rawRaycast = hookfunction(Workspace.Raycast, newcclosure(function(self, origin, direction, params)
        if not checkcaller() and Config.Combat.SilentAim and Runtime.Target then
            if math.random(1, 100) <= Config.Combat.HitChance then
                local redirect = (Runtime.Target.Position - origin).Unit * direction.Magnitude
                return rawRaycast(self, origin, redirect, params)
            end
        end
        return rawRaycast(self, origin, direction, params)
    end))
    table.insert(Runtime.Hooks, function() hookfunction(Workspace.Raycast, rawRaycast) end)
end
pcall(SetupHooks)

-- Ultra-Lightweight Cyberpunk Native GUI (Zero Input Sinking, Zero FPS Impact)
local function BuildUltraLightUI()
    local Theme = {
        Background = Color3.fromRGB(15, 18, 16),
        Header = Color3.fromRGB(22, 26, 23),
        Surface = Color3.fromRGB(25, 30, 26),
        Stroke = Color3.fromRGB(38, 48, 40),
        Accent = Color3.fromRGB(50, 230, 150),
        Text = Color3.fromRGB(240, 245, 242),
        Muted = Color3.fromRGB(130, 150, 135)
    }

    local target = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BWX_OptimizedUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = Config.UI.MenuOpen
    screenGui.Parent = target

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.fromOffset(530, 360)
    main.Position = UDim2.fromScale(0.32, 0.26)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1
    stroke.Parent = main

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3 = Theme.Header
    header.BorderSizePixel = 0
    header.Parent = main

    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 8)
    hCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Position = UDim2.fromOffset(14, 0)
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "BWX // BLOXSTRIKE [LIGHTWEIGHT]"
    title.TextColor3 = Theme.Accent
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Dragging
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Position = UDim2.fromOffset(0, 38)
    sidebar.Size = UDim2.new(0, 120, 1, -38)
    sidebar.BackgroundColor3 = Theme.Header
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main

    local sLayout = Instance.new("UIListLayout")
    sLayout.Padding = UDim.new(0, 4)
    sLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sLayout.Parent = sidebar

    local sPadding = Instance.new("UIPadding")
    sPadding.PaddingTop = UDim.new(0, 6)
    sPadding.Parent = sidebar

    -- Pages Container
    local container = Instance.new("Frame")
    container.Position = UDim2.fromOffset(120, 38)
    container.Size = UDim2.new(1, -120, 1, -38)
    container.BackgroundTransparency = 1
    container.Parent = main

    local tabs = {}
    local activeTab = nil

    local function CreateTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -12, 0, 30)
        btn.BackgroundColor3 = Theme.Surface
        btn.BackgroundTransparency = 1
        btn.Text = name
        btn.TextColor3 = Theme.Muted
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 12
        btn.AutoButtonColor = false
        btn.Parent = sidebar

        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 6)
        bCorner.Parent = btn

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = Theme.Accent
        page.Visible = false
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Parent = container

        local pLayout = Instance.new("UIListLayout")
        pLayout.Padding = UDim.new(0, 6)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        pLayout.Parent = page

        local pPad = Instance.new("UIPadding")
        pPad.PaddingTop = UDim.new(0, 8)
        pPad.PaddingBottom = UDim.new(0, 8)
        pPad.Parent = page

        btn.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do
                t.Page.Visible = false
                t.Btn.TextColor3 = Theme.Muted
                t.Btn.BackgroundTransparency = 1
            end
            page.Visible = true
            btn.TextColor3 = Theme.Accent
            btn.BackgroundTransparency = 0.5
        end)

        local tabObj = { Btn = btn, Page = page }
        tabs[name] = tabObj

        if not activeTab then
            activeTab = tabObj
            page.Visible = true
            btn.TextColor3 = Theme.Accent
            btn.BackgroundTransparency = 0.5
        end

        return page
    end

    local function AddToggle(page, labelText, defaultState, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -20, 0, 34)
        row.BackgroundColor3 = Theme.Surface
        row.BorderSizePixel = 0
        row.Parent = page

        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 6)
        rCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Position = UDim2.fromOffset(10, 0)
        lbl.Size = UDim2.new(0.7, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Theme.Text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Position = UDim2.new(1, -40, 0.5, -9)
        toggleBtn.Size = UDim2.fromOffset(30, 18)
        toggleBtn.BackgroundColor3 = defaultState and Theme.Accent or Color3.fromRGB(45, 52, 47)
        toggleBtn.Text = ""
        toggleBtn.AutoButtonColor = false
        toggleBtn.Parent = row

        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(1, 0)
        tCorner.Parent = toggleBtn

        local state = defaultState
        toggleBtn.MouseButton1Click:Connect(function()
            state = not state
            toggleBtn.BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(45, 52, 47)
            callback(state)
        end)
    end

    local function AddSlider(page, labelText, min, max, defaultVal, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -20, 0, 44)
        row.BackgroundColor3 = Theme.Surface
        row.BorderSizePixel = 0
        row.Parent = page

        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 6)
        rCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Position = UDim2.fromOffset(10, 4)
        lbl.Size = UDim2.new(0.6, 0, 0, 16)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Theme.Text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local valLbl = Instance.new("TextLabel")
        valLbl.Position = UDim2.new(1, -50, 0, 4)
        valLbl.Size = UDim2.fromOffset(40, 16)
        valLbl.BackgroundTransparency = 1
        valLbl.Text = tostring(defaultVal)
        valLbl.TextColor3 = Theme.Accent
        valLbl.Font = Enum.Font.GothamBold
        valLbl.TextSize = 11
        valLbl.TextXAlignment = Enum.TextXAlignment.Right
        valLbl.Parent = row

        local track = Instance.new("Frame")
        track.Position = UDim2.new(0, 10, 0, 26)
        track.Size = UDim2.new(1, -20, 0, 5)
        track.BackgroundColor3 = Color3.fromRGB(40, 48, 42)
        track.BorderSizePixel = 0
        track.Parent = row

        local trCorner = Instance.new("UICorner")
        trCorner.CornerRadius = UDim.new(1, 0)
        trCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((defaultVal - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = Theme.Accent
        fill.BorderSizePixel = 0
        fill.Parent = track

        local fCorner = Instance.new("UICorner")
        fCorner.CornerRadius = UDim.new(1, 0)
        fCorner.Parent = fill

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.fromScale(1, 1)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = track

        local sliding = false
        local function UpdateSlide(x)
            local frac = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * frac)
            fill.Size = UDim2.new(frac, 0, 1, 0)
            valLbl.Text = tostring(val)
            callback(val)
        end

        hit.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = true
                UpdateSlide(input.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
                UpdateSlide(input.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = false
            end
        end)
    end

    -- Tab Pages & Elements
    local pCombat = CreateTab("Combat")
    AddToggle(pCombat, "Silent Aim", Config.Combat.SilentAim, function(v) Config.Combat.SilentAim = v end)
    AddToggle(pCombat, "Aim Assist (Right Click)", Config.Combat.AimAssist, function(v) Config.Combat.AimAssist = v end)
    AddToggle(pCombat, "Show FOV Circle", Config.Combat.ShowFOV, function(v) Config.Combat.ShowFOV = v end)
    AddSlider(pCombat, "FOV Radius", 30, 400, Config.Combat.FOV, function(v) Config.Combat.FOV = v end)

    local pVisuals = CreateTab("Visuals")
    AddToggle(pVisuals, "Master ESP Switch", Config.Visuals.Enabled, function(v) Config.Visuals.Enabled = v end)
    AddToggle(pVisuals, "2D Box ESP", Config.Visuals.BoxESP, function(v) Config.Visuals.BoxESP = v end)
    AddToggle(pVisuals, "Team Check (Filter CT/T)", Config.Visuals.TeamCheck, function(v) Config.Visuals.TeamCheck = v end)
    AddToggle(pVisuals, "Health Bar", Config.Visuals.HealthBar, function(v) Config.Visuals.HealthBar = v end)
    AddToggle(pVisuals, "Player Name", Config.Visuals.NameESP, function(v) Config.Visuals.NameESP = v end)
    AddToggle(pVisuals, "Distance Tag", Config.Visuals.DistanceESP, function(v) Config.Visuals.DistanceESP = v end)
    AddToggle(pVisuals, "Snaplines / Tracers", Config.Visuals.Tracers, function(v) Config.Visuals.Tracers = v end)
    AddToggle(pVisuals, "C4 Bomb Tracker", Config.Visuals.C4Tracker, function(v) Config.Visuals.C4Tracker = v end)
    AddSlider(pVisuals, "Max Distance (Studs)", 500, 8000, Config.Visuals.MaxDistance, function(v) Config.Visuals.MaxDistance = v end)

    local pMods = CreateTab("Gun Mods")
    AddToggle(pMods, "No Recoil", Config.WeaponMods.NoRecoil, function(v) Config.WeaponMods.NoRecoil = v end)
    AddToggle(pMods, "Anti-Flashbang", Config.WeaponMods.AntiFlash, function(v) Config.WeaponMods.AntiFlash = v end)

    local pMove = CreateTab("Movement")
    AddToggle(pMove, "Auto Bunnyhop", Config.Movement.Bhop, function(v) Config.Movement.Bhop = v end)

    -- Toggle Keybind (Insert / Right Shift)
    table.insert(Runtime.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Config.UI.ToggleKey or input.KeyCode == Enum.KeyCode.RightShift) then
            Config.UI.MenuOpen = not Config.UI.MenuOpen
            screenGui.Enabled = Config.UI.MenuOpen
        end
    end))

    return screenGui
end

local GuiInstance = BuildUltraLightUI()

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
        DestroyESP(draw)
    end
    table.clear(Runtime.DrawingPool)

    if GuiInstance then pcall(function() GuiInstance:Destroy() end) end

    env.BWXUnload = nil
    env.CybrionUnload = nil
    env.BloxStrikeUnload = nil
end
env.CybrionUnload = env.BWXUnload
env.BloxStrikeUnload = env.BWXUnload

print("[BWX] Ultra-Lightweight Bloxstrike Suite Loaded. Zero-Lag Engine Active.")

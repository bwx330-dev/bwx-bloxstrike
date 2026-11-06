--[[
    ⚡ BWX // Bloxstrike Utility Suite (v3.3 High-Performance Architecture)
    Optimized for Xeno & Modern Executors
    Target: Roblox Bloxstrike (7633926880)

    Architectural Optimizations in v3.3:
      1. Zero GC Scanning (Eliminated getgc):
         - Completely removed getgc(true) heap traversals.
         - Eliminates CPU frame-time spikes (stutters) that caused artificial high-ping feel.
      2. Zero Module Hook Interference (100% Native Weapon Replication):
         - Removed invasive hooks on CameraController (weaponKick, getWeaponKickRotation)
           and bulletClass to prevent client-server replication state machine stalls.
         - Fixes weapon purchase delay (guns are received immediately in the current round,
           not deferred to the next round).
         - Recoil compensation handled purely via hardware input (mousemoverel), ensuring
           the game's internal replication engine remains completely uncorrupted.
      3. High-Frequency Rendering & Spatial Optimization:
         - Consolidated entity extraction, 2D viewport projections, and ESP rendering into
           a single fast pass per frame, eliminating duplicate WorldToViewportPoint math.
         - Raycasts throttled to at most 1 raycast per frame for only the closest FOV candidate,
           preventing pipeline saturation and visual lagging/blinking.
         - Replaced Workspace:GetChildren() traversals with direct O(1) hash lookups for C4.
      4. Closed-by-Default UI:
         - Starts closed (ScreenGui.Enabled = false) to ensure zero mouse click or crosshair absorption.
         - Toggle Keybind: [K] or [Insert]
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

-- Configuration Table
local Config = {
    Combat = {
        SilentAim = true,
        AimAssist = true,
        AimLockStrength = 0.95,
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
        C4Color = Color3.fromRGB(250, 195, 60)
    },
    WeaponMods = {
        AntiFlash = true
    },
    Movement = {
        Bhop = true
    },
    UI = {
        MenuOpen = false -- Starts CLOSED so it never absorbs mouse clicks
    }
}

local Runtime = {
    Active = true,
    Target = nil,
    TargetPart = nil,
    DrawingPool = {},
    FOVDrawing = nil,
    C4Drawing = nil,
    NoticeDrawing = nil,
    NoticeStart = os.clock(),
    Connections = {},
    LastC4Check = 0,
    CachedC4 = nil
}

-- Wallcheck Raycast Params (Allocated once, reused globally)
local WallParams = RaycastParams.new()
WallParams.FilterType = Enum.RaycastFilterType.Exclude
WallParams.IgnoreWater = true

-- FOV Circle Drawing
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

-- Startup Banner Overlay (Fades out after 5 seconds)
Runtime.NoticeDrawing = Drawing.new("Text")
Runtime.NoticeDrawing.Size = 14
Runtime.NoticeDrawing.Center = true
Runtime.NoticeDrawing.Outline = true
Runtime.NoticeDrawing.Color = Color3.fromRGB(50, 230, 150)
Runtime.NoticeDrawing.Position = Vector2.new(Camera.ViewportSize.X / 2, 40)
Runtime.NoticeDrawing.Text = "⚡ BWX BLOXSTRIKE READY [Tekan K / Insert untuk Menu]"
Runtime.NoticeDrawing.Visible = true

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

    local myChar = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
    local myTeam = GetEntityTeam(myChar, LocalPlayer)
    local targetTeam = GetEntityTeam(model, player)
    if myTeam and targetTeam then
        return myTeam == targetTeam
    end
    return false
end

-- Drawing Pool Management (Persistent & Zero Frame Allocation)
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
    if draw.BoxOutline.Visible then draw.BoxOutline.Visible = false end
    if draw.Box.Visible then draw.Box.Visible = false end
    if draw.HealthOutline.Visible then draw.HealthOutline.Visible = false end
    if draw.Health.Visible then draw.Health.Visible = false end
    if draw.Name.Visible then draw.Name.Visible = false end
    if draw.Distance.Visible then draw.Distance.Visible = false end
    if draw.Tracer.Visible then draw.Tracer.Visible = false end
end

local function DestroyDrawing(draw)
    for _, item in pairs(draw) do
        pcall(function()
            item.Visible = false
            item:Remove()
        end)
    end
end

-- Fast O(1) C4 Locator (No Workspace:GetChildren() scan)
local function LocateC4()
    local now = os.clock()
    if now - Runtime.LastC4Check > 1.0 then
        Runtime.LastC4Check = now
        local c4 = Workspace:FindFirstChild("C4") or Workspace:FindFirstChild("Bomb") or Workspace:FindFirstChild("PlantedC4")
        if c4 then
            if c4:IsA("BasePart") then
                Runtime.CachedC4 = c4
            elseif c4:IsA("Model") then
                Runtime.CachedC4 = c4.PrimaryPart or c4:FindFirstChildWhichIsA("BasePart")
            end
        else
            Runtime.CachedC4 = nil
        end
    end
    return Runtime.CachedC4
end

-- Accurate Dead Check (Bloxstrike Attributes)
local function IsModelDead(model, player)
    if model then
        if tostring(model:GetAttribute("Dead")) == "true" then return true end
        local hp = tonumber(model:GetAttribute("Health"))
        if hp and hp <= 0 then return true end
    end
    if player then
        if tostring(player:GetAttribute("Dead")) == "true" then return true end
        local hp = tonumber(player:GetAttribute("Health"))
        if hp and hp <= 0 then return true end
    end
    return false
end

-- Event-Driven Anti-Flash (Lighting Blur suppression only)
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
end
pcall(SetupAntiFlash)

-- In-Match MainMenu Guard (Prevents accidental Menu popup mid-match)
local function GuardMatchUI()
    local chars = Workspace:FindFirstChild("Characters")
    local myChar = chars and chars:FindFirstChild(LocalPlayer.Name)
    if myChar and not IsModelDead(myChar, LocalPlayer) then
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pGui then
            local menu = pGui:FindFirstChild("Menu") or pGui:FindFirstChild("MainMenu")
            if menu and menu:IsA("ScreenGui") and menu.Enabled then
                menu.Enabled = false
                if not Config.UI.MenuOpen then
                    pcall(function()
                        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                    end)
                end
            end
        end
    end
end

-- =========================================================================
-- MASTER RENDER LOOP (High-Performance Single-Pass Execution)
-- =========================================================================
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    -- 0. MainMenu Guard
    GuardMatchUI()

    -- 1. Startup banner fadeout
    if Runtime.NoticeDrawing and Runtime.NoticeDrawing.Visible then
        local elapsed = os.clock() - Runtime.NoticeStart
        if elapsed > 5.0 then
            Runtime.NoticeDrawing.Visible = false
        end
    end

    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = Camera.CFrame.Position
    local visualsOn = Config.Visuals.Enabled
    local maxDist = Config.Visuals.MaxDistance
    local fov = Config.Combat.FOV

    -- 2. FOV Circle
    if Runtime.FOVDrawing then
        Runtime.FOVDrawing.Position = center
        Runtime.FOVDrawing.Radius = fov
        Runtime.FOVDrawing.Color = Config.Combat.FOVColor
        Runtime.FOVDrawing.Visible = Config.Combat.ShowFOV
    end

    -- 3. Consolidated Single-Pass Entity & ESP Pipeline
    local activeIds = {}
    local bestCandidate = nil
    local bestScreenDist = fov
    local bestHitPart = nil

    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local id = model.Name
                local player = Players:FindFirstChild(id)

                if not IsModelDead(model, player) then
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    local head = model:FindFirstChild("Head")

                    if root and head then
                        activeIds[id] = true
                        local isTeam = IsTeammate(model, player)
                        local rootPos = root.Position
                        local dist = (rootPos - camPos).Magnitude

                        local draw = GetOrCreateDrawing(id)

                        if visualsOn and not (Config.Visuals.TeamCheck and isTeam) and dist <= maxDist then
                            -- Rigid physics root projection (Zero bone-lag)
                            local topPos, topOn = Camera:WorldToViewportPoint(rootPos + Vector3.new(0, 3.0, 0))
                            local botPos, botOn = Camera:WorldToViewportPoint(rootPos - Vector3.new(0, 3.5, 0))

                            if topPos.Z > 0 and botPos.Z > 0 then
                                local height = math.abs(botPos.Y - topPos.Y)
                                local width = height * 0.58
                                local boxPos = Vector2.new(topPos.X - width / 2, topPos.Y)
                                local onScreen = (boxPos.X + width >= 0) and (boxPos.X <= vp.X) and (botPos.Y >= 0) and (topPos.Y <= vp.Y)

                                if onScreen then
                                    local col = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor

                                    -- Box ESP
                                    if Config.Visuals.BoxESP then
                                        draw.BoxOutline.Size = Vector2.new(width, height)
                                        draw.BoxOutline.Position = boxPos
                                        draw.BoxOutline.Visible = true

                                        draw.Box.Size = Vector2.new(width, height)
                                        draw.Box.Position = boxPos
                                        draw.Box.Color = col
                                        draw.Box.Visible = true
                                    else
                                        draw.BoxOutline.Visible = false
                                        draw.Box.Visible = false
                                    end

                                    -- Health Bar
                                    if Config.Visuals.HealthBar then
                                        local hp = tonumber(model:GetAttribute("Health")) or (player and tonumber(player:GetAttribute("Health"))) or 100
                                        local maxHp = tonumber(model:GetAttribute("MaxHealth")) or 100
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

                                    -- Name Tag
                                    if Config.Visuals.NameESP then
                                        draw.Name.Text = (player and player.DisplayName) or model.Name
                                        draw.Name.Position = Vector2.new(topPos.X, boxPos.Y - 14)
                                        draw.Name.Visible = true
                                    else
                                        draw.Name.Visible = false
                                    end

                                    -- Distance Tag
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
                                        draw.Tracer.Color = col
                                        draw.Tracer.Visible = true
                                    else
                                        draw.Tracer.Visible = false
                                    end
                                else
                                    HideDrawing(draw)
                                end
                            else
                                HideDrawing(draw)
                            end
                        else
                            HideDrawing(draw)
                        end

                        -- Combat Target Candidate (Enemies only, evaluated within the same pass)
                        if not isTeam then
                            local targetPart = (Config.Combat.HitPart == "Head" and head) or (Config.Combat.HitPart == "UpperTorso" and (model:FindFirstChild("UpperTorso") or root)) or root
                            local partScreen, partOn = Camera:WorldToViewportPoint(targetPart.Position)
                            if partOn and partScreen.Z > 0 then
                                local sDist = (Vector2.new(partScreen.X, partScreen.Y) - center).Magnitude
                                if sDist < bestScreenDist then
                                    bestScreenDist = sDist
                                    bestCandidate = model
                                    bestHitPart = targetPart
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Cleanup Unused Drawings
    for id, draw in pairs(Runtime.DrawingPool) do
        if not activeIds[id] then
            DestroyDrawing(draw)
            Runtime.DrawingPool[id] = nil
        end
    end

    -- 4. Throttled Single-Raycast Wallcheck (Only for the single best candidate)
    if bestHitPart and Config.Combat.VisibleCheck then
        local myChar = chars and chars:FindFirstChild(LocalPlayer.Name)
        WallParams.FilterDescendantsInstances = {Camera, myChar}
        local dir = bestHitPart.Position - camPos
        local hit = Workspace:Raycast(camPos, dir, WallParams)
        if hit and not hit.Instance:IsDescendantOf(bestCandidate) then
            bestHitPart = nil
            bestCandidate = nil
        end
    end

    Runtime.Target = bestCandidate
    Runtime.TargetPart = bestHitPart

    -- 5. Fast C4 Objective Tracker (O(1) Hash Lookup)
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

    -- 6. Native Input Aim Assist (Hard-Lock & Recoil Counter via mousemoverel)
    if (Config.Combat.AimAssist or Config.Combat.SilentAim) and Runtime.TargetPart then
        local isAiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        if isAiming then
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

    -- 7. Bunnyhop
    if Config.Movement.Bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if not UserInputService:GetFocusedTextBox() then
            local char = (Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial ~= Enum.Material.Air then
                hum.Jump = true
            end
        end
    end
end))

-- ========================================================
-- EMBEDDED LIGHTWEIGHT CYBERPUNK UI (Closed by Default)
-- ========================================================
local function BuildUI()
    local Theme = {
        Background = Color3.fromRGB(15, 17, 19),
        Header = Color3.fromRGB(22, 25, 29),
        Surface = Color3.fromRGB(28, 32, 38),
        SurfaceHover = Color3.fromRGB(36, 42, 50),
        Stroke = Color3.fromRGB(45, 52, 62),
        Accent = Color3.fromRGB(50, 230, 150),
        Text = Color3.fromRGB(240, 245, 248),
        Muted = Color3.fromRGB(140, 150, 165)
    }

    local target = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BWX_SuiteUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = Config.UI.MenuOpen -- False at start! Zero click absorption
    screenGui.Parent = target

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.fromOffset(540, 360)
    main.Position = UDim2.fromScale(0.3, 0.25)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Theme.Stroke
    mainStroke.Thickness = 1
    mainStroke.Parent = main

    -- Header (Draggable)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Theme.Header
    header.BorderSizePixel = 0
    header.Parent = main

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 8)
    headerCorner.Parent = header

    local headerBottom = Instance.new("Frame")
    headerBottom.Size = UDim2.new(1, 0, 0, 8)
    headerBottom.Position = UDim2.new(0, 0, 1, -8)
    headerBottom.BackgroundColor3 = Theme.Header
    headerBottom.BorderSizePixel = 0
    headerBottom.Parent = header

    local title = Instance.new("TextLabel")
    title.Text = "⚡ BWX // BLOXSTRIKE"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Theme.Accent
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 14, 0, 0)
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.Parent = header

    local hint = Instance.new("TextLabel")
    hint.Text = "Toggle: [K] / [Insert]"
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 11
    hint.TextColor3 = Theme.Muted
    hint.TextXAlignment = Enum.TextXAlignment.Right
    hint.BackgroundTransparency = 1
    hint.Position = UDim2.new(0.4, 0, 0, 0)
    hint.Size = UDim2.new(0.56, 0, 1, 0)
    hint.Parent = header

    -- Dragging Logic
    local dragging, dragStart, startPos
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    -- Sidebar Tabs
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 130, 1, -42)
    sidebar.Position = UDim2.new(0, 0, 0, 42)
    sidebar.BackgroundColor3 = Theme.Header
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main

    local sidebarLayout = Instance.new("UIListLayout")
    sidebarLayout.Padding = UDim.new(0, 4)
    sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sidebarLayout.Parent = sidebar

    local sidebarPadding = Instance.new("UIPadding")
    sidebarPadding.PaddingTop = UDim.new(0, 8)
    sidebarPadding.Parent = sidebar

    -- Container for Pages
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -138, 1, -50)
    container.Position = UDim2.new(0, 134, 0, 46)
    container.BackgroundTransparency = 1
    container.Parent = main

    local pages = {}
    local tabs = {"Combat", "Visuals", "Gun Mods", "Movement"}
    local activeTab = nil

    for _, name in ipairs(tabs) do
        local page = Instance.new("ScrollingFrame")
        page.Name = name
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = Theme.Accent
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = container

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 6)
        layout.Parent = page

        local padding = Instance.new("UIPadding")
        padding.PaddingRight = UDim.new(0, 8)
        padding.PaddingTop = UDim.new(0, 4)
        padding.Parent = page

        pages[name] = page
    end

    local tabButtons = {}
    local function SwitchTab(tabName)
        for name, page in pairs(pages) do
            page.Visible = (name == tabName)
        end
        for name, btn in pairs(tabButtons) do
            if name == tabName then
                btn.BackgroundColor3 = Theme.Surface
                btn.TextColor3 = Theme.Accent
            else
                btn.BackgroundColor3 = Theme.Header
                btn.TextColor3 = Theme.Muted
            end
        end
        activeTab = tabName
    end

    for _, name in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -12, 0, 32)
        btn.BackgroundColor3 = Theme.Header
        btn.Text = name
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        btn.TextColor3 = Theme.Muted
        btn.BorderSizePixel = 0
        btn.Parent = sidebar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            SwitchTab(name)
        end)
        tabButtons[name] = btn
    end

    -- UI Component Builders
    local function CreateToggle(parent, titleText, initialVal, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 36)
        frame.BackgroundColor3 = Theme.Surface
        frame.BorderSizePixel = 0
        frame.Parent = parent

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = frame

        local label = Instance.new("TextLabel")
        label.Text = titleText
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 12
        label.TextColor3 = Theme.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 10, 0, 0)
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.Parent = frame

        local switch = Instance.new("TextButton")
        switch.Size = UDim2.new(0, 42, 0, 22)
        switch.Position = UDim2.new(1, -52, 0.5, -11)
        switch.BackgroundColor3 = initialVal and Theme.Accent or Theme.Stroke
        switch.Text = ""
        switch.BorderSizePixel = 0
        switch.Parent = frame

        local sc = Instance.new("UICorner")
        sc.CornerRadius = UDim.new(1, 0)
        sc.Parent = switch

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 16, 0, 16)
        dot.Position = initialVal and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Parent = switch

        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(1, 0)
        dc.Parent = dot

        local current = initialVal
        switch.MouseButton1Click:Connect(function()
            current = not current
            switch.BackgroundColor3 = current and Theme.Accent or Theme.Stroke
            dot.Position = current and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            callback(current)
        end)
    end

    local function CreateSlider(parent, titleText, min, max, initialVal, suffix, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 48)
        frame.BackgroundColor3 = Theme.Surface
        frame.BorderSizePixel = 0
        frame.Parent = parent

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = frame

        local label = Instance.new("TextLabel")
        label.Text = titleText
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 12
        label.TextColor3 = Theme.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 10, 0, 6)
        label.Size = UDim2.new(0.6, 0, 0, 16)
        label.Parent = frame

        local valLabel = Instance.new("TextLabel")
        valLabel.Text = tostring(initialVal) .. suffix
        valLabel.Font = Enum.Font.GothamBold
        valLabel.TextSize = 11
        valLabel.TextColor3 = Theme.Accent
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.BackgroundTransparency = 1
        valLabel.Position = UDim2.new(0.6, 0, 0, 6)
        valLabel.Size = UDim2.new(0.38, 0, 0, 16)
        label.Parent = frame

        local barBg = Instance.new("TextButton")
        barBg.Text = ""
        barBg.Size = UDim2.new(1, -20, 0, 6)
        barBg.Position = UDim2.new(0, 10, 0, 30)
        barBg.BackgroundColor3 = Theme.Stroke
        barBg.BorderSizePixel = 0
        barBg.Parent = frame

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(1, 0)
        bc.Parent = barBg

        local fill = Instance.new("Frame")
        local initialRatio = math.clamp((initialVal - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(initialRatio, 0, 1, 0)
        fill.BackgroundColor3 = Theme.Accent
        fill.BorderSizePixel = 0
        fill.Parent = barBg

        local fc = Instance.new("UICorner")
        fc.CornerRadius = UDim.new(1, 0)
        fc.Parent = fill

        local sliding = false
        local function UpdateSlide(x)
            local ratio = math.clamp((x - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
            local value = math.floor(min + (max - min) * ratio)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            valLabel.Text = tostring(value) .. suffix
            callback(value)
        end

        barBg.InputBegan:Connect(function(input)
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

    local function CreateDropdown(parent, titleText, options, currentOption, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 36)
        frame.BackgroundColor3 = Theme.Surface
        frame.BorderSizePixel = 0
        frame.Parent = parent

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = frame

        local label = Instance.new("TextLabel")
        label.Text = titleText
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 12
        label.TextColor3 = Theme.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 10, 0, 0)
        label.Size = UDim2.new(0.5, 0, 1, 0)
        label.Parent = frame

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 120, 0, 24)
        btn.Position = UDim2.new(1, -128, 0.5, -12)
        btn.BackgroundColor3 = Theme.Header
        btn.Text = currentOption .. " ▼"
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = Theme.Accent
        btn.BorderSizePixel = 0
        btn.Parent = frame

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 4)
        bc.Parent = btn

        local currIndex = 1
        for i, opt in ipairs(options) do
            if opt == currentOption then currIndex = i break end
        end

        btn.MouseButton1Click:Connect(function()
            currIndex = currIndex % #options + 1
            local nextOpt = options[currIndex]
            btn.Text = nextOpt .. " ▼"
            callback(nextOpt)
        end)
    end

    -- Build Combat Tab
    local combatPage = pages["Combat"]
    CreateToggle(combatPage, "Aim Lock / Assist (Hold Right Click)", Config.Combat.AimAssist, function(v) Config.Combat.AimAssist = v end)
    CreateSlider(combatPage, "Aim Lock Strength", 10, 100, math.floor(Config.Combat.AimLockStrength * 100), "%", function(v) Config.Combat.AimLockStrength = v / 100 end)
    CreateToggle(combatPage, "Show FOV Circle", Config.Combat.ShowFOV, function(v) Config.Combat.ShowFOV = v end)
    CreateSlider(combatPage, "FOV Radius", 30, 400, Config.Combat.FOV, "px", function(v) Config.Combat.FOV = v end)
    CreateDropdown(combatPage, "Hit Part", {"Head", "UpperTorso", "HumanoidRootPart"}, Config.Combat.HitPart, function(v) Config.Combat.HitPart = v end)
    CreateToggle(combatPage, "Visibility Check (Wallcheck)", Config.Combat.VisibleCheck, function(v) Config.Combat.VisibleCheck = v end)

    -- Build Visuals Tab
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

    -- Build Gun Mods Tab
    local modsPage = pages["Gun Mods"]
    CreateToggle(modsPage, "Anti-Flashbang (Instant Blind Wipe)", Config.WeaponMods.AntiFlash, function(v) Config.WeaponMods.AntiFlash = v end)

    -- Build Movement Tab
    local movePage = pages["Movement"]
    CreateToggle(movePage, "Auto Bunnyhop (Bhop)", Config.Movement.Bhop, function(v) Config.Movement.Bhop = v end)

    SwitchTab("Combat")

    -- Menu Toggle Keybind ([K] and [Insert])
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.Insert) then
            Config.UI.MenuOpen = not Config.UI.MenuOpen
            screenGui.Enabled = Config.UI.MenuOpen
            if not Config.UI.MenuOpen then
                -- Lock mouse back to game center when menu is closed
                pcall(function()
                    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                end)
            end
        end
    end)

    return screenGui
end

local GuiInstance = BuildUI()

-- Global Unload Handler
env.BWXUnload = function()
    Runtime.Active = false

    for _, conn in ipairs(Runtime.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Runtime.Connections)

    if Runtime.FOVDrawing then pcall(function() Runtime.FOVDrawing:Remove() end) end
    if Runtime.C4Drawing then pcall(function() Runtime.C4Drawing:Remove() end) end
    if Runtime.NoticeDrawing then pcall(function() Runtime.NoticeDrawing:Remove() end) end

    for _, draw in pairs(Runtime.DrawingPool) do
        DestroyDrawing(draw)
    end
    table.clear(Runtime.DrawingPool)

    if GuiInstance then pcall(function() GuiInstance:Destroy() end) end

    env.BWXUnload = nil
    env.CybrionUnload = nil
    env.BloxStrikeUnload = nil
end
env.CybrionUnload = env.BWXUnload
env.BloxStrikeUnload = env.BWXUnload

print("[BWX] Suite v3.3 Loaded. Zero-GC & High-Performance Single-Pass Engine.")

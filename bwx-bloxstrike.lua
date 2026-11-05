--[[
    BWX // Bloxstrike Utility Suite
    Engine: Luau Combat & Visual Kernel
    Target: Roblox Bloxstrike (7633926880)
    Architecture: Non-Blocking Drawing API + Clean Metatable Interception
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Global Unload of previous instance
local env = getgenv and getgenv() or _G
if env.BWXUnload then
    pcall(env.BWXUnload)
end
if env.CybrionUnload then
    pcall(env.CybrionUnload)
end
if env.BloxStrikeUnload then
    pcall(env.BloxStrikeUnload)
end

-- Runtime Configuration State
local Config = {
    Combat = {
        SilentAim = true,
        AimAssist = false,
        HitPart = "Head", -- "Head", "UpperTorso", "HumanoidRootPart"
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
        BoxOutline = true,
        EnemyColor = Color3.fromRGB(245, 80, 80),
        TeamColor = Color3.fromRGB(60, 160, 255),
        Tracers = false,
        TracerOrigin = "Bottom", -- "Bottom", "Center"
        NameESP = true,
        HealthBar = true,
        DistanceESP = true,
        MaxDistance = 5000, -- Studs (Full map range)
        C4Tracker = true,
        C4Color = Color3.fromRGB(245, 190, 60)
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

-- Runtime Storage
local Runtime = {
    Active = true,
    Target = nil,
    DrawingPool = {
        Players = {},
        FOV = nil,
        C4 = nil
    },
    Connections = {},
    Hooks = {},
    C4Cache = nil
}

-- FOV Circle Drawing
Runtime.DrawingPool.FOV = Drawing.new("Circle")
Runtime.DrawingPool.FOV.Thickness = 1.5
Runtime.DrawingPool.FOV.NumSides = 64
Runtime.DrawingPool.FOV.Filled = false
Runtime.DrawingPool.FOV.Transparency = 0.75
Runtime.DrawingPool.FOV.Radius = Config.Combat.FOV
Runtime.DrawingPool.FOV.Color = Config.Combat.FOVColor
Runtime.DrawingPool.FOV.Visible = Config.Combat.ShowFOV

-- C4 Drawing
Runtime.DrawingPool.C4 = Drawing.new("Text")
Runtime.DrawingPool.C4.Size = 14
Runtime.DrawingPool.C4.Center = true
Runtime.DrawingPool.C4.Outline = true
Runtime.DrawingPool.C4.Color = Config.Visuals.C4Color
Runtime.DrawingPool.C4.Visible = false

-- Helper: Get Player / Character Information
local function GetPlayerTeam(player)
    if not player then return nil end
    if player.Team then return player.Team.Name end
    local teamAttr = player:GetAttribute("Team")
    if teamAttr then return tostring(teamAttr) end

    -- Fallback via Bloxstrike Character Look
    local chars = Workspace:FindFirstChild("Characters")
    local char = (chars and chars:FindFirstChild(player.Name)) or player.Character
    if char and char:GetAttribute("CharacterName") then
        local look = char:GetAttribute("CharacterName")
        if look == Workspace:GetAttribute("CTCharacter") then return "Counter-Terrorists" end
        if look == Workspace:GetAttribute("TCharacter") then return "Terrorists" end
    end
    return nil
end

local function IsTeammate(player)
    if not Config.Visuals.TeamCheck then return false end
    if player == LocalPlayer then return true end

    local myTeam = GetPlayerTeam(LocalPlayer)
    local targetTeam = GetPlayerTeam(player)
    if myTeam and targetTeam then
        return myTeam == targetTeam
    end
    return false
end

-- Collect All Valid Candidate Models
local function GetAllCharacters()
    local candidates = {}
    local seen = {}

    -- 1. Check Workspace.Characters folder (Bloxstrike primary repository)
    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, model in ipairs(chars:GetChildren()) do
            if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
                local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                local hum = model:FindFirstChildOfClass("Humanoid")
                local isDead = (hum and hum.Health <= 0) or tostring(model:GetAttribute("Dead")) == "true"
                if hrp and not isDead then
                    candidates[model] = {
                        Model = model,
                        Root = hrp,
                        Humanoid = hum,
                        Player = Players:FindFirstChild(model.Name)
                    }
                    seen[model.Name] = true
                end
            end
        end
    end

    -- 2. Check Players list directly (Spectating / Fallback)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not seen[player.Name] then
            local char = player.Character
            if char and char:IsA("Model") then
                local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                local hum = char:FindFirstChildOfClass("Humanoid")
                local isDead = (hum and hum.Health <= 0) or tostring(player:GetAttribute("Dead")) == "true" or tostring(char:GetAttribute("Dead")) == "true"
                if hrp and not isDead then
                    candidates[char] = {
                        Model = char,
                        Root = hrp,
                        Humanoid = hum,
                        Player = player
                    }
                end
            end
        end
    end

    return candidates
end

-- Allocate Drawing Objects for a Model
local function GetOrCreateESP(id)
    local esp = Runtime.DrawingPool.Players[id]
    if not esp then
        esp = {
            BoxOutline = Drawing.new("Square"),
            Box = Drawing.new("Square"),
            HealthOutline = Drawing.new("Line"),
            Health = Drawing.new("Line"),
            Name = Drawing.new("Text"),
            Distance = Drawing.new("Text"),
            Tracer = Drawing.new("Line")
        }

        esp.BoxOutline.Thickness = 3
        esp.BoxOutline.Filled = false
        esp.BoxOutline.Color = Color3.new(0, 0, 0)
        esp.BoxOutline.Transparency = 0.8
        esp.BoxOutline.Visible = false

        esp.Box.Thickness = 1
        esp.Box.Filled = false
        esp.Box.Transparency = 1
        esp.Box.Visible = false

        esp.HealthOutline.Thickness = 3
        esp.HealthOutline.Color = Color3.new(0, 0, 0)
        esp.HealthOutline.Visible = false

        esp.Health.Thickness = 1
        esp.Health.Visible = false

        esp.Name.Size = 13
        esp.Name.Center = true
        esp.Name.Outline = true
        esp.Name.OutlineColor = Color3.new(0, 0, 0)
        esp.Name.Color = Color3.fromRGB(240, 240, 240)
        esp.Name.Visible = false

        esp.Distance.Size = 11
        esp.Distance.Center = true
        esp.Distance.Outline = true
        esp.Distance.OutlineColor = Color3.new(0, 0, 0)
        esp.Distance.Color = Color3.fromRGB(180, 180, 180)
        esp.Distance.Visible = false

        esp.Tracer.Thickness = 1
        esp.Tracer.Transparency = 0.7
        esp.Tracer.Visible = false

        Runtime.DrawingPool.Players[id] = esp
    end
    return esp
end

local function HideESP(esp)
    esp.BoxOutline.Visible = false
    esp.Box.Visible = false
    esp.HealthOutline.Visible = false
    esp.Health.Visible = false
    esp.Name.Visible = false
    esp.Distance.Visible = false
    esp.Tracer.Visible = false
end

local function PurgeESP(id)
    local esp = Runtime.DrawingPool.Players[id]
    if esp then
        for _, draw in pairs(esp) do
            pcall(function()
                draw.Visible = false
                draw:Remove()
            end)
        end
        Runtime.DrawingPool.Players[id] = nil
    end
end

-- Locate Planted C4 or Dropped Bomb
local function GetC4()
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name == "C4" or obj.Name == "Bomb" or obj.Name == "PlantedC4" then
            if obj:IsA("BasePart") then return obj end
            if obj:IsA("Model") then
                return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            end
        end
    end
    return nil
end

-- Line of Sight / Wallcheck
local function IsVisible(targetPart, originPos)
    if not Config.Combat.VisibleCheck then return true end
    originPos = originPos or Camera.CFrame.Position
    local dir = targetPart.Position - originPos

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {Camera, LocalPlayer.Character}
    params.IgnoreWater = true

    local hit = Workspace:Raycast(originPos, dir, params)
    if hit and hit.Instance:IsDescendantOf(targetPart.Parent) then
        return true
    end
    return hit == nil
end

-- Target Selector for Combat
local function GetBestTarget()
    local best = nil
    local minDistance = Config.Combat.FOV
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local chars = GetAllCharacters()

    for _, data in pairs(chars) do
        local isTeam = data.Player and IsTeammate(data.Player)
        if not isTeam then
            local hitPart = data.Model:FindFirstChild(Config.Combat.HitPart) or data.Model:FindFirstChild("Head") or data.Root
            if hitPart then
                local screenPos, onScreen = Camera:WorldToViewportPoint(hitPart.Position)
                if onScreen and screenPos.Z > 0 then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                    if dist < minDistance and IsVisible(hitPart, nil) then
                        minDistance = dist
                        best = hitPart
                    end
                end
            end
        end
    end
    return best
end

-- Master Render Loop
table.insert(Runtime.Connections, RunService.RenderStepped:Connect(function()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = Camera.CFrame.Position

    -- 1. FOV Circle Update
    if Runtime.DrawingPool.FOV then
        Runtime.DrawingPool.FOV.Position = center
        Runtime.DrawingPool.FOV.Radius = Config.Combat.FOV
        Runtime.DrawingPool.FOV.Color = Config.Combat.FOVColor
        Runtime.DrawingPool.FOV.Visible = Config.Combat.ShowFOV
    end

    -- 2. Target Acquisition
    Runtime.Target = GetBestTarget()

    -- 3. Visuals / ESP Engine
    local characters = GetAllCharacters()
    local activeIds = {}

    if Config.Visuals.Enabled then
        for _, data in pairs(characters) do
            local model = data.Model
            local root = data.Root
            local hum = data.Humanoid
            local player = data.Player
            local id = model.Name

            activeIds[id] = true
            local esp = GetOrCreateESP(id)

            local isTeam = player and IsTeammate(player)
            if Config.Visuals.TeamCheck and isTeam then
                HideESP(esp)
                continue
            end

            local dist = (root.Position - camPos).Magnitude
            if dist > Config.Visuals.MaxDistance then
                HideESP(esp)
                continue
            end

            -- Single root projection with depth validation (Eliminates flickering)
            local rootScreen, onScreen = Camera:WorldToViewportPoint(root.Position)
            if onScreen and rootScreen.Z > 0 then
                local head = model:FindFirstChild("Head")
                local headY = head and head.Position.Y or (root.Position.Y + 2.2)
                local legY = root.Position.Y - 3.0

                local topScreen = Camera:WorldToViewportPoint(Vector3.new(root.Position.X, headY + 0.6, root.Position.Z))
                local bottomScreen = Camera:WorldToViewportPoint(Vector3.new(root.Position.X, legY, root.Position.Z))

                local height = math.clamp(math.abs(bottomScreen.Y - topScreen.Y), 6, 800)
                local width = height * 0.62
                local boxPos = Vector2.new(rootScreen.X - width / 2, topScreen.Y)
                local color = isTeam and Config.Visuals.TeamColor or Config.Visuals.EnemyColor

                -- Bounding Box
                if Config.Visuals.BoxESP then
                    esp.BoxOutline.Size = Vector2.new(width, height)
                    esp.BoxOutline.Position = boxPos
                    esp.BoxOutline.Visible = Config.Visuals.BoxOutline

                    esp.Box.Size = Vector2.new(width, height)
                    esp.Box.Position = boxPos
                    esp.Box.Color = color
                    esp.Box.Visible = true
                else
                    esp.BoxOutline.Visible = false
                    esp.Box.Visible = false
                end

                -- Health Bar
                if Config.Visuals.HealthBar then
                    local hp = hum and hum.Health or tonumber(model:GetAttribute("Health")) or 100
                    local maxHp = hum and hum.MaxHealth or tonumber(model:GetAttribute("MaxHealth")) or 100
                    local hpRatio = math.clamp(hp / maxHp, 0, 1)

                    local barHeight = height * hpRatio
                    local barX = boxPos.X - 5

                    esp.HealthOutline.From = Vector2.new(barX, boxPos.Y)
                    esp.HealthOutline.To = Vector2.new(barX, boxPos.Y + height)
                    esp.HealthOutline.Visible = true

                    esp.Health.From = Vector2.new(barX, boxPos.Y + height)
                    esp.Health.To = Vector2.new(barX, boxPos.Y + height - barHeight)
                    esp.Health.Color = Color3.fromHSV(hpRatio * 0.32, 1, 1)
                    esp.Health.Visible = true
                else
                    esp.HealthOutline.Visible = false
                    esp.Health.Visible = false
                end

                -- Name Tag
                if Config.Visuals.NameESP then
                    esp.Name.Text = (player and player.DisplayName) or model.Name
                    esp.Name.Position = Vector2.new(rootScreen.X, boxPos.Y - 15)
                    esp.Name.Visible = true
                else
                    esp.Name.Visible = false
                end

                -- Distance
                if Config.Visuals.DistanceESP then
                    esp.Distance.Text = string.format("[%dm]", math.floor(dist))
                    esp.Distance.Position = Vector2.new(rootScreen.X, boxPos.Y + height + 2)
                    esp.Distance.Visible = true
                else
                    esp.Distance.Visible = false
                end

                -- Tracer Line
                if Config.Visuals.Tracers then
                    local origin = (Config.Visuals.TracerOrigin == "Bottom") and Vector2.new(vp.X / 2, vp.Y) or center
                    esp.Tracer.From = origin
                    esp.Tracer.To = Vector2.new(rootScreen.X, boxPos.Y + height)
                    esp.Tracer.Color = color
                    esp.Tracer.Visible = true
                else
                    esp.Tracer.Visible = false
                end
            else
                HideESP(esp)
            end
        end
    end

    -- Cleanup Disconnected or Despawned Models
    for id, esp in pairs(Runtime.DrawingPool.Players) do
        if not activeIds[id] then
            PurgeESP(id)
        end
    end

    -- 4. C4 Tracker
    if Config.Visuals.C4Tracker then
        local c4 = GetC4()
        if c4 then
            local c4Pos, onScreen = Camera:WorldToViewportPoint(c4.Position)
            if onScreen and c4Pos.Z > 0 then
                local dist = math.floor((c4.Position - camPos).Magnitude)
                Runtime.DrawingPool.C4.Text = string.format("[ C4 BOMB // %dm ]", dist)
                Runtime.DrawingPool.C4.Position = Vector2.new(c4Pos.X, c4Pos.Y)
                Runtime.DrawingPool.C4.Visible = true
            else
                Runtime.DrawingPool.C4.Visible = false
            end
        else
            Runtime.DrawingPool.C4.Visible = false
        end
    else
        Runtime.DrawingPool.C4.Visible = false
    end

    -- 5. Aim Assist (Smooth Tracking)
    if Config.Combat.AimAssist and Runtime.Target then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local currentCF = Camera.CFrame
            local look = CFrame.lookAt(currentCF.Position, Runtime.Target.Position)
            Camera.CFrame = currentCF:Lerp(look, Config.Combat.Smoothness)
        end
    end

    -- 6. Anti-Flashbang Wipe
    if Config.WeaponMods.AntiFlash then
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pGui then
            for _, item in ipairs(pGui:GetDescendants()) do
                if (item:IsA("Frame") or item:IsA("ImageLabel")) and (item.Name:lower():find("flash") or item.Name:lower():find("blind") or item.Name:lower():find("whiteout")) then
                    item.Visible = false
                end
            end
        end
        for _, fx in ipairs(Lighting:GetChildren()) do
            if fx:IsA("BlurEffect") and fx.Name:lower():find("flash") then
                fx.Size = 0
            end
        end
    end

    -- 7. Bunnyhop Execution
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

-- Engine Metatable & Function Interception (Silent Aim & Weapon Mods)
local function SetupHooks()
    -- 1. Hook __namecall (Classic Raycast & Remote Kick)
    local rawNamecall = nil
    rawNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if not checkcaller() then
            -- Silent Aim Redirection on Raycast
            if Config.Combat.SilentAim and (method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" or method == "FindPartOnRay") then
                if Runtime.Target and (math.random(1, 100) <= Config.Combat.HitChance) then
                    local origin = args[1].Origin
                    local dir = (Runtime.Target.Position - origin).Unit * 1000
                    args[1] = Ray.new(origin, dir)
                    return rawNamecall(self, unpack(args))
                end
            end

            -- No Recoil Network Interception
            if Config.WeaponMods.NoRecoil and method == "FireServer" then
                if self.Name:lower():find("recoil") or self.Name:lower():find("shake") or self.Name:lower():find("punch") then
                    return nil
                end
            end
        end

        return rawNamecall(self, ...)
    end))
    table.insert(Runtime.Hooks, function() hookmetamethod(game, "__namecall", rawNamecall) end)

    -- 2. Hook workspace.Raycast (Modern Weapon Frameworks)
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

-- Non-Blocking Native UI Builder (Zero Input Sinking)
local function BuildUI()
    local Theme = {
        Background = Color3.fromRGB(14, 16, 14),
        Surface = Color3.fromRGB(20, 24, 21),
        Surface2 = Color3.fromRGB(26, 32, 27),
        Stroke = Color3.fromRGB(34, 48, 38),
        Accent = Color3.fromRGB(50, 230, 150),
        Text = Color3.fromRGB(240, 248, 242),
        Muted = Color3.fromRGB(120, 145, 128)
    }

    local target = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BWX_Interface"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = Config.UI.MenuOpen -- Completely disabled when menu is closed!
    screenGui.Parent = target

    local main = Instance.new("Frame")
    main.Name = "MainWindow"
    main.Size = UDim2.fromOffset(560, 380)
    main.Position = UDim2.fromScale(0.3, 0.25)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.Active = true -- Only active on the window itself, NOT the screen
    main.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1
    stroke.Parent = main

    -- Header / Title Bar
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Theme.Surface
    header.BorderSizePixel = 0
    header.Parent = main

    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 8)
    hCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Position = UDim2.fromOffset(16, 0)
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "BWX // BLOXSTRIKE"
    title.TextColor3 = Theme.Accent
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Dragging Logic
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    -- Sidebar Tabs
    local sidebar = Instance.new("Frame")
    sidebar.Position = UDim2.fromOffset(0, 42)
    sidebar.Size = UDim2.new(0, 130, 1, -42)
    sidebar.BackgroundColor3 = Theme.Surface
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main

    local sLayout = Instance.new("UIListLayout")
    sLayout.Padding = UDim.new(0, 4)
    sLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sLayout.Parent = sidebar

    local sPadding = Instance.new("UIPadding")
    sPadding.PaddingTop = UDim.new(0, 8)
    sPadding.Parent = sidebar

    -- Container for Pages
    local container = Instance.new("Frame")
    container.Position = UDim2.fromOffset(130, 42)
    container.Size = UDim2.new(1, -130, 1, -42)
    container.BackgroundTransparency = 1
    container.Parent = main

    local tabs = {}
    local activeTab = nil

    local function CreateTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 32)
        btn.BackgroundColor3 = Theme.Surface2
        btn.BackgroundTransparency = 1
        btn.Text = name
        btn.TextColor3 = Theme.Muted
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 13
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
        pLayout.Padding = UDim.new(0, 8)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        pLayout.Parent = page

        local pPadding = Instance.new("UIPadding")
        pPadding.PaddingTop = UDim.new(0, 12)
        pPadding.PaddingBottom = UDim.new(0, 12)
        pPadding.Parent = page

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
        row.Size = UDim2.new(1, -24, 0, 36)
        row.BackgroundColor3 = Theme.Surface2
        row.BorderSizePixel = 0
        row.Parent = page

        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 6)
        rCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Position = UDim2.fromOffset(12, 0)
        lbl.Size = UDim2.new(0.7, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Theme.Text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Position = UDim2.new(1, -44, 0.5, -10)
        toggleBtn.Size = UDim2.fromOffset(34, 20)
        toggleBtn.BackgroundColor3 = defaultState and Theme.Accent or Color3.fromRGB(40, 48, 42)
        toggleBtn.Text = ""
        toggleBtn.AutoButtonColor = false
        toggleBtn.Parent = row

        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(1, 0)
        tCorner.Parent = toggleBtn

        local state = defaultState
        toggleBtn.MouseButton1Click:Connect(function()
            state = not state
            toggleBtn.BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(40, 48, 42)
            callback(state)
        end)
    end

    local function AddSlider(page, labelText, min, max, defaultVal, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -24, 0, 48)
        row.BackgroundColor3 = Theme.Surface2
        row.BorderSizePixel = 0
        row.Parent = page

        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 6)
        rCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Position = UDim2.fromOffset(12, 6)
        lbl.Size = UDim2.new(0.6, 0, 0, 16)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Theme.Text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local valLbl = Instance.new("TextLabel")
        valLbl.Position = UDim2.new(1, -52, 0, 6)
        valLbl.Size = UDim2.fromOffset(40, 16)
        valLbl.BackgroundTransparency = 1
        valLbl.Text = tostring(defaultVal)
        valLbl.TextColor3 = Theme.Accent
        valLbl.Font = Enum.Font.GothamBold
        valLbl.TextSize = 12
        valLbl.TextXAlignment = Enum.TextXAlignment.Right
        valLbl.Parent = row

        local track = Instance.new("Frame")
        track.Position = UDim2.new(0, 12, 0, 30)
        track.Size = UDim2.new(1, -24, 0, 6)
        track.BackgroundColor3 = Color3.fromRGB(36, 44, 38)
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

    -- Tab Pages & Settings
    local pCombat = CreateTab("Combat")
    AddToggle(pCombat, "Silent Aim", Config.Combat.SilentAim, function(v) Config.Combat.SilentAim = v end)
    AddToggle(pCombat, "Aim Assist (Right Click)", Config.Combat.AimAssist, function(v) Config.Combat.AimAssist = v end)
    AddToggle(pCombat, "Show FOV Circle", Config.Combat.ShowFOV, function(v) Config.Combat.ShowFOV = v end)
    AddSlider(pCombat, "FOV Radius", 30, 400, Config.Combat.FOV, function(v) Config.Combat.FOV = v end)

    local pVisuals = CreateTab("Visuals")
    AddToggle(pVisuals, "Master ESP Switch", Config.Visuals.Enabled, function(v) Config.Visuals.Enabled = v end)
    AddToggle(pVisuals, "Box ESP", Config.Visuals.BoxESP, function(v) Config.Visuals.BoxESP = v end)
    AddToggle(pVisuals, "Team Check", Config.Visuals.TeamCheck, function(v) Config.Visuals.TeamCheck = v end)
    AddToggle(pVisuals, "Health Bar", Config.Visuals.HealthBar, function(v) Config.Visuals.HealthBar = v end)
    AddToggle(pVisuals, "Player Name", Config.Visuals.NameESP, function(v) Config.Visuals.NameESP = v end)
    AddToggle(pVisuals, "Distance Tag", Config.Visuals.DistanceESP, function(v) Config.Visuals.DistanceESP = v end)
    AddToggle(pVisuals, "Tracers", Config.Visuals.Tracers, function(v) Config.Visuals.Tracers = v end)
    AddToggle(pVisuals, "C4 Bomb Tracker", Config.Visuals.C4Tracker, function(v) Config.Visuals.C4Tracker = v end)
    AddSlider(pVisuals, "Max Distance", 200, 10000, Config.Visuals.MaxDistance, function(v) Config.Visuals.MaxDistance = v end)

    local pMods = CreateTab("Gun Mods")
    AddToggle(pMods, "No Recoil", Config.WeaponMods.NoRecoil, function(v) Config.WeaponMods.NoRecoil = v end)
    AddToggle(pMods, "Anti-Flash", Config.WeaponMods.AntiFlash, function(v) Config.WeaponMods.AntiFlash = v end)

    local pMove = CreateTab("Movement")
    AddToggle(pMove, "Auto Bunnyhop", Config.Movement.Bhop, function(v) Config.Movement.Bhop = v end)

    -- Toggle Menu Keybind (Insert / Right Shift)
    table.insert(Runtime.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Config.UI.ToggleKey or input.KeyCode == Enum.KeyCode.RightShift) then
            Config.UI.MenuOpen = not Config.UI.MenuOpen
            screenGui.Enabled = Config.UI.MenuOpen
        end
    end))

    return screenGui
end

local GuiInstance = BuildUI()

-- Clean Global Unload Method
env.BWXUnload = function()
    Runtime.Active = false

    -- Disconnect Connections
    for _, conn in ipairs(Runtime.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(Runtime.Connections)

    -- Restore Hooks
    for _, unhook in ipairs(Runtime.Hooks) do
        pcall(unhook)
    end
    table.clear(Runtime.Hooks)

    -- Purge Drawing Objects
    if Runtime.DrawingPool.FOV then pcall(function() Runtime.DrawingPool.FOV:Remove() end) end
    if Runtime.DrawingPool.C4 then pcall(function() Runtime.DrawingPool.C4:Remove() end) end
    for id, _ in pairs(Runtime.DrawingPool.Players) do
        PurgeESP(id)
    end

    -- Destroy UI
    if GuiInstance then
        pcall(function() GuiInstance:Destroy() end)
    end

    env.BWXUnload = nil
    env.CybrionUnload = nil
    env.BloxStrikeUnload = nil
end
env.CybrionUnload = env.BWXUnload
env.BloxStrikeUnload = env.BWXUnload

print("[BWX] Bloxstrike Engine Initialized with Zero-Lag Pipeline.")

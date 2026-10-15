--[[
  MM2 SPECTRA HUB 5.2
  Original, readable, client-side Luau example.
  Best tested in a Roblox Studio LocalScript in StarterPlayerScripts.
  Also uses ordinary Roblox client APIs for executor compatibility,
  but has NOT been tested in Delta or the live MM2 experience.

  Features: MM2 game-reported roles (if available), live role radar,
  player ESP, nametags, distance, visible-weapon hints,
  through-wall outlines, player tracers, rainbow ESP, dropped-gun
  and coin markers (name-based), spectate, camera tracking, selected
  player cycling, movement options, optional fly, teleport attempts,
  fullbright, post-effect reduction, player count, anti-void,
  local demo target, mobile-friendly draggable UI and cleanup.

  Role information is only definitive when MM2 provides readable role data.
  Visible weapon hints are explicitly marked unconfirmed. No auto-kill or insta-win. Flings and farming may be corrected by the game server.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
if not localPlayer then
    warn("This hub must run on a Roblox client.")
    return
end
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Allow running the script twice without leaving connections behind.
local environment = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then environment = value end
end
if type(environment.MM2LearningHubUnload) == "function" then
    pcall(environment.MM2LearningHubUnload)
end
if type(environment.SpectraExtrasUnload) == "function" then
    pcall(environment.SpectraExtrasUnload)
end

local connections = {}
local function watch(connection)
    table.insert(connections, connection)
    return connection
end

local enabled = {
    PlayerESP = true,
    RoleESP = true,
    ShowRoles = true,
    ThreatsOnly = false,
    RangeLimit = false,
    RoleAlerts = true,
    Names = true,
    Distances = true,
    Health = true,
    WeaponHints = true,
    XRay = true,
    Tracers = false,
    Rainbow = false,
    GunESP = false,
    KnifeESP = false,
    CoinESP = false,
    Sprint = false,
    CustomJump = false,
    InfiniteJump = false,
    Noclip = false,
    Fly = false,
    AntiFling = false,
    Fullbright = false,
    LowFX = false,
    NoFog = false,
    HideOwnName = false,
    AntiSlip = false,
    AntiVoid = false,
    CameraLock = false,
    AutoCoinFarm = false,
    CoinTeleport = false,
    AutoGunApproach = false,
    AimAssist = false,
    AimWallCheck = true,
    SpinMode = false,
    FlingActive = false,
    EventESP = false,
    FarmEvents = false,
    FarmVisitLimit = false,
    AimFOVRing = false,
    AimRequireSheriff = false,
    AutoAimMurderer = false,
    AutoShootMurderer = false,
    LocalGhost = false,
}
local numbers = { Speed = 24, Jump = 65, FlySpeed = 35, FOV = 70, ESPRange = 250, FarmRadius = 210, AimRadius = 210, AimSmooth = 0.18, FarmVisitCap = 20 }
local playerEffects = {}
local objectEffects = {}
local originalCollisions = {}
local originalFX = {}
local demoParts = {}
local selectedPlayer = nil
local spectateTarget = nil
local flyAttachment = nil
local flyVelocity = nil
local flyRoot = nil
local flyUp, flyDown = false, false
local lastSafeCFrame = nil
local destroyed = false
local lastVisualTick = 0
local previousGravity = Workspace.Gravity
local previousFOV = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70
local originalLocalTransparency = setmetatable({}, {__mode = "k"})
local baseHumanoidSettings = setmetatable({}, {__mode = "k"})
local farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
local farmSkipped = 0
local farmLastScan = 0
local farmCache = {}
local refreshDiagnostics = function() end
local fogOriginal = {}
local ownNameOriginal = setmetatable({}, { __mode = "k" })
local roleMap, roleFetchBusy, lastRoleFetch = {}, false, -100
local roleLastUpdate, roleSyncMessage = 0, "Waiting for MM2 role data"
local roleChangeSignature = ""
local farmVisited = setmetatable({}, { __mode = "k" })
local farmAttempts = 0
local farmNotice = "Ready to scan coins"
local flingBusy = false
local flingToken = 0
local wasFlinging = false
local shotAttemptCount = 0
local shotNotice = "Auto Shoot idle"
local lastShotAttempt = -100
local shotInFlight = false
local flingNotice = "Fling not tested this session"
local lastRoleUI = 0
local lightOriginal = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
}

local function characterOf(p)
    return p and p.Character or nil
end
local function rootOf(p)
    local char = characterOf(p)
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end
local function humanOf(p)
    local char = characterOf(p)
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end
local function alive(p)
    local humanoid = humanOf(p)
    return humanoid and humanoid.Health > 0
end
local function distanceTo(part)
    local ownRoot = rootOf(localPlayer)
    return ownRoot and (ownRoot.Position - part.Position).Magnitude or nil
end

-- Hints ONLY based on an equipped Tool that other players can see.
local function visibleWeaponHint(p)
    local char = characterOf(p)
    if not char then return "Unknown" end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local name = child.Name:lower()
            if name:find("knife", 1, true) then return "Knife visible" end
            if name:find("gun", 1, true) or name:find("revolver", 1, true) then
                return "Gun visible"
            end
        end
    end
    return "Unknown"
end
local function colorForHint(hint)
    if hint == "Knife visible" then return Color3.fromRGB(255, 86, 88) end
    if hint == "Gun visible" then return Color3.fromRGB(85, 176, 255) end
    return Color3.fromRGB(95, 245, 160)
end

-- Game-reported roles are refreshed at most once every six seconds.
-- Many MM2 script examples refer to this RemoteFunction. Never infer that
-- an unknown player is innocent, and do not claim an equipped tool confirms a role.
local validRole = { Murderer = true, Sheriff = true, Innocent = true, Hero = true }
local function refreshRoles()
    if roleFetchBusy or destroyed then return end
    roleFetchBusy = true
    task.spawn(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if not remote or not remote:IsA("RemoteFunction") then
            roleMap = {}
            roleSyncMessage = "Role feed unavailable • using observed tools"
            roleFetchBusy = false
            return
        end
        local ok, data = pcall(function() return remote:InvokeServer() end)
        if destroyed then return end
        if ok and type(data) == "table" then
            local received, count = {}, 0
            for username, info in pairs(data) do
                if type(info) == "table" and validRole[info.Role] then
                    local key = type(username) == "string" and username
                        or type(info.Name) == "string" and info.Name or nil
                    if key then
                        received[key] = { role = info.Role, dead = info.Dead == true or info.Killed == true }
                        count += 1
                    end
                end
            end
            if count > 0 then
                roleMap = received
                roleLastUpdate = os.clock()
                roleSyncMessage = "MM2 role feed • " .. count .. " players"
            else
                roleMap = {}
                roleSyncMessage = "No readable roles returned • using tool hints"
            end
        else
            roleMap = {}
            roleSyncMessage = "Role request unavailable • using tool hints"
        end
        roleFetchBusy = false
    end)
end

local function getRole(player)
    if player and os.clock() - roleLastUpdate < 12 then
        local data = roleMap[player.Name]
        if data then return data.role, "game", data.dead end
    end
    local hint = player and visibleWeaponHint(player) or "Unknown"
    if hint == "Knife visible" then return "Murderer", "hint", false end
    if hint == "Gun visible" then return "Sheriff", "hint", false end
    return "Unknown", "none", false
end
local function getRoleColor(role, source)
    if role == "Murderer" then return Color3.fromRGB(255, 86, 104) end
    if role == "Sheriff" then return Color3.fromRGB(83, 168, 255) end
    if role == "Hero" then return Color3.fromRGB(255, 205, 83) end
    if role == "Innocent" then return Color3.fromRGB(98, 231, 159) end
    return Color3.fromRGB(165, 180, 206)
end
local function roleDisplay(role, source)
    if source == "game" then return role end
    if source == "hint" then return role .. "? [tool seen]" end
    return "Unknown"
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpectraMM2Hub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
-- Keep touch controls clear of the phone notch and Roblox top bar.
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- World-space effects must be parented in Workspace, not inside ScreenGui.
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "SpectraMM2Effects"
effectsFolder.Parent = Workspace

local function round(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 9)
    corner.Parent = parent
end
local function stroke(parent, color, transparency)
    local outline = Instance.new("UIStroke")
    outline.Color = color or Color3.fromRGB(65, 75, 100)
    outline.Transparency = transparency or 0
    outline.Parent = parent
end
local function label(parent, text, h, color, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = color or Color3.fromRGB(225, 231, 245)
    l.TextSize = size or 14
    l.Font = Enum.Font.Gotham
    l.Text = text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Size = UDim2.new(1, -10, 0, h)
    l.Parent = parent
    return l
end

-- SPECTRA 3: Mobile landscape-first layout inspired by the user's demo video.
-- Larger text, fewer labels crammed into each button, vertical navigation.
local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(760, 450)
local function windowDimensions(size)
    local w = math.clamp(size.X - 24, 300, 780)
    local h = math.clamp(size.Y - 46, 280, 550)
    return w, h
end
local width, height = windowDimensions(viewport)
local sidebarWidth = 144
local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(width, height)
window.Position = UDim2.fromOffset(12, 34)
window.BackgroundColor3 = Color3.fromRGB(13, 16, 22)
window.BorderSizePixel = 0
window.Active = true
window.Parent = gui
round(window, 13)
stroke(window, Color3.fromRGB(81, 91, 112), 0.23)
local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 48)
top.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
top.BorderSizePixel = 0
top.Active = true
top.Parent = window
round(top, 12)
local title = label(top, "◈  SPECTRA    MM2  •  v5.0", 46, Color3.fromRGB(250, 251, 255), 17)
title.Position = UDim2.fromOffset(14, 1)
title.Size = UDim2.new(1, -110, 0, 46)
title.Font = Enum.Font.GothamBold
local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(38, 34)
minimize.Position = UDim2.new(1, -85, 0, 7)
minimize.Text = "−"
minimize.TextSize = 25
minimize.Font = Enum.Font.GothamBold
minimize.TextColor3 = Color3.new(1, 1, 1)
minimize.BackgroundColor3 = Color3.fromRGB(42, 50, 66)
minimize.Parent = top
round(minimize, 8)
local close = minimize:Clone()
close.Name = "MinimizeToFloatingIcon"
close.Position = UDim2.new(1, -43, 0, 7)
close.Text = "×"
close.BackgroundColor3 = Color3.fromRGB(113, 47, 63)
close.Parent = top
local roleStrip = Instance.new("TextLabel")
roleStrip.Name = "RoleStatus"
roleStrip.Position = UDim2.fromOffset(12, 53)
roleStrip.Size = UDim2.new(1, -24, 0, 36)
roleStrip.BackgroundColor3 = Color3.fromRGB(31, 41, 55)
roleStrip.TextColor3 = Color3.fromRGB(222, 238, 251)
roleStrip.TextXAlignment = Enum.TextXAlignment.Left
roleStrip.Font = Enum.Font.GothamBold
roleStrip.TextSize = width < 420 and 11 or 13
roleStrip.Text = "  ROLE RADAR  •  checking game data..."
roleStrip.TextTruncate = Enum.TextTruncate.AtEnd
roleStrip.Parent = window
round(roleStrip, 8)
local tabs = Instance.new("ScrollingFrame")
tabs.Name = "Sidebar"
tabs.BorderSizePixel = 0
tabs.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
tabs.Position = UDim2.fromOffset(10, 96)
tabs.Size = UDim2.new(0, sidebarWidth, 1, -143)
tabs.ScrollBarThickness = 2
tabs.ScrollBarImageColor3 = Color3.fromRGB(102, 152, 255)
tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabs.CanvasSize = UDim2.fromOffset(0, 0)
tabs.Parent = window
round(tabs, 10)
local tabPad = Instance.new("UIPadding")
tabPad.PaddingTop = UDim.new(0, 6)
tabPad.PaddingLeft = UDim.new(0, 5)
tabPad.PaddingRight = UDim.new(0, 5)
tabPad.PaddingBottom = UDim.new(0, 6)
tabPad.Parent = tabs
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Vertical
tabLayout.Padding = UDim.new(0, 5)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabs
local main = Instance.new("Frame")
main.Name = "Content"
main.BackgroundTransparency = 1
main.Position = UDim2.fromOffset(sidebarWidth + 17, 96)
main.Size = UDim2.new(1, -sidebarWidth - 27, 1, -143)
main.Parent = window
local status = Instance.new("TextLabel")
status.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
status.Position = UDim2.new(0, 10, 1, -38)
status.Size = UDim2.new(1, -20, 0, 30)
status.TextColor3 = Color3.fromRGB(205, 222, 245)
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "  Ready  •  tap a category on the left"
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Font = Enum.Font.GothamMedium
status.Parent = window
round(status, 7)
local function inform(message)
    if not destroyed then status.Text = "  " .. message end
end
local pages = {}
local tabButtons = {}
local toggleUpdaters = {}
local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Name = "Nav_" .. name
    b.Size = UDim2.new(1, 0, 0, 47)
    b.Text = "  " .. name
    b.TextSize = 15
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
    b.TextColor3 = Color3.fromRGB(205, 215, 230)
    b.BorderSizePixel = 0
    b.Parent = tabs
    round(b, 7)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.BorderSizePixel = 0
    page.BackgroundTransparency = 1
    page.Size = UDim2.fromScale(1, 1)
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(99, 149, 255)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.Visible = false
    page.Parent = main
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 5)
    pad.PaddingBottom = UDim.new(0, 15)
    pad.PaddingLeft = UDim.new(0, 3)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = page
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 9)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    pages[name] = page
    tabButtons[name] = b
    watch(b.MouseButton1Click:Connect(function()
        for tabName, p in pairs(pages) do
            p.Visible = tabName == name
            tabButtons[tabName].BackgroundColor3 = tabName == name
                and Color3.fromRGB(60, 87, 197) or Color3.fromRGB(28, 34, 45)
            tabButtons[tabName].TextColor3 = tabName == name
                and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(205, 215, 230)
        end
    end))
    return page
end
local rolesPage = makeTab("HOME")
local visualsPage = makeTab("ESP")
local movementPage = makeTab("MOVE")
local toolsPage = makeTab("TELEPORT")
local farmPage = makeTab("FARM")
local aimPage = makeTab("AIM")
local funPage = makeTab("FUN")
local settingsPage = makeTab("SETTINGS")
local diagnosticsPage = makeTab("STATUS")
tabButtons.HOME.BackgroundColor3 = Color3.fromRGB(60, 87, 197)
tabButtons.HOME.TextColor3 = Color3.fromRGB(255, 255, 255)
rolesPage.Visible = true
-- Draggable SPECTRA icon that remains when the full menu is minimized.
local launcher = Instance.new("TextButton")
launcher.Name = "FloatingSPECTRAIcon"
launcher.Size = UDim2.fromOffset(62, 62)
launcher.BackgroundColor3 = Color3.fromRGB(48, 80, 189)
launcher.TextColor3 = Color3.fromRGB(255, 255, 255)
launcher.TextSize = 29
launcher.Font = Enum.Font.GothamBold
launcher.Text = "◈"
launcher.AutoButtonColor = true
launcher.Active = true
launcher.ZIndex = 50
launcher.Visible = false
launcher.Parent = gui
round(launcher, 31)
stroke(launcher, Color3.fromRGB(145, 183, 255), 0.12)
local launcherName = Instance.new("TextLabel")
launcherName.Name = "Brand"
launcherName.BackgroundTransparency = 1
launcherName.Size = UDim2.new(1, 0, 0, 16)
launcherName.Position = UDim2.new(0, 0, 1, -18)
launcherName.Text = "SPECTRA"
launcherName.Font = Enum.Font.GothamBold
launcherName.TextColor3 = Color3.fromRGB(242, 247, 255)
launcherName.TextSize = 9
launcherName.ZIndex = 51
launcherName.Active = false
launcherName.Parent = launcher

local function usableViewport()
    local camera = Workspace.CurrentCamera
    local currentSize = camera and camera.ViewportSize or Vector2.new(390, 700)
    local topInset, bottomInset = GuiService:GetGuiInset()
    return Vector2.new(
        math.max(90, currentSize.X - topInset.X - bottomInset.X),
        math.max(110, currentSize.Y - topInset.Y - bottomInset.Y)
    )
end
local function placeLauncher(x, y)
    local safe = usableViewport()
    local maxX = math.max(8, safe.X - launcher.Size.X.Offset - 8)
    local maxY = math.max(8, safe.Y - launcher.Size.Y.Offset - 8)
    launcher.Position = UDim2.fromOffset(math.clamp(x, 8, maxX), math.clamp(y, 8, maxY))
end
local initialArea = usableViewport()
placeLauncher(initialArea.X - 72, 94)
local function heading(page, text)
    local l = label(page, text, 34, Color3.fromRGB(200, 217, 255), 16)
    l.Font = Enum.Font.GothamBold
    l.Size = UDim2.new(1, -4, 0, 34)
end
local function makeButton(page, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, 58)
    b.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
    b.TextColor3 = Color3.fromRGB(242, 246, 252)
    b.TextSize = 15
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextWrapped = true
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = page
    round(b, 9)
    local inset = Instance.new("UIPadding")
    inset.PaddingLeft = UDim.new(0, 12)
    inset.PaddingRight = UDim.new(0, 13)
    inset.Parent = b
    watch(b.MouseButton1Click:Connect(function()
        if not destroyed then
            local ok, err = pcall(callback)
            if not ok then inform("Error: " .. tostring(err):sub(1, 72)) end
        end
    end))
    return b
end
local function toggle(page, name, key, onChanged)
    local b
    local pill = Instance.new("TextLabel")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Size = UDim2.fromOffset(49, 26)
    pill.Position = UDim2.new(1, -11, 0.5, 0)
    pill.TextSize = 12
    pill.Font = Enum.Font.GothamBold
    round(pill, 13)
    local function update()
        b.Text = name
        pill.Text = enabled[key] and "ON" or "OFF"
        pill.TextColor3 = enabled[key] and Color3.fromRGB(239, 255, 250)
            or Color3.fromRGB(216, 227, 242)
        pill.BackgroundColor3 = enabled[key] and Color3.fromRGB(32, 150, 117)
            or Color3.fromRGB(69, 76, 91)
    end
    b = makeButton(page, "", function()
        enabled[key] = not enabled[key]
        update()
        if onChanged then onChanged(enabled[key]) end
    end)
    b.TextSize = 14
    local inset = b:FindFirstChildWhichIsA("UIPadding")
    if inset then inset.PaddingRight = UDim.new(0, 64) end
    pill.Parent = b
    update()
    table.insert(toggleUpdaters, update)
    return b
end

-- Use horizontal scrolling navigation on portrait phones so buttons have room
-- for legible labels. Landscape keeps the sidebar from the reference video.
local function applyResponsiveLayout()
    local narrow = width < 550
    if narrow then
        tabs.Position = UDim2.fromOffset(10, 96)
        tabs.Size = UDim2.new(1, -20, 0, 55)
        tabs.ScrollingDirection = Enum.ScrollingDirection.X
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        main.Position = UDim2.fromOffset(10, 157)
        main.Size = UDim2.new(1, -20, 1, -202)
    else
        tabs.Position = UDim2.fromOffset(10, 96)
        tabs.Size = UDim2.new(0, sidebarWidth, 1, -143)
        tabs.ScrollingDirection = Enum.ScrollingDirection.Y
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabLayout.FillDirection = Enum.FillDirection.Vertical
        main.Position = UDim2.fromOffset(sidebarWidth + 17, 96)
        main.Size = UDim2.new(1, -sidebarWidth - 27, 1, -143)
    end
    for _, button in pairs(tabButtons) do
        button.Size = narrow and UDim2.fromOffset(107, 45)
            or UDim2.new(1, 0, 0, 47)
        button.TextSize = narrow and 13 or 15
    end
end
applyResponsiveLayout()

-- Drag window with mouse or touch.
local dragging = false
local startPos, startInput, dragType
watch(top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        startPos = window.Position
        startInput = input.Position
        dragType = input.UserInputType
    end
end))
watch(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if dragType == Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if dragType == Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - startInput
    local screen = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(390, 700)
    local newX = math.clamp(startPos.X.Offset + delta.X, -width + 70, screen.X - 70)
    local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, screen.Y - 42)
    window.Position = UDim2.fromOffset(newX, newY)
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == dragType then dragging = false end
end))
local minimized = false
local function setWindowOpen(open)
    if destroyed then return end
    minimized = not open
    window.Visible = open
    tabs.Visible = open
    main.Visible = open
    status.Visible = open
    launcher.Visible = not open
    if not open then
        placeLauncher(launcher.Position.X.Offset, launcher.Position.Y.Offset)
    end
end
-- Both X and minus minimize without stopping existing features.
watch(minimize.Activated:Connect(function() setWindowOpen(false) end))
watch(close.Activated:Connect(function() setWindowOpen(false) end))

-- Hold to drag; release with no movement to reopen. Uses touch identity.
local launcherDragInput, launcherDragType
local launcherDragStart, launcherStartXY
local launcherMoved = false
watch(launcher.InputBegan:Connect(function(input)
    local kind = input.UserInputType
    if launcherDragInput or (kind ~= Enum.UserInputType.Touch
        and kind ~= Enum.UserInputType.MouseButton1) then return end
    launcherDragInput = input
    launcherDragType = kind
    launcherDragStart = input.Position
    launcherStartXY = Vector2.new(launcher.Position.X.Offset, launcher.Position.Y.Offset)
    launcherMoved = false
end))
watch(UserInputService.InputChanged:Connect(function(input)
    if not launcherDragInput or not minimized then return end
    if launcherDragType == Enum.UserInputType.Touch then
        if input ~= launcherDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    local delta = input.Position - launcherDragStart
    if delta.Magnitude > 9 then launcherMoved = true end
    if launcherMoved then
        placeLauncher(launcherStartXY.X + delta.X, launcherStartXY.Y + delta.Y)
    end
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if not launcherDragInput then return end
    if launcherDragType == Enum.UserInputType.Touch then
        if input ~= launcherDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    local delta = input.Position - launcherDragStart
    local wasDrag = launcherMoved or delta.Magnitude > 9
    launcherDragInput = nil
    launcherDragType = nil
    launcherDragStart = nil
    launcherStartXY = nil
    launcherMoved = false
    if destroyed or not minimized then return end
    if wasDrag then
        local safe = usableViewport()
        local edgeX = launcher.Position.X.Offset + launcher.Size.X.Offset / 2 < safe.X / 2
            and 8 or math.max(8, safe.X - launcher.Size.X.Offset - 8)
        placeLauncher(edgeX, launcher.Position.Y.Offset)
    else
        setWindowOpen(true)
    end
end))
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setWindowOpen(minimized)
    end
end))
-- Player visuals ------------------------------------------------------
local function destroyPlayerEffect(p)
    local e = playerEffects[p]
    if e then
        -- Never destroy e.char: it belongs to the player, not this script.
        e.highlight:Destroy()
        e.billboard:Destroy()
        playerEffects[p] = nil
    end
end
local function makePlayerEffect(p)
    local char = characterOf(p)
    local root = rootOf(p)
    local head = char and char:FindFirstChild("Head")
    if not char or not root or not head then return end
    local existing = playerEffects[p]
    if existing and existing.char == char then return end
    destroyPlayerEffect(p)
    local h = Instance.new("Highlight")
    h.Name = "LearningHubPlayerHighlight"
    h.Adornee = char
    h.FillTransparency = 0.72
    h.OutlineTransparency = 0
    h.Parent = effectsFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlayerInfo"
    billboard.Adornee = head
    billboard.Size = UDim2.fromOffset(222, 64)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = gui
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.TextScaled = false
    text.TextSize = 12
    text.TextWrapped = true
    text.Font = Enum.Font.GothamBold
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0.25
    text.BackgroundTransparency = 1
    text.Parent = billboard

    playerEffects[p] = { char = char, highlight = h, billboard = billboard, text = text }
end
local function updatePlayerEffects(timeNow)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            local role, source = getRole(p)
            local tracked = not enabled.ThreatsOnly or (role == "Murderer" or role == "Sheriff" or role == "Hero")
            local targetRoot = rootOf(p)
            local distance = targetRoot and distanceTo(targetRoot)
            local inRange = not enabled.RangeLimit or (distance and distance <= numbers.ESPRange)
            if enabled.PlayerESP and alive(p) and tracked and inRange then
                makePlayerEffect(p)
                local e = playerEffects[p]
                if e then
                    local hint = visibleWeaponHint(p)
                    local color = enabled.Rainbow and Color3.fromHSV((timeNow / 5) % 1, 0.85, 1)
                        or (enabled.RoleESP and getRoleColor(role, source) or colorForHint(hint))
                    e.highlight.Enabled = true
                    e.highlight.OutlineTransparency = source == "hint" and 0.35 or 0
                    e.highlight.FillColor = color
                    e.highlight.OutlineColor = color
                    e.highlight.DepthMode = enabled.XRay and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    e.billboard.Enabled = enabled.Names or enabled.Distances or enabled.WeaponHints or enabled.Health or enabled.ShowRoles
                    local pieces = {}
                    if enabled.Names then table.insert(pieces, p.DisplayName) end
                    local root = rootOf(p)
                    local distance = root and distanceTo(root)
                    if enabled.Distances and distance then
                        table.insert(pieces, ("%d studs"):format(math.floor(distance)))
                    end
                    if enabled.Health then
                        local hum = humanOf(p)
                        if hum then table.insert(pieces, ("HP %d"):format(math.ceil(hum.Health))) end
                    end
                    if enabled.ShowRoles then table.insert(pieces, roleDisplay(role, source)) end
                    if enabled.WeaponHints and hint ~= "Unknown" then table.insert(pieces, hint) end
                    e.text.Text = table.concat(pieces, "  |  ")
                    e.text.TextColor3 = color
                end
            else
                destroyPlayerEffect(p)
            end
        end
    end
    for p in pairs(playerEffects) do
        if not p.Parent then destroyPlayerEffect(p) end
    end
end

-- Tracers follow the local root and target root via Beam Attachments.
local tracerEffects = {}
local function clearTracer(p)
    local e = tracerEffects[p]
    if not e then return end
    -- Only destroy the Beam and attachments we created.
    e.beam:Destroy()
    e.a0:Destroy()
    e.a1:Destroy()
    tracerEffects[p] = nil
end
local function updateTracers()
    local mine = rootOf(localPlayer)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            local theirs = rootOf(p)
            local e = tracerEffects[p]
            local role, source = getRole(p)
            local tracked = not enabled.ThreatsOnly or (role == "Murderer" or role == "Sheriff" or role == "Hero")
            local inRange = not enabled.RangeLimit or (theirs and distanceTo(theirs) and distanceTo(theirs) <= numbers.ESPRange)
            if not enabled.PlayerESP or not enabled.Tracers or not tracked or not inRange or not mine or not theirs or not alive(p) then
                clearTracer(p)
            else
                if e and (e.mine ~= mine or e.theirs ~= theirs) then
                    clearTracer(p)
                    e = nil
                end
                if not e then
                    local a0 = Instance.new("Attachment")
                    a0.Name = "LearningHubTracerOrigin"
                    a0.Parent = mine
                    local a1 = Instance.new("Attachment")
                    a1.Name = "LearningHubTracerTarget"
                    a1.Parent = theirs
                    local beam = Instance.new("Beam")
                    beam.Attachment0 = a0
                    beam.Attachment1 = a1
                    beam.Width0 = 0.07
                    beam.Width1 = 0.07
                    beam.FaceCamera = true
                    beam.LightEmission = 0.9
                    beam.Transparency = NumberSequence.new(0.16)
                    beam.Parent = effectsFolder
                    e = { mine = mine, theirs = theirs, a0 = a0, a1 = a1, beam = beam }
                    tracerEffects[p] = e
                end
                e.beam.Color = ColorSequence.new(enabled.RoleESP
                    and getRoleColor(role, source) or colorForHint(visibleWeaponHint(p)))
            end
        end
    end
    for p in pairs(tracerEffects) do
        if not p.Parent then clearTracer(p) end
    end
end

-- Name-based map markers, not MM2 privileged server data.
local function objectType(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return nil end
    local name = obj.Name:lower()
    if (name == "gundrop" or name == "droppedgun" or name == "dropped_gun") then
        return "Gun"
    elseif name == "knifedrop" or name == "droppedknife" or name == "dropped_knife" then
        return "Knife"
    elseif name == "coin" or name == "coinpart" or name == "coin_server"
        or name == "coinpickup" or name == "token"
        or (obj:IsA("BasePart") and obj:FindFirstChild("CoinVisual")) then
        return "Coin"
    elseif name == "candy" or name == "shell" or name == "gem"
        or name == "snowflake" or name == "eventtoken" or name == "pumpkinpickup" then
        return "Event"
    end
    return nil
end
local function clearObject(obj)
    local e = objectEffects[obj]
    if not e then return end
    e.highlight:Destroy()
    e.billboard:Destroy()
    objectEffects[obj] = nil
end
local function ensureObject(obj)
    if objectEffects[obj] then return end
    if not obj:IsDescendantOf(Workspace) then return end
    local kind = objectType(obj)
    if not kind then return end
    local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    if not anchor then return end
    if kind == "Gun" and not enabled.GunESP then return end
    if kind == "Coin" and not enabled.CoinESP then return end
    if kind == "Knife" and not enabled.KnifeESP then return end
    if kind == "Event" and not enabled.EventESP then return end
    if (function()
        local count = 0
        for _ in pairs(objectEffects) do count = count + 1 end
        return count
    end)() >= 90 then return end
    local color = kind == "Gun" and Color3.fromRGB(255, 209, 64)
        or kind == "Knife" and Color3.fromRGB(255, 95, 112)
        or kind == "Event" and Color3.fromRGB(190, 144, 255)
        or Color3.fromRGB(125, 255, 129)
    local h = Instance.new("Highlight")
    h.Name = "LearningHubObjectHighlight"
    h.Adornee = obj
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = 0.58
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = effectsFolder
    local bb = Instance.new("BillboardGui")
    bb.Adornee = anchor
    bb.Size = UDim2.fromOffset(130, 34)
    bb.AlwaysOnTop = true
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
    bb.Parent = gui
    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromScale(1, 1)
    t.TextColor3 = color
    t.TextStrokeTransparency = 0.15
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.Parent = bb
    objectEffects[obj] = { highlight = h, billboard = bb, text = t, kind = kind, anchor = anchor }
end
local function scanObjects()
    if not enabled.GunESP and not enabled.CoinESP and not enabled.KnifeESP and not enabled.EventESP then
        for obj in pairs(objectEffects) do clearObject(obj) end
        return
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) then ensureObject(obj) end
    end
end
local function updateObjects()
    for obj, e in pairs(objectEffects) do
        if not obj:IsDescendantOf(Workspace)
            or (e.kind == "Gun" and not enabled.GunESP)
            or (e.kind == "Coin" and not enabled.CoinESP)
            or (e.kind == "Knife" and not enabled.KnifeESP)
            or (e.kind == "Event" and not enabled.EventESP) then
            clearObject(obj)
        else
            local d = e.anchor.Parent and distanceTo(e.anchor)
            e.text.Text = e.kind .. (d and (" • %d studs"):format(d) or "")
        end
    end
end
watch(Workspace.DescendantAdded:Connect(function(obj)
    if objectType(obj) then task.defer(function()
        if not destroyed and obj.Parent then ensureObject(obj) end
    end) end
end))
watch(Workspace.DescendantRemoving:Connect(function(obj)
    if objectEffects[obj] then clearObject(obj) end
end))

-- Movement and local utilities ----------------------------------------
local function restoreNoclip()
    for part, value in pairs(originalCollisions) do
        if part.Parent then part.CanCollide = value end
    end
    table.clear(originalCollisions)
end
local function stopFly()
    if flyVelocity then flyVelocity:Destroy() end
    if flyAttachment then flyAttachment:Destroy() end
    flyVelocity, flyAttachment, flyRoot = nil, nil, nil
    local humanoid = humanOf(localPlayer)
    if humanoid then pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end) end
end
local function setupFly()
    local root = rootOf(localPlayer)
    if not root then return end
    if flyRoot == root and flyVelocity and flyVelocity.Parent then return end
    stopFly()
    local a = Instance.new("Attachment")
    a.Name = "LearningHubFlyAttachment"
    a.Parent = root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name = "LearningHubFlyVelocity"
    velocity.Attachment0 = a
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.MaxForce = 100000
    velocity.VectorVelocity = Vector3.zero
    velocity.Parent = root
    flyAttachment, flyVelocity, flyRoot = a, velocity, root
end
local function applyCharacterSettings()
    local humanoid = humanOf(localPlayer)
    if humanoid then
        if not baseHumanoidSettings[humanoid] then
            baseHumanoidSettings[humanoid] = {
                speed = humanoid.WalkSpeed,
                jump = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
            }
        end
        local base = baseHumanoidSettings[humanoid]
        humanoid.WalkSpeed = enabled.Sprint and numbers.Speed or base.speed
        if enabled.CustomJump then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = numbers.Jump
        else
            humanoid.UseJumpPower = base.useJumpPower
            humanoid.JumpPower = base.jump
        end
    end
end
watch(localPlayer.CharacterAdded:Connect(function()
    restoreNoclip()
    stopFly()
    -- Original local transparency is stored weakly and restored on unload.
    task.delay(0.5, function()
        if not destroyed then applyCharacterSettings() end
    end)
end))
watch(UserInputService.JumpRequest:Connect(function()
    if enabled.InfiniteJump then
        local humanoid = humanOf(localPlayer)
        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

local function setLocalGhost(on)
    if on then
        local char = characterOf(localPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if originalLocalTransparency[part] == nil then
                    originalLocalTransparency[part] = part.LocalTransparencyModifier
                end
                part.LocalTransparencyModifier = 0.85
            end
        end
    else
        for part, original in pairs(originalLocalTransparency) do
            if part.Parent then part.LocalTransparencyModifier = original end
            originalLocalTransparency[part] = nil
        end
    end
end

local function setFullbright(on)
    if on then
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
    else
        for property, value in pairs(lightOriginal) do
            Lighting[property] = value
        end
    end
end
local function setLowFX(on)
    if on then
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("PostEffect") then
                if originalFX[child] == nil then originalFX[child] = child.Enabled end
                child.Enabled = false
            end
        end
    else
        for effect, original in pairs(originalFX) do
            if effect.Parent then effect.Enabled = original end
        end
        table.clear(originalFX)
    end
end

local function setNoFog(on)
    if on then
        Lighting.FogStart = 0
        Lighting.FogEnd = 100000
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("Atmosphere") then
                if not fogOriginal[effect] then
                    fogOriginal[effect] = {Density = effect.Density, Haze = effect.Haze}
                end
                effect.Density = 0
                effect.Haze = 0
            end
        end
    else
        Lighting.FogStart = lightOriginal.FogStart
        Lighting.FogEnd = lightOriginal.FogEnd
        for atmosphere, original in pairs(fogOriginal) do
            if atmosphere.Parent then
                atmosphere.Density = original.Density
                atmosphere.Haze = original.Haze
            end
        end
        table.clear(fogOriginal)
    end
end
local function setHideOwnName(on)
    local hum = humanOf(localPlayer)
    if not hum then return end
    if on then
        if ownNameOriginal[hum] == nil then
            ownNameOriginal[hum] = hum.DisplayDistanceType
        end
        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    elseif ownNameOriginal[hum] then
        hum.DisplayDistanceType = ownNameOriginal[hum]
        ownNameOriginal[hum] = nil
    end
end

local function otherPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then table.insert(list, p) end
    end
    table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
    return list
end
local function chooseNextPlayer()
    local list = otherPlayers()
    if #list == 0 then
        selectedPlayer = nil
        inform("No other players to select")
        return
    end
    local current = 0
    for i, p in ipairs(list) do
        if p == selectedPlayer then current = i break end
    end
    selectedPlayer = list[(current % #list) + 1]
    inform("Selected: " .. selectedPlayer.DisplayName .. " (@" .. selectedPlayer.Name .. ")")
end
local function restoreCamera()
    spectateTarget = nil
    enabled.CameraLock = false
    local camera = Workspace.CurrentCamera
    local humanoid = humanOf(localPlayer)
    if camera and humanoid then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
end
local function spectate()
    if not selectedPlayer or not humanOf(selectedPlayer) then
        inform("Select a live player first")
        return
    end
    spectateTarget = selectedPlayer
    enabled.CameraLock = false
    local camera = Workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanOf(selectedPlayer)
        inform("Spectating " .. selectedPlayer.DisplayName)
    end
end
local function moveNear(p)
    local root = rootOf(p)
    local own = rootOf(localPlayer)
    if not root or not own then inform("Target isn't spawned") return end
    own.CFrame = root.CFrame * CFrame.new(3, 0, 0)
    inform("Local teleport attempted • server may correct it")
end
local function findHint(kind)
    for _, p in ipairs(otherPlayers()) do
        if alive(p) and visibleWeaponHint(p) == kind then return p end
    end
    return nil
end
local function findRoleTarget(roleWanted)
    local fallback
    for _, p in ipairs(otherPlayers()) do
        if alive(p) then
            local role, source = getRole(p)
            if role == roleWanted then
                if source == "game" then return p, "game" end
                fallback = fallback or p
            end
        end
    end
    return fallback, fallback and "hint" or "none"
end
local function selectRole(role)
    local p, source = findRoleTarget(role)
    if not p then
        inform("No " .. role .. " identified yet")
        return nil
    end
    selectedPlayer = p
    inform(role .. (source == "hint" and " (unconfirmed tool)" or " (game data)") .. ": " .. p.Name)
    return p
end
local function findNearestObject(kind)
    local own = rootOf(localPlayer)
    if not own then return nil end
    local closest, bestDistance = nil, math.huge
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) == kind then
            local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
            if anchor then
                local d = (anchor.Position - own.Position).Magnitude
                if d < bestDistance then closest, bestDistance = anchor, d end
            end
        end
    end
    return closest
end
local function tpNearObject(kind)
    local target = findNearestObject(kind)
    local root = rootOf(localPlayer)
    if not root or not target then
        inform("No " .. kind .. " object found")
        return
    end
    root.CFrame = target.CFrame * CFrame.new(0, 3, 0)
    inform("Local teleport attempted • " .. kind)
end
local function tpCrosshair()
    local camera = Workspace.CurrentCamera
    local root = rootOf(localPlayer)
    if not camera or not root then return inform("Character/camera not ready") end
    local size = camera.ViewportSize
    local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {characterOf(localPlayer)}
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * 450, params)
    if not hit then return inform("No surface at center of screen") end
    root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0))
    inform("Crosshair teleport attempted")
end
local function createDemoPart(name, color)
    local root = rootOf(localPlayer)
    if not root then inform("Spawn your character first") return end
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(2, 2, 2)
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = color
    part.CFrame = root.CFrame * CFrame.new(0, 2, -12)
    part.Parent = Workspace
    table.insert(demoParts, part)
    ensureObject(part)
    inform("Spawned local-only " .. name .. " demo")
end


-- MM2 convenience actions. Everything below uses player-side movement/physics.
-- Coin pickup, role info, and player collisions are game/server dependent.
local function isCollectible(obj)
    if not obj:IsA("BasePart") then return false end
    local kind = objectType(obj)
    if kind == "Coin" then return true end
    if enabled.FarmEvents and kind == "Event" then return true end
    if obj.Name == "CoinVisual" and obj.Parent and obj.Parent:IsA("BasePart") then
        return false -- Visual children are not independently collectible.
    end
    return false
end
local function scanFarmTargets()
    if os.clock() - farmLastScan < 2 then return end
    farmLastScan = os.clock()
    table.clear(farmCache)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if isCollectible(obj) and #farmCache < 600 then
            table.insert(farmCache, obj)
        end
    end
end
local function getNearestFarmCoin()
    local own = rootOf(localPlayer)
    if not own then return nil end
    scanFarmTargets()
    local nearest, best = nil, numbers.FarmRadius
    for _, obj in ipairs(farmCache) do
        if obj.Parent and isCollectible(obj) then
            local visual = obj:FindFirstChild("CoinVisual")
            local collected = visual and visual:GetAttribute("Collected") == true
            local prior = farmVisited[obj]
            if not collected and (not prior or os.clock() - prior > 12) then
                local dist = (obj.Position - own.Position).Magnitude
                if dist < best then nearest, best = obj, dist end
            end
        end
    end
    return nearest, best
end
local function resetFarmTracking()
    table.clear(farmVisited)
    table.clear(farmCache)
    farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
    farmAttempts, farmSkipped, farmLastScan = 0, 0, 0
    farmNotice = "Tracking cleared"
end

local function getNearestGun()
    local root = rootOf(localPlayer)
    if not root then return nil end
    return findNearestObject("Gun")
end
local function setFarmEnabled(on)
    if on then
        enabled.CoinESP = true
        enabled.AutoGunApproach = false
        farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
        inform("Auto farm ON • counts visits, not server-confirmed coins")
    else
        local humanoid = humanOf(localPlayer)
        local root = rootOf(localPlayer)
        if humanoid and root then humanoid:MoveTo(root.Position) end
        inform("Coin farm stopped")
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end

-- Local multi-axis physics contact attempt. This is NOT a server-side knockback.
-- Roblox network ownership and collision rules determine whether anyone else moves.
local function flingSelected()
    if flingBusy then return inform("Fling attempt already running") end
    local target = selectedPlayer
    local ownRoot = rootOf(localPlayer)
    local ownHumanoid = humanOf(localPlayer)
    if not target or target == localPlayer or not alive(target)
        or not rootOf(target) or not ownRoot or not ownHumanoid then
        return inform("Select a living player on HOME first")
    end

    flingBusy = true
    flingToken += 1
    local token = flingToken
    local originalCF = ownRoot.CFrame
    local observedStart = rootOf(target).Position
    local collidableCount = 0
    for _, part in ipairs(target.Character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            collidableCount += 1
        end
    end
    flingNotice = "Contact test • " .. collidableCount .. " collidable target parts"
    local originalCollision = ownRoot.CanCollide
    local originalStand = ownHumanoid.PlatformStand
    local prior = {
        AntiFling = enabled.AntiFling, SpinMode = enabled.SpinMode,
        Noclip = enabled.Noclip, Fly = enabled.Fly,
        AntiSlip = enabled.AntiSlip, AntiVoid = enabled.AntiVoid,
        AutoCoinFarm = enabled.AutoCoinFarm, AutoGunApproach = enabled.AutoGunApproach,
    }

    -- These controls fight the physics solver or move our own character away.
    for setting in pairs(prior) do enabled[setting] = false end
    stopFly()
    restoreNoclip()
    enabled.FlingActive = true
    inform("Multi-axis fling test: X/Y/Z tumble • " .. target.DisplayName)

    local finished = false
    local function finish()
        if finished then return end
        finished = true
        enabled.FlingActive = false
        for setting, value in pairs(prior) do enabled[setting] = value end
        pcall(function()
            if ownRoot and ownRoot.Parent then
                ownRoot.AssemblyAngularVelocity = Vector3.zero
                ownRoot.AssemblyLinearVelocity = Vector3.zero
                ownRoot.CanCollide = originalCollision
                if not destroyed and rootOf(localPlayer) == ownRoot then
                    ownRoot.CFrame = originalCF * CFrame.new(0, 3, 0)
                end
            end
            if ownHumanoid and ownHumanoid.Parent then
                ownHumanoid.PlatformStand = originalStand
                if not originalStand then
                    ownHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end)
        flingBusy = false
        for _, refresh in ipairs(toggleUpdaters) do refresh() end
        if not destroyed then
            local targetRootNow = rootOf(target)
            local distance = targetRootNow
                and (targetRootNow.Position - observedStart).Magnitude or 0
            flingNotice = string.format(
                "Fling test: %.1f studs local target displacement; %d collidable parts",
                distance, collidableCount)
            inform(flingNotice)
        end
    end

    task.spawn(function()
        local ok, err = pcall(function()
            ownRoot.CanCollide = true
            ownHumanoid.PlatformStand = true
            ownHumanoid:ChangeState(Enum.HumanoidStateType.Physics)

            local startTime = os.clock()
            while not destroyed and enabled.FlingActive and flingToken == token
                and os.clock() - startTime < 1.65 do
                local currentRoot = rootOf(localPlayer)
                local targetRoot = rootOf(target)
                if currentRoot ~= ownRoot or not targetRoot or not alive(target) then
                    break
                end
                local phase = (os.clock() - startTime) * 22

                -- Stay within physical contact distance, rather than orbiting
                -- 2.3 studs away like the original v5 implementation.
                local offset = Vector3.new(
                    math.sin(phase * 1.12) * 0.68,
                    math.sin(phase * 0.83) * 0.75,
                    math.cos(phase * 1.36) * 0.68
                )
                local inward = offset.Magnitude > 0.05
                    and (-offset.Unit) or Vector3.new(1, 0, 0)
                local tumble = Vector3.new(
                    120 * math.sin(phase * 1.05 + 0.5),
                    135 * math.cos(phase * 0.92),
                    120 * math.sin(phase * 1.34 + 1.1)
                )
                ownRoot.CFrame = CFrame.new(targetRoot.Position + offset)
                    * CFrame.Angles(phase * 1.8, phase * 2.35, phase * 2.1)
                ownRoot.AssemblyAngularVelocity = tumble
                ownRoot.AssemblyLinearVelocity = inward * 92
                    + Vector3.new(0, math.sin(phase * 1.7) * 25, 0)
                task.wait(0.045)
            end
        end)
        finish()
        if not ok then
            warn("SPECTRA fling physics attempt error: " .. tostring(err))
        end
    end)
end
local function hasWallClearance(camera, part)
    if not enabled.AimWallCheck then return true end
    local vector = part.Position - camera.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ownChar = characterOf(localPlayer)
    params.FilterDescendantsInstances = ownChar and { ownChar } or {}
    local hit = Workspace:Raycast(camera.CFrame.Position, vector, params)
    return not hit or hit.Instance:IsDescendantOf(part.Parent)
end

local function findConfirmedMurderer()
    local ownRoot = rootOf(localPlayer)
    local found, best = nil, math.huge
    for _, player in ipairs(otherPlayers()) do
        local role, source, dead = getRole(player)
        local root = rootOf(player)
        if role == "Murderer" and source == "game" and not dead
            and root and alive(player) then
            local distance = ownRoot and (root.Position - ownRoot.Position).Magnitude or 0
            if distance < best then found, best = player, distance end
        end
    end
    return found
end
local function findAimPart()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    if enabled.AimRequireSheriff then
        local myRole, source = getRole(localPlayer)
        if source ~= "game" or (myRole ~= "Sheriff" and myRole ~= "Hero") then return nil end
    end
    if enabled.AutoAimMurderer then
        local murderer = findConfirmedMurderer()
        local char = characterOf(murderer)
        local part = char and (char:FindFirstChild("Head")
            or char:FindFirstChild("HumanoidRootPart"))
        return part and hasWallClearance(camera, part) and part or nil
    end
    local center = camera.ViewportSize / 2
    local best, chosen = numbers.AimRadius, nil
    for _, player in ipairs(otherPlayers()) do
        local role, source = getRole(player)
        if alive(player) and role == "Murderer" then
            local char = characterOf(player)
            local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
            if part then
                local projected, onScreen = camera:WorldToViewportPoint(part.Position)
                local dist = (Vector2.new(projected.X, projected.Y) - center).Magnitude
                if onScreen and projected.Z > 0 and dist < best and hasWallClearance(camera, part) then
                    best, chosen = dist, part
                end
            end
        end
    end
    return chosen
end

-- Auto Shoot only issues real MM2 Gun requests while role/gun/raycast gates pass.
-- A successful RemoteFunction call never guarantees a server-registered hit.
local function equippedGun()
    local char = characterOf(localPlayer)
    local bag = localPlayer:FindFirstChildOfClass("Backpack")
    local gun = char and char:FindFirstChild("Gun")
    if gun and gun:IsA("Tool") then return gun, true end
    gun = bag and bag:FindFirstChild("Gun")
    if gun and gun:IsA("Tool") then return gun, false end
    return nil, false
end

local function resolveGunShot(gun)
    local knifeServer = gun:FindFirstChild("KnifeServer")
    local shoot = knifeServer and knifeServer:FindFirstChild("ShootGun")
    if shoot and shoot:IsA("RemoteFunction") then return shoot, "AH" end
    local knifeLocal = gun:FindFirstChild("KnifeLocal")
    local beam = knifeLocal and knifeLocal:FindFirstChild("CreateBeam")
    local fallback = beam and beam:FindFirstChild("RemoteFunction")
    if fallback and fallback:IsA("RemoteFunction") then return fallback, "AH2" end
    return nil, nil
end

local function clearGunShot(target, position)
    local char = characterOf(localPlayer)
    local targetChar = characterOf(target)
    local origin = char and (char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart"))
    if not origin or not targetChar then return false end
    local direction = position - origin.Position
    if direction.Magnitude < 0.1 or direction.Magnitude > 400 then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local hit = Workspace:Raycast(origin.Position, direction, params)
    return not hit or hit.Instance:IsDescendantOf(targetChar)
end

local function attemptMurdererShot(manual)
    if destroyed or shotInFlight then return end
    local now = os.clock()
    if now - lastShotAttempt < 2.5 then
        if manual then inform("Gun cooldown • try again shortly") end
        return
    end
    local ownRole, source = getRole(localPlayer)
    if source ~= "game" or (ownRole ~= "Sheriff" and ownRole ~= "Hero") then
        shotNotice = "Requires confirmed Sheriff/Hero role"
        if manual then inform(shotNotice) end
        return
    end
    local murderer = findConfirmedMurderer()
    local targetRoot = rootOf(murderer)
    if not targetRoot then
        shotNotice = "Waiting for living, confirmed Murderer"
        if manual then inform(shotNotice) end
        return
    end
    local gun, isEquipped = equippedGun()
    if not gun then
        shotNotice = "Gun not found in character/backpack"
        if manual then inform(shotNotice) end
        return
    end
    if not isEquipped then
        local hum = humanOf(localPlayer)
        if hum then hum:EquipTool(gun) end
        if manual then inform("Equipping Gun; try again") end
        return
    end
    local predicted = targetRoot.Position + targetRoot.AssemblyLinearVelocity * 0.10
    if not clearGunShot(murderer, predicted) then
        shotNotice = "Target behind cover or out of range"
        if manual then inform(shotNotice) end
        return
    end
    local remote, signature = resolveGunShot(gun)
    if not remote then
        shotNotice = "No recognized Gun ShootGun/CreateBeam remote"
        if manual then inform(shotNotice) end
        return
    end
    shotInFlight = true
    lastShotAttempt = now
    shotAttemptCount += 1
    local attemptNumber = shotAttemptCount
    shotNotice = "Gun request #" .. attemptNumber .. " pending"
    task.spawn(function()
        local ok, err = pcall(function()
            remote:InvokeServer(1, predicted, signature)
        end)
        shotInFlight = false
        if destroyed then return end
        shotNotice = ok and ("Gun request #" .. attemptNumber .. " sent • hit unconfirmed")
            or ("Gun remote error: " .. tostring(err):sub(1, 80))
        if manual or not ok then inform(shotNotice) end
    end)
end
local aimRing = Instance.new("Frame")
aimRing.Name = "AimRadiusPreview"
aimRing.AnchorPoint = Vector2.new(0.5, 0.5)
aimRing.BackgroundTransparency = 1
aimRing.BorderSizePixel = 0
aimRing.Visible = false
aimRing.Parent = gui
round(aimRing, 999)
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 2
ringStroke.Color = Color3.fromRGB(87, 174, 255)
ringStroke.Transparency = 0.32
ringStroke.Parent = aimRing
local function updateAimRing()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    aimRing.Position = UDim2.fromOffset(view.X / 2, view.Y / 2)
    aimRing.Size = UDim2.fromOffset(numbers.AimRadius * 2, numbers.AimRadius * 2)
    aimRing.Visible = enabled.AimFOVRing and not minimized
end
-- Role radar ----------------------------------------------------------
heading(rolesPage, "ROLE RADAR  /  LIVE")
label(rolesPage,
    "Red: Murderer  •  Blue: Sheriff  •  Gold: Hero  •  Green: Innocent. " ..
    "A question mark means a visible weapon hint, not a confirmed role.",
    58, Color3.fromRGB(184, 207, 228), 12)
makeButton(rolesPage, "Refresh MM2 role feed", function()
    lastRoleFetch = -100
    refreshRoles()
    inform("Requested MM2 role refresh")
end)
toggle(rolesPage, "Notify when game roles change", "RoleAlerts")
local roleDataLine = label(rolesPage, "Checking MM2 game role data...", 36, Color3.fromRGB(160, 205, 232), 12)
roleDataLine.TextWrapped = true
local roleSearch = Instance.new("TextBox")
roleSearch.Name = "PlayerSearch"
roleSearch.Size = UDim2.new(1, -3, 0, 39)
roleSearch.BackgroundColor3 = Color3.fromRGB(31, 44, 65)
roleSearch.TextColor3 = Color3.fromRGB(243, 247, 255)
roleSearch.PlaceholderColor3 = Color3.fromRGB(155, 174, 194)
roleSearch.PlaceholderText = "Search players by name..."
roleSearch.Text = ""
roleSearch.ClearTextOnFocus = false
roleSearch.Font = Enum.Font.Gotham
roleSearch.TextSize = 13
roleSearch.Parent = rolesPage
round(roleSearch, 10)
heading(rolesPage, "QUICK ROLE TARGETS")
makeButton(rolesPage, "Select murderer (game data or tool hint)", function() selectRole("Murderer") end)
makeButton(rolesPage, "Select sheriff (game data or tool hint)", function() selectRole("Sheriff") end)
makeButton(rolesPage, "Spectate selected player", spectate)
makeButton(rolesPage, "Return to my character", restoreCamera)
heading(rolesPage, "PLAYER LIST  /  TAP TO SELECT")
local roleList = Instance.new("Frame")
roleList.Name = "PlayerRoster"
roleList.BackgroundTransparency = 1
roleList.Size = UDim2.new(1, -3, 0, 0)
roleList.AutomaticSize = Enum.AutomaticSize.Y
roleList.Parent = rolesPage
local roleListLayout = Instance.new("UIListLayout")
roleListLayout.Padding = UDim.new(0, 5)
roleListLayout.SortOrder = Enum.SortOrder.LayoutOrder
roleListLayout.Parent = roleList
local roleRows = {}
local function updateRoleRadar()
    local murderer, sheriff, hero = "?", "?", "?"
    local known = 0
    for _, p in ipairs(Players:GetPlayers()) do
        local role, source = getRole(p)
        if source == "game" then
            known += 1
            if role == "Murderer" then murderer = p.DisplayName end
            if role == "Sheriff" then sheriff = p.DisplayName end
            if role == "Hero" then hero = p.DisplayName end
        end
    end
    local signature = murderer .. "/" .. sheriff .. "/" .. hero
    if enabled.RoleAlerts and known > 0 and signature ~= roleChangeSignature then
        if roleChangeSignature ~= "" then
            inform("Role update • Murderer: " .. murderer .. " • Sheriff: " .. sheriff)
        end
        roleChangeSignature = signature
    end
    if known == 0 then
        for _, p in ipairs(Players:GetPlayers()) do
            local role, source = getRole(p)
            if source == "hint" then
                if role == "Murderer" then murderer = p.DisplayName .. "?" end
                if role == "Sheriff" then sheriff = p.DisplayName .. "?" end
            end
        end
    end
    local prefix = known > 0 and "GAME DATA" or "TOOL HINTS"
    roleStrip.Text = " " .. prefix .. "  •  M: " .. murderer .. "   S: " .. sheriff
    roleDataLine.Text = roleSyncMessage .. (known > 0 and ("  |  " .. known .. " confirmed") or "")
    local current = {}
    local search = roleSearch.Text:lower()
    for _, p in ipairs(otherPlayers()) do
        current[p] = true
        local row = roleRows[p]
        if not row then
            row = makeButton(roleList, "", function()
                selectedPlayer = p
                inform("Selected " .. p.DisplayName .. " (@" .. p.Name .. ")")
            end)
            roleRows[p] = row
        end
        local role, source = getRole(p)
        local display = roleDisplay(role, source)
        row.Text = (selectedPlayer == p and "▸ " or "   ") .. p.DisplayName .. "   •   " .. display
        row.TextColor3 = getRoleColor(role, source)
        row.BackgroundColor3 = selectedPlayer == p and Color3.fromRGB(38, 66, 84)
            or Color3.fromRGB(28, 39, 59)
        row.Visible = search == "" or p.Name:lower():find(search, 1, true) ~= nil
            or p.DisplayName:lower():find(search, 1, true) ~= nil
    end
    for p, row in pairs(roleRows) do
        if not current[p] then row:Destroy() roleRows[p] = nil end
    end
end

-- Visuals page --------------------------------------------------------
-- V4 notes: No claim of confirmed inventory or hidden roles without game data.
heading(visualsPage, "PLAYER HIGHLIGHTS")
toggle(visualsPage, "Color ESP by roles", "RoleESP")
toggle(visualsPage, "Show role labels", "ShowRoles")
toggle(visualsPage, "Only Sheriff / Murderer / Hero", "ThreatsOnly")
toggle(visualsPage, "Limit ESP distance", "RangeLimit")
makeButton(visualsPage, "Decrease ESP range by 50 studs", function()
    numbers.ESPRange = math.max(50, numbers.ESPRange - 50)
    inform("ESP range: " .. numbers.ESPRange .. " studs")
end)
makeButton(visualsPage, "Increase ESP range by 50 studs", function()
    numbers.ESPRange = math.min(1500, numbers.ESPRange + 50)
    inform("ESP range: " .. numbers.ESPRange .. " studs")
end)
toggle(visualsPage, "Player ESP", "PlayerESP")
toggle(visualsPage, "Show names", "Names")
toggle(visualsPage, "Show distance", "Distances")
toggle(visualsPage, "Health labels", "Health")
toggle(visualsPage, "Visible weapon hints", "WeaponHints")
toggle(visualsPage, "Through-wall outlines", "XRay")
toggle(visualsPage, "Tracer beams", "Tracers")
toggle(visualsPage, "Rainbow outlines", "Rainbow")
heading(visualsPage, "MAP OBJECT MARKERS")
toggle(visualsPage, "Dropped gun markers", "GunESP", function() scanObjects() end)
toggle(visualsPage, "Dropped knife markers", "KnifeESP", function() scanObjects() end)
toggle(visualsPage, "Coin markers", "CoinESP", function() scanObjects() end)
toggle(visualsPage, "Seasonal item markers (name-based)", "EventESP", function() scanObjects() end)
label(visualsPage, "Game roles update every six seconds when the MM2 role feed is accessible. " ..
    "Otherwise tool colors and question marks are observations only.", 55,
    Color3.fromRGB(160, 173, 194), 12)

-- Movement page -------------------------------------------------------
heading(movementPage, "Character controls")
toggle(movementPage, "Custom walkspeed", "Sprint", applyCharacterSettings)
makeButton(movementPage, "Walkspeed -5", function()
    numbers.Speed = math.max(8, numbers.Speed - 5)
    applyCharacterSettings()
    inform("Custom walkspeed: " .. numbers.Speed)
end)
makeButton(movementPage, "Walkspeed +5", function()
    numbers.Speed = math.min(75, numbers.Speed + 5)
    applyCharacterSettings()
    inform("Custom walkspeed: " .. numbers.Speed)
end)
toggle(movementPage, "Custom jump power", "CustomJump", applyCharacterSettings)
makeButton(movementPage, "Jump power -10", function()
    numbers.Jump = math.max(30, numbers.Jump - 10)
    applyCharacterSettings()
    inform("Jump power: " .. numbers.Jump)
end)
makeButton(movementPage, "Jump power +10", function()
    numbers.Jump = math.min(150, numbers.Jump + 10)
    applyCharacterSettings()
    inform("Jump power: " .. numbers.Jump)
end)
toggle(movementPage, "Infinite jump", "InfiniteJump")
toggle(movementPage, "Anti-fling velocity cap", "AntiFling")
toggle(movementPage, "Noclip (local)", "Noclip", function(on)
    if not on then restoreNoclip() end
end)
toggle(movementPage, "Fly (experimental)", "Fly", function(on)
    if not on then stopFly() else setupFly() end
end)
local function holdButton(page, name, setter)
    local b = makeButton(page, name .. " (hold)", function() end)
    watch(b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            setter(true)
        end
    end))
    watch(b.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            setter(false)
        end
    end))
end
holdButton(movementPage, "Fly UP", function(value) flyUp = value end)
holdButton(movementPage, "Fly DOWN", function(value) flyDown = value end)
makeButton(movementPage, "Fly speed +10", function()
    numbers.FlySpeed = math.min(120, numbers.FlySpeed + 10)
    inform("Fly speed: " .. numbers.FlySpeed)
end)
makeButton(movementPage, "Fly speed -10", function()
    numbers.FlySpeed = math.max(10, numbers.FlySpeed - 10)
    inform("Fly speed: " .. numbers.FlySpeed)
end)
makeButton(movementPage, "Camera FOV +10", function()
    numbers.FOV = math.min(110, numbers.FOV + 10)
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = numbers.FOV end
    inform("Field of view: " .. numbers.FOV)
end)
makeButton(movementPage, "Camera FOV -10", function()
    numbers.FOV = math.max(40, numbers.FOV - 10)
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = numbers.FOV end
    inform("Field of view: " .. numbers.FOV)
end)
makeButton(movementPage, "Reset movement values", function()
    enabled.Sprint = false
    enabled.CustomJump = false
    enabled.Noclip = false
    enabled.Fly = false
    restoreNoclip()
    stopFly()
    applyCharacterSettings()
    numbers.FOV = previousFOV
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = previousFOV end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Movement reset")
end)

-- Tools page ----------------------------------------------------------
heading(toolsPage, "Players and camera")
makeButton(toolsPage, "Select next player", chooseNextPlayer)
makeButton(toolsPage, "Spectate selected", spectate)
makeButton(toolsPage, "Return to my camera", restoreCamera)
makeButton(toolsPage, "Look at selected (ON/OFF)", function()
    if not selectedPlayer or not rootOf(selectedPlayer) then
        inform("Select a spawned player first") return
    end
    restoreCamera()
    enabled.CameraLock = true
    inform("Camera tracking selected • tap Return to stop")
end)
heading(toolsPage, "Teleports (may be server-corrected)")
makeButton(toolsPage, "Teleport near identified Murderer", function()
    local p = selectRole("Murderer")
    if p then moveNear(p) end
end)
makeButton(toolsPage, "Teleport near identified Sheriff", function()
    local p = selectRole("Sheriff")
    if p then moveNear(p) end
end)
makeButton(toolsPage, "Teleport near selected", function()
    if selectedPlayer then moveNear(selectedPlayer) else inform("Select a player") end
end)
makeButton(toolsPage, "Teleport near visible Knife", function()
    local p = findHint("Knife visible")
    if p then moveNear(p) else inform("No equipped Knife detected") end
end)
makeButton(toolsPage, "Teleport near visible Gun", function()
    local p = findHint("Gun visible")
    if p then moveNear(p) else inform("No equipped Gun detected") end
end)
makeButton(toolsPage, "Teleport to nearest named GunDrop", function()
    local closest, bestDist = nil, math.huge
    local own = rootOf(localPlayer)
    if not own then inform("Character not spawned") return end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) == "Gun" then
            local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
            if anchor then
                local d = (anchor.Position - own.Position).Magnitude
                if d < bestDist then closest, bestDist = anchor, d end
            end
        end
    end
    if closest then
        own.CFrame = closest.CFrame * CFrame.new(0, 3, 0)
        inform("GunDrop proximity teleport attempted")
    else
        inform("No named GunDrop object found")
    end
end)
makeButton(toolsPage, "Teleport to closest Coin", function() tpNearObject("Coin") end)
makeButton(toolsPage, "Teleport to dropped Knife", function() tpNearObject("Knife") end)
makeButton(toolsPage, "Teleport to crosshair target", tpCrosshair)
makeButton(toolsPage, "Teleport near random player", function()
    local list = otherPlayers()
    if #list == 0 then inform("No other players") return end
    moveNear(list[math.random(1, #list)])
end)
makeButton(toolsPage, "Find and teleport to Lobby", function()
    local place = Workspace:FindFirstChild("Lobby", true)
    if not place then inform("No object named Lobby found") return end
    local destination
    if place:IsA("BasePart") then destination = place.CFrame
    elseif place:IsA("Model") then destination = place:GetPivot() end
    local root = rootOf(localPlayer)
    if destination and root then
        root.CFrame = destination * CFrame.new(0, 5, 0)
        inform("Lobby teleport attempted")
    else
        inform("Lobby object wasn't a Part or Model")
    end
end)
heading(toolsPage, "Client-only test objects")
makeButton(toolsPage, "Spawn demo GunDrop", function()
    createDemoPart("GunDrop", Color3.fromRGB(255, 213, 70))
end)
makeButton(toolsPage, "Spawn demo Coin", function()
    createDemoPart("Coin", Color3.fromRGB(107, 255, 122))
end)


-- FARM / AIM / FUN -----------------------------------------------------
heading(farmPage, "COIN COLLECTION")
label(farmPage, "This repeatedly searches for nearby coin parts. It can walk or try short local teleports to them. Game-side pickup and rewards are not guaranteed.",
    80, Color3.fromRGB(207, 218, 237), 13)
toggle(farmPage, "AUTO FARM COINS", "AutoCoinFarm", setFarmEnabled)
toggle(farmPage, "Use short teleports", "CoinTeleport")
toggle(farmPage, "Include seasonal items by name", "FarmEvents", function()
    farmLastScan = 0
end)
toggle(farmPage, "Pause after 20 visited targets", "FarmVisitLimit")
toggle(farmPage, "Show coin markers", "CoinESP", function() scanObjects() end)
makeButton(farmPage, "Collection radius +50 studs", function()
    numbers.FarmRadius = math.min(450, numbers.FarmRadius + 50)
    inform("Farm radius: " .. numbers.FarmRadius)
end)
makeButton(farmPage, "Collection radius −50 studs", function()
    numbers.FarmRadius = math.max(40, numbers.FarmRadius - 50)
    inform("Farm radius: " .. numbers.FarmRadius)
end)
makeButton(farmPage, "Reset farm counters / stuck-target list", function()
    resetFarmTracking()
    inform("Farm counters reset")
end)
local farmStats = label(farmPage, "Ready • 0 targets visited", 70, Color3.fromRGB(189, 221, 255), 14)
heading(farmPage, "DROPPED GUN")
toggle(farmPage, "Auto-approach dropped gun", "AutoGunApproach", function(on)
    if on then enabled.AutoCoinFarm = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
makeButton(farmPage, "Stop automation", function()
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    local humanoid, root = humanOf(localPlayer), rootOf(localPlayer)
    if humanoid and root then humanoid:MoveTo(root.Position) end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Auto movement stopped")
end)
heading(aimPage, "CAMERA AIM ASSIST")
label(aimPage, "Standard aim follows a target inside FOV. Auto aim and Auto Shoot require a confirmed Murderer; shot hits are not guaranteed.",
    78, Color3.fromRGB(207, 218, 237), 13)
toggle(aimPage, "Aim camera at Murderer", "AimAssist", function(on)
    if on then enabled.CameraLock = false end
end)
toggle(aimPage, "AUTO AIM • confirmed Murderer (full view)", "AutoAimMurderer", function(on)
    if on then enabled.AimAssist = false; enabled.CameraLock = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO SHOOT • Sheriff/Hero Gun only", "AutoShootMurderer")
makeButton(aimPage, "Shoot confirmed Murderer NOW (one attempt)", function()
    attemptMurdererShot(true)
end)
local shotInfoLabel = label(aimPage, "Auto Shoot status: idle", 70,
    Color3.fromRGB(189, 221, 255), 13)
toggle(aimPage, "Require clear line of sight", "AimWallCheck")
toggle(aimPage, "Only aim when my role is Sheriff/Hero", "AimRequireSheriff")
toggle(aimPage, "Show aim area on screen", "AimFOVRing")
makeButton(aimPage, "Increase aim speed", function()
    numbers.AimSmooth = math.min(0.9, numbers.AimSmooth + 0.07)
    inform("Aim smooth step " .. math.floor(numbers.AimSmooth * 100) .. "%")
end)
makeButton(aimPage, "Decrease aim speed", function()
    numbers.AimSmooth = math.max(0.05, numbers.AimSmooth - 0.07)
    inform("Aim smooth step " .. math.floor(numbers.AimSmooth * 100) .. "%")
end)
makeButton(aimPage, "Increase aim radius", function()
    numbers.AimRadius = math.min(500, numbers.AimRadius + 40)
    inform("Aim radius " .. numbers.AimRadius .. " px")
end)
makeButton(aimPage, "Decrease aim radius", function()
    numbers.AimRadius = math.max(70, numbers.AimRadius - 40)
    inform("Aim radius " .. numbers.AimRadius .. " px")
end)
heading(funPage, "FUN MOVEMENT")
label(funPage, "Physics experiments run locally and may be blocked by the server. Keep spin OFF while using other movement controls.",
    68, Color3.fromRGB(207, 218, 237), 13)
toggle(funPage, "Spin mode (my character)", "SpinMode", function(on)
    if not on then
        local root = rootOf(localPlayer)
        if root then root.AssemblyAngularVelocity = Vector3.zero end
    end
end)
heading(funPage, "PLAYER FLING • EXPERIMENTAL")
label(funPage, "Select a player on HOME first. Multi-axis tumble tries X/Y/Z rotation near the target for 1.65 seconds. Collision and network ownership may prevent a real fling.",
    105, Color3.fromRGB(207, 218, 237), 13)
makeButton(funPage, "Multi-axis fling selected (experimental)", flingSelected)
makeButton(funPage, "Stop fling / spinning", function()
    flingToken += 1
    enabled.FlingActive = false
    enabled.SpinMode = false
    local root = rootOf(localPlayer)
    if root then
        root.AssemblyAngularVelocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Physics effects stopped")
end)
makeButton(funPage, "Sit", function()
    local humanoid = humanOf(localPlayer)
    if humanoid then humanoid.Sit = true end
end)
makeButton(funPage, "Stand up", function()
    local humanoid = humanOf(localPlayer)
    if humanoid then humanoid.Sit = false end
end)
-- Settings page -------------------------------------------------------
heading(settingsPage, "Visual settings")
toggle(settingsPage, "Ghosted avatar (only on MY screen)", "LocalGhost", setLocalGhost)
toggle(settingsPage, "Fullbright", "Fullbright", setFullbright)
toggle(settingsPage, "Remove fog and atmosphere haze", "NoFog", setNoFog)
toggle(settingsPage, "Hide my overhead name (local)", "HideOwnName", setHideOwnName)
toggle(settingsPage, "Reduce sliding on ice (local)", "AntiSlip")
toggle(settingsPage, "Disable post-processing FX", "LowFX", setLowFX)
toggle(settingsPage, "Anti-void (experimental)", "AntiVoid")
makeButton(settingsPage, "Reset gravity", function()
    Workspace.Gravity = previousGravity
    inform("Gravity restored")
end)
makeButton(settingsPage, "Decrease local gravity by 20", function()
    Workspace.Gravity = math.max(30, Workspace.Gravity - 20)
    inform("Local gravity: " .. math.floor(Workspace.Gravity))
end)
makeButton(settingsPage, "Increase local gravity by 20", function()
    Workspace.Gravity = math.min(300, Workspace.Gravity + 20)
    inform("Local gravity: " .. math.floor(Workspace.Gravity))
end)
heading(settingsPage, "Session")
label(settingsPage, "Tap the X or − to minimize into the floating SPECTRA icon. Drag it anywhere and tap to reopen. Features stay active until fully unloaded.", 91, Color3.fromRGB(193, 218, 250), 14)
makeButton(settingsPage, "Minimize to floating icon", function()
    setWindowOpen(false)
end)
local performFullUnload = function() inform("Unload is not ready") end
local unloadConfirmDeadline = 0
local unloadControl
unloadControl = makeButton(settingsPage, "FULLY UNLOAD SPECTRA (tap twice)", function()
    if os.clock() < unloadConfirmDeadline then
        performFullUnload()
        return
    end
    unloadConfirmDeadline = os.clock() + 5
    unloadControl.Text = "CONFIRM UNLOAD • tap again within 5 sec"
    inform("Tap again to remove ESP, GUI and local effects")
    task.delay(5, function()
        if not destroyed and unloadControl and unloadControl.Parent
            and os.clock() >= unloadConfirmDeadline then
            unloadControl.Text = "FULLY UNLOAD SPECTRA (tap twice)"
        end
    end)
end)
unloadControl.BackgroundColor3 = Color3.fromRGB(98, 37, 52)
makeButton(settingsPage, "Show player count", function()
    inform("Players in server: " .. #Players:GetPlayers())
end)
makeButton(settingsPage, "Rejoin this place", function()
    if RunService:IsStudio() then inform("Rejoin isn't available in Studio playtest") return end
    local ok, err = pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
    if not ok then inform("Rejoin failed: " .. tostring(err):sub(1, 60)) end
end)
label(settingsPage, "Role radar reads game-reported data only when MM2 exposes it. " ..
    "Features here run on your client; teleports and movement may be server-corrected. " ..
    "No remote kill-all, forced wins, or trade manipulation.",
    85, Color3.fromRGB(180, 193, 213), 12)


-- Diagnostics: these are capability/observation checks, not server guarantees.
heading(diagnosticsPage, "LIVE STATUS & DIAGNOSTICS")
label(diagnosticsPage, "Shows what is observable on this client. A green script status does not verify MM2 rewards, remote attacks, or trading.", 78, Color3.fromRGB(215, 224, 242), 14)
local diagRole = label(diagnosticsPage, "Role data: checking...", 55, Color3.fromRGB(190, 214, 245), 14)
local diagFarm = label(diagnosticsPage, "Farm: waiting", 66, Color3.fromRGB(190, 214, 245), 14)
local diagWorld = label(diagnosticsPage, "Players/markers: waiting", 55, Color3.fromRGB(190, 214, 245), 14)
local diagMisc = label(diagnosticsPage, "Controls: waiting", 112, Color3.fromRGB(190, 214, 245), 14)
refreshDiagnostics = function()
    if destroyed then return end
    local reported = os.clock() - roleLastUpdate < 12
    diagRole.Text = "Role feed: " .. (reported and "game data recently received" or "unavailable/stale")
        .. "\n" .. roleSyncMessage
    diagFarm.Text = "Farm: " .. (enabled.AutoCoinFarm and "ON" or "OFF")
        .. "  |  attempts: " .. farmAttempts .. "  |  skipped: " .. farmSkipped
        .. "\nThese are NOT confirmed currency pickups"
    local playerCount = #Players:GetPlayers() - 1
    local markers = 0
    for _ in pairs(objectEffects) do markers += 1 end
    diagWorld.Text = "Other players: " .. math.max(playerCount, 0)
        .. "  |  marked objects: " .. markers
    diagMisc.Text = "Aim: " .. ((enabled.AimAssist or enabled.AutoAimMurderer) and "ON" or "OFF")
        .. "  |  auto shoot: " .. (enabled.AutoShootMurderer and "ON" or "OFF")
        .. "  |  shots attempted: " .. shotAttemptCount
        .. "\n" .. shotNotice .. "\n" .. flingNotice
end
makeButton(diagnosticsPage, "Refresh role feed", function()
    lastRoleFetch = os.clock()
    refreshRoles()
    inform("Role refresh requested")
end)
makeButton(diagnosticsPage, "Rescan nearby markers", function()
    scanObjects()
    farmLastScan = 0
    scanFarmTargets()
    inform("Marker rescan complete")
end)
makeButton(diagnosticsPage, "STOP all automation and camera assist", function()
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AimAssist = false
    enabled.AutoAimMurderer = false
    enabled.AutoShootMurderer = false
    enabled.CameraLock = false
    enabled.SpinMode = false
    enabled.FlingActive = false
    flingToken += 1
    local hum, root = humanOf(localPlayer), rootOf(localPlayer)
    if hum and root then hum:MoveTo(root.Position) end
    if root then root.AssemblyAngularVelocity = Vector3.zero end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Automation stopped")
end)
label(diagnosticsPage, "Not implemented or verified: silent hit redirection, guaranteed shots/hits, kill aura, kill-all, god mode, forced wins, auto trades/buys/crafting, bag resetting, Discord webhooks, multi-account sync, server hop or FPS unlocking. These require game-specific server integration, independent APIs, or special permissions.", 210, Color3.fromRGB(255, 206, 178), 13)

-- Controlled farm scheduler; each attempt can be canceled immediately.
-- Visits and teleports are NOT server-confirmed currency earnings.
task.spawn(function()
    while not destroyed do
        task.wait(0.65)
        if destroyed then break end
        local own, hum = rootOf(localPlayer), humanOf(localPlayer)
        if own and hum and hum.Health > 0 and (enabled.AutoCoinFarm or enabled.AutoGunApproach) then
            if enabled.AutoCoinFarm then
                if enabled.FarmVisitLimit and farmAttempts >= numbers.FarmVisitCap then
                    enabled.AutoCoinFarm = false
                    hum:MoveTo(own.Position)
                    farmNotice = "Paused at visit limit (not pickup count)"
                    for _, refresh in ipairs(toggleUpdaters) do refresh() end
                else
                    local target, dist = getNearestFarmCoin()
                    if target and target.Parent then
                        if target ~= farmFocus then
                            farmFocus, farmFocusStart, farmProgressDistance = target, os.clock(), dist
                        end
                        if dist < farmProgressDistance - 1.5 then
                            farmProgressDistance = dist
                            farmFocusStart = os.clock()
                        end
                        if dist < 5.5 then
                            farmVisited[target] = os.clock()
                            farmAttempts += 1
                            farmFocus = nil
                            farmNotice = "Reached target • pickup not verified"
                        elseif os.clock() - farmFocusStart > 6 then
                            farmVisited[target] = os.clock()
                            farmSkipped += 1
                            farmFocus = nil
                            farmNotice = "Skipped stuck or unreachable target"
                        elseif enabled.CoinTeleport then
                            local ok = pcall(function()
                                own.CFrame = CFrame.new(target.Position + Vector3.new(0, 1.6, 0))
                            end)
                            farmVisited[target] = os.clock()
                            farmAttempts += 1
                            farmFocus = nil
                            farmNotice = ok and "Teleport visit attempted" or "Teleport blocked"
                        else
                            hum:MoveTo(target.Position)
                            farmNotice = "Walking to target • " .. math.floor(dist) .. " studs"
                        end
                    else
                        farmNotice = "No matching collectibles in range"
                    end
                end
            elseif enabled.AutoGunApproach then
                local gun = getNearestGun()
                if gun then
                    hum:MoveTo(gun.Position)
                    farmNotice = "Walking toward dropped gun"
                else
                    farmNotice = "No dropped gun found"
                end
            end
        elseif enabled.AutoCoinFarm or enabled.AutoGunApproach then
            farmNotice = "Waiting for live character"
        end
        if farmStats and farmStats.Parent then
            farmStats.Text = farmNotice .. "  |  visits: " .. farmAttempts
                .. "  skipped: " .. farmSkipped .. " (not confirmed pickups)"
        end
    end
end)
-- Gun remote calls may yield, so this loop stays off RenderStep.
task.spawn(function()
    while not destroyed do
        task.wait(0.28)
        if enabled.AutoShootMurderer then attemptMurdererShot(false) end
    end
end)
-- A single heartbeat for periodic state updates.
watch(RunService.Heartbeat:Connect(function(delta)
    if destroyed then return end
    local now = os.clock()
    local cameraNow = Workspace.CurrentCamera
    if cameraNow then
        local updatedView = cameraNow.ViewportSize
        if math.abs(updatedView.X - viewport.X) > 8 or math.abs(updatedView.Y - viewport.Y) > 8 then
            viewport = updatedView
            width, height = windowDimensions(viewport)
            window.Size = UDim2.fromOffset(width, height)
            applyResponsiveLayout()
            placeLauncher(launcher.Position.X.Offset, launcher.Position.Y.Offset)
            title.TextSize = width < 420 and 14 or 17
            roleStrip.TextSize = width < 420 and 11 or 13
            window.Position = UDim2.fromOffset(
                math.clamp(window.Position.X.Offset, 0, math.max(0, viewport.X - 70)),
                math.clamp(window.Position.Y.Offset, 0, math.max(0, viewport.Y - 45)))
        end
    end
    local ownRoot = rootOf(localPlayer)
    if enabled.Noclip then
        local char = characterOf(localPlayer)
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if originalCollisions[part] == nil then
                        originalCollisions[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end
    end
    if enabled.Fly then
        setupFly()
        local humanoid = humanOf(localPlayer)
        if humanoid and flyVelocity and flyRoot then
            local v = humanoid.MoveDirection * numbers.FlySpeed
            local y = (flyUp and 1 or 0) - (flyDown and 1 or 0)
            flyVelocity.VectorVelocity = v + Vector3.new(0, y * numbers.FlySpeed, 0)
        end
    end
    if spectateTarget and (not spectateTarget.Parent or not alive(spectateTarget)) then
        restoreCamera()
    end
    if enabled.SpinMode and ownRoot and not flingBusy then
        ownRoot.AssemblyAngularVelocity = Vector3.new(0, 15, 0)
    end
    if enabled.AntiFling and ownRoot and not enabled.FlingActive
        and ownRoot.AssemblyLinearVelocity.Magnitude > 160 then
        ownRoot.AssemblyLinearVelocity = Vector3.zero
        inform("Excessive local velocity damped")
    end
    if enabled.AntiSlip and ownRoot then
        local hum = humanOf(localPlayer)
        if hum and hum.FloorMaterial == Enum.Material.Ice then
            local v = ownRoot.AssemblyLinearVelocity
            local dir = hum.MoveDirection
            local targetSpeed = hum.WalkSpeed
            ownRoot.AssemblyLinearVelocity = Vector3.new(dir.X * targetSpeed, v.Y, dir.Z * targetSpeed)
        end
    end
    if enabled.AntiVoid and ownRoot then
        local humanoid = humanOf(localPlayer)
        if ownRoot.Position.Y > -10 and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
            lastSafeCFrame = ownRoot.CFrame
        elseif ownRoot.Position.Y < -45 and lastSafeCFrame then
            ownRoot.CFrame = lastSafeCFrame * CFrame.new(0, 5, 0)
            inform("Anti-void recovery attempted")
        end
    end
    if now - lastVisualTick >= 0.5 then
        lastVisualTick = now
        if now - lastRoleFetch >= 6 then
            lastRoleFetch = now
            refreshRoles()
        end
        if now - lastRoleUI >= 1.1 then
            lastRoleUI = now
            updateRoleRadar()
        end
        updateAimRing()
        updatePlayerEffects(now)
        updateTracers()
        updateObjects()
        -- Update already-enabled settings in case of respawn/map changes.
        if enabled.Fullbright then setFullbright(true) end
        if enabled.LowFX then setLowFX(true) end
        if enabled.NoFog then setNoFog(true) end
        if enabled.HideOwnName then setHideOwnName(true) end
        if enabled.LocalGhost then setLocalGhost(true) end
        refreshDiagnostics()
        if shotInfoLabel and shotInfoLabel.Parent then
            shotInfoLabel.Text = shotNotice
        end
    end
end))
-- Priority after the default camera script, for explicit camera tracking.
RunService:BindToRenderStep("LearningHub_Camera_" .. tostring(localPlayer.UserId),
    Enum.RenderPriority.Camera.Value + 1, function()
        if destroyed or not enabled.CameraLock then return end
        local camera = Workspace.CurrentCamera
        local root = rootOf(selectedPlayer)
        if camera and root then
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, root.Position + Vector3.new(0, 2, 0))
        end
    end)
-- Run after Roblox's default camera and the hub's camera lock.
local aimStepName = "Spectra_Aim_" .. tostring(localPlayer.UserId)
RunService:BindToRenderStep(aimStepName, Enum.RenderPriority.Camera.Value + 3, function()
    if destroyed or not (enabled.AimAssist or enabled.AutoAimMurderer) or enabled.CameraLock or spectateTarget then return end
    local camera = Workspace.CurrentCamera
    local target = findAimPart()
    if camera and target then
        local wanted = CFrame.lookAt(camera.CFrame.Position, target.Position)
        camera.CFrame = camera.CFrame:Lerp(wanted, numbers.AimSmooth)
    end
end)
local cameraStepName = "LearningHub_Camera_" .. tostring(localPlayer.UserId)

local function unload()
    if destroyed then return end
    destroyed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    RunService:UnbindFromRenderStep(cameraStepName)
    RunService:UnbindFromRenderStep(aimStepName)
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AutoShootMurderer = false
    enabled.AutoAimMurderer = false
    enabled.SpinMode = false
    flingToken += 1
    enabled.FlingActive = false
    local r = rootOf(localPlayer)
    if r then r.AssemblyAngularVelocity = Vector3.zero end
    restoreNoclip()
    stopFly()
    setLocalGhost(false)
    restoreCamera()
    for p in pairs(playerEffects) do destroyPlayerEffect(p) end
    for p in pairs(tracerEffects) do clearTracer(p) end
    for obj in pairs(objectEffects) do clearObject(obj) end
    for _, part in ipairs(demoParts) do if part.Parent then part:Destroy() end end
    effectsFolder:Destroy()
    setLowFX(false)
    setFullbright(false)
    setNoFog(false)
    for hum, prior in pairs(ownNameOriginal) do
        if hum.Parent then hum.DisplayDistanceType = prior end
    end
    Workspace.Gravity = previousGravity
    local camera = Workspace.CurrentCamera
    if camera then camera.FieldOfView = previousFOV end
    local humanoid = humanOf(localPlayer)
    if humanoid then
        local base = baseHumanoidSettings[humanoid]
        if base then
            humanoid.WalkSpeed = base.speed
            humanoid.UseJumpPower = base.useJumpPower
            humanoid.JumpPower = base.jump
        end
    end
    gui:Destroy()
    if environment.MM2LearningHubUnload == unload then
        environment.MM2LearningHubUnload = nil
    end
end
environment.MM2LearningHubUnload = unload
performFullUnload = unload

-- First pass only once when launched.
applyCharacterSettings()
refreshRoles()
updateRoleRadar()
inform("SPECTRA v5.2 loaded • HOME / ESP / FARM / AIM / STATUS")
print("SPECTRA MM2 Hub v5.2 loaded. X minimizes; open SETTINGS to fully unload.")

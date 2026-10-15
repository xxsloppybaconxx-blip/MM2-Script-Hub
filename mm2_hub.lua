--[[
  MM2-STYLE LEARNING HUB 1.0
  Original, readable, client-side Luau example.
  Best tested in a Roblox Studio LocalScript in StarterPlayerScripts.
  Also uses ordinary Roblox client APIs for executor compatibility,
  but has NOT been tested in Delta or the live MM2 experience.

  Features: player ESP, nametags, distance, visible-weapon hints,
  through-wall outlines, player tracers, rainbow ESP, dropped-gun
  and coin markers (name-based), spectate, camera tracking, selected
  player cycling, movement options, optional fly, teleport attempts,
  fullbright, post-effect reduction, player count, anti-void,
  local demo target, mobile-friendly draggable UI and cleanup.

  IMPORTANT: Neither weapon hints nor object names reveal verified
  secret MM2 roles. No remote-event abuse, auto-kill or insta-win.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
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

local connections = {}
local function watch(connection)
    table.insert(connections, connection)
    return connection
end

local enabled = {
    PlayerESP = false,
    Names = true,
    Distances = true,
    Health = true,
    WeaponHints = true,
    XRay = true,
    Tracers = false,
    Rainbow = false,
    GunESP = false,
    CoinESP = false,
    Sprint = false,
    CustomJump = false,
    InfiniteJump = false,
    Noclip = false,
    Fly = false,
    AntiFling = false,
    Fullbright = false,
    LowFX = false,
    AntiVoid = false,
    CameraLock = false,
}
local numbers = { Speed = 24, Jump = 65, FlySpeed = 35, FOV = 70 }
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
local lightOriginal = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
    FogEnd = Lighting.FogEnd,
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

local gui = Instance.new("ScreenGui")
gui.Name = "LearningMM2Hub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- World-space effects must be parented in Workspace, not inside ScreenGui.
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "LearningMM2HubEffects"
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

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(390, 700)
local width = math.clamp(viewport.X - 22, 260, 370)
local height = math.clamp(viewport.Y - 85, 280, 485)
local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(width, height)
window.Position = UDim2.new(0, 12, 0, 52)
window.BackgroundColor3 = Color3.fromRGB(19, 24, 38)
window.Active = true
window.Parent = gui
round(window, 12)
stroke(window)

local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 44)
top.BackgroundColor3 = Color3.fromRGB(29, 37, 56)
top.Active = true
top.Parent = window
round(top, 11)
local title = label(top, "MM2 LEARNING HUB  •  v1.0", 42, Color3.fromRGB(166, 215, 255), 16)
title.Position = UDim2.fromOffset(11, 1)
title.Size = UDim2.new(1, -83, 0, 42)
title.Font = Enum.Font.GothamBold

local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(32, 30)
minimize.Position = UDim2.new(1, -72, 0, 7)
minimize.Text = "−"
minimize.TextSize = 21
minimize.Font = Enum.Font.GothamBold
minimize.TextColor3 = Color3.new(1, 1, 1)
minimize.BackgroundColor3 = Color3.fromRGB(65, 79, 111)
minimize.Parent = top
round(minimize, 7)
local close = minimize:Clone()
close.Position = UDim2.new(1, -36, 0, 7)
close.Text = "×"
close.BackgroundColor3 = Color3.fromRGB(141, 58, 73)
close.Parent = top

local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.Position = UDim2.new(0, 8, 0, 50)
tabs.Size = UDim2.new(1, -16, 0, 36)
tabs.Parent = window
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabs
local main = Instance.new("Frame")
main.Name = "Pages"
main.BackgroundTransparency = 1
main.Position = UDim2.fromOffset(8, 92)
main.Size = UDim2.new(1, -16, 1, -130)
main.Parent = window
local status = Instance.new("TextLabel")
status.BackgroundColor3 = Color3.fromRGB(29, 37, 56)
status.Position = UDim2.new(0, 8, 1, -34)
status.Size = UDim2.new(1, -16, 0, 26)
status.TextColor3 = Color3.fromRGB(188, 212, 231)
status.TextSize = 12
status.Text = "Ready • test in your own Studio place"
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Font = Enum.Font.Gotham
status.Parent = window
round(status, 6)
local function inform(message)
    if not destroyed then status.Text = message end
end

local pages = {}
local tabButtons = {}
local toggleUpdaters = {}
local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.25, -3, 1, 0)
    b.Text = name
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = Color3.fromRGB(45, 56, 79)
    b.TextColor3 = Color3.fromRGB(220, 229, 246)
    b.Parent = tabs
    round(b, 7)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.BorderSizePixel = 0
    page.BackgroundTransparency = 1
    page.Size = UDim2.fromScale(1, 1)
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(99, 174, 255)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.Visible = false
    page.Parent = main
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 3)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 3)
    pad.PaddingRight = UDim.new(0, 7)
    pad.Parent = page
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    pages[name] = page
    tabButtons[name] = b
    watch(b.MouseButton1Click:Connect(function()
        for tabName, p in pairs(pages) do
            p.Visible = tabName == name
            tabButtons[tabName].BackgroundColor3 = tabName == name
                and Color3.fromRGB(48, 115, 160) or Color3.fromRGB(45, 56, 79)
        end
    end))
    return page
end
local visualsPage = makeTab("Visuals")
local movementPage = makeTab("Movement")
local toolsPage = makeTab("Tools")
local settingsPage = makeTab("Settings")
tabButtons.Visuals.BackgroundColor3 = Color3.fromRGB(48, 115, 160)
visualsPage.Visible = true

local function heading(page, text)
    local l = label(page, text, 25, Color3.fromRGB(156, 213, 255), 15)
    l.Font = Enum.Font.GothamBold
    l.Size = UDim2.new(1, -4, 0, 25)
end
local function makeButton(page, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -3, 0, 37)
    b.BackgroundColor3 = Color3.fromRGB(41, 52, 75)
    b.TextColor3 = Color3.fromRGB(237, 242, 251)
    b.TextSize = 13
    b.TextWrapped = true
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.Parent = page
    round(b, 8)
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
    local function update()
        b.Text = name .. "   [" .. (enabled[key] and "ON" or "OFF") .. "]"
        b.BackgroundColor3 = enabled[key] and Color3.fromRGB(29, 109, 100)
            or Color3.fromRGB(41, 52, 75)
    end
    b = makeButton(page, "", function()
        enabled[key] = not enabled[key]
        update()
        if onChanged then onChanged(enabled[key]) end
    end)
    update()
    table.insert(toggleUpdaters, update)
    return b
end

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
watch(minimize.MouseButton1Click:Connect(function()
    minimized = not minimized
    tabs.Visible = not minimized
    main.Visible = not minimized
    status.Visible = not minimized
    window.Size = minimized and UDim2.fromOffset(width, 44) or UDim2.fromOffset(width, height)
    minimize.Text = minimized and "+" or "−"
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
    billboard.Size = UDim2.fromOffset(185, 49)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = gui
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.TextScaled = false
    text.TextSize = 13
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
            if enabled.PlayerESP and alive(p) then
                makePlayerEffect(p)
                local e = playerEffects[p]
                if e then
                    local hint = visibleWeaponHint(p)
                    local color = enabled.Rainbow and Color3.fromHSV((timeNow / 5) % 1, 0.85, 1)
                        or colorForHint(hint)
                    e.highlight.Enabled = true
                    e.highlight.FillColor = color
                    e.highlight.OutlineColor = color
                    e.highlight.DepthMode = enabled.XRay and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    e.billboard.Enabled = enabled.Names or enabled.Distances or enabled.WeaponHints or enabled.Health
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
                    if enabled.WeaponHints then table.insert(pieces, hint) end
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
            if not enabled.PlayerESP or not enabled.Tracers or not mine or not theirs or not alive(p) then
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
                e.beam.Color = ColorSequence.new(colorForHint(visibleWeaponHint(p)))
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
    elseif name == "coin" or name == "coinpart" then
        return "Coin"
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
    if (function()
        local count = 0
        for _ in pairs(objectEffects) do count = count + 1 end
        return count
    end)() >= 90 then return end
    local color = kind == "Gun" and Color3.fromRGB(255, 209, 64)
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
    if not enabled.GunESP and not enabled.CoinESP then
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
            or (e.kind == "Coin" and not enabled.CoinESP) then
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
        humanoid.WalkSpeed = enabled.Sprint and numbers.Speed or 16
        humanoid.UseJumpPower = true
        humanoid.JumpPower = enabled.CustomJump and numbers.Jump or 50
    end
end
watch(localPlayer.CharacterAdded:Connect(function()
    restoreNoclip()
    stopFly()
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

-- Visuals page --------------------------------------------------------
heading(visualsPage, "Players")
toggle(visualsPage, "Player ESP", "PlayerESP")
toggle(visualsPage, "Show names", "Names")
toggle(visualsPage, "Show distance", "Distances")
toggle(visualsPage, "Health labels", "Health")
toggle(visualsPage, "Visible weapon hints", "WeaponHints")
toggle(visualsPage, "Through-wall outlines", "XRay")
toggle(visualsPage, "Tracer beams", "Tracers")
toggle(visualsPage, "Rainbow outlines", "Rainbow")
heading(visualsPage, "Map objects")
toggle(visualsPage, "Dropped gun markers", "GunESP", function() scanObjects() end)
toggle(visualsPage, "Coin markers", "CoinESP", function() scanObjects() end)
label(visualsPage, "Markers match object names; role hints only examine visibly equipped weapons.", 42,
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

-- Settings page -------------------------------------------------------
heading(settingsPage, "Visual settings")
toggle(settingsPage, "Fullbright", "Fullbright", setFullbright)
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
makeButton(settingsPage, "Show player count", function()
    inform("Players in server: " .. #Players:GetPlayers())
end)
makeButton(settingsPage, "Rejoin this place", function()
    if RunService:IsStudio() then inform("Rejoin isn't available in Studio playtest") return end
    local ok, err = pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
    if not ok then inform("Rejoin failed: " .. tostring(err):sub(1, 60)) end
end)
label(settingsPage, "No auto-win, remote kills, hidden-role reveal, coin auto-farm, or trade manipulation. " ..
    "These need server permissions or MM2-specific internals and are not reliable generic Luau features.",
    82, Color3.fromRGB(180, 193, 213), 12)

-- A single heartbeat for periodic state updates.
watch(RunService.Heartbeat:Connect(function(delta)
    if destroyed then return end
    local now = os.clock()
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
    if enabled.AntiFling and ownRoot and ownRoot.AssemblyLinearVelocity.Magnitude > 160 then
        ownRoot.AssemblyLinearVelocity = Vector3.zero
        inform("Excessive local velocity damped")
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
        updatePlayerEffects(now)
        updateTracers()
        updateObjects()
        -- Update already-enabled settings in case of respawn/map changes.
        if enabled.Fullbright then setFullbright(true) end
        if enabled.LowFX then setLowFX(true) end
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
local cameraStepName = "LearningHub_Camera_" .. tostring(localPlayer.UserId)

local function unload()
    if destroyed then return end
    destroyed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    RunService:UnbindFromRenderStep(cameraStepName)
    restoreNoclip()
    stopFly()
    restoreCamera()
    for p in pairs(playerEffects) do destroyPlayerEffect(p) end
    for p in pairs(tracerEffects) do clearTracer(p) end
    for obj in pairs(objectEffects) do clearObject(obj) end
    for _, part in ipairs(demoParts) do if part.Parent then part:Destroy() end end
    effectsFolder:Destroy()
    setLowFX(false)
    setFullbright(false)
    Workspace.Gravity = previousGravity
    local camera = Workspace.CurrentCamera
    if camera then camera.FieldOfView = previousFOV end
    local humanoid = humanOf(localPlayer)
    if humanoid then
        humanoid.WalkSpeed = 16
        humanoid.UseJumpPower = true
        humanoid.JumpPower = 50
    end
    gui:Destroy()
    if environment.MM2LearningHubUnload == unload then
        environment.MM2LearningHubUnload = nil
    end
end
environment.MM2LearningHubUnload = unload
watch(close.MouseButton1Click:Connect(unload))

-- First pass only once when launched.
applyCharacterSettings()
inform("Loaded • Client-only tools; game updates can affect them")
print("MM2 Learning Hub loaded. Press X to unload.")

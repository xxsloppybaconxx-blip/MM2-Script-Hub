-- SPECTRA v9.1 RECOVERY LOADER
-- This runs BEFORE the larger hub and keeps a visible status / recovery menu.
-- v8.3 hub is kept unchanged until a tested fling variant is available.
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
if not localPlayer then warn("[SPECTRA v9.1] LocalPlayer unavailable") return end
local playerGui = localPlayer:WaitForChild("PlayerGui", 12)
if not playerGui then warn("[SPECTRA v9.1] PlayerGui timed out") return end

-- Remove previously failed recovery panels; they can remain on top of the new UI.
for _, oldName in ipairs({"SpectraV84Recovery", "SpectraV85Recovery", "SpectraV86Recovery", "SpectraV87Recovery", "SpectraV88Recovery", "SpectraV89Recovery", "SpectraV90Recovery", "SpectraV91Recovery"}) do
    local previous = playerGui:FindFirstChild(oldName)
    if previous then pcall(function() previous:Destroy() end) end
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpectraV91Recovery"
gui.ResetOnSpawn = false
gui.DisplayOrder = 250
gui.IgnoreGuiInset = false
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "BootAndRecoveryPanel"
panel.Size = UDim2.fromOffset(310, 233)
panel.Position = UDim2.new(0.5, -155, 0.21, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 11)
corner.Parent = panel
local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(108, 143, 214)
border.Thickness = 2
border.Parent = panel

local function label(text,y,h)
    local item=Instance.new("TextLabel")
    item.BackgroundTransparency=1
    item.TextXAlignment=Enum.TextXAlignment.Left
    item.TextYAlignment=Enum.TextYAlignment.Center
    item.TextWrapped=true
    item.Font=Enum.Font.GothamBold
    item.TextSize=13
    item.TextColor3=Color3.fromRGB(233,243,255)
    item.Text=text
    item.Position=UDim2.fromOffset(12,y)
    item.Size=UDim2.new(1,-24,0,h)
    item.Parent=panel
    return item
end
label("◈ SPECTRA 9.1 • Startup Recovery",8,32)
local status=label("Creating recovery UI…",43,78)
status.Font=Enum.Font.Gotham
status.TextSize=12

local function button(text,y,callback)
    local b=Instance.new("TextButton")
    b.Name=text:gsub("[^%w]","")
    b.Size=UDim2.new(1,-24,0,30)
    b.Position=UDim2.fromOffset(12,y)
    b.BackgroundColor3=Color3.fromRGB(44,76,144)
    b.Text=text
    b.TextColor3=Color3.fromRGB(255,255,255)
    b.Font=Enum.Font.GothamBold
    b.TextSize=12
    b.Parent=panel
    local round=Instance.new("UICorner")
    round.CornerRadius=UDim.new(0,6)
    round.Parent=b
    b.Activated:Connect(callback)
    return b
end

local reopen=Instance.new("TextButton")
reopen.Name="OpenRecovery"
reopen.Size=UDim2.fromOffset(45,42)
reopen.Position=UDim2.fromOffset(6,72)
reopen.Text="◈"
reopen.TextSize=22
reopen.Font=Enum.Font.GothamBold
reopen.TextColor3=Color3.fromRGB(255,255,255)
reopen.BackgroundColor3=Color3.fromRGB(48,90,184)
reopen.Visible=false
reopen.Parent=gui
local reopenCorner=Instance.new("UICorner")
reopenCorner.CornerRadius=UDim.new(0,10)
reopenCorner.Parent=reopen
reopen.Activated:Connect(function()
    panel.Visible=true
    reopen.Visible=false
end)

local function revealHub()
    local hub=playerGui:FindFirstChild("SpectraMM2Hub")
    if not hub then
        status.Text="Hub UI has not been created. The error above or console should explain why."
        return
    end
    hub.Enabled=true
    local win=hub:FindFirstChild("Window")
    local launch=hub:FindFirstChild("FloatingSPECTRAIcon")
    if win then win.Visible=true end
    if launch then launch.Visible=false end
    status.Text=win and "Hub window requested. Use this recovery panel if it vanishes."
        or "Found hub ScreenGui, but its Window was not created."
end

local running=false
local url="https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/spectra_v9_1_core.lua"
local function errorText(e)
    if debug and type(debug.traceback)=="function" then
        return debug.traceback(tostring(e),2)
    end
    return tostring(e)
end
local function runHub()
    if running then return end
    running=true
    panel.Visible=true
    reopen.Visible=false
    status.Text="Downloading existing SPECTRA v9.1 core…"
    task.spawn(function()
        -- Fresh filename plus a per-attempt query avoids executor HTTP caches.
        local requestUrl = url .. "?cache_bust=" .. tostring(math.floor(os.clock() * 1000000))
        local loaded,source=pcall(function() return game:HttpGet(requestUrl, true) end)
        if not loaded then
            -- Some executors don't support HttpGet's optional no-cache argument.
            loaded,source=pcall(function() return game:HttpGet(url) end)
        end
        if not loaded or type(source)~="string" or #source<100 then
            status.Text="Download error: "..tostring(source):sub(1,125)
            warn("[SPECTRA v9.1 loader] "..status.Text)
            running=false
            return
        end
        -- Confirm the corrected source actually arrived, not a stale cached file.
        if not source:find("local ok, status = v54.attackWithKnife(p, true)", 1, true) then
            status.Text="Downloaded file is stale or incomplete. Try another session; core v8.6 correction missing."
            warn("[SPECTRA v9.1] Unexpected core content; expected fixed line 3129")
            running=false
            return
        end
        status.Text="Fresh v8.6 source ("..#source.." bytes). Compiling…"
        if type(loadstring)~="function" then
            status.Text="This environment doesn't provide loadstring."
            running=false
            return
        end
        local compiled,chunk,syntaxError=pcall(function() return loadstring(source) end)
        if not compiled or type(chunk)~="function" then
            local reason = compiled and (syntaxError or "loadstring returned nil without an error message")
                or chunk
            status.Text="Compile error: "..tostring(reason):sub(1,165)
            warn("[SPECTRA v9.1 compile] "..tostring(reason))
            running=false
            return
        end
        status.Text="Syntax OK. Starting hub…"
        local success,reason=xpcall(chunk,errorText)
        if not success then
            status.Text="Hub error: "..tostring(reason):sub(1,170)
            warn("[SPECTRA v9.1 runtime] "..tostring(reason))
            running=false
            return
        end
        local hub=playerGui:FindFirstChild("SpectraMM2Hub")
        if not hub then
            status.Text="The script returned but no hub ScreenGui was found. Check console for early returns."
            running=false
            return
        end
        revealHub()
        status.Text="Core loaded. SPECTRA window should be open. Use the OPEN button to restore it."
        running=false
        task.delay(3,function()
            if panel.Parent and status.Parent and status.Text:find("Core loaded",1,true) then
                panel.Visible=false
                reopen.Visible=true
            end
        end)
    end)
end
button("OPEN / RESTORE SPECTRA WINDOW",127,revealHub)
button("RETRY CORE LOAD",164,runHub)
button("MINIMIZE RECOVERY PANEL",201,function()
    panel.Visible=false
    reopen.Visible=true
end)
runHub()

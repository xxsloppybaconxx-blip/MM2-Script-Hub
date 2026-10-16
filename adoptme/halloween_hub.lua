-- Adopt Me Halloween Helper v2 | experimental (2026)
-- Isolated from MM2. No server bypasses or invented safe-door information.
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local CollectionService=game:GetService("CollectionService")
local UserInputService=game:GetService("UserInputService")
local player=Players.LocalPlayer
local env=(getgenv and getgenv()) or _G
if env.AdoptMeHalloweenHub and type(env.AdoptMeHalloweenHub.Stop)=="function" then
    pcall(env.AdoptMeHalloweenHub.Stop)
end

local config={
    mode="Hauntlet 2",
    ghostESP=true,ghostMove=false,ghostFire=false,
    doorESP=true,doorWalk=false,doorTP=false,safeOnly=false
}
local alive=true
local connections={}
local manual={}
local highlights={}
local chosenDoorSlot=0
local doorTravel=nil
local currentHauntletRoom=nil
local scanned={}
local scanWhen=0
local lastDoor,lastDoorAt=nil,-100
local lastFire=0
local lastMove=0
local statusMessage="Starting..."
local scanInfo="No scan yet"
local viewVisible=true

local function lower(x) return string.lower(tostring(x or "")) end
local function has(x,needle) return string.find(lower(x),needle,1,true)~=nil end
local function attribute(inst,key)
    if not inst then return nil end
    local ok,v=pcall(function()return inst:GetAttribute(key)end)
    return ok and v or nil
end
local function tagged(inst,key)
    if not inst then return false end
    local ok,v=pcall(function()return CollectionService:HasTag(inst,key)end)
    return ok and v or false
end
local function character()
    local c=player.Character
    return c,c and c:FindFirstChild("HumanoidRootPart"),
        c and c:FindFirstChildOfClass("Humanoid")
end
local function ownPart(part)
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character and part:IsDescendantOf(p.Character) then return true end
    end
    return false
end
local function alivePart(part)
    return part and part:IsA("BasePart") and part:IsDescendantOf(Workspace)
end
local function getPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)
    end
end
local function clampedDistance(part)
    local _,root=character()
    return root and (root.Position-part.Position).Magnitude or math.huge
end
local function isDoorName(n)
    return has(n,"door") or has(n,"portal") or has(n,"gateway")
        or has(n,"threshold") or has(n,"entrance") or has(n,"exitgate")
end
local function isGhostName(n)
    return has(n,"ghost") or has(n,"possess") or has(n,"poltergeist")
        or has(n,"specter") or has(n,"haunted")
end
local function doorForPart(part)
    if not alivePart(part) or ownPart(part) then return nil end
    local candidate=nil
    local inst=part
    for depth=1,4 do
        if not inst or inst==Workspace then break end
        if (inst:IsA("BasePart") or inst:IsA("Model")) and
            (isDoorName(inst.Name) or tagged(inst,"Door") or tagged(inst,"HauntletDoor")
             or attribute(inst,"IsDoor")==true or attribute(inst,"DoorId")~=nil) then
            candidate=inst
        end
        inst=inst.Parent
    end
    if candidate then
        local p=getPart(candidate)
        if p and clampedDistance(p)<=105 then return candidate,p end
    end
    local prompt=part:FindFirstChildOfClass("ProximityPrompt")
    if prompt and (has(prompt.Name,"door") or has(prompt.Name,"open")
        or has(prompt.ActionText,"open") or has(prompt.ActionText,"enter")) then
        return part,part
    end
    return nil
end
local function ghostForPart(part)
    if not alivePart(part) or ownPart(part) then return nil end
    local inst=part
    local match=nil
    for depth=1,3 do
        if not inst or inst==Workspace then break end
        if (isGhostName(inst.Name) or tagged(inst,"Ghost") or tagged(inst,"Haunted")
            or attribute(inst,"Haunted")==true or attribute(inst,"Possessed")==true
            or attribute(inst,"HasGhost")==true) then
            if not has(inst.Name,"gallery") and not has(inst.Name,"lobby")
                and not has(inst.Name,"manager") and not has(inst.Name,"spawner") then
                match=inst
            end
        end
        inst=inst.Parent
    end
    if match then
        local p=getPart(match)
        if p and clampedDistance(p)<=110 then return match,p end
    end
end
local function signal(inst,part)
    local nodes={inst,part}
    local risk,name,color,safe=10,"UNKNOWN",Color3.fromRGB(250,204,91),false
    for _,v in ipairs(nodes) do
        for _,k in ipairs({"HasGhost","GhostInside","ContainsGhost","Unsafe","IsDangerous"}) do
            if attribute(v,k)==true then
                return 100,"GHOST SIGNAL",Color3.fromRGB(250,79,86),false
            end
        end
        if tagged(v,"DangerDoor") or tagged(v,"GhostDoor") then
            return 100,"GHOST SIGNAL",Color3.fromRGB(250,79,86),false
        end
    end
    for _,v in ipairs(nodes) do
        for _,k in ipairs({"Safe","IsSafe","GhostFree"}) do
            if attribute(v,k)==true then
                return -20,"SAFE SIGNAL",Color3.fromRGB(54,224,124),true
            end
        end
        if tagged(v,"SafeDoor") then
            return -20,"SAFE SIGNAL",Color3.fromRGB(54,224,124),true
        end
    end
    local n=lower(inst.Name)
    if has(n,"nightmare") then risk=65;name="RISK TYPE";color=Color3.fromRGB(255,145,80) end
    return risk,name,color,safe
end

-- Exact live structure confirmed by room diagnostics:
-- Workspace.Interiors.HauntletInterior::<id>.Rooms.<room>.Doors.<1|2|3>.DoorPart
-- Other door-* collections are decorative markers and MUST NOT be targeted.
local function knownHauntletDoors()
    local interiors=Workspace:FindFirstChild("Interiors")
    if not interiors then return {},"Interiors missing",nil end
    local best,bestRange=nil,math.huge
    local sawInterior=false
    for _,interior in ipairs(interiors:GetChildren()) do
        if has(interior.Name,"HauntletInterior") then
            sawInterior=true
            local rooms=interior:FindFirstChild("Rooms")
            if rooms then
                for _,room in ipairs(rooms:GetChildren()) do
                    local doors=room:FindFirstChild("Doors")
                    if doors then
                        local thisRoom={}
                        local minDist=math.huge
                        for _,slot in ipairs(doors:GetChildren()) do
                            local number=tonumber(slot.Name)
                            if number and number>=1 and number<=3 then
                                local anchor=slot:FindFirstChild("DoorPart",true)
                                if alivePart(anchor) then
                                    local distance=clampedDistance(anchor)
                                    if distance<140 then
                                        minDist=math.min(minDist,distance)
                                        local score,riskLabel,color,safe=signal(slot,anchor)
                                        thisRoom[#thisRoom+1]={
                                            obj=slot,part=anchor,slot=number,
                                            room=room,score=score,label=riskLabel,
                                            color=color,safe=safe,distance=distance
                                        }
                                    end
                                end
                            end
                        end
                        if #thisRoom>0 and minDist<bestRange then
                            bestRange=minDist
                            best={items=thisRoom,room=room}
                        end
                    end
                end
            end
        end
    end
    if best then
        table.sort(best.items,function(a,b)return a.slot<b.slot end)
        return best.items,"Detected room "..best.room.Name,best.room
    end
    if sawInterior then return {},"No live DoorPart slots nearby",nil end
    return {},"Not in a Hauntlet interior",nil
end

local function clearMarks()
    for inst,marks in pairs(highlights) do
        pcall(function()marks.highlight:Destroy()end)
        pcall(function()marks.billboard:Destroy()end)
        highlights[inst]=nil
    end
end

-- ESP MUST live outside ScreenGui to render on more Roblox clients.
local espFolder=Instance.new("Folder")
espFolder.Name="AdoptMeHalloweenESP_Local"
espFolder.Parent=Workspace
local gui=Instance.new("ScreenGui")
gui.Name="AdoptMeHalloweenHub2026"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.DisplayOrder=300
gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame")
panel.Name="Panel"
panel.BackgroundColor3=Color3.fromRGB(25,29,41)
panel.BorderSizePixel=0
panel.Size=UDim2.fromOffset(290,444)
panel.Position=UDim2.new(0,12,0.5,-222)
panel.Active=true
panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
local stroke=Instance.new("UIStroke",panel)
stroke.Color=Color3.fromRGB(95,105,145)
local function label(y,height,contents,sz)
    local l=Instance.new("TextLabel")
    l.Name="Text"
    l.Position=UDim2.fromOffset(12,y)
    l.Size=UDim2.new(1,-24,0,height)
    l.BackgroundTransparency=1
    l.Font=Enum.Font.GothamMedium
    l.TextColor3=Color3.fromRGB(225,229,246)
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextYAlignment=Enum.TextYAlignment.Center
    l.TextSize=sz or 12
    l.TextWrapped=true
    l.Text=contents
    l.Parent=panel
    return l
end
label(8,23,"Adopt Me Halloween Helper v3",16)
label(31,28,"Actual Hauntlet DoorParts | unknown != safe",10)
local function button(y,caption,fn)
    local b=Instance.new("TextButton")
    b.Position=UDim2.fromOffset(12,y)
    b.Size=UDim2.new(1,-24,0,33)
    b.BackgroundColor3=Color3.fromRGB(52,58,81)
    b.TextColor3=Color3.fromRGB(245,246,255)
    b.TextSize=12
    b.Font=Enum.Font.GothamMedium
    b.Text=caption
    b.BorderSizePixel=0
    b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    b.MouseButton1Click:Connect(function()
        if alive then fn(b) end
    end)
    return b
end
local modeButton
local rows={}
local function toggle(y,caption,key,mode)
    local b=button(y,"",function(self)
        config[key]=not config[key]
        self.Text=caption.." ["..(config[key] and "ON" or "OFF").."]"
        self.BackgroundColor3=config[key] and Color3.fromRGB(32,112,94)
            or Color3.fromRGB(52,58,81)
        scanWhen=0
    end)
    rows[#rows+1]={button=b,mode=mode,key=key,caption=caption}
end
local function updateRows()
    for _,row in ipairs(rows) do
        row.button.Visible=row.mode==config.mode
        row.button.Text=row.caption.." ["..(config[row.key] and "ON" or "OFF").."]"
        row.button.BackgroundColor3=config[row.key] and Color3.fromRGB(32,112,94)
            or Color3.fromRGB(52,58,81)
    end
    modeButton.Text="Mode: "..config.mode.."  (tap to switch)"
    clearMarks()
    scanWhen=0
end
modeButton=button(67,"Mode",function()
    config.mode=config.mode=="Hauntlet 2" and "Ghost Gallery" or "Hauntlet 2"
    updateRows()
end)
toggle(109,"Door ESP","doorESP","Hauntlet 2")
toggle(148,"Auto WALK to doors","doorWalk","Hauntlet 2")
toggle(187,"Teleport near doors","doorTP","Hauntlet 2")
toggle(226,"Confirmed safe only","safeOnly","Hauntlet 2")
toggle(109,"Ghost ESP","ghostESP","Ghost Gallery")
toggle(148,"Auto WALK to ghosts","ghostMove","Ghost Gallery")
toggle(187,"Auto fire Ghost Blaster","ghostFire","Ghost Gallery")
updateRows()
local info=label(272,31,"Scanning nearby...",11)
local status=label(370,35,"Starting...",11)
local manualTargets={}
local function aimTarget()
    local camera=Workspace.CurrentCamera
    if not camera then return nil end
    local point=camera.ViewportSize/2
    local ray=camera:ViewportPointToRay(point.X,point.Y)
    local rp=RaycastParams.new()
    local c=player.Character
    if c then rp.FilterDescendantsInstances={c,espFolder} else rp.FilterDescendantsInstances={espFolder} end
    rp.FilterType=Enum.RaycastFilterType.Exclude
    local hit=Workspace:Raycast(ray.Origin,ray.Direction*250,rp)
    return hit and hit.Instance
end
button(308,"Door choice: AUTO (tap to change)",function(self)
    chosenDoorSlot=(chosenDoorSlot+1)%4
    self.Text="Door choice: "..(chosenDoorSlot==0 and "AUTO" or tostring(chosenDoorSlot))
    doorTravel=nil
    statusMessage="Selected door: "..(chosenDoorSlot==0 and "AUTO" or tostring(chosenDoorSlot))
end)
local function diagnostic()
    local _,root=character()
    if not root then statusMessage="No character; cannot scan";return end
    local doors,explanation,room=knownHauntletDoors()
    local lines={
        "Adopt Me Halloween Helper v3 diagnostic",
        "Mode: "..config.mode,
        "Detected room: "..(room and room:GetFullName() or "(none)"),
        "Door selection: "..(chosenDoorSlot==0 and "AUTO" or tostring(chosenDoorSlot)),
        "Detection: "..explanation,
        "Live door count: "..#doors
    }
    for _,d in ipairs(doors) do
        local prompt=d.obj:FindFirstChildWhichIsA("ProximityPrompt",true)
        lines[#lines+1]=string.format(
            "DOOR %d | %.1f studs | %s | collision=%s | prompt=%s | risk=%s",
            d.slot,d.distance,d.part:GetFullName(),tostring(d.part.CanCollide),
            prompt and prompt:GetFullName() or "none",d.label)
    end
    if #doors==0 then
        lines[#lines+1]="No matching Rooms.<room>.Doors.<1-3>.DoorPart currently visible."
        lines[#lines+1]="Try copying again after entering a Hauntlet room."
    end
    local output=table.concat(lines,"\n")
    print(output)
    if type(setclipboard)=="function" then
        statusMessage=pcall(setclipboard,output) and "Door debug copied."
            or "Debug printed to console."
    else
        statusMessage="Door debug printed to console."
    end
end

button(345,"Copy nearby door debug",diagnostic)
local function stop()
    if not alive then return end
    alive=false
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    clearMarks()
    espFolder:Destroy()
    gui:Destroy()
    if env.AdoptMeHalloweenHub and env.AdoptMeHalloweenHub.Stop==stop then
        env.AdoptMeHalloweenHub=nil
    end
end
button(410,"Unload / Close",stop)
local function render(items)
    local enabled=config.mode=="Hauntlet 2" and config.doorESP or config.ghostESP
    if not enabled then clearMarks();return end
    local active={}
    for i=1,math.min(#items,12) do
        local item=items[i]
        if alivePart(item.part) then
            active[item.obj]=true
            local pair=highlights[item.obj]
            if not pair then
                local hl=Instance.new("Highlight")
                hl.Name="HalloweenTarget"
                hl.Adornee=item.part
                hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillTransparency=0.78
                hl.OutlineTransparency=0
                hl.Parent=espFolder
                local bb=Instance.new("BillboardGui")
                bb.Name="TargetInfo"
                bb.Adornee=item.part
                bb.Size=UDim2.fromOffset(155,23)
                bb.StudsOffsetWorldSpace=Vector3.new(0,3,0)
                bb.MaxDistance=125
                bb.AlwaysOnTop=true
                bb.Parent=gui
                local t=Instance.new("TextLabel")
                t.Size=UDim2.fromScale(1,1)
                t.BackgroundColor3=Color3.fromRGB(20,22,33)
                t.BackgroundTransparency=.2
                t.TextColor3=Color3.new(1,1,1)
                t.Font=Enum.Font.GothamBold
                t.TextSize=11
                t.Parent=bb
                pair={highlight=hl,billboard=bb,text=t}
                highlights[item.obj]=pair
            end
            pair.highlight.Adornee=item.part
            pair.highlight.OutlineColor=item.color
            pair.highlight.FillColor=item.color
            pair.billboard.Adornee=item.part
            pair.text.Text=(item.slot and ("DOOR "..item.slot.." ") or "")
                ..item.label.." | "..math.floor(item.distance).." studs"
        end
    end
    for obj,pair in pairs(highlights) do
        if not active[obj] then
            pair.highlight:Destroy()
            pair.billboard:Destroy()
            highlights[obj]=nil
        end
    end
end
-- No Workspace:GetDescendants() in any repeated loop: eliminates old FPS spike.
local function scan()
    local _,root=character()
    if not root then
        scanned={};scanInfo="No character";clearMarks()
        currentHauntletRoom=nil
        return
    end
    if config.mode=="Hauntlet 2" then
        local items,explanation,room=knownHauntletDoors()
        if currentHauntletRoom~=room then
            currentHauntletRoom=room
            doorTravel=nil
            lastDoor=nil
            lastDoorAt=-100
        end
        scanned=items
        scanInfo=string.format("Hauntlet: %d real doors | %s",#items,explanation)
        render(items)
        return
    end
    -- Ghost Gallery remains a bounded, low-frequency spatial search.
    currentHauntletRoom=nil
    doorTravel=nil
    local params=OverlapParams.new()
    params.MaxParts=500
    local ok,parts=pcall(function()
        return Workspace:GetPartBoundsInRadius(root.Position,105,params)
    end)
    if not ok then
        scanned={};scanInfo="Spatial query not supported";clearMarks();return
    end
    local seen,found={},{}
    for _,part in ipairs(parts) do
        local obj,anchor=ghostForPart(part)
        if obj and alivePart(anchor) and not seen[obj] then
            seen[obj]=true
            found[#found+1]={
                obj=obj,part=anchor,score=0,label="GHOST",
                color=Color3.fromRGB(117,194,255),safe=true,
                distance=clampedDistance(anchor)
            }
        end
    end
    table.sort(found,function(a,b) return a.distance<b.distance end)
    scanned=found
    scanInfo=string.format("Ghost Gallery: %d targets / %d nearby parts",
        #found,#parts)
    render(found)
end

local function moveTo(part,tp)
    local _,root,hum=character()
    if not root or not hum or not alivePart(part) then return false end
    if tp and (root.Position-part.Position).Magnitude>7 then
        local offset=root.Position-part.Position
        if offset.Magnitude<.3 then offset=Vector3.new(0,0,1) end
        pcall(function()
            root.CFrame=CFrame.new(part.Position+offset.Unit*5+Vector3.new(0,2,0))
        end)
    end
    hum:MoveTo(part.Position)
    return true
end
local function activateDoor(obj,part)
    local prompt=part:FindFirstChildOfClass("ProximityPrompt")
    if not prompt and obj~=part then
        prompt=obj:FindFirstChildWhichIsA("ProximityPrompt",true)
    end
    if prompt and prompt.Enabled then
        local ok=pcall(function()
            prompt:InputHoldBegin()
            task.delay(math.max(.1,prompt.HoldDuration+.12),function()
                if alive then pcall(function()prompt:InputHoldEnd()end) end
            end)
        end)
        return ok and "prompt attempted" or "prompt blocked"
    end
    -- No simulated click or fabricated server event; walking through the door
    -- remains the fallback for games with touch-triggered entry.
    return "walking to door"
end

local function horizontalDistance(a,b)
    return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude
end
-- Walk up to the player's side of the door, then attempt to cross it.
-- MoveTo requests can still be blocked by the game's door collision/server.
local function walkThroughDoor(item,now)
    local _,root,hum=character()
    if not root or not hum or not alivePart(item.part) then
        return "No character or door part"
    end
    if not doorTravel or doorTravel.obj~=item.obj then
        local part=item.part
        local normal=part.CFrame.LookVector
        local sign=(root.Position-part.Position):Dot(normal)>=0 and 1 or -1
        local reach=math.max(3.2,math.min(7,part.Size.Z*0.5+2))
        local approach=part.Position+normal*sign*reach
        local through=part.Position-normal*sign*reach
        -- Use character's floor height rather than a tall door mesh's Y center.
        approach=Vector3.new(approach.X,root.Position.Y,approach.Z)
        through=Vector3.new(through.X,root.Position.Y,through.Z)
        doorTravel={
            obj=item.obj,phase="approach",at=now,
            front=approach,back=through,attempted=false,detail=""
        }
        if config.doorTP then
            pcall(function()
                root.CFrame=CFrame.new(approach,Vector3.new(
                    part.Position.X,approach.Y,part.Position.Z))
            end)
        end
    end
    local job=doorTravel
    if job.phase=="approach" then
        hum:MoveTo(job.front)
        if horizontalDistance(root.Position,job.front)<4.0
           or horizontalDistance(root.Position,item.part.Position)<5.5
           or now-job.at>6 then
            job.phase="cross"
            job.at=now
        end
    end
    if job.phase=="cross" then
        hum:MoveTo(job.back)
        if not job.attempted and horizontalDistance(root.Position,item.part.Position)<12 then
            job.detail=activateDoor(item.obj,item.part)
            job.attempted=true
        end
        if now-job.at>6.5 then
            lastDoor=item.obj
            lastDoorAt=now
            doorTravel=nil
            return "Door "..tostring(item.slot)..": crossing attempted"
        end
        return "Door "..tostring(item.slot)..": moving through"
            ..(job.attempted and " / "..job.detail or "")
    end
    return "Door "..tostring(item.slot)..": approaching entrance"
end

local function fireBlaster(point)
    local c=player.Character
    if not c then return false end
    local tool
    for _,parent in ipairs({c,player:FindFirstChildOfClass("Backpack")}) do
        if parent then
            for _,t in ipairs(parent:GetChildren()) do
                if t:IsA("Tool") and
                    (has(t.Name,"blaster") or has(t.Name,"vacuum")) then
                    tool=t;break
                end
            end
        end
        if tool then break end
    end
    if not tool then return false end
    if tool.Parent~=c then
        local hum=c:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function()hum:EquipTool(tool)end)end
    end
    if tool.Parent~=c then return false end
    local cam=Workspace.CurrentCamera
    if cam then pcall(function()
        cam.CFrame=CFrame.lookAt(cam.CFrame.Position,point)
    end)end
    return pcall(function()tool:Activate()end)
end
local function automate()
    local now=os.clock()
    if #scanned==0 then
        statusMessage="0 targets. Copy nearby door debug in Hauntlet."
        return
    end
    if config.mode=="Hauntlet 2" then
        if not config.doorWalk then
            doorTravel=nil
            statusMessage="Door ESP detected "..#scanned.." real doors. Auto walk OFF."
            return
        end
        local choice
        -- Keep the same active door during approach/cross so the bot
        -- does not alternate between entrances every update.
        if doorTravel then
            for _,d in ipairs(scanned) do
                if d.obj==doorTravel.obj then choice=d;break end
            end
        end
        if not choice then
            for _,d in ipairs(scanned) do
                if d.score<100 and (not config.safeOnly or d.safe)
                    and (chosenDoorSlot==0 or chosenDoorSlot==d.slot)
                    and (d.obj~=lastDoor or now-lastDoorAt>12) then
                    if not choice or d.distance<choice.distance then choice=d end
                end
            end
        end
        if not choice then
            statusMessage=config.safeOnly and "No door with confirmed SAFE signal."
                or "No selectable door right now."
            return
        end
        if now-lastMove<0.65 then return end
        lastMove=now
        statusMessage=walkThroughDoor(choice,now)
    else
        local g=scanned[1]
        if config.ghostMove and now-lastMove>1.5 then
            lastMove=now
            moveTo(g.part,false)
            statusMessage="Walking toward "..g.obj.Name
        end
        if config.ghostFire and now-lastFire>1.2 then
            lastFire=now
            local fired=fireBlaster(g.part.Position)
            statusMessage=fired and "Blaster activated (capture not verified)"
                or "No usable Ghost Blaster tool"
        end
    end
end

local moving=false
local dragStart,oldPosition
panel.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or
        i.UserInputType==Enum.UserInputType.Touch then
        moving=true;dragStart=i.Position;oldPosition=panel.Position
    end
end)
panel.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or
        i.UserInputType==Enum.UserInputType.Touch then moving=false end
end)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(i)
    if moving and dragStart and (i.UserInputType==Enum.UserInputType.Touch
        or i.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=i.Position-dragStart
        panel.Position=UDim2.new(oldPosition.X.Scale,oldPosition.X.Offset+d.X,
            oldPosition.Y.Scale,oldPosition.Y.Offset+d.Y)
    end
end)
connections[#connections+1]=UserInputService.InputBegan:Connect(function(i,handled)
    if not handled and i.KeyCode==Enum.KeyCode.F6 then
        viewVisible=not viewVisible
        panel.Visible=viewVisible
    end
end)
env.AdoptMeHalloweenHub={Stop=stop,Settings=config,Diagnostic=diagnostic}
task.spawn(function()
    while alive and gui.Parent do
        local now=os.clock()
        if now>=scanWhen then
            local ok,err=pcall(scan)
            if not ok then statusMessage="Scan error: "..tostring(err):sub(1,65) end
            scanWhen=now+4.0
        end
        local ok,err=pcall(automate)
        if not ok then statusMessage="Action error: "..tostring(err):sub(1,65) end
        if info.Parent then info.Text=scanInfo end
        if status.Parent then status.Text=statusMessage end
        task.wait(.45)
    end
end)
print("[AdoptMe Halloween v3] Exact 1-3 DoorPart targeting enabled.")

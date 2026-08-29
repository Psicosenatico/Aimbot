--==============================================================
-- PSICOSENATICO • WEAPON RESEARCH V2
-- MINIMALISTA + MINUCIOSO • Mobile / LocalScript
--
-- OBJETIVO
-- Coletar somente o necessário para validar 4 funções futuras:
-- 1) NO RELOAD / INFINITE AMMO
-- 2) RAPID FIRE / NO FIRE DELAY
-- 3) AUTO FIRE em armas Semi
-- 4) BULLET NOCLIP / WALL PENETRATION (Hitscan/Raycast)
--
-- PRINCÍPIO
-- • Scanner observacional
-- • Não altera arma, munição, reload, remotes, raycast ou dano
-- • Event-driven; sem varredura global contínua
-- • Registra mudanças com timestamp de alta resolução
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "V2",
    GUI_NAME = "PsicosenaticoWeaponResearch_V2",
    MAX_EVENTS = 6000,
    MAX_LIVE = 180,
    UI_REFRESH = 0.75,

    ATTRIBUTES = {
        "_ammo","ammo","Ammo","currentAmmo","CurrentAmmo",
        "magazineSize","MagSize",
        "_reloading","reloadTime","reloadTimePerRound","reloadType",
        "serverControlled",
        "projectileType",
        "rateOfFire","fireRate","FireRate",
        "fireMode","FireMode","automatic","Automatic","auto",
        "raysPerShot","rayRadius","range","spread","damage",
        "projectileSpeed","penetration","pierce","canPierce"
    }
}

local AMMO_NAMES = {"_ammo","ammo","Ammo","currentAmmo","CurrentAmmo"}
local RATE_NAMES = {"rateOfFire","fireRate","FireRate"}
local MODE_NAMES = {"fireMode","FireMode","automatic","Automatic","auto"}

local function parentGui()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then return p end
    end
    return CoreGui
end

local Parent = parentGui()
for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == CONFIG.GUI_NAME then
        pcall(function() v:Destroy() end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.Parent = Parent

local S = {
    Recording = false,
    Started = false,
    StartUnix = nil,
    EndUnix = nil,

    Events = {},
    Live = {},
    Errors = 0,

    Tools = {},
    ToolList = {},
    ToolConnections = {},
    Connections = {},

    ActiveTool = nil,
    Animations = {},
    Blaster = nil,

    Input = {
        fireHeld = false,
        beganAt = nil,
        endedAt = nil
    }
}

local function tnow() return os.clock() end
local function unow() return os.time() end

local function safeFullName(obj)
    local ok, v = pcall(function() return obj:GetFullName() end)
    return ok and tostring(v) or tostring(obj and obj.Name or "UNKNOWN")
end

local function safeAttr(obj, name)
    local ok, v = pcall(function() return obj:GetAttribute(name) end)
    return ok and v or nil
end

local function firstAttr(tool, names)
    for _, n in ipairs(names) do
        local v = safeAttr(tool, n)
        if v ~= nil then return v, n end
    end
    return nil, nil
end

local function readAmmo(tool) return firstAttr(tool, AMMO_NAMES) end
local function readRate(tool) return firstAttr(tool, RATE_NAMES) end
local function readMode(tool) return firstAttr(tool, MODE_NAMES) end

local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    for _, n in ipairs(CONFIG.ATTRIBUTES) do
        if tool:GetAttribute(n) ~= nil then return true end
    end
    return false
end

local function snapshotAttributes(tool)
    local out = {}
    local ok, attrs = pcall(function() return tool:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            local typ = typeof(v)
            if typ == "Instance" then
                out[tostring(k)] = safeFullName(v)
            else
                out[tostring(k)] = v
            end
        end
    end
    return out
end

local function pushLive(tp, msg)
    S.Live[#S.Live + 1] = {time=tnow(), type=tp, message=tostring(msg or "")}
    while #S.Live > CONFIG.MAX_LIVE do
        table.remove(S.Live, 1)
    end
end

local function log(tp, record, data, msg)
    pushLive(tp, msg)
    if tp == "ERROR" then S.Errors += 1 end
    if not S.Recording then return end
    if #S.Events >= CONFIG.MAX_EVENTS then return end

    S.Events[#S.Events + 1] = {
        unix = unow(),
        time = tnow(),
        type = tp,
        toolId = record and record.id or nil,
        toolName = record and record.name or nil,
        data = data or {}
    }
end

local function summaryIntervals(values)
    if #values == 0 then return {count=0} end
    local mn, mx, sum = math.huge, 0, 0
    for _, v in ipairs(values) do
        mn = math.min(mn, v)
        mx = math.max(mx, v)
        sum += v
    end
    return {count=#values, min=mn, max=mx, average=sum/#values}
end

--==============================================================
-- BLASTER SYSTEM / RAYCAST DISCOVERY
--==============================================================

local function scanBlaster()
    local root = ReplicatedStorage:FindFirstChild("BlasterSystem")
    local result = {
        found = root ~= nil,
        root = root and safeFullName(root) or nil,
        relevant = {}
    }

    if root then
        for _, obj in ipairs(root:GetDescendants()) do
            local name = string.lower(obj.Name)
            local relevant =
                obj:IsA("RemoteEvent")
                or obj:IsA("RemoteFunction")
                or obj:IsA("ModuleScript")
                or string.find(name, "ray", 1, true)
                or string.find(name, "pierce", 1, true)
                or string.find(name, "cast", 1, true)
                or string.find(name, "shoot", 1, true)
                or string.find(name, "projectile", 1, true)

            if relevant then
                result.relevant[#result.relevant + 1] = {
                    class = obj.ClassName,
                    name = obj.Name,
                    path = safeFullName(obj)
                }
            end
        end
    end

    S.Blaster = result
    log("BLASTER_SCAN", nil, {
        found = result.found,
        count = #result.relevant
    }, result.found and ("BlasterSystem: "..#result.relevant.." itens relevantes") or "BlasterSystem ausente")
end

--==============================================================
-- TOOL RECORD
--==============================================================

local function disconnectTool(tool)
    local list = S.ToolConnections[tool]
    if not list then return end
    for _, c in ipairs(list) do
        pcall(function() c:Disconnect() end)
    end
    S.ToolConnections[tool] = nil
end

local function addToolConn(tool, c)
    S.ToolConnections[tool] = S.ToolConnections[tool] or {}
    table.insert(S.ToolConnections[tool], c)
end

local function newRecord(tool, reason)
    local ammo, ammoAttr = readAmmo(tool)
    local rate, rateAttr = readRate(tool)
    local mode, modeAttr = readMode(tool)

    local r = {
        id = #S.ToolList + 1,
        tool = tool,
        name = tool.Name,
        firstPath = safeFullName(tool),
        detectedAt = tnow(),
        reason = reason,

        initialAttributes = snapshotAttributes(tool),

        ammo = ammo,
        ammoAttr = ammoAttr,
        rate = rate,
        rateAttr = rateAttr,
        mode = mode,
        modeAttr = modeAttr,

        activations = 0,
        lastActivation = nil,
        lastDeactivation = nil,
        activationDurations = {},

        ammoDrops = 0,
        ammoIncreases = 0,
        lastAmmoDrop = nil,
        shotIntervals = {},
        ammoTransitions = {},

        reloadStarted = nil,
        reloads = {},

        fireAnimations = 0,
        reloadAnimations = 0,
        fireAnimationTimes = {},
        fireAnimationIntervals = {},

        inputPresses = {},
        attributeChanges = {}
    }

    return r
end

local function registerTool(tool, reason)
    if not isWeapon(tool) then return nil end
    if S.Tools[tool] then return S.Tools[tool] end

    local r = newRecord(tool, reason)
    S.Tools[tool] = r
    S.ToolList[#S.ToolList + 1] = r

    log("WEAPON_FOUND", r, {
        reason = reason,
        attributes = r.initialAttributes
    }, "Arma: "..r.name)

    addToolConn(tool, tool.Equipped:Connect(function()
        S.ActiveTool = tool
        log("WEAPON_EQUIPPED", r, {attributes=snapshotAttributes(tool)}, r.name.." equipada")
    end))

    addToolConn(tool, tool.Unequipped:Connect(function()
        if S.ActiveTool == tool then S.ActiveTool = nil end
        log("WEAPON_UNEQUIPPED", r, {}, r.name.." desequipada")
    end))

    addToolConn(tool, tool.Activated:Connect(function()
        r.activations += 1
        r.lastActivation = tnow()
        r.lastDeactivation = nil

        log("TOOL_ACTIVATED", r, {
            activation = r.activations,
            ammo = select(1, readAmmo(tool)),
            rateOfFire = select(1, readRate(tool)),
            fireMode = select(1, readMode(tool)),
            fireHeld = S.Input.fireHeld
        }, r.name.." Activated")
    end))

    addToolConn(tool, tool.Deactivated:Connect(function()
        local t = tnow()
        r.lastDeactivation = t
        local duration = r.lastActivation and (t-r.lastActivation) or nil
        if duration then r.activationDurations[#r.activationDurations+1] = duration end

        log("TOOL_DEACTIVATED", r, {
            duration = duration,
            fireHeld = S.Input.fireHeld
        }, r.name.." Deactivated")
    end))

    local watched = {}
    for _, attributeName in ipairs(CONFIG.ATTRIBUTES) do
        if not watched[attributeName] then
            watched[attributeName] = true

            local ok, signal = pcall(function()
                return tool:GetAttributeChangedSignal(attributeName)
            end)

            if ok and signal then
                addToolConn(tool, signal:Connect(function()
                    local value = safeAttr(tool, attributeName)
                    r.attributeChanges[#r.attributeChanges+1] = {
                        time=tnow(), name=attributeName, value=value
                    }

                    if table.find(AMMO_NAMES, attributeName) then
                        local old = tonumber(r.ammo)
                        local new = tonumber(value)

                        if old and new and new < old then
                            local t = tnow()
                            local interval = r.lastAmmoDrop and (t-r.lastAmmoDrop) or nil
                            if interval then r.shotIntervals[#r.shotIntervals+1] = interval end
                            r.lastAmmoDrop = t
                            r.ammoDrops += 1

                            r.ammoTransitions[#r.ammoTransitions+1] = {
                                time=t, old=old, new=new, delta=new-old,
                                intervalFromPrevious=interval
                            }

                            log("AMMO_DECREASED", r, {
                                old=old,new=new,delta=new-old,
                                intervalFromPrevious=interval,
                                fireHeld=S.Input.fireHeld
                            }, string.format("%s ammo %s>%s",r.name,old,new))

                        elseif old and new and new > old then
                            r.ammoIncreases += 1
                            log("AMMO_INCREASED", r, {
                                old=old,new=new,delta=new-old
                            }, string.format("%s ammo %s>%s",r.name,old,new))
                        end

                        r.ammo = value
                        r.ammoAttr = attributeName
                    end

                    if attributeName == "_reloading" then
                        if value == true then
                            r.reloadStarted = tnow()
                            log("RELOAD_STARTED", r, {
                                ammo=select(1,readAmmo(tool)),
                                reloadTime=safeAttr(tool,"reloadTime"),
                                reloadTimePerRound=safeAttr(tool,"reloadTimePerRound"),
                                reloadType=safeAttr(tool,"reloadType")
                            }, r.name.." reload START")
                        elseif value == false and r.reloadStarted then
                            local duration = tnow()-r.reloadStarted
                            r.reloads[#r.reloads+1] = {duration=duration}
                            log("RELOAD_FINISHED", r, {
                                duration=duration,
                                ammo=select(1,readAmmo(tool))
                            }, string.format("%s reload END %.3fs",r.name,duration))
                            r.reloadStarted = nil
                        end
                    end

                    if table.find(RATE_NAMES, attributeName) then
                        r.rate = value
                        r.rateAttr = attributeName
                    end

                    if table.find(MODE_NAMES, attributeName) then
                        r.mode = value
                        r.modeAttr = attributeName
                    end

                    log("ATTRIBUTE_CHANGED", r, {
                        name=attributeName,
                        value=value
                    }, r.name.." "..attributeName.."="..tostring(value))
                end))
            end
        end
    end

    return r
end

local function scanWeapons(reason)
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj, reason or "CHARACTER_SCAN") end
        end
    end

    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj, reason or "BACKPACK_SCAN") end
        end
    end
end

--==============================================================
-- ANIMATION CORRELATION
--==============================================================

local function connectAnimator(character)
    task.spawn(function()
        local hum = character:WaitForChild("Humanoid",5)
        if not hum then return end

        local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator",5)
        if not animator then return end

        S.Connections[#S.Connections+1] = animator.AnimationPlayed:Connect(function(track)
            local tool = S.ActiveTool
            local r = tool and S.Tools[tool] or nil

            local name, id, length, speed, priority = nil,nil,nil,nil,nil
            pcall(function() name = track.Animation and track.Animation.Name or track.Name end)
            pcall(function() id = track.Animation and track.Animation.AnimationId or nil end)
            pcall(function() length = track.Length end)
            pcall(function() speed = track.Speed end)
            pcall(function() priority = tostring(track.Priority) end)

            local info = {
                time=tnow(),
                toolId=r and r.id or nil,
                toolName=r and r.name or nil,
                animationName=name,
                animationId=id,
                length=length,
                speed=speed,
                priority=priority
            }
            S.Animations[#S.Animations+1] = info

            local lower = string.lower(tostring(name or ""))

            if r and string.find(lower,"fire",1,true) then
                local t = info.time
                local previous = r.fireAnimationTimes[#r.fireAnimationTimes]
                if previous then
                    r.fireAnimationIntervals[#r.fireAnimationIntervals+1] = t-previous
                end
                r.fireAnimationTimes[#r.fireAnimationTimes+1] = t
                r.fireAnimations += 1
                log("FIRE_ANIMATION",r,info,r.name.." Fire animation")

            elseif r and string.find(lower,"reload",1,true) then
                r.reloadAnimations += 1
                log("RELOAD_ANIMATION",r,info,r.name.." Reload animation")
            else
                log("ANIMATION_PLAYED",r,info,tostring(name))
            end
        end)
    end)
end

--==============================================================
-- INPUT CORRELATION (somente observação)
--==============================================================

S.Connections[#S.Connections+1] = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        S.Input.fireHeld = true
        S.Input.beganAt = tnow()

        local tool = S.ActiveTool
        local r = tool and S.Tools[tool] or nil
        if r then
            log("INPUT_FIRE_BEGIN",r,{
                inputType=tostring(input.UserInputType)
            },r.name.." input BEGIN")
        end
    end
end)

S.Connections[#S.Connections+1] = UserInputService.InputEnded:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        local ended = tnow()
        local duration = S.Input.beganAt and (ended-S.Input.beganAt) or nil
        S.Input.fireHeld = false
        S.Input.endedAt = ended

        local tool = S.ActiveTool
        local r = tool and S.Tools[tool] or nil
        if r then
            r.inputPresses[#r.inputPresses+1] = {duration=duration}
            log("INPUT_FIRE_END",r,{
                duration=duration,
                inputType=tostring(input.UserInputType)
            },r.name.." input END")
        end
    end
end)

--==============================================================
-- CONTAINERS
--==============================================================

local function connectContainers()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        S.Connections[#S.Connections+1] = backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then task.defer(registerTool,child,"BACKPACK_ADDED") end
        end)
    end

    if LocalPlayer.Character then
        S.Connections[#S.Connections+1] = LocalPlayer.Character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.defer(function()
                    local r=registerTool(child,"CHARACTER_ADDED")
                    if r then S.ActiveTool=child end
                end)
            end
        end)
        connectAnimator(LocalPlayer.Character)
    end
end

S.Connections[#S.Connections+1] = LocalPlayer.CharacterAdded:Connect(function(character)
    S.ActiveTool=nil
    task.wait(0.4)
    connectAnimator(character)

    S.Connections[#S.Connections+1] = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(function()
                local r=registerTool(child,"RESPAWN_CHARACTER_ADDED")
                if r then S.ActiveTool=child end
            end)
        end
    end)

    scanWeapons("RESPAWN_SCAN")
end)

--==============================================================
-- START / STOP / EXPORT
--==============================================================

local function resetSessionStats()
    S.Events={}
    S.Animations={}
    S.Errors=0

    for _,r in ipairs(S.ToolList) do
        r.activations=0
        r.activationDurations={}
        r.ammoDrops=0
        r.ammoIncreases=0
        r.lastAmmoDrop=nil
        r.shotIntervals={}
        r.ammoTransitions={}
        r.reloadStarted=nil
        r.reloads={}
        r.fireAnimations=0
        r.reloadAnimations=0
        r.fireAnimationTimes={}
        r.fireAnimationIntervals={}
        r.inputPresses={}
        r.attributeChanges={}
    end
end

local function startDiagnostic()
    if S.Recording then return end
    resetSessionStats()
    S.Recording=true
    S.Started=true
    S.StartUnix=unow()
    S.EndUnix=nil

    log("DIAGNOSTIC_STARTED",nil,{},"Weapon Research V2 iniciado")
    scanBlaster()
    scanWeapons("DIAGNOSTIC_START")
end

local function stopDiagnostic()
    if not S.Recording then return end
    log("DIAGNOSTIC_STOPPED",nil,{},"Weapon Research V2 parado")
    S.Recording=false
    S.EndUnix=unow()
end

local function serializeTools()
    local out={}
    for _,r in ipairs(S.ToolList) do
        local tool=r.tool

        out[#out+1]={
            id=r.id,
            name=r.name,
            firstPath=r.firstPath,

            initialAttributes=r.initialAttributes,
            finalAttributes=tool and tool.Parent and snapshotAttributes(tool) or nil,

            ammoAttribute=r.ammoAttr,
            rateAttribute=r.rateAttr,
            fireModeAttribute=r.modeAttr,

            currentAmmo=tool and tool.Parent and select(1,readAmmo(tool)) or r.ammo,
            rateOfFire=tool and tool.Parent and select(1,readRate(tool)) or r.rate,
            fireMode=tool and tool.Parent and select(1,readMode(tool)) or r.mode,

            reloadTime=tool and tool.Parent and safeAttr(tool,"reloadTime") or nil,
            reloadTimePerRound=tool and tool.Parent and safeAttr(tool,"reloadTimePerRound") or nil,
            reloadType=tool and tool.Parent and safeAttr(tool,"reloadType") or nil,
            projectileType=tool and tool.Parent and safeAttr(tool,"projectileType") or nil,
            raysPerShot=tool and tool.Parent and safeAttr(tool,"raysPerShot") or nil,
            rayRadius=tool and tool.Parent and safeAttr(tool,"rayRadius") or nil,
            range=tool and tool.Parent and safeAttr(tool,"range") or nil,

            activations=r.activations,
            activationDurationSummary=summaryIntervals(r.activationDurations),

            ammoDrops=r.ammoDrops,
            ammoIncreases=r.ammoIncreases,
            ammoTransitions=r.ammoTransitions,
            shotIntervalSummary=summaryIntervals(r.shotIntervals),
            shotIntervals=r.shotIntervals,

            reloads=r.reloads,

            fireAnimations=r.fireAnimations,
            reloadAnimations=r.reloadAnimations,
            fireAnimationIntervalSummary=summaryIntervals(r.fireAnimationIntervals),
            fireAnimationIntervals=r.fireAnimationIntervals,

            inputPresses=r.inputPresses,
            attributeChanges=r.attributeChanges
        }
    end
    return out
end

local function buildExport()
    return {
        format="Psicosenatico Weapon Research",
        version=CONFIG.VERSION,
        mode="MINIMAL_DETAILED_EVENT_DRIVEN",
        generatedAtUnix=unow(),

        objective={
            "NO_RELOAD",
            "RAPID_FIRE",
            "AUTO_FIRE",
            "BULLET_NOCLIP_WALL_PENETRATION"
        },

        knownInterpretation={
            note="Campos abaixo são observados; o scanner não modifica nada.",
            rateFormula="expectedIntervalSeconds = 60 / rateOfFire"
        },

        diagnostic={
            status=S.Recording and "RECORDING" or "STOPPED",
            startedAtUnix=S.StartUnix,
            finishedAtUnix=S.EndUnix
        },

        summary={
            weaponsDetected=#S.ToolList,
            events=#S.Events,
            animations=#S.Animations,
            errors=S.Errors
        },

        blasterSystem=S.Blaster,
        weapons=serializeTools(),
        animations=S.Animations,
        events=S.Events
    }
end

local function makeJson()
    local ok,data=pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)
    return ok and data or nil, ok and nil or data
end

--==============================================================
-- UI
--==============================================================

local C={
    bg=Color3.fromRGB(10,10,13),
    panel=Color3.fromRGB(19,19,24),
    panel2=Color3.fromRGB(28,28,35),
    text=Color3.fromRGB(245,245,248),
    sub=Color3.fromRGB(158,158,172),
    blue=Color3.fromRGB(22,55,105),
    blue2=Color3.fromRGB(32,82,145),
    green=Color3.fromRGB(65,210,118),
    red=Color3.fromRGB(235,38,52),
    yellow=Color3.fromRGB(242,184,57)
}

local function new(class,props)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    return o
end

local function round(o,r)
    new("UICorner",{Parent=o,CornerRadius=UDim.new(0,r or 8)})
end

local function lbl(parent,text,size,pos,textSize)
    return new("TextLabel",{
        Parent=parent,BackgroundTransparency=1,Text=text,
        Size=size,Position=pos,TextColor3=C.text,
        Font=Enum.Font.Gotham,TextSize=textSize or 10,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center
    })
end

local Main=new("Frame",{
    Parent=Gui,BackgroundColor3=C.bg,BorderSizePixel=0,
    AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5)
})
round(Main,15)

local function resize()
    local cam=Workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    local w=math.min(math.floor(v.X*0.91),v.X-18)
    local h=math.min(math.floor(v.Y*0.70),v.Y-18)
    Main.Size=UDim2.fromOffset(math.max(300,w),math.max(250,h))
end
resize()

local Header=new("Frame",{
    Parent=Main,Size=UDim2.new(1,0,0,58),
    BackgroundColor3=C.panel,BorderSizePixel=0
})
round(Header,15)

lbl(Header,"PSICOSENATICO • WEAPON RESEARCH",UDim2.new(1,-140,0,24),UDim2.fromOffset(16,6),15)
local V=lbl(Header,"V2",UDim2.fromOffset(28,16),UDim2.fromOffset(16,34),9); V.TextColor3=C.blue2
local Sub=lbl(Header,"4 FUNÇÕES • COLETA MINIMALISTA",UDim2.new(1,-170,0,16),UDim2.fromOffset(43,34),8); Sub.TextColor3=C.sub

local Min=new("TextButton",{
    Parent=Header,Size=UDim2.fromOffset(36,34),
    Position=UDim2.new(1,-84,0,11),Text="—",
    BackgroundColor3=C.panel2,TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=18,BorderSizePixel=0
}); round(Min,9)

local Close=new("TextButton",{
    Parent=Header,Size=UDim2.fromOffset(36,34),
    Position=UDim2.new(1,-42,0,11),Text="×",
    BackgroundColor3=C.red,TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=20,BorderSizePixel=0
}); round(Close,9)

local Status=lbl(Main,"Pronto • scanner não altera armas.",UDim2.new(1,-32,0,20),UDim2.fromOffset(16,63),9); Status.TextColor3=C.sub

local Start=new("TextButton",{
    Parent=Main,Size=UDim2.new(0.5,-18,0,38),
    Position=UDim2.fromOffset(16,87),Text="INICIAR",
    BackgroundColor3=C.blue2,TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0
}); round(Start,8)

local Export=new("TextButton",{
    Parent=Main,Size=UDim2.new(0.5,-18,0,38),
    Position=UDim2.new(0.5,2,0,87),Text="EXPORTAR",
    BackgroundColor3=C.blue,TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0
}); round(Export,8)

local Summary=lbl(Main,"",UDim2.new(1,-32,0,22),UDim2.fromOffset(16,130),9); Summary.TextColor3=C.sub

local Viewer=new("ScrollingFrame",{
    Parent=Main,Position=UDim2.fromOffset(16,155),
    Size=UDim2.new(1,-32,1,-164),
    BackgroundColor3=C.panel,BorderSizePixel=0,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ScrollBarThickness=5,ScrollingDirection=Enum.ScrollingDirection.Y
}); round(Viewer,9)

local Text=new("TextLabel",{
    Parent=Viewer,BackgroundTransparency=1,
    Position=UDim2.fromOffset(9,7),
    Size=UDim2.new(1,-18,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    Text="",TextColor3=C.text,Font=Enum.Font.Code,TextSize=9,
    TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top
})

local Mini=new("TextButton",{
    Parent=Gui,Visible=false,Size=UDim2.fromOffset(56,56),
    Position=UDim2.fromScale(0.06,0.24),Text="W V2",
    BackgroundColor3=C.blue,TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0
}); round(Mini,17)

local function draggable(target,handle)
    local dragging=false
    local dragInput=nil
    local dragStart=nil
    local startPos=nil

    S.Connections[#S.Connections+1]=handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            dragStart=input.Position
            startPos=target.Position

            input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then
                    dragging=false
                end
            end)
        end
    end)

    S.Connections[#S.Connections+1]=handle.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement
            or input.UserInputType==Enum.UserInputType.Touch then
            dragInput=input
        end
    end)

    S.Connections[#S.Connections+1]=UserInputService.InputChanged:Connect(function(input)
        if dragging and input==dragInput then
            local d=input.Position-dragStart
            target.Position=UDim2.new(
                startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y
            )
        end
    end)
end

draggable(Main,Header)
draggable(Mini,Mini)

local function updatePreview()
    Summary.Text=string.format(
        "REC: %s • ARMAS: %d • EVENTOS: %d • ANIMS: %d • ERR: %d",
        S.Recording and "ON" or "OFF",
        #S.ToolList,#S.Events,#S.Animations,S.Errors
    )

    local lines={
        "WEAPON RESEARCH V2",
        "────────────────────────────────────────",
        "1 NO RELOAD",
        "2 RAPID FIRE",
        "3 AUTO FIRE",
        "4 BULLET NOCLIP / WALL PENETRATION",
        "",
        "TESTE IDEAL",
        "• Semi: clique várias vezes",
        "• Semi: segure o disparo",
        "• Auto: segure o disparo",
        "• Faça reload manual",
        "• Atire numa parede",
        "• Atire no mesmo alvo sem parede",
        "",
        "ÚLTIMOS EVENTOS",
        "────────────────────────────────────────"
    }

    local s=math.max(1,#S.Live-110)
    for i=s,#S.Live do
        local x=S.Live[i]
        lines[#lines+1]=string.format("[%.3f] %-20s %s",x.time or 0,tostring(x.type),tostring(x.message))
    end

    Text.Text=table.concat(lines,"\n")
end

Start.Activated:Connect(function()
    if not S.Recording then
        startDiagnostic()
        Start.Text="PARAR"
        Status.Text="Gravando • execute o protocolo de teste."
        Status.TextColor3=C.green
    else
        stopDiagnostic()
        Start.Text="INICIAR"
        Status.Text="Parado • dados preservados."
        Status.TextColor3=C.sub
    end
    updatePreview()
end)

Export.Activated:Connect(function()
    if not S.Started then
        Status.Text="Inicie a coleta antes de exportar."
        Status.TextColor3=C.yellow
        return
    end

    local data,err=makeJson()
    if not data then
        Status.Text="Falha JSON: "..tostring(err)
        Status.TextColor3=C.red
        return
    end

    local filename="Psicosenatico_WeaponResearch_V2_"..tostring(game.PlaceId).."_"..tostring(os.time())..".json"

    local saved=false
    if typeof(writefile)=="function" then
        saved=pcall(function() writefile(filename,data) end)
    end

    if saved then
        Status.Text="✓ EXPORTADO: "..filename
        Status.TextColor3=C.green
    elseif typeof(setclipboard)=="function" and pcall(function() setclipboard(data) end) then
        Status.Text="✓ JSON COPIADO."
        Status.TextColor3=C.green
    else
        Status.Text="writefile/setclipboard indisponíveis."
        Status.TextColor3=C.red
    end
end)

Min.Activated:Connect(function()
    Main.Visible=false
    Mini.Visible=true
end)

Mini.Activated:Connect(function()
    Mini.Visible=false
    Main.Visible=true
end)

local function cleanup()
    if S.Recording then stopDiagnostic() end

    for tool in pairs(S.ToolConnections) do
        disconnectTool(tool)
    end

    for _,c in ipairs(S.Connections) do
        pcall(function() c:Disconnect() end)
    end

    pcall(function() Gui:Destroy() end)
end

Close.Activated:Connect(cleanup)

if Workspace.CurrentCamera then
    local ok, sig=pcall(function()
        return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")
    end)
    if ok and sig then
        S.Connections[#S.Connections+1]=sig:Connect(resize)
    end
end

connectContainers()
scanWeapons("INITIAL_SCAN")
pushLive("SYSTEM","Weapon Research V2 pronto.")
pushLive("SYSTEM","Somente observação; nenhuma arma é alterada.")
updatePreview()

task.spawn(function()
    while Gui.Parent do
        pcall(updatePreview)
        task.wait(CONFIG.UI_REFRESH)
    end
end)

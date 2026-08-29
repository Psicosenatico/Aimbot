--==============================================================
-- PSICOSENATICO • WEAPON RESEARCH V1
-- Scanner observacional de armas • Mobile / LocalScript
--
-- Objetivo:
-- • estudar disparo, cadência, reload e animações
-- • NÃO altera munição, cooldown, RemoteEvents ou dano
-- • exporta JSON para análise posterior
--
-- Base conhecida do scan anterior:
-- _ammo, magazineSize, _reloading, reloadTime,
-- reloadTimePerRound, serverControlled, projectileType, rateOfFire
-- ReplicatedStorage.BlasterSystem
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local GUI_NAME = "PsicosenaticoWeaponResearch_V1"
local VERSION = "V1.1"
local MAX_EVENTS = 4000

local AmmoNames = {"_ammo","ammo","Ammo","currentAmmo","CurrentAmmo"}
local RateNames = {"rateOfFire","fireRate","FireRate"}
local AutoNames = {"automatic","Automatic","auto","fireMode","FireMode"}

local WeaponHints = {
    "_ammo","magazineSize","MagSize","_reloading","reloadTime",
    "reloadTimePerRound","serverControlled","projectileType",
    "rateOfFire","fireRate","FireRate","automatic","Automatic",
    "auto","fireMode","FireMode"
}

local function getParent()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then return p end
    end
    return CoreGui
end

local Parent = getParent()
for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == GUI_NAME then pcall(function() v:Destroy() end) end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.Parent = Parent

local State = {
    Recording = false,
    EverStarted = false,
    StartUnix = nil,
    EndUnix = nil,
    Events = {},
    Live = {},
    Tools = {},
    ToolList = {},
    ToolConnections = {},
    Connections = {},
    ActiveTool = nil,
    Animations = {},
    BlasterSystem = nil,
    Errors = 0
}

local function now() return os.clock() end
local function unix() return os.time() end

local function safeFullName(obj)
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value) or tostring(obj and obj.Name or "UNKNOWN")
end

local function safeAttr(obj, name)
    local ok, value = pcall(function() return obj:GetAttribute(name) end)
    return ok and value or nil
end

local function firstAttr(tool, names)
    for _, name in ipairs(names) do
        local v = safeAttr(tool, name)
        if v ~= nil then return v, name end
    end
    return nil, nil
end

local function readAmmo(tool) return firstAttr(tool, AmmoNames) end
local function readRate(tool) return firstAttr(tool, RateNames) end
local function readAuto(tool) return firstAttr(tool, AutoNames) end

local function snapshotAttributes(tool)
    local out = {}
    local ok, attrs = pcall(function() return tool:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            local t = typeof(v)
            if t == "Instance" then
                out[tostring(k)] = safeFullName(v)
            else
                out[tostring(k)] = v
            end
        end
    end
    return out
end

local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    for _, name in ipairs(WeaponHints) do
        if tool:GetAttribute(name) ~= nil then return true end
    end
    local n = string.lower(tool.Name)
    for _, word in ipairs({"gun","rifle","pistol","shotgun","smg","blaster","weapon","sniper","launcher"}) do
        if string.find(n, word, 1, true) then return true end
    end
    return false
end

local function log(eventType, record, data, message)
    State.Live[#State.Live + 1] = {time = now(), type = eventType, message = tostring(message or "")}
    while #State.Live > 180 do table.remove(State.Live, 1) end

    if eventType == "ERROR" then State.Errors = State.Errors + 1 end
    if not State.Recording or #State.Events >= MAX_EVENTS then return end

    State.Events[#State.Events + 1] = {
        unix = unix(),
        time = now(),
        type = eventType,
        toolId = record and record.id or nil,
        toolName = record and record.name or nil,
        data = data or {}
    }
end

local function scanBlasterSystem()
    local root = ReplicatedStorage:FindFirstChild("BlasterSystem")
    if not root then
        State.BlasterSystem = {found = false}
        log("BLASTER_NOT_FOUND", nil, {}, "BlasterSystem não encontrado.")
        return
    end

    local result = {found = true, path = safeFullName(root), objects = {}}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")
        or obj:IsA("ModuleScript") or obj:IsA("LocalScript") or obj:IsA("Folder") then
            result.objects[#result.objects + 1] = {
                class = obj.ClassName,
                name = obj.Name,
                path = safeFullName(obj)
            }
        end
    end
    State.BlasterSystem = result
    log("BLASTER_SCANNED", nil, {count = #result.objects}, "BlasterSystem mapeado.")
end

local function disconnectTool(tool)
    local list = State.ToolConnections[tool]
    if not list then return end
    for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
    State.ToolConnections[tool] = nil
end

local function addToolConnection(tool, c)
    State.ToolConnections[tool] = State.ToolConnections[tool] or {}
    table.insert(State.ToolConnections[tool], c)
end

local function registerTool(tool, reason)
    if not isWeapon(tool) then return nil end
    if State.Tools[tool] then return State.Tools[tool] end

    local ammo, ammoName = readAmmo(tool)
    local rate, rateName = readRate(tool)
    local auto, autoName = readAuto(tool)

    local record = {
        id = #State.ToolList + 1,
        tool = tool,
        name = tool.Name,
        path = safeFullName(tool),
        detectedAtUnix = unix(),
        initialAttributes = snapshotAttributes(tool),
        ammo = ammo,
        ammoAttribute = ammoName,
        rate = rate,
        rateAttribute = rateName,
        auto = auto,
        autoAttribute = autoName,
        activationCount = 0,
        activationShotCount = 0,
        totalAmmoDrops = 0,
        lastActivation = nil,
        lastDeactivation = nil,
        lastAmmoDrop = nil,
        shotIntervals = {},
        reloads = {},
        activationSummaries = {},
        attributeChanges = {}
    }

    State.Tools[tool] = record
    State.ToolList[#State.ToolList + 1] = record

    log("WEAPON_FOUND", record, {
        reason = reason,
        ammo = ammo,
        ammoAttribute = ammoName,
        rateOfFire = rate,
        rateAttribute = rateName,
        automatic = auto,
        automaticAttribute = autoName,
        attributes = record.initialAttributes
    }, "Arma detectada: " .. record.name)

    addToolConnection(tool, tool.Equipped:Connect(function()
        State.ActiveTool = tool
        log("WEAPON_EQUIPPED", record, {attributes = snapshotAttributes(tool)}, record.name .. " equipada")
    end))

    addToolConnection(tool, tool.Unequipped:Connect(function()
        if State.ActiveTool == tool then State.ActiveTool = nil end
        log("WEAPON_UNEQUIPPED", record, {}, record.name .. " desequipada")
    end))

    addToolConnection(tool, tool.Activated:Connect(function()
        record.activationCount = record.activationCount + 1
        record.activationShotCount = 0
        record.lastActivation = now()
        record.lastDeactivation = nil
        log("TOOL_ACTIVATED", record, {
            activation = record.activationCount,
            ammo = select(1, readAmmo(tool)),
            rateOfFire = select(1, readRate(tool)),
            automatic = select(1, readAuto(tool))
        }, record.name .. " • Activated")
    end))

    addToolConnection(tool, tool.Deactivated:Connect(function()
        record.lastDeactivation = now()
        local duration = record.lastActivation and (record.lastDeactivation - record.lastActivation) or nil
        local behavior = "NO_AMMO_DROP"
        if record.activationShotCount == 1 then behavior = "ONE_AMMO_DROP" end
        if record.activationShotCount >= 2 then behavior = "MULTIPLE_AMMO_DROPS_ONE_ACTIVATION" end

        local summary = {
            activation = record.activationCount,
            duration = duration,
            ammoDrops = record.activationShotCount,
            behavior = behavior
        }
        record.activationSummaries[#record.activationSummaries + 1] = summary
        log("TOOL_DEACTIVATED", record, summary, record.name .. " • Deactivated")
    end))

    -- Mudanças de atributos.
    -- Usa GetAttributeChangedSignal para compatibilidade e evita depender
    -- de um evento genérico AttributeChanged.
    local watchedAttributes = {}
    for _, attributeName in ipairs(WeaponHints) do
        if not watchedAttributes[attributeName] then
            watchedAttributes[attributeName] = true

            local okSignal, signal = pcall(function()
                return tool:GetAttributeChangedSignal(attributeName)
            end)

            if okSignal and signal then
                addToolConnection(tool, signal:Connect(function()
                    local newValue = safeAttr(tool, attributeName)
                    local change = {
                        time = now(),
                        name = attributeName,
                        value = newValue
                    }

                    record.attributeChanges[#record.attributeChanges + 1] = change

                    local isAmmo = table.find(AmmoNames, attributeName) ~= nil

                    if isAmmo then
                        local oldAmmo = tonumber(record.ammo)
                        local newAmmo = tonumber(newValue)

                        if oldAmmo and newAmmo and newAmmo < oldAmmo then
                            local t = now()
                            local interval = nil

                            if record.lastAmmoDrop then
                                interval = t - record.lastAmmoDrop
                                record.shotIntervals[#record.shotIntervals + 1] = interval
                            end

                            record.lastAmmoDrop = t
                            record.totalAmmoDrops = record.totalAmmoDrops + 1

                            if record.lastActivation and not record.lastDeactivation then
                                record.activationShotCount = record.activationShotCount + 1
                            end

                            log(
                                "AMMO_DECREASED",
                                record,
                                {
                                    attribute = attributeName,
                                    old = oldAmmo,
                                    new = newAmmo,
                                    intervalFromPrevious = interval,
                                    activationShotCount = record.activationShotCount
                                },
                                string.format(
                                    "%s • ammo %s -> %s",
                                    record.name,
                                    tostring(oldAmmo),
                                    tostring(newAmmo)
                                )
                            )

                        elseif oldAmmo and newAmmo and newAmmo > oldAmmo then
                            log(
                                "AMMO_INCREASED",
                                record,
                                {
                                    attribute = attributeName,
                                    old = oldAmmo,
                                    new = newAmmo
                                },
                                string.format(
                                    "%s • ammo %s -> %s",
                                    record.name,
                                    tostring(oldAmmo),
                                    tostring(newAmmo)
                                )
                            )
                        end

                        record.ammo = newValue
                        record.ammoAttribute = attributeName
                    end

                    if attributeName == "_reloading" then
                        if newValue == true then
                            record.reloadStarted = now()

                            log(
                                "RELOAD_STARTED",
                                record,
                                {
                                    reloadTime = safeAttr(tool, "reloadTime"),
                                    reloadTimePerRound = safeAttr(tool, "reloadTimePerRound"),
                                    ammo = select(1, readAmmo(tool))
                                },
                                record.name .. " • reload iniciado"
                            )

                        elseif newValue == false and record.reloadStarted then
                            local duration = now() - record.reloadStarted

                            record.reloads[#record.reloads + 1] = {
                                duration = duration
                            }

                            log(
                                "RELOAD_FINISHED",
                                record,
                                {
                                    duration = duration,
                                    ammo = select(1, readAmmo(tool))
                                },
                                string.format(
                                    "%s • reload %.3fs",
                                    record.name,
                                    duration
                                )
                            )

                            record.reloadStarted = nil
                        end
                    end

                    if table.find(RateNames, attributeName) then
                        record.rate = newValue
                        record.rateAttribute = attributeName
                    end

                    if table.find(AutoNames, attributeName) then
                        record.auto = newValue
                        record.autoAttribute = attributeName
                    end

                    log(
                        "ATTRIBUTE_CHANGED",
                        record,
                        change,
                        string.format(
                            "%s • %s = %s",
                            record.name,
                            attributeName,
                            tostring(newValue)
                        )
                    )
                end))
            end
        end
    end

    addToolConnection(tool, tool.DescendantAdded:Connect(function(obj)
        if obj:IsA("Animation") or obj:IsA("RemoteEvent")
        or obj:IsA("RemoteFunction") or obj:IsA("ValueBase") then
            log("TOOL_OBJECT_ADDED", record, {
                class = obj.ClassName,
                name = obj.Name,
                path = safeFullName(obj),
                animationId = obj:IsA("Animation") and obj.AnimationId or nil
            }, record.name .. " • novo " .. obj.ClassName .. ": " .. obj.Name)
        end
    end))

    return record
end

local function scanWeapons(reason)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if character then
        for _, obj in ipairs(character:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj, reason or "CHARACTER_SCAN") end
        end
    end

    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj, reason or "BACKPACK_SCAN") end
        end
    end
end

local function connectAnimator(character)
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
        if not animator then return end

        State.Connections[#State.Connections + 1] = animator.AnimationPlayed:Connect(function(track)
            local animation = track.Animation
            local tool = State.ActiveTool
            local record = tool and State.Tools[tool] or nil

            local animationName = nil
            local animationId = nil
            local trackName = nil
            local priority = nil
            local speed = nil
            local length = nil

            pcall(function()
                animationName = animation and animation.Name or nil
            end)

            pcall(function()
                animationId = animation and animation.AnimationId or nil
            end)

            pcall(function()
                trackName = track.Name
            end)

            pcall(function()
                priority = tostring(track.Priority)
            end)

            pcall(function()
                speed = track.Speed
            end)

            pcall(function()
                length = track.Length
            end)

            local info = {
                time = now(),
                toolId = record and record.id or nil,
                toolName = record and record.name or nil,
                animationName = animationName,
                animationId = animationId,
                trackName = trackName,
                priority = priority,
                speed = speed,
                length = length
            }

            State.Animations[#State.Animations + 1] = info
            log("ANIMATION_PLAYED", record, info,
                "Animação: " .. tostring(info.animationName or info.trackName))
        end)
    end)
end

local function connectContainers()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        State.Connections[#State.Connections + 1] = backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then task.defer(registerTool, child, "BACKPACK_ADDED") end
        end)
    end

    if LocalPlayer.Character then
        State.Connections[#State.Connections + 1] = LocalPlayer.Character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.defer(function()
                    local r = registerTool(child, "CHARACTER_ADDED")
                    if r then State.ActiveTool = child end
                end)
            end
        end)
        connectAnimator(LocalPlayer.Character)
    end
end

State.Connections[#State.Connections + 1] = LocalPlayer.CharacterAdded:Connect(function(character)
    State.ActiveTool = nil
    task.wait(0.5)
    connectAnimator(character)

    State.Connections[#State.Connections + 1] = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(function()
                local r = registerTool(child, "RESPAWN_CHARACTER_ADDED")
                if r then State.ActiveTool = child end
            end)
        end
    end)

    scanWeapons("RESPAWN_SCAN")
end)

local function startDiagnostic()
    if State.Recording then return end

    State.Events = {}
    State.Animations = {}
    State.Errors = 0

    for _, r in ipairs(State.ToolList) do
        r.shotIntervals = {}
        r.reloads = {}
        r.activationSummaries = {}
        r.attributeChanges = {}
        r.activationCount = 0
        r.activationShotCount = 0
        r.totalAmmoDrops = 0
        r.lastActivation = nil
        r.lastDeactivation = nil
        r.lastAmmoDrop = nil
        r.reloadStarted = nil
    end

    State.Recording = true
    State.EverStarted = true
    State.StartUnix = unix()
    State.EndUnix = nil

    log("DIAGNOSTIC_STARTED", nil, {}, "Weapon Research V1.1 iniciado.")
    scanBlasterSystem()
    scanWeapons("DIAGNOSTIC_START")
end

local function stopDiagnostic()
    if not State.Recording then return end
    log("DIAGNOSTIC_STOPPED", nil, {}, "Weapon Research V1.1 parado.")
    State.Recording = false
    State.EndUnix = unix()
end

local function intervalSummary(values)
    if #values == 0 then return {count = 0} end
    local mn, mx, sum = math.huge, 0, 0
    for _, v in ipairs(values) do
        mn = math.min(mn, v)
        mx = math.max(mx, v)
        sum = sum + v
    end
    return {count = #values, min = mn, max = mx, average = sum / #values}
end

local function serializeTools()
    local out = {}
    for _, r in ipairs(State.ToolList) do
        local tool = r.tool
        out[#out + 1] = {
            id = r.id,
            name = r.name,
            firstPath = r.path,
            currentPath = tool and tool.Parent and safeFullName(tool) or nil,
            initialAttributes = r.initialAttributes,
            finalAttributes = tool and tool.Parent and snapshotAttributes(tool) or nil,
            ammoAttribute = r.ammoAttribute,
            rateAttribute = r.rateAttribute,
            rateOfFire = tool and tool.Parent and select(1, readRate(tool)) or r.rate,
            autoAttribute = r.autoAttribute,
            autoMode = tool and tool.Parent and select(1, readAuto(tool)) or r.auto,
            activationCount = r.activationCount,
            totalAmmoDrops = r.totalAmmoDrops,
            shotIntervalSummary = intervalSummary(r.shotIntervals),
            shotIntervals = r.shotIntervals,
            reloads = r.reloads,
            activationSummaries = r.activationSummaries,
            attributeChanges = r.attributeChanges
        }
    end
    return out
end

local function buildExport()
    return {
        format = "Psicosenatico Weapon Research",
        version = VERSION,
        collectionMode = "EVENT_DRIVEN_OBSERVATIONAL",
        generatedAtUnix = unix(),
        description = "Estudo observacional de Tool, munição, cadência, reload, animações e BlasterSystem.",
        game = {placeId = game.PlaceId, gameId = game.GameId, jobId = game.JobId},
        diagnostic = {
            startedAtUnix = State.StartUnix,
            finishedAtUnix = State.EndUnix,
            status = State.Recording and "RECORDING" or "STOPPED"
        },
        summary = {
            weaponsDetected = #State.ToolList,
            events = #State.Events,
            animations = #State.Animations,
            errors = State.Errors
        },
        blasterSystem = State.BlasterSystem,
        weapons = serializeTools(),
        animations = State.Animations,
        events = State.Events
    }
end

local function jsonExport()
    local ok, data = pcall(function() return HttpService:JSONEncode(buildExport()) end)
    return ok and data or nil, ok and nil or data
end

--==============================================================
-- INTERFACE
--==============================================================

local C = {
    bg=Color3.fromRGB(10,10,13), panel=Color3.fromRGB(19,19,24),
    panel2=Color3.fromRGB(28,28,35), text=Color3.fromRGB(245,245,248),
    sub=Color3.fromRGB(158,158,172), blue=Color3.fromRGB(22,55,105),
    blue2=Color3.fromRGB(32,82,145), green=Color3.fromRGB(65,210,118),
    red=Color3.fromRGB(235,38,52), yellow=Color3.fromRGB(242,184,57)
}

local function new(class, props)
    local o = Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    return o
end

local function round(o,r)
    new("UICorner",{Parent=o,CornerRadius=UDim.new(0,r or 8)})
end

local function label(parent,text,size,pos,textSize)
    return new("TextLabel",{
        Parent=parent,BackgroundTransparency=1,Text=text,Size=size,Position=pos,
        TextColor3=C.text,Font=Enum.Font.Gotham,TextSize=textSize or 10,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center
    })
end

local Main = new("Frame",{
    Parent=Gui,BackgroundColor3=C.bg,BorderSizePixel=0,
    AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5)
})
round(Main,16)

local function resize()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=camera.ViewportSize
    local w=math.min(math.floor(v.X*0.90),v.X-20)
    local h=math.min(math.floor(v.Y*0.70),v.Y-20)
    Main.Size=UDim2.fromOffset(math.max(300,w),math.max(260,h))
end
resize()

if workspace.CurrentCamera then
    local okResize, resizeSignal = pcall(function()
        return workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")
    end)
    if okResize and resizeSignal then
        State.Connections[#State.Connections + 1] = resizeSignal:Connect(resize)
    end
end

local Header=new("Frame",{Parent=Main,Size=UDim2.new(1,0,0,61),BackgroundColor3=C.panel,BorderSizePixel=0})
round(Header,16)
label(Header,"PSICOSENATICO • WEAPON RESEARCH",UDim2.new(1,-145,0,25),UDim2.fromOffset(18,7),16)
local VL=label(Header,"V1",UDim2.fromOffset(30,17),UDim2.fromOffset(18,34),9); VL.TextColor3=C.blue2
local ST=label(Header,"DISPARO • CADÊNCIA • RELOAD • ANIMAÇÕES",UDim2.new(1,-185,0,17),UDim2.fromOffset(45,34),8); ST.TextColor3=C.sub

local Min=new("TextButton",{Parent=Header,Size=UDim2.fromOffset(38,36),Position=UDim2.new(1,-88,0,12),Text="—",BackgroundColor3=C.panel2,TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=19,BorderSizePixel=0}); round(Min,10)
local Close=new("TextButton",{Parent=Header,Size=UDim2.fromOffset(38,36),Position=UDim2.new(1,-44,0,12),Text="×",BackgroundColor3=C.red,TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=21,BorderSizePixel=0}); round(Close,10)

local Status=label(Main,"Scanner pronto • somente observação.",UDim2.new(1,-36,0,21),UDim2.fromOffset(18,67),9); Status.TextColor3=C.sub

local Start=new("TextButton",{Parent=Main,Size=UDim2.new(0.5,-20,0,40),Position=UDim2.fromOffset(18,91),Text="INICIAR DIAGNÓSTICO",BackgroundColor3=C.blue2,TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0}); round(Start,9)
local Export=new("TextButton",{Parent=Main,Size=UDim2.new(0.5,-20,0,40),Position=UDim2.new(0.5,2,0,91),Text="EXPORTAR DIAGNÓSTICO",BackgroundColor3=C.blue,TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0}); round(Export,9)

local Summary=label(Main,"",UDim2.new(1,-36,0,25),UDim2.fromOffset(18,137),9); Summary.TextColor3=C.sub
local Viewer=new("ScrollingFrame",{Parent=Main,Position=UDim2.fromOffset(18,168),Size=UDim2.new(1,-36,1,-177),BackgroundColor3=C.panel,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5,ScrollingDirection=Enum.ScrollingDirection.Y}); round(Viewer,10)
local Text=new("TextLabel",{Parent=Viewer,BackgroundTransparency=1,Position=UDim2.fromOffset(10,8),Size=UDim2.new(1,-20,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text="",TextColor3=C.text,Font=Enum.Font.Code,TextSize=9,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top})

local Mini=new("TextButton",{Parent=Gui,Visible=false,Size=UDim2.fromOffset(58,58),Position=UDim2.fromScale(0.07,0.25),Text="W1.1",BackgroundColor3=C.blue,TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=12,BorderSizePixel=0}); round(Mini,18)

local function draggable(target,handle)
    local dragging,dragInput,dragStart,startPos=false,nil,nil,nil
    local function update(input)
        local d=input.Position-dragStart
        target.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
    State.Connections[#State.Connections+1]=handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=input.Position; startPos=target.Position
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    State.Connections[#State.Connections+1]=handle.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
    end)
    State.Connections[#State.Connections+1]=UserInputService.InputChanged:Connect(function(input)
        if input==dragInput and dragging then update(input) end
    end)
end
draggable(Main,Header); draggable(Mini,Mini)

local function updatePreview()
    Summary.Text=string.format("DIAGNÓSTICO: %s • ARMAS: %d • EVENTOS: %d • ANIMAÇÕES: %d • ERROS: %d",
        State.Recording and "GRAVANDO" or "PARADO",#State.ToolList,#State.Events,#State.Animations,State.Errors)

    local lines={
        "══════════════════════════════════════════",
        "PSICOSENATICO • WEAPON RESEARCH V1.1",
        "══════════════════════════════════════════","",
        "TESTE SUGERIDO",
        "  1. Semiautomática: vários cliques",
        "  2. Segure disparo alguns segundos",
        "  3. Recarregue",
        "  4. Repita com arma automática","",
        "ÚLTIMOS EVENTOS","══════════════════════════════════════════"
    }
    local s=math.max(1,#State.Live-120)
    for i=s,#State.Live do
        local x=State.Live[i]
        lines[#lines+1]=string.format("[%.2f] %-22s %s",x.time or 0,tostring(x.type),tostring(x.message))
    end
    Text.Text=table.concat(lines, "\n")
end

Start.Activated:Connect(function()
    if not State.Recording then
        startDiagnostic()
        Start.Text="PARAR DIAGNÓSTICO"
        Status.Text="Gravando • use a arma normalmente."
        Status.TextColor3=C.green
    else
        stopDiagnostic()
        Start.Text="INICIAR DIAGNÓSTICO"
        Status.Text="Diagnóstico parado • pronto para exportar."
        Status.TextColor3=C.sub
    end
    updatePreview()
end)

Export.Activated:Connect(function()
    if not State.EverStarted then
        Status.Text="Inicie o diagnóstico antes de exportar."
        Status.TextColor3=C.yellow
        return
    end

    local data,err=jsonExport()
    if not data then
        Status.Text="Falha ao gerar JSON: "..tostring(err)
        Status.TextColor3=C.red
        return
    end

    local filename="Psicosenatico_WeaponResearch_V1_1_"..tostring(game.PlaceId).."_"..tostring(os.time())..".json"
    local ok=false
    if typeof(writefile)=="function" then ok=pcall(function() writefile(filename,data) end) end
    if ok then
        Status.Text="✓ EXPORTADO: "..filename
        Status.TextColor3=C.green
    elseif typeof(setclipboard)=="function" and pcall(function() setclipboard(data) end) then
        Status.Text="✓ JSON COPIADO PARA A ÁREA DE TRANSFERÊNCIA."
        Status.TextColor3=C.green
    else
        Status.Text="writefile/setclipboard indisponíveis."
        Status.TextColor3=C.red
    end
end)

Min.Activated:Connect(function() Main.Visible=false; Mini.Visible=true end)
Mini.Activated:Connect(function() Mini.Visible=false; Main.Visible=true end)

local function cleanup()
    if State.Recording then stopDiagnostic() end
    for tool in pairs(State.ToolConnections) do disconnectTool(tool) end
    for _,c in ipairs(State.Connections) do pcall(function() c:Disconnect() end) end
    pcall(function() Gui:Destroy() end)
end
Close.Activated:Connect(cleanup)

connectContainers()
scanWeapons("INITIAL_SCAN")
log("SYSTEM",nil,{},"Weapon Research V1.1 inicializado.")
log("SYSTEM",nil,{},"Nenhuma arma é modificada pelo scanner.")
updatePreview()

task.spawn(function()
    while Gui.Parent do
        pcall(updatePreview)
        task.wait(1)
    end
end)

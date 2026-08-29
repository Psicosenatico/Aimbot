--==============================================================
-- PSICOSENATICO • WEAPON RESEARCH V2.1
-- BULLET NOCLIP / WALL PENETRATION • MINIMALISTA E DIRECIONADO
--
-- OBJETIVO
-- Fechar a única lacuna restante da V2:
-- entender a arquitetura client-visible relacionada a:
--   • castRays
--   • canPierce
--   • Shoot / ShootProjectile
--   • ReplicateProjectile / ProjectileHit
--   • diferenças observáveis entre disparo livre e disparo contra obstáculo
--
-- IMPORTANTE
-- • Scanner observacional
-- • NÃO altera raycast, arma, dano, remotes ou colisão
-- • NÃO chama FireServer / InvokeServer
-- • NÃO modifica ModuleScripts
-- • Event-driven; baixo custo
--
-- PROTOCOLO RECOMENDADO
-- 1) Equipar uma arma Hitscan
-- 2) Atirar 3x sem obstáculo
-- 3) Atirar 3x diretamente em uma parede
-- 4) Atirar 3x em alvo com parede entre você e ele
-- 5) Atirar 3x no mesmo alvo sem parede
-- 6) Exportar JSON
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "V2.1",
    GUI_NAME = "PsicosenaticoWeaponResearch_V2_1",
    MAX_EVENTS = 4000,
    MAX_LIVE = 140,
    UI_REFRESH = 0.8,

    WATCH_ATTRS = {
        "projectileType",
        "raysPerShot",
        "rayRadius",
        "range",
        "spread",
        "damage",
        "fireMode",
        "rateOfFire",
        "_ammo",
        "_reloading",
        "reloadTime"
    },

    RELEVANT_TERMS = {
        "ray",
        "pierce",
        "cast",
        "shoot",
        "projectile",
        "hit",
        "damage",
        "impact",
        "replicate"
    }
}

local function parentGui()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then return p end
    end
    return CoreGui
end

local Parent = parentGui()
for _,v in ipairs(Parent:GetChildren()) do
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
    Errors = 0,

    Events = {},
    Live = {},

    ActiveTool = nil,
    Tools = {},
    ToolList = {},
    ToolConnections = {},
    Connections = {},

    Architecture = {
        blasterFound = false,
        rootPath = nil,
        objects = {},
        remotes = {},
        modules = {},
        namedTargets = {},
        snapshots = {}
    },

    Input = {
        held = false,
        startedAt = nil
    },

    TestMarkers = {}
}

local function tnow() return os.clock() end
local function unow() return os.time() end

local function safeFullName(obj)
    local ok, v = pcall(function() return obj:GetFullName() end)
    return ok and tostring(v) or tostring(obj and obj.Name or "UNKNOWN")
end

local function safeAttr(obj,name)
    local ok,v=pcall(function() return obj:GetAttribute(name) end)
    return ok and v or nil
end

local function snapshotAttributes(obj)
    local out={}
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for k,v in pairs(attrs) do
            if typeof(v)=="Instance" then
                out[tostring(k)]=safeFullName(v)
            else
                out[tostring(k)]=v
            end
        end
    end
    return out
end

local function pushLive(tp,msg)
    S.Live[#S.Live+1]={time=tnow(),type=tp,message=tostring(msg or "")}
    while #S.Live>CONFIG.MAX_LIVE do
        table.remove(S.Live,1)
    end
end

local function log(tp,toolRec,data,msg)
    pushLive(tp,msg)
    if tp=="ERROR" then S.Errors+=1 end
    if not S.Recording then return end
    if #S.Events>=CONFIG.MAX_EVENTS then return end

    S.Events[#S.Events+1]={
        unix=unow(),
        time=tnow(),
        type=tp,
        toolId=toolRec and toolRec.id or nil,
        toolName=toolRec and toolRec.name or nil,
        data=data or {}
    }
end

local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("projectileType")~=nil then return true end
    if tool:GetAttribute("rateOfFire")~=nil then return true end
    if tool:GetAttribute("_ammo")~=nil then return true end
    return false
end

local function readToolSnapshot(tool)
    local out={
        path=safeFullName(tool),
        name=tool.Name,
        attributes={}
    }
    for _,a in ipairs(CONFIG.WATCH_ATTRS) do
        out.attributes[a]=safeAttr(tool,a)
    end
    return out
end

local function termMatch(name)
    local lower=string.lower(tostring(name or ""))
    for _,term in ipairs(CONFIG.RELEVANT_TERMS) do
        if string.find(lower,term,1,true) then
            return true,term
        end
    end
    return false,nil
end

local function scanArchitecture(reason)
    local root=ReplicatedStorage:FindFirstChild("BlasterSystem")
    local arch={
        reason=reason,
        time=tnow(),
        found=root~=nil,
        rootPath=root and safeFullName(root) or nil,
        objects={},
        remotes={},
        modules={},
        namedTargets={}
    }

    if root then
        S.Architecture.blasterFound=true
        S.Architecture.rootPath=safeFullName(root)

        for _,obj in ipairs(root:GetDescendants()) do
            local matched,term=termMatch(obj.Name)
            local special=
                obj:IsA("RemoteEvent")
                or obj:IsA("RemoteFunction")
                or obj:IsA("ModuleScript")

            if matched or special then
                local item={
                    class=obj.ClassName,
                    name=obj.Name,
                    path=safeFullName(obj),
                    matchedTerm=term,
                    attributes=snapshotAttributes(obj)
                }

                arch.objects[#arch.objects+1]=item
                S.Architecture.objects[item.path]=item

                if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    arch.remotes[#arch.remotes+1]=item
                    S.Architecture.remotes[item.path]=item
                end

                if obj:IsA("ModuleScript") then
                    arch.modules[#arch.modules+1]=item
                    S.Architecture.modules[item.path]=item
                end

                local lname=string.lower(obj.Name)
                if lname=="canpierce" or lname=="castrays"
                    or lname=="shoot" or lname=="shootprojectile"
                    or lname=="replicateprojectile" or lname=="projectilehit"
                then
                    arch.namedTargets[#arch.namedTargets+1]=item
                    S.Architecture.namedTargets[item.path]=item
                end
            end
        end
    end

    S.Architecture.snapshots[#S.Architecture.snapshots+1]=arch

    log("ARCHITECTURE_SCAN",nil,{
        reason=reason,
        found=arch.found,
        objectCount=#arch.objects,
        remoteCount=#arch.remotes,
        moduleCount=#arch.modules,
        namedTargetCount=#arch.namedTargets
    },arch.found and ("BlasterSystem mapeado: "..#arch.namedTargets.." alvos-chave") or "BlasterSystem ausente")
end

local function addToolConn(tool,c)
    S.ToolConnections[tool]=S.ToolConnections[tool] or {}
    table.insert(S.ToolConnections[tool],c)
end

local function disconnectTool(tool)
    local list=S.ToolConnections[tool]
    if not list then return end
    for _,c in ipairs(list) do
        pcall(function() c:Disconnect() end)
    end
    S.ToolConnections[tool]=nil
end

local function registerTool(tool,reason)
    if not isWeapon(tool) then return nil end
    if S.Tools[tool] then return S.Tools[tool] end

    local r={
        id=#S.ToolList+1,
        tool=tool,
        name=tool.Name,
        firstPath=safeFullName(tool),
        reason=reason,
        initial=readToolSnapshot(tool),
        equippedAt=nil,
        activations=0,
        activationTimes={},
        ammoChanges={},
        attrChanges={}
    }

    S.Tools[tool]=r
    S.ToolList[#S.ToolList+1]=r

    log("WEAPON_FOUND",r,{
        reason=reason,
        snapshot=r.initial
    },"Arma: "..r.name)

    addToolConn(tool,tool.Equipped:Connect(function()
        S.ActiveTool=tool
        r.equippedAt=tnow()
        log("WEAPON_EQUIPPED",r,{
            snapshot=readToolSnapshot(tool)
        },r.name.." equipada")
    end))

    addToolConn(tool,tool.Unequipped:Connect(function()
        if S.ActiveTool==tool then S.ActiveTool=nil end
        log("WEAPON_UNEQUIPPED",r,{},r.name.." desequipada")
    end))

    addToolConn(tool,tool.Activated:Connect(function()
        r.activations+=1
        local t=tnow()
        r.activationTimes[#r.activationTimes+1]=t

        log("TOOL_ACTIVATED",r,{
            activation=r.activations,
            fireHeld=S.Input.held,
            projectileType=safeAttr(tool,"projectileType"),
            raysPerShot=safeAttr(tool,"raysPerShot"),
            rayRadius=safeAttr(tool,"rayRadius"),
            range=safeAttr(tool,"range"),
            ammo=safeAttr(tool,"_ammo")
        },r.name.." Activated")
    end))

    for _,attr in ipairs(CONFIG.WATCH_ATTRS) do
        local ok,sig=pcall(function()
            return tool:GetAttributeChangedSignal(attr)
        end)

        if ok and sig then
            addToolConn(tool,sig:Connect(function()
                local v=safeAttr(tool,attr)
                local rec={time=tnow(),name=attr,value=v}
                r.attrChanges[#r.attrChanges+1]=rec

                if attr=="_ammo" then
                    r.ammoChanges[#r.ammoChanges+1]=rec
                end

                log("ATTRIBUTE_CHANGED",r,rec,r.name.." "..attr.."="..tostring(v))
            end))
        end
    end

    return r
end

local function scanWeapons(reason)
    local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
    local character=LocalPlayer.Character

    if backpack then
        for _,obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj,reason or "BACKPACK_SCAN") end
        end
    end

    if character then
        for _,obj in ipairs(character:GetChildren()) do
            if obj:IsA("Tool") then registerTool(obj,reason or "CHARACTER_SCAN") end
        end
    end
end

--==============================================================
-- ANIMATION OBSERVATION
--==============================================================

local function connectAnimator(character)
    task.spawn(function()
        local hum=character:WaitForChild("Humanoid",5)
        if not hum then return end

        local animator=hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator",5)
        if not animator then return end

        S.Connections[#S.Connections+1]=animator.AnimationPlayed:Connect(function(track)
            local tool=S.ActiveTool
            local r=tool and S.Tools[tool] or nil

            local name,id,length,speed,priority=nil,nil,nil,nil,nil
            pcall(function() name=track.Animation and track.Animation.Name or track.Name end)
            pcall(function() id=track.Animation and track.Animation.AnimationId or nil end)
            pcall(function() length=track.Length end)
            pcall(function() speed=track.Speed end)
            pcall(function() priority=tostring(track.Priority) end)

            local lower=string.lower(tostring(name or ""))
            if string.find(lower,"fire",1,true)
                or string.find(lower,"reload",1,true)
            then
                log("RELEVANT_ANIMATION",r,{
                    animationName=name,
                    animationId=id,
                    length=length,
                    speed=speed,
                    priority=priority
                },tostring(name))
            end
        end)
    end)
end

--==============================================================
-- TEST MARKERS
--==============================================================

local function addMarker(kind)
    local tool=S.ActiveTool
    local r=tool and S.Tools[tool] or nil

    local marker={
        unix=unow(),
        time=tnow(),
        kind=kind,
        toolId=r and r.id or nil,
        toolName=r and r.name or nil,
        snapshot=tool and readToolSnapshot(tool) or nil
    }

    S.TestMarkers[#S.TestMarkers+1]=marker
    log("TEST_MARKER",r,marker,"MARCADOR: "..kind)
end

--==============================================================
-- INPUT CORRELATION
--==============================================================

S.Connections[#S.Connections+1]=UserInputService.InputBegan:Connect(function(input,processed)
    if processed then return end

    if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch
    then
        S.Input.held=true
        S.Input.startedAt=tnow()

        local tool=S.ActiveTool
        local r=tool and S.Tools[tool] or nil

        log("INPUT_FIRE_BEGIN",r,{
            inputType=tostring(input.UserInputType)
        },r and (r.name.." input BEGIN") or "input BEGIN")
    end
end)

S.Connections[#S.Connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch
    then
        local duration=S.Input.startedAt and (tnow()-S.Input.startedAt) or nil
        S.Input.held=false

        local tool=S.ActiveTool
        local r=tool and S.Tools[tool] or nil

        log("INPUT_FIRE_END",r,{
            inputType=tostring(input.UserInputType),
            duration=duration
        },r and (r.name.." input END") or "input END")
    end
end)

--==============================================================
-- CONTAINER MONITORING
--==============================================================

local function connectContainers()
    local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        S.Connections[#S.Connections+1]=backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.defer(registerTool,child,"BACKPACK_ADDED")
            end
        end)
    end

    local character=LocalPlayer.Character
    if character then
        S.Connections[#S.Connections+1]=character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.defer(function()
                    local r=registerTool(child,"CHARACTER_ADDED")
                    if r then S.ActiveTool=child end
                end)
            end
        end)

        connectAnimator(character)
    end
end

S.Connections[#S.Connections+1]=LocalPlayer.CharacterAdded:Connect(function(character)
    S.ActiveTool=nil
    task.wait(0.35)

    connectAnimator(character)

    S.Connections[#S.Connections+1]=character.ChildAdded:Connect(function(child)
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
-- SESSION
--==============================================================

local function resetSession()
    S.Events={}
    S.TestMarkers={}
    S.Errors=0

    for _,r in ipairs(S.ToolList) do
        r.activations=0
        r.activationTimes={}
        r.ammoChanges={}
        r.attrChanges={}
    end
end

local function startDiagnostic()
    if S.Recording then return end

    resetSession()
    S.Started=true
    S.Recording=true
    S.StartUnix=unow()
    S.EndUnix=nil

    log("DIAGNOSTIC_STARTED",nil,{},"Weapon Research V2.1 iniciado")
    scanArchitecture("DIAGNOSTIC_START")
    scanWeapons("DIAGNOSTIC_START")
end

local function stopDiagnostic()
    if not S.Recording then return end

    scanArchitecture("DIAGNOSTIC_STOP")
    log("DIAGNOSTIC_STOPPED",nil,{},"Weapon Research V2.1 parado")

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
            reason=r.reason,

            initial=r.initial,
            final=tool and tool.Parent and readToolSnapshot(tool) or nil,

            activations=r.activations,
            activationTimes=r.activationTimes,
            ammoChanges=r.ammoChanges,
            attributeChanges=r.attrChanges
        }
    end

    return out
end

local function buildExport()
    local named={}
    for _,snapshot in ipairs(S.Architecture.snapshots) do
        for _,item in ipairs(snapshot.namedTargets or {}) do
            named[item.path]=item
        end
    end

    local namedList={}
    for _,item in pairs(named) do
        namedList[#namedList+1]=item
    end
    table.sort(namedList,function(a,b)
        return tostring(a.path)<tostring(b.path)
    end)

    return {
        format="Psicosenatico Weapon Research",
        version=CONFIG.VERSION,
        focus="BULLET_NOCLIP_WALL_PENETRATION",
        generatedAtUnix=unow(),

        diagnostic={
            status=S.Recording and "RECORDING" or "STOPPED",
            startedAtUnix=S.StartUnix,
            finishedAtUnix=S.EndUnix
        },

        protocol={
            "3 SHOTS_CLEAR",
            "3 SHOTS_WALL",
            "3 SHOTS_TARGET_BEHIND_WALL",
            "3 SHOTS_SAME_TARGET_CLEAR"
        },

        summary={
            weaponsDetected=#S.ToolList,
            events=#S.Events,
            markers=#S.TestMarkers,
            errors=S.Errors,
            blasterFound=S.Architecture.blasterFound
        },

        architecture={
            rootPath=S.Architecture.rootPath,
            namedTargets=namedList,
            snapshots=S.Architecture.snapshots
        },

        tools=serializeTools(),
        testMarkers=S.TestMarkers,
        events=S.Events,

        limitations={
            "Scanner observacional; não lê automaticamente o source interno de ModuleScripts.",
            "Não intercepta FireServer/InvokeServer.",
            "Não altera canPierce/castRays.",
            "Marque manualmente cada fase para permitir correlação temporal."
        }
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
        Parent=parent,
        BackgroundTransparency=1,
        Text=text,
        Size=size,
        Position=pos,
        TextColor3=C.text,
        Font=Enum.Font.Gotham,
        TextSize=textSize or 10,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center
    })
end

local Main=new("Frame",{
    Parent=Gui,
    BackgroundColor3=C.bg,
    BorderSizePixel=0,
    AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5)
})
round(Main,15)

local function resize()
    local cam=Workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    local w=math.min(math.floor(v.X*0.92),v.X-16)
    local h=math.min(math.floor(v.Y*0.70),v.Y-16)
    Main.Size=UDim2.fromOffset(math.max(310,w),math.max(270,h))
end
resize()

local Header=new("Frame",{
    Parent=Main,
    Size=UDim2.new(1,0,0,58),
    BackgroundColor3=C.panel,
    BorderSizePixel=0
})
round(Header,15)

lbl(Header,"PSICOSENATICO • WEAPON RESEARCH",UDim2.new(1,-140,0,24),UDim2.fromOffset(16,6),15)
local V=lbl(Header,"V2.1",UDim2.fromOffset(38,16),UDim2.fromOffset(16,34),9); V.TextColor3=C.blue2
local Sub=lbl(Header,"WALL PENETRATION",UDim2.new(1,-185,0,16),UDim2.fromOffset(56,34),8); Sub.TextColor3=C.sub

local Min=new("TextButton",{
    Parent=Header,
    Size=UDim2.fromOffset(36,34),
    Position=UDim2.new(1,-84,0,11),
    Text="—",
    BackgroundColor3=C.panel2,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=18,
    BorderSizePixel=0
}); round(Min,9)

local Close=new("TextButton",{
    Parent=Header,
    Size=UDim2.fromOffset(36,34),
    Position=UDim2.new(1,-42,0,11),
    Text="×",
    BackgroundColor3=C.red,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=20,
    BorderSizePixel=0
}); round(Close,9)

local Status=lbl(Main,"Pronto • scanner observacional.",UDim2.new(1,-32,0,20),UDim2.fromOffset(16,62),9)
Status.TextColor3=C.sub

local Start=new("TextButton",{
    Parent=Main,
    Size=UDim2.new(0.34,-12,0,36),
    Position=UDim2.fromOffset(16,86),
    Text="INICIAR",
    BackgroundColor3=C.blue2,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=10,
    BorderSizePixel=0
}); round(Start,8)

local Export=new("TextButton",{
    Parent=Main,
    Size=UDim2.new(0.34,-12,0,36),
    Position=UDim2.new(0.34,4,0,86),
    Text="EXPORTAR",
    BackgroundColor3=C.blue,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=10,
    BorderSizePixel=0
}); round(Export,8)

local Marker=new("TextButton",{
    Parent=Main,
    Size=UDim2.new(0.32,-12,0,36),
    Position=UDim2.new(0.68,0,0,86),
    Text="MARCADOR",
    BackgroundColor3=C.panel2,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=10,
    BorderSizePixel=0
}); round(Marker,8)

local Phase=lbl(Main,"FASE: CLEAR",UDim2.new(1,-32,0,20),UDim2.fromOffset(16,128),9)
Phase.TextColor3=C.yellow

local Summary=lbl(Main,"",UDim2.new(1,-32,0,20),UDim2.fromOffset(16,147),9)
Summary.TextColor3=C.sub

local Viewer=new("ScrollingFrame",{
    Parent=Main,
    Position=UDim2.fromOffset(16,171),
    Size=UDim2.new(1,-32,1,-180),
    BackgroundColor3=C.panel,
    BorderSizePixel=0,
    CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ScrollBarThickness=5,
    ScrollingDirection=Enum.ScrollingDirection.Y
}); round(Viewer,9)

local Text=new("TextLabel",{
    Parent=Viewer,
    BackgroundTransparency=1,
    Position=UDim2.fromOffset(9,7),
    Size=UDim2.new(1,-18,0,0),
    AutomaticSize=Enum.AutomaticSize.Y,
    Text="",
    TextColor3=C.text,
    Font=Enum.Font.Code,
    TextSize=9,
    TextWrapped=false,
    TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top
})

local Mini=new("TextButton",{
    Parent=Gui,
    Visible=false,
    Size=UDim2.fromOffset(58,58),
    Position=UDim2.fromScale(0.06,0.24),
    Text="W2.1",
    BackgroundColor3=C.blue,
    TextColor3=C.text,
    Font=Enum.Font.GothamBold,
    TextSize=10,
    BorderSizePixel=0
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

local phases={
    "CLEAR",
    "WALL",
    "TARGET_BEHIND_WALL",
    "TARGET_CLEAR"
}
local phaseIndex=1

local function updatePreview()
    Summary.Text=string.format(
        "REC:%s • ARMAS:%d • EVT:%d • MARK:%d • ERR:%d",
        S.Recording and "ON" or "OFF",
        #S.ToolList,#S.Events,#S.TestMarkers,S.Errors
    )

    local lines={
        "WEAPON RESEARCH V2.1",
        "──────────────────────────────────────",
        "FOCO: BULLET NOCLIP / WALL PENETRATION",
        "",
        "PROTOCOLO",
        "1 CLEAR: 3 tiros sem obstáculo",
        "2 WALL: 3 tiros direto na parede",
        "3 TARGET_BEHIND_WALL: 3 tiros",
        "4 TARGET_CLEAR: 3 tiros no mesmo alvo",
        "",
        "Use MARCADOR antes de cada bloco.",
        "",
        "ALVOS DE ARQUITETURA",
        "• castRays",
        "• canPierce",
        "• Shoot / ShootProjectile",
        "• ReplicateProjectile / ProjectileHit",
        "",
        "ÚLTIMOS EVENTOS",
        "──────────────────────────────────────"
    }

    local s=math.max(1,#S.Live-90)
    for i=s,#S.Live do
        local x=S.Live[i]
        lines[#lines+1]=string.format("[%.3f] %-19s %s",x.time or 0,tostring(x.type),tostring(x.message))
    end

    Text.Text=table.concat(lines,"\n")
end

Start.Activated:Connect(function()
    if not S.Recording then
        startDiagnostic()
        Start.Text="PARAR"
        Status.Text="Gravando • siga o protocolo."
        Status.TextColor3=C.green
    else
        stopDiagnostic()
        Start.Text="INICIAR"
        Status.Text="Parado • dados preservados."
        Status.TextColor3=C.sub
    end
    updatePreview()
end)

Marker.Activated:Connect(function()
    local phase=phases[phaseIndex]
    addMarker(phase)

    phaseIndex+=1
    if phaseIndex>#phases then
        phaseIndex=1
    end

    Phase.Text="FASE: "..phases[phaseIndex]
    Status.Text="Marcado: "..phase
    Status.TextColor3=C.yellow

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

    local filename="Psicosenatico_WeaponResearch_V2_1_"..tostring(game.PlaceId).."_"..tostring(os.time())..".json"

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
    local ok,sig=pcall(function()
        return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")
    end)
    if ok and sig then
        S.Connections[#S.Connections+1]=sig:Connect(resize)
    end
end

connectContainers()
scanWeapons("INITIAL_SCAN")
pushLive("SYSTEM","Weapon Research V2.1 pronto.")
pushLive("SYSTEM","Use MARCADOR antes de cada bloco de tiros.")
updatePreview()

task.spawn(function()
    while Gui.Parent do
        pcall(updatePreview)
        task.wait(CONFIG.UI_REFRESH)
    end
end)

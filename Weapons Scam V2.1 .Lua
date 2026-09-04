--==============================================================
-- PSICOSENATICO • PESQUISA DE ARMAS V2.2
-- PENETRAÇÃO DE PAREDE • DIAGNÓSTICO CIRÚRGICO / OBSERVACIONAL
--
-- OBJETIVO
-- • mapear castRays / canPierce e remotes relacionados
-- • tentar ler Source somente se o ambiente permitir
-- • comparar quatro cenários com a mesma arma equipada
-- • registrar raycast local de referência por gatilho e por gasto de munição
--
-- SEGURANÇA DA COLETA
-- • não altera arma, dano, raycast, colisão ou módulos
-- • não executa ModuleScripts via require()
-- • não chama FireServer / InvokeServer
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "V2.2",
    GUI_NAME = "PsicosenaticoWeaponResearch_V2_2",
    MAX_EVENTS = 1800,
    MAX_LIVE = 90,
    UI_REFRESH = 0.8,
    PHASES = {"CLEAR", "WALL", "TARGET_BEHIND_WALL", "TARGET_CLEAR"},
    PHASE_LABELS = {
        CLEAR = "LIVRE",
        WALL = "PAREDE",
        TARGET_BEHIND_WALL = "ALVO ATRÁS DA PAREDE",
        TARGET_CLEAR = "ALVO LIVRE"
    },
    WATCH_ATTRS = {
        "_ammo", "projectileType", "raysPerShot", "rayRadius",
        "range", "fireMode", "rateOfFire", "damage", "spread"
    }
}

--==============================================================
-- CONTROLE DE INSTÂNCIA / LIMPEZA DE VERSÕES ANTERIORES
--==============================================================

local RuntimeEnv = _G
if typeof(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        RuntimeEnv = env
    end
end

local RUNTIME_KEY = "__PSICOSENATICO_WEAPON_RESEARCH_RUNTIME"
local PreviousRuntime = RuntimeEnv[RUNTIME_KEY]
if type(PreviousRuntime) == "table" and type(PreviousRuntime.cleanup) == "function" then
    pcall(PreviousRuntime.cleanup)
end

local function getGuiParent()
    if typeof(gethui) == "function" then
        local ok, parent = pcall(gethui)
        if ok and parent then
            return parent
        end
    end
    return CoreGui
end

local GuiParent = getGuiParent()
local OLD_GUI_NAMES = {
    ["PsicosenaticoWeaponResearch_V2_1"] = true,
    [CONFIG.GUI_NAME] = true
}

for _, child in ipairs(GuiParent:GetChildren()) do
    if OLD_GUI_NAMES[child.Name] then
        pcall(function()
            child:Destroy()
        end)
    end
end

--==============================================================
-- ESTADO
--==============================================================

local S = {
    Recording = false,
    Started = false,
    StartUnix = nil,
    EndUnix = nil,
    Errors = 0,
    Events = {},
    Live = {},
    Markers = {},
    Shots = {},
    CurrentPhase = nil,
    ActiveTool = nil,
    Tools = {},
    ToolConnections = {},
    Connections = {},
    Architecture = nil,
    SourceInspection = {}
}

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

local function fullName(obj)
    local ok, value = pcall(function()
        return obj:GetFullName()
    end)
    return ok and tostring(value) or tostring(obj and obj.Name or "DESCONHECIDO")
end

local function attribute(obj, name)
    local ok, value = pcall(function()
        return obj:GetAttribute(name)
    end)
    return ok and value or nil
end

local function pushLive(kind, message)
    S.Live[#S.Live + 1] = {
        time = now(),
        type = kind,
        message = tostring(message or "")
    }
    while #S.Live > CONFIG.MAX_LIVE do
        table.remove(S.Live, 1)
    end
end

local function log(kind, data, message)
    pushLive(kind, message)
    if kind == "ERROR" then
        S.Errors += 1
    end
    if not S.Recording or #S.Events >= CONFIG.MAX_EVENTS then
        return
    end
    S.Events[#S.Events + 1] = {
        unix = unix(),
        time = now(),
        type = kind,
        phase = S.CurrentPhase,
        data = data or {}
    }
end

local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    return attribute(tool, "projectileType") ~= nil
        or attribute(tool, "rateOfFire") ~= nil
        or attribute(tool, "_ammo") ~= nil
end

local function weaponSnapshot(tool)
    if not tool then
        return nil
    end
    local attrs = {}
    for _, name in ipairs(CONFIG.WATCH_ATTRS) do
        attrs[name] = attribute(tool, name)
    end
    return {
        name = tool.Name,
        path = fullName(tool),
        attributes = attrs
    }
end

--==============================================================
-- ARQUITETURA: castRays / canPierce / remotes
--==============================================================

local function inspectSource(moduleScript)
    local result = {
        name = moduleScript.Name,
        path = fullName(moduleScript),
        sourceReadable = false,
        sourceLength = nil,
        source = nil,
        error = nil
    }
    local ok, source = pcall(function()
        return moduleScript.Source
    end)
    if ok and type(source) == "string" then
        result.sourceReadable = true
        result.sourceLength = #source
        result.source = source
    else
        result.error = tostring(source)
    end
    return result
end

local function inspectArchitecture(reason)
    local root = ReplicatedStorage:FindFirstChild("BlasterSystem")
    local result = {
        reason = reason,
        time = now(),
        found = root ~= nil,
        rootPath = root and fullName(root) or nil,
        targets = {},
        remotes = {},
        sourceInspection = {}
    }

    if not root then
        S.Architecture = result
        log("ARCHITECTURE_SCAN", {found = false, reason = reason}, "BlasterSystem não encontrado")
        return
    end

    local wanted = {
        canpierce = true,
        castrays = true,
        shoot = true,
        shootprojectile = true,
        replicateprojectile = true,
        projectilehit = true
    }

    for _, obj in ipairs(root:GetDescendants()) do
        if wanted[string.lower(obj.Name)] then
            local item = {
                name = obj.Name,
                class = obj.ClassName,
                path = fullName(obj)
            }
            result.targets[#result.targets + 1] = item

            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent") then
                result.remotes[#result.remotes + 1] = item
            end

            if obj:IsA("ModuleScript") then
                local sourceInfo = inspectSource(obj)
                result.sourceInspection[#result.sourceInspection + 1] = sourceInfo
                S.SourceInspection[sourceInfo.path] = sourceInfo
            end
        end
    end

    table.sort(result.targets, function(a, b)
        return a.path < b.path
    end)

    S.Architecture = result

    local readable = 0
    for _, item in ipairs(result.sourceInspection) do
        if item.sourceReadable then
            readable += 1
        end
    end

    log("ARCHITECTURE_SCAN", {
        reason = reason,
        targetCount = #result.targets,
        remoteCount = #result.remotes,
        readableSources = readable,
        moduleCount = #result.sourceInspection
    }, string.format(
        "Arquitetura: %d alvos • código legível %d/%d",
        #result.targets,
        readable,
        #result.sourceInspection
    ))
end

--==============================================================
-- RAYCAST LOCAL DE REFERÊNCIA
--==============================================================

local function hitDescription(result, origin)
    if not result then
        return nil
    end

    local instance = result.Instance
    local model = instance and instance:FindFirstAncestorOfClass("Model") or nil
    local humanoid = model and model:FindFirstChildOfClass("Humanoid") or nil

    return {
        instance = instance and fullName(instance) or nil,
        instanceName = instance and instance.Name or nil,
        instanceClass = instance and instance.ClassName or nil,
        model = model and fullName(model) or nil,
        modelName = model and model.Name or nil,
        hasHumanoid = humanoid ~= nil,
        material = tostring(result.Material),
        distance = (result.Position - origin).Magnitude,
        position = {result.Position.X, result.Position.Y, result.Position.Z},
        normal = {result.Normal.X, result.Normal.Y, result.Normal.Z}
    }
end

local function referenceRaycast(referenceTool)
    local camera = Workspace.CurrentCamera
    if not camera then
        return {ok = false, reason = "SEM_CAMERA"}
    end

    local viewport = camera.ViewportSize
    local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
    local range = tonumber(attribute(referenceTool or S.ActiveTool, "range")) or 2000
    local direction = ray.Direction.Unit * range

    local excluded = {camera}
    if LocalPlayer.Character then
        excluded[#excluded + 1] = LocalPlayer.Character
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excluded
    params.IgnoreWater = false

    local ok, first = pcall(function()
        return Workspace:Raycast(ray.Origin, direction, params)
    end)

    if not ok then
        return {ok = false, reason = tostring(first), range = range}
    end

    local output = {
        ok = true,
        hit = first ~= nil,
        origin = {ray.Origin.X, ray.Origin.Y, ray.Origin.Z},
        direction = {direction.X, direction.Y, direction.Z},
        range = range,
        firstHit = hitDescription(first, ray.Origin),
        nextHit = nil
    }

    -- Segunda leitura geométrica: ignora somente a primeira peça atingida.
    -- Não simula canPierce; serve para registrar o que está logo atrás.
    if first and first.Instance then
        local firstDistance = (first.Position - ray.Origin).Magnitude
        local remaining = range - firstDistance - 0.05
        if remaining > 0 then
            local excludedNext = {camera, first.Instance}
            if LocalPlayer.Character then
                excludedNext[#excludedNext + 1] = LocalPlayer.Character
            end

            local nextParams = RaycastParams.new()
            nextParams.FilterType = Enum.RaycastFilterType.Exclude
            nextParams.FilterDescendantsInstances = excludedNext
            nextParams.IgnoreWater = false

            local nextOrigin = first.Position + ray.Direction.Unit * 0.05
            local okNext, second = pcall(function()
                return Workspace:Raycast(nextOrigin, ray.Direction.Unit * remaining, nextParams)
            end)

            if okNext and second then
                output.nextHit = hitDescription(second, nextOrigin)
            end
        end
    end

    return output
end

--==============================================================
-- ARMAS / DISPAROS
--==============================================================

local function addToolConnection(tool, connection)
    S.ToolConnections[tool] = S.ToolConnections[tool] or {}
    table.insert(S.ToolConnections[tool], connection)
end

local function registerWeapon(tool, reason)
    if not isWeapon(tool) or S.Tools[tool] then
        return
    end

    S.Tools[tool] = {
        name = tool.Name,
        reason = reason,
        firstPath = fullName(tool),
        initial = weaponSnapshot(tool),
        lastAmmo = tonumber(attribute(tool, "_ammo"))
    }

    log("WEAPON_FOUND", {
        reason = reason,
        snapshot = weaponSnapshot(tool)
    }, "Arma identificada: " .. tool.Name)

    addToolConnection(tool, tool.Equipped:Connect(function()
        S.ActiveTool = tool
        local toolData = S.Tools[tool]
        if toolData then
            toolData.lastAmmo = tonumber(attribute(tool, "_ammo"))
        end
        log("WEAPON_EQUIPPED", {snapshot = weaponSnapshot(tool)}, tool.Name .. " equipada")
    end))

    addToolConnection(tool, tool.Unequipped:Connect(function()
        if S.ActiveTool == tool then
            S.ActiveTool = nil
        end
        log("WEAPON_UNEQUIPPED", {name = tool.Name}, tool.Name .. " desequipada")
    end))

    addToolConnection(tool, tool.Activated:Connect(function()
        local phaseLabel = CONFIG.PHASE_LABELS[S.CurrentPhase] or "SEM FASE"
        local reference = referenceRaycast(tool)
        log("SHOT_TRIGGER", {
            time = now(),
            unix = unix(),
            phase = S.CurrentPhase,
            weapon = weaponSnapshot(tool),
            referenceRay = reference
        }, string.format(
            "%s • %s • gatilho registrado",
            tool.Name,
            phaseLabel
        ))
    end))

    for _, attrName in ipairs(CONFIG.WATCH_ATTRS) do
        local ok, signal = pcall(function()
            return tool:GetAttributeChangedSignal(attrName)
        end)

        if ok and signal then
            addToolConnection(tool, signal:Connect(function()
                local value = attribute(tool, attrName)
                local toolData = S.Tools[tool]

                if attrName == "_ammo" and toolData then
                    local before = tonumber(toolData.lastAmmo)
                    local after = tonumber(value)

                    if before and after and after < before then
                        local shot = {
                            time = now(),
                            unix = unix(),
                            source = "AMMO_DECREASE",
                            phase = S.CurrentPhase,
                            ammoBefore = before,
                            ammoAfter = after,
                            ammoDelta = before - after,
                            weapon = weaponSnapshot(tool),
                            referenceRay = referenceRaycast(tool)
                        }
                        S.Shots[#S.Shots + 1] = shot

                        local phaseLabel = CONFIG.PHASE_LABELS[S.CurrentPhase] or "SEM FASE"
                        log("SHOT_AMMO_CONFIRMED", shot, string.format(
                            "%s • %s • munição %s→%s",
                            tool.Name,
                            phaseLabel,
                            tostring(before),
                            tostring(after)
                        ))
                    end

                    toolData.lastAmmo = after or value
                end

                log("ATTRIBUTE_CHANGED", {
                    weapon = tool.Name,
                    attribute = attrName,
                    value = value
                }, tool.Name .. " • " .. attrName .. "=" .. tostring(value))
            end))
        end
    end
end

local function scanWeapons(reason)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local character = LocalPlayer.Character

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                registerWeapon(item, reason or "BACKPACK_SCAN")
            end
        end
    end

    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") then
                registerWeapon(item, reason or "CHARACTER_SCAN")
                if isWeapon(item) then
                    S.ActiveTool = item
                end
            end
        end
    end
end

local function connectCharacter(character)
    S.Connections[#S.Connections + 1] = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(function()
                registerWeapon(child, "CHARACTER_ADDED")
                if isWeapon(child) then
                    S.ActiveTool = child
                end
            end)
        end
    end)
end

local function connectBackpack()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        return
    end

    S.Connections[#S.Connections + 1] = backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(registerWeapon, child, "BACKPACK_ADDED")
        end
    end)
end

if LocalPlayer.Character then
    connectCharacter(LocalPlayer.Character)
end
connectBackpack()

S.Connections[#S.Connections + 1] = LocalPlayer.CharacterAdded:Connect(function(character)
    S.ActiveTool = nil
    task.wait(0.35)
    connectCharacter(character)
    scanWeapons("RESPAWN_SCAN")
end)

--==============================================================
-- FASES / SESSÃO / EXPORTAÇÃO
--==============================================================

local function setPhase(phase)
    if not S.Recording then
        pushLive("AVISO", "Inicie a coleta antes de escolher uma fase.")
        return false
    end

    if not S.ActiveTool or not isWeapon(S.ActiveTool) then
        S.Errors += 1
        pushLive("ERRO", "Equipe uma arma antes de escolher a fase.")
        return false
    end

    S.CurrentPhase = phase
    local marker = {
        time = now(),
        unix = unix(),
        kind = phase,
        label = CONFIG.PHASE_LABELS[phase] or phase,
        weapon = weaponSnapshot(S.ActiveTool),
        referenceRay = referenceRaycast(S.ActiveTool)
    }
    S.Markers[#S.Markers + 1] = marker
    log("PHASE_MARKER", marker, "FASE: " .. marker.label)
    return true
end

local function startDiagnostic()
    if S.Recording then
        return
    end

    S.Events = {}
    S.Markers = {}
    S.Shots = {}
    S.Errors = 0
    S.CurrentPhase = nil
    S.SourceInspection = {}
    S.Started = true
    S.Recording = true
    S.StartUnix = unix()
    S.EndUnix = nil

    log("DIAGNOSTIC_STARTED", {}, "Pesquisa de Armas V2.2 iniciada")
    inspectArchitecture("DIAGNOSTIC_START")
    scanWeapons("DIAGNOSTIC_START")
end

local function stopDiagnostic()
    if not S.Recording then
        return
    end

    inspectArchitecture("DIAGNOSTIC_STOP")
    log("DIAGNOSTIC_STOPPED", {}, "Pesquisa de Armas V2.2 parada")
    S.Recording = false
    S.EndUnix = unix()
end

local function serializeTools()
    local output = {}
    for tool, data in pairs(S.Tools) do
        output[#output + 1] = {
            name = data.name,
            reason = data.reason,
            firstPath = data.firstPath,
            initial = data.initial,
            final = tool and tool.Parent and weaponSnapshot(tool) or nil
        }
    end
    table.sort(output, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return output
end

local function buildExport()
    return {
        format = "Psicosenatico Weapon Research",
        version = CONFIG.VERSION,
        focus = "BULLET_NOCLIP_WALL_PENETRATION",
        generatedAtUnix = unix(),
        diagnostic = {
            status = S.Recording and "RECORDING" or "STOPPED",
            startedAtUnix = S.StartUnix,
            finishedAtUnix = S.EndUnix
        },
        summary = {
            events = #S.Events,
            markers = #S.Markers,
            confirmedShotRecords = #S.Shots,
            errors = S.Errors
        },
        architecture = S.Architecture,
        sourceInspection = S.SourceInspection,
        tools = serializeTools(),
        markers = S.Markers,
        shots = S.Shots,
        events = S.Events,
        interpretationRules = {
            "referenceRay é somente uma leitura geométrica local do cenário.",
            "nextHit ignora somente a primeira peça atingida e não simula canPierce.",
            "Nenhum RemoteEvent é disparado por este diagnóstico.",
            "Nenhum ModuleScript é executado via require()."
        }
    }
end

local function encodeExport()
    local ok, data = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)
    if ok then
        return data, nil
    end
    return nil, data
end

--==============================================================
-- INTERFACE EM PORTUGUÊS
--==============================================================

local COLORS = {
    bg = Color3.fromRGB(10, 10, 13),
    panel = Color3.fromRGB(19, 19, 24),
    panel2 = Color3.fromRGB(28, 28, 35),
    text = Color3.fromRGB(245, 245, 248),
    sub = Color3.fromRGB(158, 158, 172),
    blue = Color3.fromRGB(22, 55, 105),
    blue2 = Color3.fromRGB(32, 82, 145),
    green = Color3.fromRGB(65, 210, 118),
    red = Color3.fromRGB(235, 38, 52),
    yellow = Color3.fromRGB(242, 184, 57)
}

local function new(className, props)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    return object
end

local function round(object, radius)
    new("UICorner", {
        Parent = object,
        CornerRadius = UDim.new(0, radius or 8)
    })
end

local function label(parent, text, size, position, textSize)
    return new("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        Text = text,
        Size = size,
        Position = position,
        TextColor3 = COLORS.text,
        Font = Enum.Font.Gotham,
        TextSize = textSize or 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
end

local Gui = new("ScreenGui", {
    Parent = GuiParent,
    Name = CONFIG.GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true
})

local Main = new("Frame", {
    Parent = Gui,
    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5)
})
round(Main, 15)

local function resize()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local viewport = camera.ViewportSize
    local width = math.min(math.floor(viewport.X * 0.94), viewport.X - 14)
    local height = math.min(math.floor(viewport.Y * 0.72), viewport.Y - 14)
    Main.Size = UDim2.fromOffset(math.max(320, width), math.max(285, height))
end
resize()

local Header = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, 0, 0, 56),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0
})
round(Header, 15)

label(Header, "PSICOSENATICO • PESQUISA DE ARMAS", UDim2.new(1, -140, 0, 24), UDim2.fromOffset(14, 5), 14)
local Version = label(Header, "V2.2", UDim2.fromOffset(38, 16), UDim2.fromOffset(14, 32), 9)
Version.TextColor3 = COLORS.blue2
local Subtitle = label(Header, "PENETRAÇÃO DE PAREDE • DIAGNÓSTICO", UDim2.new(1, -180, 0, 16), UDim2.fromOffset(55, 32), 8)
Subtitle.TextColor3 = COLORS.sub

local Minimize = new("TextButton", {
    Parent = Header,
    Size = UDim2.fromOffset(36, 32),
    Position = UDim2.new(1, -82, 0, 11),
    Text = "—",
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    BorderSizePixel = 0
})
round(Minimize, 9)

local Close = new("TextButton", {
    Parent = Header,
    Size = UDim2.fromOffset(36, 32),
    Position = UDim2.new(1, -41, 0, 11),
    Text = "×",
    BackgroundColor3 = COLORS.red,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 19,
    BorderSizePixel = 0
})
round(Close, 9)

local Status = label(Main, "Pronto • equipe uma arma.", UDim2.new(1, -28, 0, 19), UDim2.fromOffset(14, 59), 9)
Status.TextColor3 = COLORS.sub

local Start = new("TextButton", {
    Parent = Main,
    Size = UDim2.new(0.5, -17, 0, 34),
    Position = UDim2.fromOffset(14, 81),
    Text = "INICIAR",
    BackgroundColor3 = COLORS.blue2,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(Start, 8)

local Export = new("TextButton", {
    Parent = Main,
    Size = UDim2.new(0.5, -17, 0, 34),
    Position = UDim2.new(0.5, 3, 0, 81),
    Text = "EXPORTAR",
    BackgroundColor3 = COLORS.blue,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(Export, 8)

local PhaseRow = new("Frame", {
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 120),
    Size = UDim2.new(1, -28, 0, 35)
})

local phaseButtons = {}
local shortLabels = {
    CLEAR = "LIVRE",
    WALL = "PAREDE",
    TARGET_BEHIND_WALL = "ALVO+PAREDE",
    TARGET_CLEAR = "ALVO LIVRE"
}

for index, phase in ipairs(CONFIG.PHASES) do
    local button = new("TextButton", {
        Parent = PhaseRow,
        Size = UDim2.new(0.25, -5, 1, 0),
        Position = UDim2.new((index - 1) * 0.25, (index - 1) * 2, 0, 0),
        Text = shortLabels[phase],
        BackgroundColor3 = COLORS.panel2,
        TextColor3 = COLORS.text,
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        BorderSizePixel = 0
    })
    round(button, 7)
    phaseButtons[phase] = button
end

local Summary = label(Main, "", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 159), 8)
Summary.TextColor3 = COLORS.sub

local Viewer = new("ScrollingFrame", {
    Parent = Main,
    Position = UDim2.fromOffset(14, 181),
    Size = UDim2.new(1, -28, 1, -190),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 5,
    ScrollingDirection = Enum.ScrollingDirection.Y
})
round(Viewer, 9)

local Text = new("TextLabel", {
    Parent = Viewer,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 7),
    Size = UDim2.new(1, -16, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    Text = "",
    TextColor3 = COLORS.text,
    Font = Enum.Font.Code,
    TextSize = 9,
    TextWrapped = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top
})

local Mini = new("TextButton", {
    Parent = Gui,
    Visible = false,
    Size = UDim2.fromOffset(58, 58),
    Position = UDim2.fromScale(0.06, 0.24),
    Text = "V2.2",
    BackgroundColor3 = COLORS.blue,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(Mini, 17)

local function draggable(target, handle)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    S.Connections[#S.Connections + 1] = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    S.Connections[#S.Connections + 1] = handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    S.Connections[#S.Connections + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

draggable(Main, Header)
draggable(Mini, Mini)

local function updatePreview()
    local active = S.ActiveTool and S.ActiveTool.Name or "NENHUMA"
    local phase = CONFIG.PHASE_LABELS[S.CurrentPhase] or "-"

    Summary.Text = string.format(
        "GRAV:%s • ARMA:%s • FASE:%s • TIROS:%d • ERROS:%d",
        S.Recording and "SIM" or "NÃO",
        active,
        phase,
        #S.Shots,
        S.Errors
    )

    local lines = {
        "PESQUISA DE ARMAS V2.2",
        "────────────────────────────────────────",
        "FOCO: canPierce / castRays",
        "",
        "PROTOCOLO",
        "1 LIVRE → 3 tiros",
        "2 PAREDE → 3 tiros",
        "3 ALVO+PAREDE → 3 tiros",
        "4 ALVO LIVRE → 3 tiros",
        "",
        "MANTENHA A MESMA ARMA EQUIPADA",
        "• marque a fase antes dos 3 tiros",
        "• mire exatamente no ponto do teste",
        "• o diagnóstico não altera o disparo",
        "",
        "ÚLTIMOS EVENTOS",
        "────────────────────────────────────────"
    }

    local first = math.max(1, #S.Live - 70)
    for index = first, #S.Live do
        local item = S.Live[index]
        lines[#lines + 1] = string.format(
            "[%.3f] %-18s %s",
            item.time or 0,
            tostring(item.type),
            tostring(item.message)
        )
    end
    Text.Text = table.concat(lines, "\n")
end

Start.Activated:Connect(function()
    if not S.Recording then
        startDiagnostic()
        Start.Text = "PARAR"
        Status.Text = "Gravando • escolha uma fase e atire."
        Status.TextColor3 = COLORS.green
    else
        stopDiagnostic()
        Start.Text = "INICIAR"
        Status.Text = "Parado • dados preservados."
        Status.TextColor3 = COLORS.sub
    end
    updatePreview()
end)

for phase, button in pairs(phaseButtons) do
    button.Activated:Connect(function()
        if setPhase(phase) then
            Status.Text = "✓ FASE ATIVA: " .. (CONFIG.PHASE_LABELS[phase] or phase)
            Status.TextColor3 = COLORS.yellow
        else
            Status.Text = "Equipe uma arma e inicie a coleta."
            Status.TextColor3 = COLORS.red
        end
        updatePreview()
    end)
end

Export.Activated:Connect(function()
    if not S.Started then
        Status.Text = "Inicie a coleta antes de exportar."
        Status.TextColor3 = COLORS.yellow
        return
    end

    local data, err = encodeExport()
    if not data then
        Status.Text = "Falha ao gerar JSON: " .. tostring(err)
        Status.TextColor3 = COLORS.red
        return
    end

    local filename = "Psicosenatico_WeaponResearch_V2_2_"
        .. tostring(game.PlaceId)
        .. "_"
        .. tostring(os.time())
        .. ".json"

    local saved = false
    if typeof(writefile) == "function" then
        saved = pcall(function()
            writefile(filename, data)
        end)
    end

    if saved then
        Status.Text = "✓ ARQUIVO EXPORTADO: " .. filename
        Status.TextColor3 = COLORS.green
    elseif typeof(setclipboard) == "function" and pcall(function()
        setclipboard(data)
    end) then
        Status.Text = "✓ JSON COPIADO."
        Status.TextColor3 = COLORS.green
    else
        Status.Text = "Não foi possível salvar ou copiar o JSON."
        Status.TextColor3 = COLORS.red
    end
end)

Minimize.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

local function cleanup()
    if S.Recording then
        stopDiagnostic()
    end

    for _, list in pairs(S.ToolConnections) do
        for _, connection in ipairs(list) do
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    for _, connection in ipairs(S.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    pcall(function()
        Gui:Destroy()
    end)

    local runtime = RuntimeEnv[RUNTIME_KEY]
    if type(runtime) == "table" and runtime.cleanup == cleanup then
        RuntimeEnv[RUNTIME_KEY] = nil
    end
end

RuntimeEnv[RUNTIME_KEY] = {
    version = CONFIG.VERSION,
    cleanup = cleanup
}

Close.Activated:Connect(cleanup)

if Workspace.CurrentCamera then
    local ok, signal = pcall(function()
        return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")
    end)
    if ok and signal then
        S.Connections[#S.Connections + 1] = signal:Connect(resize)
    end
end

scanWeapons("INITIAL_SCAN")
pushLive("SISTEMA", "Pesquisa de Armas V2.2 pronta.")
pushLive("SISTEMA", "Interface em português • coleta observacional.")
updatePreview()

task.spawn(function()
    while Gui.Parent do
        pcall(updatePreview)
        task.wait(CONFIG.UI_REFRESH)
    end
end)

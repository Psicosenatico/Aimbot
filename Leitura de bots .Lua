-- ============================================================
-- CAFEÍNA • BOT RESEARCH V3
-- SOMENTE LEITURA / COLETA PASSIVA
--
-- V3:
-- • Interface responsiva
-- • Altura máxima de 70% da tela
-- • ScrollingFrame para dados
-- • Menu principal arrastável
-- • Botão minimizado arrastável
-- • Identificação visual V3 no cabeçalho
-- • Registro de spawn/remoção/mudanças
-- • Exportação JSON
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- PARENT
-- ============================================================

local function getParent()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then
            return p
        end
    end

    return CoreGui
end

local Parent = getParent()

for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == "CafeinaBotResearch_V3" then
        pcall(function()
            v:Destroy()
        end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotResearch_V3"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

-- ============================================================
-- CORES
-- ============================================================

local COLORS = {
    bg = Color3.fromRGB(10,10,13),
    panel = Color3.fromRGB(19,19,24),
    panel2 = Color3.fromRGB(28,28,35),

    text = Color3.fromRGB(245,245,248),
    sub = Color3.fromRGB(158,158,172),

    blue = Color3.fromRGB(22,55,105),
    blue2 = Color3.fromRGB(32,82,145),

    green = Color3.fromRGB(65,210,118),
    red = Color3.fromRGB(235,38,52),
    yellow = Color3.fromRGB(242,184,57),

    scroll = Color3.fromRGB(65,65,75)
}

-- ============================================================
-- HELPERS
-- ============================================================

local function new(class, props)
    local obj = Instance.new(class)

    for k, v in pairs(props or {}) do
        obj[k] = v
    end

    return obj
end

local function round(obj, radius)
    new("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = obj
    })
end

local function label(parent, text, size, pos, textSize)
    return new("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        Text = text,
        Size = size,
        Position = pos,
        TextColor3 = COLORS.text,
        Font = Enum.Font.Gotham,
        TextSize = textSize or 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
end

-- ============================================================
-- ESTADO
-- ============================================================

local State = {
    Started = false,
    Scanned = false,

    Records = {},
    Army = {},
    Rebels = {},
    Unknown = {},

    Mannequins = {},
    Playable = {},

    PatrolPoints = {},

    Events = {},
    Snapshots = {},

    BotCounter = 0,

    StartUnix = nil,
    EndUnix = nil,

    Connections = {}
}

local MonitorRunning = false

-- ============================================================
-- UTILITÁRIOS
-- ============================================================

local function safeFullName(x)
    local ok, result = pcall(function()
        return x:GetFullName()
    end)

    if ok then
        return tostring(result)
    end

    return tostring(x.Name)
end

local function attr(x, key)
    local ok, result = pcall(function()
        return x:GetAttribute(key)
    end)

    if ok then
        return result
    end

    return nil
end

local function getRoot(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function getHumanoid(model)
    return model:FindFirstChildOfClass("Humanoid")
end

local function isPlayerCharacter(model)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end

    return false
end

local function unix()
    return os.time()
end

local function clock()
    return os.clock()
end

-- ============================================================
-- EVENTOS
-- ============================================================

local function addEvent(eventType, data)
    State.Events[#State.Events + 1] = {
        time = clock(),
        unix = unix(),
        type = eventType,
        data = data or {}
    }
end

-- ============================================================
-- IDENTIFICAÇÃO DE EQUIPE
-- ============================================================

local function inspectTeam(model)

    local teamAttribute = attr(model, "Team")

    if teamAttribute ~= nil then
        return tostring(teamAttribute), "Attribute.Team"
    end

    local teamValue = model:FindFirstChild("Team")

    if teamValue and teamValue:IsA("StringValue") then
        return tostring(teamValue.Value), "StringValue.Team"
    end

    if teamValue and teamValue:IsA("ObjectValue") then
        local value = teamValue.Value

        if value then
            return tostring(value.Name), "ObjectValue.Team"
        end
    end

    for _, child in ipairs(model:GetChildren()) do

        local lower = child.Name:lower()

        if lower == "team"
        or lower == "faction"
        or lower == "side" then

            if child:IsA("StringValue") then
                return tostring(child.Value), child.ClassName .. "." .. child.Name
            end

            if child:IsA("ObjectValue") and child.Value then
                return tostring(child.Value.Name), child.ClassName .. "." .. child.Name
            end
        end
    end

    return nil, nil
end

-- ============================================================
-- HIGHLIGHT
-- ============================================================

local function inspectHighlight(model)

    local result = {
        exists = false,
        count = 0,
        details = {}
    }

    for _, obj in ipairs(model:GetDescendants()) do

        if obj:IsA("Highlight") then

            result.exists = true
            result.count += 1

            result.details[#result.details + 1] = {
                name = obj.Name,
                parent = safeFullName(obj.Parent),

                enabled = obj.Enabled,

                fillColor = {
                    r = obj.FillColor.R,
                    g = obj.FillColor.G,
                    b = obj.FillColor.B
                },

                outlineColor = {
                    r = obj.OutlineColor.R,
                    g = obj.OutlineColor.G,
                    b = obj.OutlineColor.B
                },

                fillTransparency = obj.FillTransparency,
                outlineTransparency = obj.OutlineTransparency,

                adornee = obj.Adornee and safeFullName(obj.Adornee) or nil
            }
        end
    end

    return result
end

-- ============================================================
-- SNAPSHOT
-- ============================================================

local function buildBotSnapshot(model)

    if not model
    or not model.Parent
    or not model:IsA("Model") then
        return nil
    end

    local humanoid = getHumanoid(model)

    if not humanoid then
        return nil
    end

    local root = getRoot(model)

    local team, teamSource = inspectTeam(model)

    local position = nil

    if root then
        position = {
            x = root.Position.X,
            y = root.Position.Y,
            z = root.Position.Z
        }
    end

    local moveDirection = {
        x = humanoid.MoveDirection.X,
        y = humanoid.MoveDirection.Y,
        z = humanoid.MoveDirection.Z
    }

    local attributes = {}

    pcall(function()
        for key, value in pairs(model:GetAttributes()) do
            attributes[tostring(key)] = tostring(value)
        end
    end)

    local objects = {}

    for _, child in ipairs(model:GetDescendants()) do

        objects[#objects + 1] = {
            name = child.Name,
            className = child.ClassName,
            path = safeFullName(child)
        }

    end

    return {
        time = clock(),
        unix = unix(),

        name = model.Name,
        path = safeFullName(model),
        className = model.ClassName,

        team = team,
        teamSource = teamSource,

        health = humanoid.Health,
        maxHealth = humanoid.MaxHealth,

        walkSpeed = humanoid.WalkSpeed,
        jumpPower = humanoid.JumpPower,

        rigType = tostring(humanoid.RigType),

        rootPart = root and root.Name or nil,

        position = position,
        moveDirection = moveDirection,

        attributes = attributes,

        highlight = inspectHighlight(model),

        objects = objects
    }
end

-- ============================================================
-- REGISTRO DE BOT
-- ============================================================

local function registerBot(model, reason)

    if not model
    or not model:IsA("Model")
    or isPlayerCharacter(model) then
        return
    end

    local humanoid = getHumanoid(model)

    if not humanoid then
        return
    end

    for _, record in ipairs(State.Records) do
        if record.instance == model then
            return
        end
    end

    State.BotCounter += 1

    local snapshot = buildBotSnapshot(model)

    if not snapshot then
        return
    end

    local lowerName = model.Name:lower()

    local likelyMannequin =
        lowerName:find("dummy", 1, true) ~= nil
        or lowerName:find("mannequin", 1, true) ~= nil
        or lowerName:find("manequim", 1, true) ~= nil

    local record = {
        id = State.BotCounter,

        instance = model,

        registeredAt = clock(),
        registeredAtUnix = unix(),

        spawnReason = reason or "UNKNOWN",

        name = snapshot.name,
        path = snapshot.path,

        team = snapshot.team,
        teamSource = snapshot.teamSource,

        likelyMannequin = likelyMannequin,

        snapshots = {
            snapshot
        }
    }

    State.Records[#State.Records + 1] = record

    if snapshot.team == "Army" then
        State.Army[#State.Army + 1] = record

    elseif snapshot.team == "Rebels" then
        State.Rebels[#State.Rebels + 1] = record

    else
        State.Unknown[#State.Unknown + 1] = record
    end

    if likelyMannequin then
        State.Mannequins[#State.Mannequins + 1] = record
    else
        State.Playable[#State.Playable + 1] = record
    end

    addEvent("BOT_REGISTERED", {
        id = record.id,
        name = record.name,
        path = record.path,
        team = snapshot.team,
        teamSource = snapshot.teamSource,
        reason = reason
    })
end

-- ============================================================
-- SNAPSHOT PERIÓDICO
-- ============================================================

local function monitorBots()

    for _, record in ipairs(State.Records) do

        local model = record.instance

        if model and model.Parent then

            local snapshot = buildBotSnapshot(model)

            if snapshot then

                record.snapshots[#record.snapshots + 1] = snapshot

                State.Snapshots[#State.Snapshots + 1] = {
                    botId = record.id,
                    snapshot = snapshot
                }

            end
        end
    end
end

-- ============================================================
-- PATROL POINTS
-- ============================================================

local function scanPatrolPoints()

    State.PatrolPoints = {}

    local folder = workspace:FindFirstChild("BotPatrolPoints")

    if not folder then
        return
    end

    for _, teamFolder in ipairs(folder:GetChildren()) do

        if teamFolder:IsA("Folder") then

            local list = {}

            for _, obj in ipairs(teamFolder:GetDescendants()) do

                if obj:IsA("BasePart") then

                    list[#list + 1] = {
                        name = obj.Name,
                        path = safeFullName(obj),

                        teamAttribute = attr(obj, "Team"),

                        position = {
                            x = obj.Position.X,
                            y = obj.Position.Y,
                            z = obj.Position.Z
                        },

                        anchored = obj.Anchored,
                        transparency = obj.Transparency
                    }

                end
            end

            State.PatrolPoints[teamFolder.Name] = list
        end
    end
end

-- ============================================================
-- SCAN EXISTENTE
-- ============================================================

local function scanExisting()

    for _, inst in ipairs(workspace:GetDescendants()) do

        if inst:IsA("Model") then
            registerBot(inst, "EXISTING_ON_SCAN")
        end
    end

    scanPatrolPoints()
end

-- ============================================================
-- MONITORAMENTO DE SPAWN / REMOÇÃO
-- ============================================================

local function connectMonitoring()

    table.insert(
        State.Connections,
        workspace.DescendantAdded:Connect(function(instance)

            if instance:IsA("Model") then

                task.defer(function()

                    if instance.Parent then
                        registerBot(instance, "DESCENDANT_ADDED")
                    end

                end)

            end
        end)
    )

    table.insert(
        State.Connections,
        workspace.DescendantRemoving:Connect(function(instance)

            if not instance:IsA("Model") then
                return
            end

            for _, record in ipairs(State.Records) do

                if record.instance == instance then

                    record.removedAt = clock()
                    record.removedAtUnix = unix()

                    addEvent("BOT_REMOVED", {
                        id = record.id,
                        name = record.name,
                        path = record.path,
                        team = record.team
                    })

                    break
                end
            end
        end)
    )
end

-- ============================================================
-- MONITORAMENTO DE ATRIBUTOS
-- ============================================================

local function monitorAttributeChanges(model, record)

    local ok = pcall(function()

        model.AttributeChanged:Connect(function(attributeName)

            local newValue = attr(model, attributeName)

            addEvent("ATTRIBUTE_CHANGED", {
                botId = record.id,
                name = attributeName,
                value = tostring(newValue)
            })

        end)

    end)

    return ok
end

-- ============================================================
-- ATUALIZAÇÃO DE EQUIPE
-- ============================================================

local function updateTeamClassification()

    for _, record in ipairs(State.Records) do

        local model = record.instance

        if model and model.Parent then

            local team, source = inspectTeam(model)

            if team ~= record.team then

                local oldTeam = record.team

                record.team = team
                record.teamSource = source

                addEvent("TEAM_CHANGED", {
                    botId = record.id,
                    name = record.name,
                    oldTeam = oldTeam,
                    newTeam = team,
                    source = source
                })

            end
        end
    end
end

-- ============================================================
-- INÍCIO / PARADA
-- ============================================================

local function startScanner()

    if MonitorRunning then
        return
    end

    MonitorRunning = true

    State.Started = true
    State.Scanned = false
    State.StartUnix = unix()
    State.EndUnix = nil

    scanExisting()
    connectMonitoring()

    for _, record in ipairs(State.Records) do
        monitorAttributeChanges(record.instance, record)
    end

    State.Scanned = true
end

local function stopScanner()

    if not MonitorRunning then
        return
    end

    MonitorRunning = false

    State.EndUnix = unix()

    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    State.Connections = {}

    addEvent("SCAN_STOPPED", {})
end

-- ============================================================
-- EXPORTAÇÃO
-- ============================================================

local function serializeRecord(record)

    local data = {}

    for k, v in pairs(record) do

        if k ~= "instance" then
            data[k] = v
        end

    end

    return data
end

local function buildExport()

    local bots = {}

    for _, record in ipairs(State.Records) do
        bots[#bots + 1] = serializeRecord(record)
    end

    return {
        format = "Cafeina Bot Research",
        version = "V3",

        generatedAtUnix = unix(),

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId
        },

        research = {
            startUnix = State.StartUnix,
            endUnix = State.EndUnix,

            status = MonitorRunning and "COLLECTING" or "STOPPED"
        },

        summary = {
            registeredBots = #State.Records,
            army = #State.Army,
            rebels = #State.Rebels,
            unknown = #State.Unknown,

            mannequins = #State.Mannequins,
            likelyPlayable = #State.Playable,

            events = #State.Events,
            snapshots = #State.Snapshots
        },

        bots = bots,

        events = State.Events,

        snapshots = State.Snapshots,

        patrolPoints = State.PatrolPoints
    }
end

local function jsonExport()

    local ok, result = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)

    if ok then
        return result
    end

    return nil
end

-- ============================================================
-- INTERFACE
-- ============================================================

local Main = new("Frame", {
    Parent = Gui,

    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,

    AnchorPoint = Vector2.new(0.5, 0.5),

    Position = UDim2.fromScale(0.5, 0.5)
})

round(Main, 16)

-- ============================================================
-- RESPONSIVIDADE
-- ============================================================

local function updateMainSize()

    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local viewport = camera.ViewportSize

    local maxHeight = math.floor(viewport.Y * 0.70)
    local maxWidth = math.floor(viewport.X * 0.92)

    local desiredHeight = math.floor(viewport.Y * 0.68)
    local desiredWidth = math.floor(viewport.X * 0.88)

    local height = math.min(desiredHeight, maxHeight)
    local width = math.min(desiredWidth, maxWidth)

    height = math.max(height, 300)
    width = math.max(width, 420)

    height = math.min(height, viewport.Y - 20)
    width = math.min(width, viewport.X - 20)

    Main.Size = UDim2.fromOffset(width, height)
end

updateMainSize()

if workspace.CurrentCamera then

    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(
        updateMainSize
    )

end

-- ============================================================
-- HEADER COMPACTO
-- ============================================================

local Header = new("Frame", {
    Parent = Main,

    Size = UDim2.new(1, 0, 0, 61),

    BackgroundColor3 = COLORS.panel,

    BorderSizePixel = 0
})

round(Header, 16)

-- ============================================================
-- TÍTULO
-- ============================================================

local Title = label(
    Header,
    "CAFÉINA • BOT RESEARCH",
    UDim2.new(1, -150, 0, 25),
    UDim2.fromOffset(18, 7),
    17
)

-- ============================================================
-- V3
-- ============================================================

local Version = label(
    Header,
    "V3",
    UDim2.fromOffset(40, 17),
    UDim2.fromOffset(18, 34),
    9
)

Version.TextColor3 = COLORS.sub
Version.TextXAlignment = Enum.TextXAlignment.Left

-- ============================================================
-- SUBTÍTULO
-- ============================================================

local Subtitle = label(
    Header,
    "PESQUISA DE COMPORTAMENTO • SOMENTE LEITURA",
    UDim2.new(1, -190, 0, 17),
    UDim2.fromOffset(48, 34),
    8
)

Subtitle.TextColor3 = COLORS.sub

-- ============================================================
-- MINIMIZAR
-- ============================================================

local Min = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(38, 36),

    Position = UDim2.new(1, -88, 0, 12),

    Text = "—",

    BackgroundColor3 = COLORS.panel2,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 19,

    BorderSizePixel = 0
})

round(Min, 10)

-- ============================================================
-- FECHAR
-- ============================================================

local Close = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(38, 36),

    Position = UDim2.new(1, -44, 0, 12),

    Text = "×",

    BackgroundColor3 = COLORS.red,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 21,

    BorderSizePixel = 0
})

round(Close, 10)

-- ============================================================
-- STATUS
-- ============================================================

local Status = label(
    Main,
    "Pesquisa parada • pressione INICIAR LEITURA DE BOTS.",
    UDim2.new(1, -36, 0, 21),
    UDim2.fromOffset(18, 67),
    9
)

Status.TextColor3 = COLORS.sub

-- ============================================================
-- BOTÕES
-- ============================================================

local Scan = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(0.5, -23, 0, 40),

    Position = UDim2.fromOffset(18, 91),

    Text = "INICIAR LEITURA DE BOTS",

    BackgroundColor3 = COLORS.blue2,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0
})

round(Scan, 9)

local Export = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(0.5, -23, 0, 40),

    Position = UDim2.new(0.5, 5, 0, 91),

    Text = "BAIXAR ARQUIVO DE LEITURA",

    BackgroundColor3 = COLORS.blue,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0
})

round(Export, 9)

-- ============================================================
-- RESUMO COMPACTO
-- ============================================================

local Summary = label(
    Main,
    "Nenhuma leitura realizada.",
    UDim2.new(1, -36, 0, 26),
    UDim2.fromOffset(18, 137),
    9
)

Summary.TextWrapped = true
Summary.TextYAlignment = Enum.TextYAlignment.Center

-- ============================================================
-- ÁREA DE LEITURA
-- ============================================================

local Viewer = new("ScrollingFrame", {
    Parent = Main,

    Size = UDim2.new(1, -36, 1, -177),

    Position = UDim2.fromOffset(18, 168),

    BackgroundColor3 = COLORS.panel,

    BorderSizePixel = 0,

    CanvasSize = UDim2.fromOffset(0, 0),

    AutomaticCanvasSize = Enum.AutomaticSize.Y,

    ScrollBarThickness = 7,

    ScrollBarImageColor3 = COLORS.scroll,

    ScrollingDirection = Enum.ScrollingDirection.Y,

    Active = true,

    ClipsDescendants = true,

    ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
})

round(Viewer, 9)

local ViewerText = new("TextLabel", {
    Parent = Viewer,

    Size = UDim2.new(1, -20, 0, 0),

    Position = UDim2.fromOffset(10, 10),

    AutomaticSize = Enum.AutomaticSize.Y,

    BackgroundTransparency = 1,

    Text = "Nenhuma leitura realizada.",

    TextColor3 = COLORS.text,

    Font = Enum.Font.Code,

    TextSize = 10,

    TextXAlignment = Enum.TextXAlignment.Left,

    TextYAlignment = Enum.TextYAlignment.Top,

    TextWrapped = false
})

-- ============================================================
-- BOTÃO FLUTUANTE
-- ============================================================

local Mini = new("TextButton", {
    Parent = Gui,

    Size = UDim2.fromOffset(58, 58),

    Position = UDim2.new(0.5, -29, 0.5, -29),

    BackgroundColor3 = COLORS.blue,

    Text = "C",

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBlack,

    TextSize = 20,

    BorderSizePixel = 0,

    Visible = false,

    AutoButtonColor = true
})

round(Mini, 99)

-- ============================================================
-- PREVIEW
-- ============================================================

local function updatePreview()

    local lines = {}

    lines[#lines + 1] = "════════════════════════════════"
    lines[#lines + 1] = "CAFÉINA • BOT RESEARCH V3"
    lines[#lines + 1] = "════════════════════════════════"
    lines[#lines + 1] = ""

    lines[#lines + 1] =
        "STATUS: "
        .. (MonitorRunning and "COLETANDO" or "PARADO")

    lines[#lines + 1] =
        "EVENTOS: "
        .. tostring(#State.Events)

    lines[#lines + 1] =
        "SNAPSHOTS: "
        .. tostring(#State.Snapshots)

    lines[#lines + 1] =
        "BOTS REGISTRADOS: "
        .. tostring(#State.Records)

    lines[#lines + 1] = ""

    lines[#lines + 1] = "BOTS ATIVOS / REGISTRADOS"

    lines[#lines + 1] =
        "  Army: "
        .. tostring(#State.Army)

    lines[#lines + 1] =
        "  Rebels: "
        .. tostring(#State.Rebels)

    lines[#lines + 1] =
        "  Desconhecido: "
        .. tostring(#State.Unknown)

    lines[#lines + 1] = ""

    lines[#lines + 1] = "CATEGORIAS"

    lines[#lines + 1] =
        "  Possíveis jogáveis: "
        .. tostring(#State.Playable)

    lines[#lines + 1] =
        "  Possíveis manequins: "
        .. tostring(#State.Mannequins)

    lines[#lines + 1] = ""

    lines[#lines + 1] = "ENTIDADES REGISTRADAS"
    lines[#lines + 1] = ""

    for _, record in ipairs(State.Records) do

        local snapshot =
            record.snapshots[#record.snapshots]

        lines[#lines + 1] =
            string.format(
                "[Bot #%d] %s",
                record.id,
                record.name
            )

        lines[#lines + 1] =
            "  Team: "
            .. tostring(record.team or "UNKNOWN")
            .. " | Fonte: "
            .. tostring(record.teamSource or "UNKNOWN")

        lines[#lines + 1] =
            "  Snapshots: "
            .. tostring(#record.snapshots)

        if snapshot then

            lines[#lines + 1] =
                string.format(
                    "  HP: %.1f / %.1f",
                    snapshot.health or 0,
                    snapshot.maxHealth or 0
                )

            lines[#lines + 1] =
                "  Highlight: "
                .. (
                    snapshot.highlight.exists
                    and "SIM"
                    or "NÃO"
                )

            lines[#lines + 1] =
                "  Path: "
                .. tostring(record.path)
        end

        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "════════════════════════════════"
    lines[#lines + 1] = "LINHA DO TEMPO"
    lines[#lines + 1] = "════════════════════════════════"
    lines[#lines + 1] = ""

    local startIndex = math.max(
        1,
        #State.Events - 150
    )

    for i = #State.Events, startIndex, -1 do

        local event = State.Events[i]

        lines[#lines + 1] =
            string.format(
                "[%.2f] %s",
                event.time or 0,
                tostring(event.type)
            )

        if event.data then

            if event.data.id then
                lines[#lines + 1] =
                    "    Bot ID: "
                    .. tostring(event.data.id)
            end

            if event.data.name then
                lines[#lines + 1] =
                    "    Nome: "
                    .. tostring(event.data.name)
            end

            if event.data.oldTeam
            or event.data.newTeam then

                lines[#lines + 1] =
                    "    Equipe: "
                    .. tostring(event.data.oldTeam)
                    .. " -> "
                    .. tostring(event.data.newTeam)
            end
        end
    end

    ViewerText.Text = table.concat(lines, "\n")
end

-- ============================================================
-- LOOP DE MONITORAMENTO
-- ============================================================

task.spawn(function()

    while Gui.Parent do

        if MonitorRunning then

            pcall(function()
                monitorBots()
                updateTeamClassification()
                updatePreview()
            end)

        end

        task.wait(2)
    end
end)

-- ============================================================
-- INICIAR / PARAR
-- ============================================================

Scan.Activated:Connect(function()

    if not MonitorRunning then

        Scan.Text = "PARAR LEITURA DE BOTS"

        Status.Text =
            "Pesquisa ativa • observando spawn, equipe, objetos e Highlight."

        Status.TextColor3 = COLORS.green

        local ok, err = pcall(startScanner)

        if not ok then

            MonitorRunning = false

            Scan.Text = "INICIAR LEITURA DE BOTS"

            Status.Text =
                "Erro ao iniciar: "
                .. tostring(err)

            Status.TextColor3 = COLORS.red

            return
        end

    else

        stopScanner()

        Scan.Text = "INICIAR LEITURA DE BOTS"

        Status.Text =
            "Pesquisa parada. Dados preservados para exportação."

        Status.TextColor3 = COLORS.sub
    end

    updatePreview()
end)

-- ============================================================
-- EXPORTAÇÃO
-- ============================================================

Export.Activated:Connect(function()

    if not State.Scanned then

        Status.Text =
            "Nenhuma leitura realizada. Inicie a pesquisa primeiro."

        Status.TextColor3 = COLORS.yellow

        return
    end

    Status.Text =
        "Preparando arquivo de leitura..."

    Status.TextColor3 = COLORS.sub

    local data = jsonExport()

    if not data then

        Status.Text =
            "Falha ao gerar o arquivo JSON."

        Status.TextColor3 = COLORS.red

        return
    end

    local filename =
        "Cafeina_BotResearch_V3_"
        .. tostring(game.PlaceId)
        .. "_"
        .. tostring(os.time())
        .. ".json"

    local wrote = false

    -- ========================================================
    -- WRITEFILE
    -- ========================================================

    if typeof(writefile) == "function" then

        local ok = pcall(function()
            writefile(filename, data)
        end)

        wrote = ok
    end

    -- ========================================================
    -- RESULTADO
    -- ========================================================

    if wrote then

        Status.Text =
            "✓ ARQUIVO EXPORTADO COM SUCESSO: "
            .. filename

        Status.TextColor3 = COLORS.green

    elseif typeof(setclipboard) == "function" then

        local ok = pcall(function()
            setclipboard(data)
        end)

        if ok then

            Status.Text =
                "✓ DADOS EXPORTADOS PARA A ÁREA DE TRANSFERÊNCIA."

            Status.TextColor3 = COLORS.green

        else

            Status.Text =
                "Não foi possível salvar nem copiar os dados."

            Status.TextColor3 = COLORS.red
        end

    else

        Status.Text =
            "Scanner concluído, mas este ambiente não possui writefile/clipboard."

        Status.TextColor3 = COLORS.yellow
    end
end)

-- ============================================================
-- FECHAR
-- ============================================================

Close.Activated:Connect(function()

    stopScanner()

    pcall(function()
        Gui:Destroy()
    end)
end)

-- ============================================================
-- MINIMIZAR
-- ============================================================

Min.Activated:Connect(function()

    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()

    Main.Visible = true
    Mini.Visible = false
end)

-- ============================================================
-- SISTEMA DE ARRASTAR
-- ============================================================

local function makeDraggable(handle, target)

    local dragging = false
    local dragStart = nil
    local startPosition = nil

    local function update(input)

        if not dragging
        or not dragStart
        or not startPosition then
            return
        end

        local delta =
            input.Position - dragStart

        local newX =
            startPosition.X.Offset + delta.X

        local newY =
            startPosition.Y.Offset + delta.Y

        local camera = workspace.CurrentCamera

        if camera then

            local viewport =
                camera.ViewportSize

            local targetSize =
                target.AbsoluteSize

            local minX =
                -(viewport.X - targetSize.X) / 2

            local maxX =
                (viewport.X - targetSize.X) / 2

            local minY =
                -(viewport.Y - targetSize.Y) / 2

            local maxY =
                (viewport.Y - targetSize.Y) / 2

            newX =
                math.clamp(
                    newX,
                    minX,
                    maxX
                )

            newY =
                math.clamp(
                    newY,
                    minY,
                    maxY
                )
        end

        target.Position =
            UDim2.new(
                0.5,
                newX,
                0.5,
                newY
            )
    end

    handle.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch then

            dragging = true

            dragStart =
                input.Position

            startPosition =
                target.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)

        if dragging
        and (
            input.UserInputType
                == Enum.UserInputType.MouseMovement
            or input.UserInputType
                == Enum.UserInputType.Touch
        ) then

            update(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch then

            dragging = false
        end
    end)
end

-- ============================================================
-- ARRASTAR
-- ============================================================

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

-- ============================================================
-- POSIÇÃO INICIAL
-- ============================================================

Main.Position =
    UDim2.fromScale(0.5, 0.5)

Mini.Position =
    UDim2.fromScale(0.5, 0.5)

updatePreview()

Status.Text =
    "Pesquisa parada • pressione INICIAR LEITURA DE BOTS."

Status.TextColor3 = COLORS.sub

-- ============================================================
-- FIM DA V3
-- ============================================================
